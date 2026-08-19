# S4 — The painter: the double solve

Session 4 of `OPTIMIZATION_PLAN.md` §5. Owns `frontend/lib/widgets/viewport.dart`
and, in `app_state.dart`, `displayGeometry` and nothing else.

**Status at time of writing:** predictions registered, mechanism established,
implementation and pinning tests done. No device measurement exists yet — see
§2 of the plan. Nothing below claims the application is faster.

---

## 1. What the brief said, and the one thing it got wrong

The brief called this "the cheapest large win in the whole ranking — it is a
duplicated call, not an algorithm", and warned:

> **Correctness risk:** if the second call currently observes geometry mutated
> by the first, reusing the first result changes what is drawn. Prove it does
> not, with a test that paints both ways and compares the output geometry lists.

I ran that test. **The second call does observe geometry mutated by the first.**
The two calls are not duplicates. What follows is the measurement that
establishes it, and what I did about it.

---

## 2. The mechanism, corrected

`displayGeometry` is not a pure function. `_displayGeometryInner`
(`app_state.dart`, locate by grepping `_displayGeometryInner`) ends a successful
frame with

```dart
_lastGoodDragGeo = gs;
return gs;
```

and opens the *next* call by warm-starting from exactly that field:

```dart
final prev = grip.isBody ? null : _lastGoodDragGeo;
```

So within one painted frame:

| | reads | writes | returns |
| --- | --- | --- | --- |
| call A (`ent.dofColour` phase) | `_lastGoodDragGeo` from frame N−1 | `_lastGoodDragGeo := gsA` | gsA |
| call B (`constraints` phase) | `_lastGoodDragGeo` = **gsA** | `_lastGoodDragGeo := gsB` | gsB |

Call B re-applies `moveGrip` to pull the grip back to the cursor (the solver
treats a drag as a wish, not a command, so it may have left the point away from
the cursor) and then runs **25 more solver iterations**. It is a convergence
refinement step, not a repeat.

Three consequences, all of which I measured rather than argued:

1. **Entities and constraint glyphs are drawn from different geometry.** `gs`
   from call A drives every entity, grip and halo; `gs2` from call B drives
   `constraintGlyphs` and every dimension label. The glyphs therefore sit where
   the geometry will be after another 25 iterations, not where it is drawn.
2. **The number of solves per frame is not fixed.** Call B is behind
   `if (s != null && app.inEditMode)`. A third site (the tool-preview block,
   `buildToolGeometry(..., existing: app.displayGeometry(s2))`) fires whenever a
   tool is active with a hover point. So the painter performs **1, 2 or 3**
   solves per frame depending on UI state.
3. **The commit is downstream of all of it.** `endGripDrag` opens with
   `final shown = List<Geo>.from(displayGeometry(s));` — a *fourth* solve — and
   settles from there.

Taken together: **the geometry a drag commits today depends on whether the user
had constraint glyphs switched on.** That is a defect, and it is in my own file.

---

## 3. Measurement — host-side, no device needed

All figures from `frontend/test/s4_display_geometry_once_test.dart`, which is
the permanent form of the throwaway probes I used to get them. `maxDelta` is the
largest absolute difference over every parameter of every entity.

### 3.1 Where collapsing is exactly identical

Calling `displayGeometry` twice in a row and comparing:

| Fixture | A == B | maxDelta(A,B) |
| --- | --- | ---: |
| Free line, endpoint drag | **yes** | 0.000e+0 |
| Body drag (whole-entity translate) | **yes** | 0.000e+0 |
| Fixed-length line, cursor far outside reach | **yes** | 0.000e+0 |
| Two coupled slots (tangent + point-on-curve) | no | 9.748e−5 |

Body drags are identical by construction: `prev = grip.isBody ? null : …`, so a
body drag never warm-starts and both calls begin from the committed geometry.
The free and unreachable cases are identical because the solve converges and the
re-pull is a fixed point — the second call has nothing left to do.

Only a genuinely coupled system moves, and it *converges*: on the same fixture
the third call differs from the second by **6.602e−11**, six orders of magnitude
below the second-vs-first difference.

### 3.2 The regimes compared over a whole drag

The fixture is the two coupled slots from `m207_drag_continuity_test.dart` — the
sketch M207 was written for, the hardest constrained system in the repo. Same
60-frame cursor path, painted with N solves per frame, then committed through
`endGripDrag`:

| Comparison | last shown frame | committed geometry |
| --- | ---: | ---: |
| 2 solves/frame (today) vs 1 (fixed) | 3.225e−4 | 2.611e−4 |
| 3 solves/frame vs 2 | 1.475e−4 | 1.347e−4 |

Sketch span: **64.08 model units**. So the largest disagreement is
**3.2e−4 / 64.08 = 5.0 ppm of the sketch**.

Two things follow, and the second is the one that decided the design:

- **The difference is not a loss of accuracy.** Constraint residual norm of the
  committed geometry, both regimes: **2.828e−6**, equal to four significant
  figures. Both commits land on the constraint manifold equally well; they land
  on *different points of it*, which a 1022-DOF system is entitled to do. For
  scale, the solver's own satisfaction threshold is `_satisfied = 1e-6` and the
  value it will render without complaint is `_renderable = 1e-2` — the shown
  frame's disagreement is **31× inside what the code already declares legal for
  a drag frame**.
- **There is no single current behaviour to preserve.** 1, 2 and 3 solves per
  frame give three different answers, each about half the previous difference.
  Today's answer is whichever of those the UI state happened to select. "Keep it
  bit-identical" is therefore not achievable *and not meaningful* here; the
  achievable goal is to make the answer well-defined.

---

## 4. What I did

Made `displayGeometry` a function of the drag state instead of a function of how
many times it is called: one solve per **drag position**, memoised, returned to
every caller within that position.

I chose this over the brief's preferred paint-local variable in `viewport.dart`
deliberately. A paint-local fixes call sites A and B but leaves the tool-preview
call and `endGripDrag`'s call solving independently, so the answer would still
depend on UI state — less than before, but still. The memo makes the quantity
well-defined for every caller at once, including the snap path, and it is inside
`displayGeometry`, which §3 of the plan assigns to me.

**Invalidation.** The cached answer is reused only when all four hold:

| Guard | Catches |
| --- | --- |
| `identical(_dgSketch, s)` | tab / sketch switch |
| `identical(_dgGrip, dragGrip)` | a new drag (`beginGripDrag` allocates a new `Grip`) |
| `_dgPos == dragPos` | the cursor moving (`Offset` has value equality) |
| `identical(_dgSource, s.geometry)` | the geometry list being replaced — `SketchModel.geometry` is assigned wholesale by the rebuild path and by undo, never patched in place |

An in-place mutation of the same list object, at the same cursor position,
during the same drag, would slip past all four. No such path exists while a grip
drag is live: drag frames work on copies, and the only writer is the commit in
`endGripDrag`, which runs after its own `displayGeometry` call and then nulls
`dragGrip`. Pinned by test rather than left as an argument — see
`s4_display_geometry_once_test.dart`, group "the memo invalidates".

---

## 5. Predictions, registered before the change

Derived against **`perf/baseline.json`**, not against the §5.2 narrative. The
two are different captures — §5.2 is the paired run of build `230f179`, the
baseline is what `ci/perf_gate.py` actually compares a new bundle to — and the
gate adjudicates the baseline. §5.2 is used below only as a cross-check.

### Prediction P1 — one display solve per painted frame

```
Target        : the gate's scenario scope, ui.drag60's contribution to it
Baseline      : perf/baseline.json
                2d.displayGeometry            mean 0.142383 ms, n = 120
                2d.paint                      mean 0.167527 ms, n = 150
                2d.paint.constraints          mean 0.058053 ms, n = 150
                2d.paint.ent.dofColour        mean 0.057173 ms, n = 150
                2d.paint.entities             mean 0.050433 ms, n = 150
                2d.displayGeometry.solves     120
                solve.iterationsRequested     11300
                solve.ok / solve.unsatisfied  405 / 3
                solve.path.slvs / .lm         394 / 14
                solve.total                   mean 1.658341 ms, n = 408
Mechanism     : two call sites in viewport.dart (the ent.dofColour phase and
                the constraints phase) each ran a full 25-iteration constraint
                solve for the same drag position. drag60 is the only dragging
                scenario, so all 120 of the baseline's displayGeometry calls
                are its 60 frames x 2.
Change        : memoise displayGeometry on (sketch, grip, dragPos, geometry
                list identity). The constraints-phase call becomes a hit.
Derivation    :
    One display solve costs 0.142383 ms (the baseline's own mean, n = 120).
    Sixty of them are removed:
        60 x 0.142383 = 8.5430 ms
    Phase totals in the baseline, and what fraction of each those 60 solves are:
        2d.paint               25.1291 ms      34.00 %
        2d.paint.constraints    8.7080 ms      98.11 %
        2d.paint.ent.dofColour  8.5760 ms      99.62 %
    The last two lines are the check that the mechanism is right, and they are
    the strongest evidence in this file: each of those two phases is ~99 % ONE
    SOLVE. That is §5.2's finding ("the phase name misleads — it is the solve
    located inside that segment") re-derived from the baseline artifact instead
    of from the narrative, and the two agree.
Predicted     :
    COUNTERS — exact, zero noise, and every one of these is a gate FAILURE by
    design (ci/perf_gate.py:326, "the amount of work changed, not merely its
    speed"). They are the win. Read them, do not silence them:
        2d.displayGeometry.solves    120   -> 60      (-60)
        solve.iterationsRequested    11300 -> 9800    (-1500 = 60 x 25)
        solve.ok                     405   -> 345     (-60)
        solve.path.slvs              394   -> 334     (-60)
        solve.unsatisfied            3     -> 3       unchanged
        solve.path.lm                14    -> 14      unchanged (drag60 never
                                                      took the LM path: §5.2
                                                      records lm = 0)
        ffi.slvs.solve.constraints   48071 -> 48071 - 60*(drag60 constraints)
        ffi.slvs.solve.points        46032 -> 46032 - 60*(drag60 points)
        2d.displayGeometry.cacheHit  --    -> 60      NEW counter, a gate NOTE
                                                      rather than a failure
    SPANS:
        2d.displayGeometry     n 120 -> 60, mean UNCHANGED at ~0.1424 ms —
                               the cost of one solve is not what changed
        2d.paint               0.167527 -> 0.11057 ms   (-34.0 %)
        2d.paint.constraints   0.058053 -> 0.00110 ms   (-98.1 %)
        2d.paint.ent.dofColour 0.057173 -> unchanged, it keeps the real solve
        2d.paint.entities      0.050433 -> unchanged
        solve.total            n 408 -> 348, mean 1.6583 -> ~1.92 ms, i.e.
                               the mean RISES ~16 %
    That last line needs saying out loud, because it will read as a regression
    and is not one. It is survivorship: the samples removed are drag60's cheap
    0.14 ms solves, so the surviving pool is more heavily weighted toward the
    stress tier's expensive ones. The TOTAL falls by 8.5 ms; only the mean of a
    smaller pool rises. Any duration-tier finding on solve.total, solve.slvs or
    ffi.slvs.solve should be attributed here before it is attributed to anyone.
    Their n must fall by exactly 60 (408 -> 348, 408 -> 348, 406 -> 346); if it
    does not, this prediction is wrong.
Cross-check against §5.2 (the paired run, a different capture):
    Static painting leaves dragGrip == null, so displayGeometry early-returns
    before the counter and the span; the static phase costs are DRAWING ONLY:
        d(constraints) = 0.0022 ms, d(ent.dofColour) = 0.0010 ms
    Each drag-regime phase is that drawing plus one solve, giving two
    independent estimates of the solve:
        0.2772 - 0.0022 = 0.2750 ms      0.2748 - 0.0010 = 0.2738 ms
    They agree to 0.44 %. On that capture 2d.paint during drag would go
    0.6359 -> 0.3609 ms and the regime share 86.8 % solving -> 76.0 %.
Falsifiable by:
    - 2d.displayGeometry.solves != 60. That is the core claim and it carries no
      interval: any other number means the painter reaches the solve by a path
      I did not account for.
    - 2d.displayGeometry n not halving while its mean stays put — that would
      mean I changed the cost of a solve rather than the number of them.
    - 2d.paint.constraints not collapsing to ~1 microsecond. It is 98.1 % solve
      by the arithmetic above; if it does not collapse, that arithmetic is wrong.
    - 2d.paint.ent.dofColour moving at all. It keeps its solve; if it moves, the
      call I left solving is not the one I think it is.
Risk          :
    - drag60's fixture is small. The solve is superlinear in sketch size, so the
      absolute saving on a real part is larger than 8.5 ms and must not be
      quoted from it.
    - The baseline's 2d.paint spans aggregate 150 frames across scenarios, only
      60 of which drag. The -34.0 % is therefore a figure for the whole painting
      pass, not for a dragging frame; the dragging frame roughly halves.
```

### Prediction P2 — the gauge that will NOT move, and is not a refutation

`quality.frameBudget` (`lib/perf_scenarios_quality.dart`) hardcodes

```dart
final perFrame = ms * 2;   // TWO solves per painted frame
```

with a comment citing the two viewport call sites. That file is the measurement
apparatus, which §3 of the plan puts off limits to **every** session. So:

```
Predicted     : quality.budget.entitiesAt120Hz stays 192
                quality.budget.entitiesAt60Hz  stays 256
                — UNCHANGED, because the scenario still multiplies by two.
Derivation    : the gauge is computed from a hardcoded factor, not observed
                from the painter. Nothing I changed can move it.
Falsifiable by: the gauge moving at all, which would mean somebody edited the
                apparatus and the baseline comparison is void.
```

**Say this out loud at integration:** an unchanged frame-budget gauge is *not*
evidence the fix did nothing. The budget the painter can now actually sustain is
one rung or more up the ladder `[…, 128, 192, 256, 384]`, but the suite will
keep reporting the two-solve figure until the apparatus is corrected. Logged in
`CROSS-SESSION.md` for whoever owns that correction.

### Prediction P3 — the gate goes red, and that is the result

`ci/perf_gate.py` puts any changed counter in `fail`, not in `note`. So a run
against the existing baseline **will exit non-zero**, with at least:

```
COUNTER  2d.displayGeometry.solves: 120 -> 60  (-60) — the amount of work
         changed, not merely its speed
COUNTER  solve.iterationsRequested: 11300 -> 9800  (-1500) — …
COUNTER  solve.ok: 405 -> 345  (-60) — …
COUNTER  solve.path.slvs: 394 -> 334  (-60) — …
new counter   2d.displayGeometry.cacheHit = 60
```

Plan §8 step 3 anticipates this ("Expect it to report counter changes — those
are the wins"). Nobody should re-record the baseline to make it green before the
adjudication in step 4 is written up.

## 6. What I am uncertain about

- **The 5 ppm.** I have shown it is a point on the manifold, not a residual, and
  that it is 31× inside the code's own render tolerance. I have *not* shown that
  no real part exists where a 3e−4 difference at commit matters. The strongest
  counter-argument I can make against myself: `endGripDrag`'s settle runs 80
  iterations with nothing dragged, which pulls both regimes onto the manifold to
  the same residual, and a 3e−4 perturbation is far too small to cross between
  solution branches (branches on this fixture are separated by whole
  millimetres). I believe the risk is negligible. I cannot prove it is zero.
- **Whether the coupled-slot case is representative.** It is the worst fixture I
  could build from the repo's own tests. A device part with hundreds of coupled
  constraints might behave differently, and I have no way to run one.
- **Attributing all 120 baseline `2d.displayGeometry` calls to drag60.** The
  gate's counters are summed across scenarios, so the split is inferred, not
  read: drag60 is the only scenario that drags, and §5.2 counted exactly 120
  there. If another scenario contributes some, the span predictions shift and
  the counter predictions shift with them. The falsifier is cheap — n must fall
  from 120 to exactly 60.
- **The §5.2 cross-check decomposition.** s = 0.2744 ms there rests on
  subtracting two different scenarios' phase costs. Two independent estimates
  agreeing to 0.44 % is good evidence but not proof. It is a cross-check on the
  baseline derivation, not the derivation itself.

## 7. What I deliberately did not do

- **Did not touch `lib/perf*.dart`**, including the `perFrame = ms * 2` line
  that is now wrong. Plan §3 forbids it to every session. Raised in
  `CROSS-SESSION.md` instead.
- **Did not change the solver, `analyzeSketch`, or any call site of it.** That
  is Session 3's, and the `ent.dofColour` phase name misleads exactly the way
  §5.2 warns — the cost in it is the solve, not the colouring.
- **Did not "fix" the glyph/entity inconsistency separately.** Collapsing the
  calls resolves it as a side effect: both now read the same list.
- **Did not re-record `perf/baseline.json`.**
- **Did not claim anything is faster.** No device measurement exists.

---

## 8. Verification — what I ran, and what it said

Per plan §6. Flutter 3.47.0 stable (the channel `subosito/flutter-action@v2`
resolves in `m1-core-build.yml`), Dart 3.13.0.

| Gate | Result |
| --- | --- |
| `flutter analyze --no-pub` | **0 errors.** 55 issues, all `info`/`warning`, all pre-existing — none in a line this session wrote. CI runs it `--no-fatal-infos --no-fatal-warnings`, so this is the same state it was in before. |
| `flutter test` | **2065 passed, 0 failed**, including the 15 new ones. |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | **45 tests, OK.** |

The new tests are in `frontend/test/s4_display_geometry_once_test.dart`, in four
groups:

- *one solve per drag position* — every caller in a frame gets the **same list
  object**; the counters read one solve and three hits; sixty frames cost sixty
  solves rather than a hundred and twenty; a cursor move solves again.
- *painted both ways — where collapsing is exact* — free line, body drag and
  unreachable cursor, each pinned at `maxDelta == 0.0` exactly.
- *painted both ways — the coupled system* — the one case that moves, pinned
  both above zero (if it ever reaches zero the warm start has been changed and
  §3 of this file needs re-deriving) and below 1e-3; and both regimes pinned to
  the same committed constraint residual.
- *the memo invalidates* — a new drag at the same cursor position, the geometry
  list replaced under an unchanged cursor, the sketch switched, and release.
- *the drag still behaves* — M207's no-teleport property re-asserted at one
  solve per frame, and the commit still satisfying its constraints.

`_paintAgainTheOldWay` in that file is how "both ways" is done without keeping a
second copy of the painter: it replaces `s.geometry` with a list holding the
same immutable entities but a new identity, which trips the one cache guard a
test can trip without altering a single number the solve reads. Grip, cursor and
`_lastGoodDragGeo` are untouched, so what comes back is exactly what the old
second call computed.

What none of this establishes: that the application is faster. That needs the
device capture in plan §8, and until then the numbers in §5 are predictions.
