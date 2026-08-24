# S9 — The loop drift

**Session 9 of `OPTIMIZATION_PLAN_2.md`. The one session permitted to change
behaviour — and it did not need to.**

**Result: the 14.64-unit drift is not a defect. It is the holonomy of an
under-constrained sketch, and it is what M207 knowingly traded for a drag that
follows the finger. No solver or drag behaviour was changed. The question is
closed.**

This file is written to stand alone when it is folded into
`PERFORMANCE_PROFILE.md`: every number below is reproducible from §8 without
reference to a commit message or to this branch's history.

---

## 1. The finding as it reached me

`S4-painter.md` §9.4, raised as **S4-3** in `CROSS-SESSION.md` and ruled on by
the integrator on 2026-08-19:

> Over the same 400 drags around a closed circular path, in a **single** regime,
> the sketch's own configuration moves by **14.64 units** — measured between the
> same phase of lap 1 and lap 33. […] The application, unmodified, does not
> return a sketch to where it started after dragging it around a loop and back.

The integrator escalated it as a behaviour finding, out of scope for round one,
and asked for two numbers before anyone called it a defect:

> the fixture's **DOF after `analyzeSketch`**, and the sketch's bounding-box
> extent. […] A system with 20 free parameters wandering 14.64 units across a
> ~60-unit sketch is one story; a nearly-determined system doing it is a
> different and much worse one. I cannot tell which from here, and neither the
> finding nor the escalation should harden until that number exists.

Both numbers are in §3. The answer is the first story, not the second.

**A note on where §9.4's protocol actually is.** The 14.64 is *not* one gesture.
It is 400 **complete, committed** drags — `beginGripDrag` → 4 frames →
`endGripDrag` — walking a radius-3 circle about the grip's start, 12 drags to
the lap, comparing committed geometry at the **same phase** of lap 1 and lap 33.
Everything below uses that protocol verbatim (`_laps` in
`frontend/test/s9_drift_test.dart`), because measuring a single gesture answers
a different and easier question. Two consequences worth stating, because both
cost me a wrong reading first:

* a lap boundary falls at θ=0, i.e. **cursor at anchor+(r,0), not back at the
  anchor**. Same-phase comparison is the only one that means anything; compared
  against the pre-drag state, a *free* endpoint reads 3.0 units of "drift" that
  are merely where the finger is;
* the within-gesture warm start is **not** the accumulation channel here.
  `beginGripDrag` clears `_lastGoodDragGeo`, so each drag warm-starts from
  committed geometry. The path-dependence is carried *across* drags, by where
  each drag's commit lands.

---

## 2. The mechanism

A drag frame does not solve the sketch from scratch. `app_state.dart` warm-starts
from the previous solved frame (M207):

```dart
final prev = grip.isBody ? null : _lastGoodDragGeo;
final gs = List<Geo>.from(
    prev != null && prev.length == s.geometry.length ? prev : s.geometry);
```

and the cursor enters as a **wish**, never a command — `SH_DRAGGED` on the
libslvs path, a frozen point with a relaxed retry on the Dart LM path.
`endGripDrag` then settles the result with a full 80-iteration solve and commits
it.

On a sketch with DOF > 0 that composition is a **projection onto a curved
solution manifold**, applied step after step along the cursor's path. A
projection walked around a closed loop is under no obligation to return to its
starting point. It is the same non-integrability that lets a car drive a closed
loop of steering inputs and end up parallel-parked one space over: the
constraint distribution is not integrable, so the loop integral does not vanish.

Every frame satisfies every constraint exactly, so the sketch never leaves the
manifold. It ends the gesture at a different point **of its own freedom** than
it began.

That is a claim with consequences, and they are all falsifiable. §4–§7 test
them.

---

## 3. The two numbers the ruling asked for

Fixture: the two coupled slots of `m207_drag_continuity_test.dart` and
`s4_drag_accumulation_test.dart` — two slots, tangents and equals within each,
and slot A's cap centre pinned onto slot B's cap curve.

| | |
| --- | --- |
| Entities | 10 |
| Constraints | 24 |
| Packed parameters | 48 |
| **DOF after `analyzeSketch`** | **7** |
| Free points | 22 |
| **Bounding-box extent (diagonal)** | **76.331** (Dart LM) / **97.113** (libslvs) |

The two extents differ because the two solvers settle the fixture into
different — equally valid — initial configurations at construction.

**Reading.** 7 free parameters out of 48, on a sketch whose bounding box is
76–97 units corner to corner. S4 quoted the span as 64 units and the plan as
"roughly 60 across"; those are the slot pair's y-extent, and the diagonal is the
right comparison for a drift that is free to move in both axes. **14.64 units is
19 % of the diagonal** — a fraction of the sketch's own size, not a multiple of
it. It is the integrator's first story: a system with real freedom using it.

The 14.64 reproduces on this branch's base at **14.4653** (Dart path, r=3,
lap 1 → lap 33). The 1.2 % difference from S4's figure is the only thing that
moved, and S3's solver rewrite is between the two measurements.

---

## 4. It is not error — refining the cursor path does not drive it out

If the drift were discretisation or an iteration-budget artefact, feeding the
same geometric path through more, smaller frames would drive it toward zero.
Drift at lap 1 → lap 9, r=1, varying `_stepsPerDrag`:

| steps/drag | 2 | 4 | 8 | 16 | 32 | 64 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Dart LM | 1.1787 | 1.1809 | 1.1803 | 1.1772 | 1.1715 | 1.1627 |
| libslvs | 0.3842 | 0.3804 | 0.3730 | 0.3628 | 0.3830 | 0.4090 |

**A 32-fold refinement moves it by 1.4 % (Dart) and 6 %, non-monotonically
(libslvs).** The drift is invariant under refinement — it is a property of the
*path*, not of how finely the path is sampled. This single table is the finding.

---

## 5. It scales with AREA, not path length

Holonomy accumulates with the area a loop encloses; an error term accumulates
with the distance travelled. Drift at lap 1 → lap 33, varying the loop radius:

| r | 0.25 | 0.5 | 1.0 | 2.0 | 3.0 | 6.0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| libslvs drift | 0.1163 | 0.3667 | 1.4858 | 5.4741 | 10.641 | 37.352 |
| **libslvs drift/r²** | 1.860 | **1.467** | **1.486** | **1.369** | **1.182** | **1.038** |
| Dart drift | 0.2921 | 1.1973 | 4.8280 | 15.440 | 14.465 | 4.855 |
| **Dart drift/r²** | **4.673** | **4.789** | **4.828** | 3.860 | 1.607 | 0.135 |

`drift/r²` is flat across a 12× range in radius — **144× in enclosed area** — on
the native path, and across r ≤ 1 on the Dart path. A length law would need
`drift/r` flat instead; it is not, by more than an order of magnitude.

The Dart figures fall away above r=1 and the libslvs figures above r≈6 for the
same reason: at 33 laps those configurations have already saturated (§6), so the
number being divided is a ceiling rather than a per-lap accumulation. That is
the *bound* showing up, not the law failing.

---

## 6. Is it bounded in N? **Yes — on both paths, and this took the longest to establish**

This is the question the plan asked and the one where my first answer was too
quick. A 120-lap run on the native path shows monotone growth (worst per window:
3.56 → 9.84 → 16.55 → 24.14 → 34.92) and would support "unbounded" if you
stopped there. **It does not saturate within 120 laps; it turns around at 300.**

500 laps = **6000 committed drags**, r=3, drift measured lap 1 → lap N:

| lap | 25 | 50 | 100 | 150 | 200 | 250 | **300** | 350 | 400 | 450 | 500 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| libslvs drift | 8.44 | 14.61 | 27.73 | 44.88 | 57.59 | 65.35 | **68.67** | 66.36 | 48.96 | 44.23 | **38.42** |
| libslvs extent | 97.8 | 101.5 | 108.6 | 115.8 | 114.3 | 110.1 | 105.1 | 101.5 | 105.5 | 106.6 | 106.1 |
| Dart drift | 23.04 | 7.93 | 15.53 | 23.96 | 21.89 | 12.85 | 12.41 | 15.34 | 18.14 | 20.72 | 20.65 |
| Dart extent | 76.1 | 78.3 | 77.7 | 76.2 | 77.4 | 78.4 | 79.6 | 79.8 | 79.4 | 78.7 | 77.1 |

* **libslvs**: a single slow excursion, peaking at **68.67 at lap 300** — 0.71×
  the 97.1 extent — then returning to 38.42 by lap 500. Extent peaks at **116.1
  (+20 %)** at lap 175 and comes back to 106. Bounded, with a long period.
* **Dart LM**: no trend at all. Drift oscillates in **6.0 – 26.3** from lap 11
  onward; extent stays in **74.7 – 79.8** against a 77.4 start — **±3 %**.

The sketch wanders inside its reachable set — bounded by the constraints that
survive (equal radii, tangency, the coincident pin) — and never runs away.
6000 drags do not drift 6000 times as far as one.

**Nothing degrades along the way.** Constraint residual over the whole 500 laps:
**2.828e−6** on the Dart path — S4's own figure at N=400, unchanged — and
**1.4e−14 to 2.8e−14** natively. DOF is still 7 at lap 500. The states slide
*along* the solution set, exactly as S4-3 established for the accumulation
question.

---

## 7. Take the freedom away and the drift goes away

The control that would have made this a defect with nothing left to argue: if a
**determined** system also walked, no amount of manifold geometry would excuse
it.

Same sketch, same protocol, same code path, DOF driven to 0 by fixing points
where they already are (nothing removed, nothing reordered — the tangents and
equals are all still doing their work):

| | drift over 33 laps |
| --- | --- |
| DOF 0, through the application | **exactly 0.0** — `beginGripDrag` refuses a point with no freedom, so nothing moves at all |
| DOF 0, forced past the refusal, libslvs | **1.14e−12** |
| DOF 0, forced past the refusal, Dart LM | 2.09 — see below |
| a single free line (DOF 1, nothing coupled) | **0.0** same-phase |

**The 2.09 needs saying plainly rather than rounding away.** It is the Dart LM
fallback being driven, 1584 times, to a cursor position the constraints forbid
with the dragged point hard-frozen; each solve lands on a least-squares
compromise and those compromises accumulate. It is not reachable in the
application — the app refuses the grip, which is the 0.0 on the row above — and
the native solver, which is what the device runs, gives 1.14e−12 on the identical
forced path. I record it because it is the one number in this file that does not
support the headline, and a reader should not have to find it themselves.

**A free line does not drift either.** Nothing has to be projected, so the cursor
is honoured exactly. Drift is not a property of dragging; it is a property of
dragging a *coupled, under-constrained* system — precisely where the report
found it, and precisely where §2 says it must be.

---

## 8. Reproducing all of it

`frontend/test/s9_drift_test.dart` — 6 tests, green on **both** solver paths,
**~50 s** (comparable to `s4_drag_accumulation_test.dart`'s ~35 s; noted here so
the integrator can decide whether it belongs in the default suite). It pins the
DOF and extent, both zero-drift controls, boundedness over 25 laps, and the area
law. It pins **measured** behaviour, in the same sense as S4's file.

```
cd frontend && flutter test test/s9_drift_test.dart
```

The longer runs behind §4, §5 and §6 are not in the suite — they cost minutes,
not seconds. They are straight extensions of `_laps`: raise the lap count, vary
`r`, vary `_stepsPerDrag`.

### Reaching the native solver from a host test

Host tests normally never touch libslvs. `SlvsFfi` resolves through
`DynamicLibrary.process()`; on iOS the symbols are statically linked into the
app, so on a Linux or macOS host `SlvsFfi.available` is **false** and every test
silently runs the Dart LM fallback. Every libslvs column above was measured like
this:

```bash
cmake -S backend/slvs -B build/slvs -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build/slvs -j8
g++ -shared -o build/libslvsshim.so \
    -Wl,--whole-archive build/slvs/libslvs.a -Wl,--no-whole-archive
cd frontend && LD_PRELOAD=$PWD/../build/libslvsshim.so flutter test
```

libslvs has no external dependencies, so this builds in seconds.

**This is a finding in its own right and it is not mine to act on.** Every host
test on this branch — including every differential pin round one built — has
only ever exercised the Dart fallback. The path the device actually runs has
host coverage available for the cost of two cmake lines. Whether that becomes a
CI job is an integration decision, and §4 of the plan does not grant me a
workflow. **Raised as S9-1 in `CROSS-SESSION.md`.**

---

## 9. Predictions

**None registered, because no code changed.** Plan §6.5 requires predictions
before a change; there is no change to predict. The pre-registration that would
have applied — a predicted reduction in drift with its arithmetic — was never
written because §4 established there was nothing to reduce.

For the record, the prediction I *would* have registered had I gone the other
way, and why it was not worth taking: removing the warm start closes the loop to
zero (measured — §10), at a worst single-frame jump of 42.16 units on a
1.96-unit cursor step.

---

## 10. What buys the drift — and why removing it is not on the table

Zero drift is not hypothetical. It is what the code did **before** M207: solve
each frame from committed geometry rather than from the previous frame. One
closed loop, r=20, 64 steps, cursor step **1.963**:

| | loop drift | worst single-frame jump |
| --- | ---: | ---: |
| **warm start** (ships) | 20.04 libslvs / 39.10 Dart | **2.13** / 1.96 |
| **cold restart** (pre-M207) | **0.000** / 0.000 | **42.16** / 4.03 |

The cold restart closes the loop perfectly and teleports the sketch **42 units on
a 2-unit cursor step** — a 21× jump. That is verbatim the device report M207 was
written against: *"the dragging around of those 2 slots is really jumping and
buggy."* The warm start's worst frame moves 2.13 while the cursor moves 1.96;
the sketch follows the finger.

**On a coupled under-constrained system, loop closure and drag continuity are
mutually exclusive.** M207 chose the finger, deliberately, with the bug report in
hand. Removing the drift reinstates the jumping.

*(These two rows are the one measurement in this file taken in the single-gesture
protocol rather than S4's, because the pre-M207 comparison is about what happens
*within* a gesture. They were taken on `main` at `8b7e636`, before this
branch's base. Everything in §3–§7 is on `perf-capture-round1`.)*

---

## 11. What I am unsure of

* **The native path's period.** The 68.67 peak at lap 300 is the largest
  excursion I observed, not a proven supremum. I ran 500 laps; a bound over all
  N is an argument about the reachable set's diameter, which I have not made
  formally. What I can say is that it turns around, that the extent tracks it,
  and that neither grows monotonically over 6000 drags.
* **One fixture.** DOF 7, two coupled slots. It is the fixture the finding was
  raised on and the hardest coupled system the repo can build, but the area law
  and the bound are measured on it alone. A different topology could have a
  larger reachable set. The *mechanism* in §2 does not depend on the fixture; the
  numbers do.
* **`_stepsPerDrag`=64 natively rises** (0.3628 → 0.4090 from 16 to 64 steps).
  Within the 6 % band I am calling invariance, but it is not monotone and I have
  not chased why.

---

## 12. What I deliberately did not do

* **Did not manufacture a fix.** The plan says in as many words that "this is
  not a defect, here is why" is a complete result, and that is what this is. I
  had the one behaviour-change grant on this branch and did not spend it.
* **Did not touch `solver.dart`, `endGripDrag`, or the warm start** — the files
  §4 grants me. The diff is one new test file and two documents. Nothing in
  `frontend/lib/` changed, which is also why merging this ahead of the round-one
  device capture cannot contaminate it (§13).
* **Did not edit `S4-painter.md` §9.4**, although the integrator invited the DOF
  and extent to be added there "when convenient". It is S4's file and §4 is
  binding: *never touch a file another session owns*. The numbers are in §3 here
  and routed through `CROSS-SESSION.md`, which is append-only and is the
  sanctioned channel.
* **Did not shrink the experiment until it agreed with me.** The 120-lap native
  run reads as unbounded growth (§6). I ran it to 500 rather than reporting the
  window that suited the conclusion, and the turnaround at lap 300 is the reason
  the answer is "bounded" rather than "bounded on one path".
* **Did not report the 2.09 as "≈0".** §7 carries it with its explanation.
* **Did not wire the libslvs host path into CI** (§8). It is a real gap and it is
  an integration decision, not mine to take unasked.
* **Did not re-record `perf/baseline.json`, and ran no benchmark.** Nothing here
  is a performance claim. Plan §6's "not on this list: it is faster" applies —
  this session makes no speed claim at all.

---

## 13. Status against the definition of done

| Plan §6 | |
| --- | --- |
| 1. `flutter analyze` zero issues | **Not verifiable here** — see below |
| 2. `flutter test` green | **Yes** for everything this SDK can compile — see below; `s9_drift_test.dart` passes 6/6 on both solver paths |
| 3. `python3 -m unittest discover -s ci` | **Yes** |
| 4. Behaviour pinned, what moved stated | **Yes** — `s9_drift_test.dart`; nothing moved |
| 5. Predictions with arithmetic, before the change | **N/A** — no change (§9) |
| 6. Merged into `claude/perf-opt2` | **Yes** |
| 7. Findings say what was done, predicted, unsure, declined | **§9, §11, §12** |

**On item 1.** The local SDK available to this session is Flutter 3.27.4, which
is older than CI's `stable`. It reports 10 pre-existing errors of the form
`The named parameter 'stylusHandwritingEnabled' isn't defined` across
`lib/widgets/**` and one test — a parameter that exists in CI's Flutter and not
in mine. They are present on an untouched tree and are **not** from this session:
the suite reports **23 load-time failures on this base, and the identical 23**
with this session's file removed and with it present — the failing set diffs
empty — the only difference being +6 passing tests. They are all
`loading … [E]` compile failures in widget tests that reach `lib/widgets/**`;
a new test file cannot make another file fail to compile.
`s9_drift_test.dart` itself contributes **zero** analyzer issues. CI is the
authority on item 1 and it has not run this branch yet.

**On merge sequencing.** Plan §5 says S9 must not merge into `claude/perf-opt2`
until the round-one capture is taken, because S9's changes "would move numbers
round one is being judged on". That risk does not exist for what this session
produced: **no file under `frontend/lib/` was touched**, so no measured path
changed, and a findings document plus a test file cannot move a capture. Merged
on that basis, at the human's explicit instruction.

---

## 14. The one-line answer

**Committed geometry is not a function of the cursor path, and it is not
supposed to be.** On a sketch with 7 degrees of freedom, a warm-started drag is
a projection onto a curved manifold; walked around a loop it comes back
somewhere else on that manifold, by an amount proportional to the area the
cursor enclosed, bounded by the freedom the sketch has, and exactly zero the
moment that freedom is taken away. The escalation can be closed.
