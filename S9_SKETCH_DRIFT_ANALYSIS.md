# S9 — "The drag that does not come back" — Analysis

Report: *dragging a sketch around a closed loop leaves it 14.64 units from where it
started, unmodified.*

**Verdict: not a defect.** The number is real and reproducible at any magnitude you
care to name, but it is the *holonomy* of an under-constrained sketch, and it is
precisely what M207 traded for a drag that follows the finger. Zero drift is
available, was measured, and is the bug M207 fixed. Nothing was changed in the
solver or the drag path; one regression test was added so a later session does not
"fix" this.

Everything below is measured, not argued. Reproduction instructions are at the end.

---

## 0. What could not be checked

The brief points at `OPTIMIZATION_PLAN_2.md`, `perf/findings/S4-painter.md` §9, the
S4-3 entry, and the integrator's ruling in `CROSS-SESSION.md`. **None of those files
exist in this repository, on any branch, at any commit** (`git log --all
--diff-filter=A -- …` finds nothing, and there is no `perf/` directory). So the
original fixture and the exact 14.64 could not be read back, and this analysis
rebuilds the question from the code instead.

The fixture used here is the one the repository already keeps for exactly this
class of question: the two coupled slots of `test/m207_drag_continuity_test.dart`,
which are the device's own auto-constrained pair from `bug20260805T180020`. 14.64 is
an ordinary point on the curve measured below — it falls between the r=16 and r=20
loops on the native solver — so whatever the original fixture was, the phenomenon is
the same one.

This document follows the repository's own convention for this kind of write-up
(`M182_ANALYSIS.md`, `M214_STEP_EXPORT_ANALYSIS.md`) rather than the absent
`perf/findings/` layout.

---

## 1. The mechanism, from the code

A drag frame does **not** solve the sketch from scratch. `app_state.dart:8058`
warm-starts from the previous solved frame:

```dart
final prev = grip.isBody ? null : _lastGoodDragGeo;
final gs = List<Geo>.from(
    prev != null && prev.length == s.geometry.length ? prev : s.geometry);
```

and the cursor enters as a *wish*, not a command — `SH_DRAGGED` on the native path
(`solver.dart:1398`), a frozen point with a relaxed retry on the Dart LM path
(`solver.dart:2159`).

On a sketch with DOF > 0 that composition is a **projection onto a curved solution
manifold**, applied step after step along the cursor's path. A projection walked
around a closed loop in cursor space is under no obligation to return to its
starting point. It is the same non-integrability that lets a car drive a closed loop
of steering inputs and end up parallel-parked one space over. Every frame still
satisfies every constraint exactly, so the sketch never leaves the manifold — it
merely ends the gesture at a different point *of its own freedom* than it began.

That is a prediction, and it makes four falsifiable claims. All four were tested.

---

## 2. The measurements

Fixture: two coupled slots, **DOF 7**, extent (bbox diagonal) **76.3** on the Dart
path / **97.1** on the native path (the two solvers pick different, equally valid,
initial configurations). The grip is rail 0's far end; the cursor walks a circle of
radius *r* in *N* steps and lands **exactly** back on its start, so any residue is
the solver's and not the caller's arithmetic. "Drift" = furthest any defining point
of the sketch ended from where it began.

Both solver paths were exercised: the Dart LM fallback, and the real **libslvs**
path the device uses (built for the host and injected with `LD_PRELOAD`, see §5).

### 2.1 Refining the cursor path does not drive it out — so it is not error

r = 20, increasing step count:

| steps | 8 | 16 | 32 | 64 | 128 | 256 | limit |
|---|---|---|---|---|---|---|---|
| libslvs | 13.32 | 17.16 | 19.13 | 20.04 | 20.47 | 20.67 | ≈ **20.9** |
| Dart LM | 32.94 | 37.70 | 38.89 | 39.10 | 39.150 | 39.151 | ≈ **39.15** |

First-order convergence — the gap halves on each doubling — onto a **non-zero**
limit. A discretisation or iteration-budget artefact would converge to zero. This
one does not, and that single table is the finding: the drift survives an
arbitrarily fine cursor path.

### 2.2 It is proportional to the AREA the cursor encloses

| r | 0.25 | 0.5 | 1 | 2 | 4 | 8 | 16 | 32 |
|---|---|---|---|---|---|---|---|---|
| libslvs drift | 0.0052 | 0.0153 | 0.0530 | 0.2087 | 0.804 | 2.99 | 12.11 | 28.38 |
| libslvs drift/r² | 0.083 | 0.061 | 0.053 | 0.052 | 0.050 | 0.047 | 0.047 | 0.028 |
| Dart drift | 0.0103 | 0.0432 | 0.1762 | 0.7155 | 2.93 | 17.14 | 30.23 | 43.89 |
| Dart drift/r² | 0.165 | 0.173 | 0.176 | 0.179 | 0.183 | 0.268 | 0.118 | 0.043 |

`drift/r²` is flat to a few percent across a 16× range in *r* — a 256× range in
enclosed area — then saturates once the loop is comparable to the sketch itself and
the manifold's reachable set runs out. **Area-proportional is the signature of
holonomy.** An error term would scale with the path *length*, i.e. with r¹.

### 2.3 It is bounded in N — it does not accumulate

200 consecutive loops inside one gesture, r = 20, 32 steps each:

| after loops | 1 | 2 | 5 | 10 | 20 | 60 | 100 | 140 | 200 |
|---|---|---|---|---|---|---|---|---|---|
| libslvs drift | 19.1 | 43.1 | 47.1 | 61.8 | 52.7 | 50.9 | 50.3 | 49.8 | **49.0** |
| libslvs extent | 94.2 | 87.0 | 99.8 | 86.0 | 94.4 | 89.6 | 89.7 | 91.3 | **93.5** |
| Dart drift | 38.9 | 42.1 | 39.1 | 38.9 | 44.9 | 48.3 | 48.3 | 48.3 | **48.3** |
| Dart extent | 93.4 | 94.2 | 104.2 | 94.1 | 98.0 | 122.2 | 122.3 | 122.4 | **122.5** |

The drift settles into a band (libslvs 19–62, worst 61.8; Dart 23–52, worst 52.1)
and then onto an attracting cycle. It is **not a ratchet**: 200 loops do not drift
200 times as far as one. The sketch's size ends within **5 %** of where it started
on the native path and within **60 %** on the Dart path — bounded, not runaway.
Constraint residual after 200 loops: **1.4e-14** (libslvs), **1.5e-8** (Dart). DOF
is still 7. The drifted sketch is a perfectly legitimate solution of exactly the
same system.

### 2.4 Take the freedom away and the drift goes away

Same sketch, same loop, same code path, with the DOF driven to 0 by fixing points
where they already are (nothing removed, nothing reordered):

| | drift |
|---|---|
| DOF 0, via the app | **drag refused** — `beginGripDrag` will not grip a point with no freedom (`app_state.dart:8274`) |
| DOF 0, forced straight at the solver | **2.0e-12** (libslvs) / 1.0e-3 (Dart LM — its iteration budget, not drift) |
| a single free line, DOF 1, nothing coupled | **0.0** (libslvs) / 5.3e-10 (Dart) |

Drift is not a property of dragging. It is a property of dragging a *coupled,
under-constrained* system — exactly where the report found it, and exactly where the
theory says it must be.

---

## 3. What the drift buys — the trade-off M207 made

Zero drift is not hypothetical. It is what this code did **before** M207: solve each
frame from the committed geometry instead of from the previous frame. Same fixture,
same closed loop, r = 20, 64 steps, cursor step **1.963**:

| | loop drift | worst single-frame jump |
|---|---|---|
| **warm start** (what ships) | 20.04 (libslvs) / 39.10 (Dart) | **2.13** / 1.96 |
| **cold restart** (pre-M207) | **0.000** / 0.000 | **42.16** / 4.03 |

The cold restart closes the loop perfectly — and teleports the sketch **42 units on
a 2-unit cursor step**, a 21× jump. That is verbatim the device report M207 was
written against: *"the dragging around of those 2 slots is really jumping and
buggy."* The warm start's worst frame moves 2.13 while the cursor moves 1.96: the
sketch follows the finger.

**On a coupled under-constrained system, loop closure and drag continuity are
mutually exclusive.** M207 chose the finger, deliberately and with the bug report in
hand. Removing the drift means reinstating the jumping.

---

## 4. Why there is nothing to fix

* The drift is **correct behaviour**, not an error: it survives refinement (§2.1)
  and scales with area, not path length (§2.2).
* It is **bounded** (§2.3). The sketch cannot be walked off the page by shaking it.
* It only ever moves the sketch **within its own declared freedom** — residual
  1e-14, DOF unchanged (§2.3) — which is what dragging an under-constrained sketch
  is *for*.
* It **vanishes** the moment the freedom does (§2.4), which is the user's own lever:
  a sketch that must not move under a drag is a sketch that should be constrained,
  and Inventor answers this the same way.
* The only known way to remove it reinstates a fixed device bug (§3).

The right response to "my sketch moved when I dragged it" on a DOF-7 sketch is that
it was free to move. No behaviour was changed.

---

## 5. Reproduction

`test/sketch_loop_drift_test.dart` (added by this commit) pins the parts that must
never change: no drift at DOF 0, no drift on a free line, drift bounded over 40
loops, and drift falling off with area rather than length. Six tests, green on
**both** solver paths.

```
cd frontend && flutter test test/sketch_loop_drift_test.dart      # Dart LM path
```

Host tests normally never reach the native solver — `SlvsFfi` resolves through
`DynamicLibrary.process()` (`lib/ffi/slvs_ffi.dart:149`) and on iOS the symbols are
statically linked into the app, so on a Linux host `SlvsFfi.available` is false and
every test silently runs the Dart fallback. It can be reached, which is how the
libslvs columns above were measured:

```
cmake -S backend/slvs -B build/slvs -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build/slvs -j8
g++ -shared -o build/libslvsshim.so \
    -Wl,--whole-archive build/slvs/libslvs.a -Wl,--no-whole-archive
cd frontend && LD_PRELOAD=$PWD/../build/libslvsshim.so flutter test
```

libslvs has no external dependencies, so this builds in seconds. Worth knowing
independently of this investigation: **every host test in this repository currently
runs the Dart fallback solver only**, and the native path — the one the device
actually uses — has host coverage available for the cost of two cmake lines. Not
wired into CI here; that is a separate decision.

---

## 6. Status

**No change requested.** No solver or drag behaviour was modified, so there is
nothing for the integrator to rule on: the S9 behaviour-change permission was not
used. What is in this commit is one regression test and this document.
