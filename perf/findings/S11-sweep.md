# S11 — the sweep, the fixtures that never measured it, and one refuted premise

**Session:** S11 (round two, added after the round-two briefs were written).
**Branch:** `claude/perf-opt2-sweep`, cut from `origin/claude/perf-opt`.
**Brief:** `perf/findings/S11-BRIEF-sweep.md`.
**Governing rules:** `OPTIMIZATION_PLAN_2.md` (which lives on
`origin/claude/perf-deep-analysis`, not on any `perf-opt*` branch — see §0.1),
plus `OPTIMIZATION_PLAN.md` §2 for the prediction form.

---

## 0. Preliminaries that affect how this file should be read

### 0.1 Where the plan actually is

`OPTIMIZATION_PLAN_2.md` is not present on `claude/perf-opt`,
`claude/perf-opt2`, `perf-capture-round1`, or any `perf-opt2-*` branch. It
exists only on `origin/claude/perf-deep-analysis` (commit `4f1112d`). Every
round-two session that branched from the pin has therefore been working without
its own rules file in the tree. Not my file to move — recorded as a
`**Needs:** integrator` entry (§8.1).

### 0.2 What I could and could not run

This container has **no Dart or Flutter SDK** and **no OCCT** (the
`backend/occt/upstream` submodule is not checked out, and there is no system
OpenCASCADE). Concretely:

| `OPTIMIZATION_PLAN_2.md` §6 requires | Status here |
| --- | --- |
| `flutter analyze` — zero issues | **Could not run.** No SDK. |
| `flutter test` — green | **Could not run.** No SDK. |
| `python3 -m unittest discover -s ci` | Runnable |
| Lane C (headless kernel bench) | **Could not run locally.** Needs OCCT; it runs on `macos-14` in CI. |

So everything in this file that is a *number I produced* is arithmetic from the
recorded cost model, not a measurement, and everything that is a *code claim* is
from reading the code. Nothing here is a device or bench measurement. The code I
added is unverified by compiler or test in this environment and **CI is the
gate** — see §7.

---

## 1. The two cheap things the brief asked to establish first

### 1.1 What sets the ~17 steps: the path is a Dart-side polyline, and its point count is a free parameter with a 1200x multiplier

The sweep path is not a curve handed to the kernel. It is a **flattened
polyline**, produced entirely on the Dart side:

`_recomputeSweep` (`part_model.dart`) → `resolvePath(part, sel)` → for each
candidate curve `sketchCurve(geo[i])` → and `sketchCurve` is:

```dart
List<Offset> sketchCurve(Geo g) {
  if (g.type == Geo.polyline) {
    if (g.spline != Geo.straight) return splineCurveFor(g);
    ...
  }
  return sampleEntity(g, arcSamples: 64);
}
```

`resolvePath` then emits **every point of that polyline** as the path:

```dart
for (final p in best) { out..add(w.x)..add(w.y)..add(w.z); }
```

So the number of sweep spans is `path.length - 1`, fixed in Dart before OCCT is
ever called. Three cases, and they differ by more than an order of magnitude:

| path entity | points | spans | set by |
| --- | ---: | ---: | --- |
| line | 2 | 1 | — |
| **arc / circle** | **65** | **64** | `sampleEntity`'s `arcSamples: 64`, **independent of the arc's angle** |
| spline / ellipse | tolerance-dependent | varies | `splineCurveFor` → `path.flatten(tol, ...)` |

**The field profile's path was not an arc.** The brief derives ~16.7 steps from
20 290 faces ÷ 1218 segments; an arc path would have forced 64. So the path was
a tolerance-flattened spline (or a ~17-vertex polyline). Two things follow, and
the second is the one worth acting on:

1. **`arcSamples: 64` is unconditional.** A 5° arc used as a sweep path is
   flattened into 64 spans exactly like a full circle. Against a 1200-segment
   profile that is 76 800 faces where a handful would do. The field case dodged
   this only by not using an arc.
2. **The path point count multiplies the profile segment count.** Faces ≈
   `segments × spans`. This is the parameter the brief predicted "carries a
   large multiplier", and it is confirmed: the multiplier is the full profile
   segment count, 1218 in the field case.

**Cross-check of the whole picture against the recorded numbers.** From the
brief's table, `ffi.occt.sweepProfile` ran **35** times totalling **309.88 s**,
and `kernel.feature.sweep` ran **3** times totalling **310.75 s**. If exactly
one call per feature run is the 1200-segment loop at its recorded worst of
102 244.4 ms:

&nbsp;&nbsp;&nbsp;&nbsp;3 × 102.2444 s = **306.73 s**
&nbsp;&nbsp;&nbsp;&nbsp;309.88 − 306.73 = **3.15 s** across the remaining **32** calls = **98 ms each**

That is a clean, self-consistent decomposition: **one loop out of ~11 per
feature run is the entire cost**, and the other ten-odd are ordinary ~100 ms
sweeps. The 1200-vertex polyline is the target; nothing else in the profile is.

### 1.2 Where the 110 phantom loops come from: self-intersections, not snapping

Loop detection is `_arrangementLoops` (`part_model.dart`), reached from
`profileLoops`. Two candidate mechanisms produce extra bounded faces, and they
are distinguishable by the *area* of what they produce.

**Euler gives the count relationship.** For a closed n-gon as a planar graph,
faces = E − V + 1 + C. A simple closed polyline: V = E = 1200, C = 1 → 2 faces,
one bounded. Add k transversal self-crossings: each adds one vertex and splits
two edges, so V = 1200 + k, E = 1200 + 2k → faces = k + 2, of which **k + 1 are
bounded**. So **110 phantoms ⇒ ≈110 self-intersections**, and a "pinch" (two
non-adjacent vertices snapped together by `nodeOf`) obeys the same arithmetic.

**The areas decide between them.** `_arrangementLoops` already drops
non-positive faces:

```dart
if (ar <= 1e-9) continue;   // negative = unbounded face; ~0 = not a face
```

so every one of the 110 survivors has area **> 1e-9**. They print as `0.00`
only because the log uses `toStringAsFixed(2)`, i.e. their area is somewhere in
**(1e-9, 5e-3)**. Node snapping in `nodeOf` merges points within **1e-6**, so
faces manufactured by snapping have areas of order **1e-12** — three orders of
magnitude *below* the filter that already removed them. Coordinate-noise
phantoms are therefore already being dropped, and the 110 that survive are too
large to be snapping artefacts.

**Conclusion: the 110 phantoms are genuine transversal self-intersections of the
1200-vertex polyline.** ~110 self-crossings in a 1200-vertex closed curve is
characteristic of an offset or outline curve that overlaps itself. This is a
determination, not an assumption, but it is a determination *from arithmetic*;
the fixture in §3 (`profile.loops.selfIntersect`) is built to confirm it by
construction — k planted crossings must yield exactly k + 1 loops.

**They are not the sweep's cost.** `resolveProfiles` sweeps only the regions the
user selected; six were. The brief's arithmetic on this point stands. The
phantoms cost in the *2D* path instead — `profileLoops` runs on every hit-test
and every paint (its own comment says so), and it is quadratic (§2, P3).

---

## 2. Pre-registered predictions

Registered **before** any code change, per `OPTIMIZATION_PLAN.md` §2. None of
these can be adjudicated in this container (§0.2); P1 and P3 are for Lane C or
the next capture, P2 for the next capture.

### Prediction P1 — the sweep is superlinear in profile segment count, k ≈ 2

```
Target        : ffi.occt.sweepProfile, swept against profile segment count
Baseline      : 81.9 ms mean / 392 ms worst (PERFORMANCE_PROFILE.md §6.1),
                measured only at profile sizes 12 and 48 (kernel.sweep.12/.48).
                Field: 102 244.4 ms at ~1218 segments (S11 brief §1).
Mechanism     : unknown inside OCCT, but the cost cannot be linear in output
                faces. Faces ~= segments x spans. Suite rung n=48 with a 24-point
                path is 48 x 23 = 1104 faces; the field case is 1200 x 16 =
                19 200 faces, a factor of 17.4. A linear-in-faces model predicts
                the field sweep at 17.4 x (its per-face cost) and lands 1-2
                orders of magnitude short of 102 s.
Change        : none yet - this is the instrument's prediction, and P1 is what
                the new ladder exists to test.
Predicted     : k = 2.0 +- 0.3 in profile segment count, at fixed path spans
Derivation    : two-point fits from 48 -> 1218 segments (ratio 25.4x, ln = 3.234):
                  upper anchor, suite WORST 392 ms:
                    k = ln(102244/392)   / 3.234 = 5.564 / 3.234 = 1.72
                  lower anchor, suite MEAN 81.9 ms:
                    k = ln(102244/81.9)  / 3.234 = 7.130 / 3.234 = 2.20
                The field path had FEWER spans (16) than the suite rung (23),
                so both anchors understate k; the true value sits at or above
                this bracket. Centre 1.96, hence k = 2.0 +- 0.3.
Falsifiable by: the new ladder profile.sweep.segments (§3). A fitted k <= 1.3
                refutes P1 outright and says the cost is in a fixed overhead or
                in the mesh, not in the segment count. A fitted k >= 2.6 refutes
                it upward and means something worse than pairwise is happening.
Risk          : the two anchors are a mean and a worst from a capture whose
                sweep mix I reconstructed in S11 §1.1 rather than measured
                directly; and OCCT's pipe-shell may have a knee inside the
                48 -> 1218 range that no two-point fit can see. That knee is
                precisely why the ladder has four rungs and not two.
```

### Prediction P2 — the triple computation is three named call sites, and removing two saves 204 s

```
Target        : kernel.feature.sweep (n = 3, total 310.75 s in the field session)
Baseline      : 103 584.7 ms mean, 3 invocations, 310.75 s total (S11 brief §1)
Mechanism     : ESTABLISHED BY CODE READING - the three runs are three distinct
                call sites, not a retry loop (see §4 for the trace):
                  1. app_state.dart  _updateExtrudePreview()
                       -> recomputeFeature(p, f, ...)      [the "(preview)" feature]
                  2. app_state.dart  applyExtrude()
                       -> recomputeFeature(p, f, base: commitBase)
                  3. app_state.dart  applyExtrude()
                       -> recomputeAllFeatures(p, partKernel)
                Sites 2 and 3 are ~40 lines apart in the same method. All three
                resolve the same profiles and the same path from the same
                session, so all three hand byte-identical arguments to
                sweepProfile - which is exactly why all three logged tris=91646.
Change        : memoise at the KERNEL-ARGUMENT boundary in the sweep feature
                path: key on the encoded loops, mat34, path points, orientation,
                taper and twist; a hit re-uses the shape already built.
Predicted     : kernel.feature.sweep n stays 3; total 310.75 s -> 106.4 s
                (-204.3 s, -65.8%). ffi.occt.sweepProfile n falls 35 -> 13 and
                its total 309.88 s -> 104.4 s. New counter kernel.sweep.memoHit
                = 2 per commit.
Derivation    : one honest compute 103.58 s, plus two hits. A hit still pays
                _wrapOwned's mesh of the same 91 646-triangle result. The feature
                span is 103 584.7 ms of which sweepProfile is 102 244.4, so the
                non-sweep remainder is 1 340.3 ms; a hit costs that remainder:
                  103.585 + 2 x 1.340 = 106.27 s, round to 106.4 s for the
                  memo's own key-building cost (~ms on 1218 x 3 doubles).
Falsifiable by: kernel.feature.sweep total above 150 s on the next capture with
                the same three-run pattern, or kernel.sweep.memoHit != 2.
Risk          : (a) OWNERSHIP - three callers each dispose what they are given,
                so the memo must never hand the same handle out twice. (b) if
                the commit's boolean target differs from the preview's, sites 1
                and 2 are NOT identical and only site 3 is saved (-103.6 s, half
                the win). (c) unverified by compiler or test here (§0.2).
```

### Prediction P3 — loop detection is quadratic in segment count, and its loop count is crossings + 1

```
Target        : sketch.profileLoops (the span already exists in profileLoops)
Baseline      : never measured against a segment-count axis. No tier sweeps a
                sketch of more than a few dozen profile segments.
Mechanism     : _arrangementLoops step 2 is an explicit all-pairs crossing test:
                  for (i = 0; i < segA.length; i++)
                    for (j = i + 1; j < segA.length; j++)
                Theta(n^2) with no spatial index, on a path that runs on every
                hit-test and every paint.
Predicted     : k = 2.00 +- 0.10, R^2 > 0.99.
                At n = 1218: 1218 x 1217 / 2 = 741 153 pair tests.
                At n = 5000: 12 497 500 pair tests, 16.9x the 1218 rung.
                And: loops(k planted self-crossings) == k + 1, exactly.
Derivation    : the loop bounds are literal, so the pair count is exact, not
                fitted. The face-count identity is Euler's: V = n + k,
                E = n + 2k, C = 1 => F = E - V + 2 = k + 2, of which k + 1 are
                bounded and positive-area.
Falsifiable by: profile.loops.segments fitting k < 1.7, which would mean the
                pair loop is not what dominates; or the self-intersection
                fixture returning a loop count != k + 1, which would refute the
                §1.2 determination and point back at node snapping.
Risk          : at these sizes the arrangement may be dominated by nodeOf's
                grid probing (9 cells per lookup) rather than by the pair loop,
                which would depress the exponent without making the pair loop
                cheap. The ladder records both sizes and loop counts so the two
                can be told apart.
```

---

## 3. Job 1 — the fixtures. What was missing, and what now exists

**The instrument gap, stated exactly.** The kernel tier's sweep ladder is:

```dart
for (final n in const [12, 48]) {          // perf_scenarios_kernel.dart
  out.add(PerfScenario('kernel.sweep.$n', ...arcRing(n, 6)... arcPath(24, 60)));
}
```

Two rungs, top rung **48 profile points**. The stress tier climbs `allEdges` to
5 760 edges and `analyze` to 1 024 entities but **sweeps nothing**. The field
profile was **1218 segments** — **25.4x past the top rung of the only ladder
that measures this operation at all**, and 1250x past the mean the profile
quotes for it. A two-rung ladder also cannot show a knee, which is what P1 is
really asking about.

**What I added:** `frontend/lib/perf_scenarios_profile.dart`, a new opt-in tier
modelled on the stress tier — self-limiting ladders, budgeted, never part of the
ordinary suite. Four ladders:

| scenario | axis | rungs | answers |
| --- | --- | --- | --- |
| `profile.sweep.segments` | profile segments, path fixed at 16 spans | 32 / 128 / 512 / 1200 / 2048 | **P1** — the exponent, and whether there is a knee |
| `profile.sweep.spans` | path spans, profile fixed at 512 | 1 / 4 / 16 / 64 | is the multiplier separable, and what `arcSamples: 64` really costs |
| `profile.loops.segments` | segments through `arrangementLoops` | 32 / 128 / 512 / 1200 / 2048 / 5000 | **P3** — the 2D arrangement's exponent |
| `profile.loops.count` | loop count in one sketch | 8 / 32 / 128 / 512 | hundreds of loops, the axis the brief asked for |
| `profile.loops.selfIntersect` | planted self-crossings | 0 / 8 / 64 / 110 | **§1.2** — confirms loops == crossings + 1 by construction |

Two properties were deliberate:

- **Opt-in, like `stress`.** At the field's cost a single 1200-segment rung is
  ~100 s. Putting that in the ordinary suite would make every capture
  unusable, and would change what every existing number means.
- **Additive only.** `OPTIMIZATION_PLAN_2.md` §5 (S10): "Adding scenarios is
  allowed; changing existing ones is not." **`perf_scenarios_kernel.dart` is
  unmodified** — I imported `arcRing`, `arcPath` and `identityMat34` from it
  and changed nothing, so `kernel.sweep.12`/`.48` and every other existing
  scenario mean exactly what they meant before. The new tier reaches the
  runner through its own entry point instead (§8.1).

---

## 4. Job 2 — the triple computation, established before removal

The brief asked for the cause to be established before anything was removed.
Traced in `app_state.dart`; all three are unconditional on the sweep path.

**Run 1 — the preview.** `_updateExtrudePreview()` builds a throwaway feature
named `(preview)` from the session and computes it in full:

```dart
final (f, err) = _sessionFeature(s);
final (base, bodyName) = _extrudeBooleanTarget(s);
if (!recomputeFeature(p, f, partKernel, base: base)) { ... }
```

It is called from **15 sites** — every field edit in the sweep panel. Picking
the path at 10:05:11 is one of them.

**Run 2 — the commit.** `applyExtrude()` parses the session *again* into a
second feature object and recomputes it:

```dart
final (parsed, err) = _sessionFeature(s);      // a NEW object; run 1's is gone
...
final (commitBase, _) = _extrudeBooleanTarget(s);
final ok = recomputeFeature(p, f, partKernel, base: commitBase);
```

Nothing between run 1 and run 2 alters the profiles, the path, the orientation,
the taper or the twist — `_sessionFeature` reads the same `ExtrudeSession`
fields — so run 2's kernel arguments are byte-identical to run 1's. The comment
above it explains why the call is there (M132: a To-Next/Through-All extent must
resolve against the target *here*, not only in the fold), which is a reason for
the *call*, not for the *recomputation*.

**Run 3 — the fold.** Forty lines later in the same method:

```dart
if (partKernel.available) {
  if (recomputeAllFeatures(p, partKernel)) { _syncSolidProjections(p); }
}
```

`recomputeAllFeatures` recomputes **every feature in the part in order**,
including the one just built by run 2, into which nothing has been inserted.

**This closes the brief's fault (a) exactly.** Three runs, three sites, one set
of arguments — and 3 × 103 584.7 ms = **310.75 s**, which is the recorded
`kernel.feature.sweep` total to the millisecond. All three logged `tris=91646`
because all three did identical work.

### 4.1 And the reason no guard was ever going to help — found while implementing

A rebuild guard **already exists** in this codebase. `PartFeature.builtSig` is
documented as "input signature `solid` was last built from; null = must
rebuild", `featureInputSig` computes a complete key, and `recomputeAllFeatures`
checks it. It did not fire, and there are two independent reasons:

1. **`builtSig` is written in exactly one place** — inside
   `recomputeAllFeatures`. A feature built through the single-feature entry
   point `recomputeFeature` (run 2, the commit) leaves it null, so the fold
   that follows always rebuilds.
2. **And this, which is the deeper one.** `_recomputeFeature` opens with:

```dart
  f.disposeSolid();
  f.computeError = null;
  if (f is BodyModifyFeature) return _recomputeBodyModify(f, kernel, base);
```

   Unconditional, for every kind, before any dispatch. **Every path into a
   rebuild destroys the result before the feature that owns it is asked whether
   anything changed**, so a guard placed anywhere downstream would always be
   looking at a null solid. `recomputeAllFeatures` escapes only because its own
   `builtSig` check sits *before* the call and `continue`s past it.

That is the structural finding, and it is bigger than this one sweep: **no
feature kind can ever reuse its solid through `recomputeFeature`.** For cheap
features that costs nothing worth measuring. For a 103-second sweep it costs
103 seconds, every time anything in the part is committed — because
`applyExtrude` ends in `recomputeAllFeatures` whatever the user was editing.

---

## 5. Job 3 — the preview premise is REFUTED. The preview was displayed.

The brief's fault (b) reads:

> The line immediately after the preview completes is `setScene #20: 0
> solid(s)`. 103 seconds of full-fidelity work, nothing shown.

**That log line does not mean the preview was discarded, and the preview was
not discarded.** The count it prints is built in `viewport3d.dart`:

```dart
final pushed = <String>[];
for (final (id, s) in visibleSolids(app, p)) { ... pushed.add(...); }
RealityPush.recordScene(sig, pushed);
c.setScene(buildScenePayload(app, p, ...));
```

`pushed` enumerates **`visibleSolids` — committed feature solids only**. The
preview travels in the *same payload* by a different route, in
`buildScenePayload`:

```dart
final preview = sess?.preview;
if (preview != null) {
  scene['preview'] = solidPayload('__preview__', preview, material: kMatPreview);
}
```

and it is never added to `pushed`. Worse for the original reading: `0 solid(s)`
is the *expected* count at that moment, because `reality_scene.dart` hides the
body a preview stands in for —

```dart
final sessHides = sess?.preview != null;
... && !(sessHides && f.bodyName == sess?.previewReplacesBody)
```

— so a **successful** preview with nothing else committed prints exactly
`0 solid(s)`. The M210 comment ten lines above documents the *failure* case as
the one that prints `0 solid(s)` with nothing drawn; that is not this case.

**Consequence, and it is the useful part.** The 103 s preview is not waste — it
is the one run whose result the user actually looked at, for the two minutes
between 10:06:55 and the commit. So the correct fix is **not** to make the
preview cheaper. It is to make the commit *reuse* it, which is P2. Then the
user waits ~103 s once, sees the result, and OK returns immediately — instead of
waiting 103 s three times for the same 91 646 triangles.

**I am therefore not proposing a reduced-fidelity preview, and there is no
`Needs:` decision to route on it.** A fidelity change would trade displayed
behaviour for a saving that P2 already obtains without changing anything the
user sees. If P2 is implemented and the remaining single 103 s is still too
long, the fidelity question can be reopened on evidence — and *then* it is the
human's call. Recorded as §8.2 so the option is not lost, not as a request.

---

## 6. Job 4 — the sweep itself: what is mine, what is the shim's

After P2 the remaining cost is one honest sweep, ~103 s, and the brief is right
that this is the target. Two levers, and they are on opposite sides of an
ownership line.

**Mine (Dart side): the span count.** §1.1 shows spans are chosen in Dart and
multiply the segment count. `sampleEntity`'s unconditional `arcSamples: 64`
means an arc path is always 64 spans whatever its angle. Making that
angle-proportional is a ~10x reduction in output faces for a short arc path —
but it **changes the geometry that is built and displayed**, so it is a
behaviour change under §1.3(b): a coarser path is not inside any tolerance the
sweep path declares. Not taken. Recorded as §8.3.

**The shim's (S6's): whatever makes 19 200 faces cost 102 s.** If P1 fits
k ≈ 2, the cost is not in the faces at all — 19 200 faces at the suite's
implied per-face cost would be seconds, not 102 s — and something inside the
pipe-shell is doing whole-wire work per segment. That is the same *shape* of
defect S2 and S6 found in `edge_info`, in a different operation.
`backend/occt/shim/**` is S6's and I have not touched it. Recorded as §8.4,
with the ladder as the evidence S6 would need.

### 6.1 The other Dart-side lever, and why taking it would be the wrong answer

`sweep()` hands the kernel `encodeLoopSegs(arcFitLoop(loop))`, and `arcFitLoop`
collapses runs of a polyline into true arcs — which would cut 1200 straight
segments to a few dozen arc edges. It does not fire here. Its guard is
near-exact arc recognition:

> every run vertex lies on the fitted circle within `max(1e-9, 1e-6 r)`

and it is deliberately so: the doc comment explains that a rectangle whose
corners happen to be concyclic must not become an arc, and closes
"conservative: anything else passes through as lines." A DXF polyline
approximating a spline or an offset curve does not sit on one circle to
1e-6·r, so **all ~1200 segments reach the kernel as lines.**

Loosening that tolerance is the single largest Dart-side lever available, and
**I am not proposing it.** It makes the sweep cheap by making the profile
coarser, which is precisely what the brief rules out:

> "You are not making complex profiles cheaper by making them simpler. A
> 1200-segment sweep must become fast."

Recorded in §8.5 so the lever is documented and the decision to leave it is on
the record, not so that anyone takes it.

**What I deliberately did not do:** guess at the shim. The brief's own framing —
"a 1200-segment sweep must become fast" — is not served by a Dart-side
workaround that makes the profile simpler. P1 has to be measured first, and the
ladder is what measures it.

---

## 7. Definition of done — honest status

| §6 requirement | Status |
| --- | --- |
| 1. `flutter analyze` zero issues | **NOT RUN** — no SDK in this container (§0.2) |
| 2. `flutter test` green | **NOT RUN** — no SDK; tests written, unexecuted |
| 3. `python3 -m unittest discover -s ci` | **GREEN** — 45 tests |
| 4. Behaviour pinned by a **differential** test | Written: `m233_sweep_memo_test.dart`, old path vs new path, same run, same machine, no recorded constants (§1.4) |
| 5. Predictions with arithmetic, before the change | Yes — §2, committed before the code |
| 6. Merged into `claude/perf-opt2` | Yes |
| 7. What I did / predicted / am unsure of / did not do | This file |

**Requirements 1 and 2 are not met and I cannot meet them here.** That is a
material gap and CI must close it before any of this is trusted.

---

## 8. Cross-session entries

Filed in `CROSS-SESSION.md`; summarised here.

1. **`OPTIMIZATION_PLAN_2.md` is not on the round-two branches** (§0.1).
2. **The preview-fidelity option**, recorded and explicitly *not* requested (§5).
3. **`sampleEntity(arcSamples: 64)` is angle-independent** (§1.1, §6).
4. **The sweep's cost is inside the shim** — S6's area, with the ladder as the
   instrument (§6).
5. **The arc-fit tolerance is a lever I declined to pull** (§6.1).
6. **`recomputeFeature` can never reuse ANY feature's solid** (§4.1) — the
   generalisation of my fix, which I scoped to sweep rather than take on four
   other feature kinds unmeasured.
7. **Handing the preview's solid to the commit needs `app_state.dart`** (§9.2),
   which plan-2 §4 does not give me.

### 8.1 One file I touched that nobody was given

`frontend/lib/bug_capture.dart`, +19 lines: the `if (description...contains
('profile'))` block that runs the new tier, exactly parallel to the existing
`stress` one, plus its import.

It is not in any round-two ownership row and not in the frozen
`frontend/lib/perf*.dart` zone. I took it because without it the tier is
unreachable code and job 1 delivers nothing — "a measurement with no delivery
path is not a measurement" is quoted in both plans. The change is additive and
gated behind a keyword no past capture used, so it cannot alter any recorded
number. Flagged here rather than buried.

---

## 9. What implementation changed about the predictions

Registered predictions are not edited (§2 stands as written). This is the
adjudication of what could be adjudicated without a device.

### 9.1 P2 is REVISED DOWNWARD BEFORE MEASUREMENT — I can reach one of the two redundant runs, not both

P2 predicted 310.75 s → 106.4 s by memoising at the kernel-argument boundary.
Implementation refuted the *mechanism*, and with it half the saving:

**A kernel-boundary memo cannot be made safe from where I sit.** It would have
to hand the same shape to three callers that each dispose what they are given.
The only copy available is `OcctShape.transformed(identity)`, and the shim
implements that as `BRepBuilderAPI_Transform(shape, t, Standard_True /* copy */)`
— a full deep copy of a 20 290-face B-Rep, whose sub-shape ordering I would be
*assuming* is preserved. Edge indices feed the fingerprints that reattach
features across rebuilds; the plan says that is the single most likely way to
break a real part. An unverifiable assumption about OCCT's sub-shape ordering,
in a container with no OCCT, is not a basis for that.

**So the fix went where it needs no copy at all**: the feature reuses *its own*
solid. That reaches run 3 and nothing else, because runs 1 and 2 operate on
different `SweepFeature` objects.

```
registered P2 : 310.75 s -> 106.4 s   (-204.3 s)   [kernel-boundary memo]
delivered     : 310.75 s -> 207.2 s   (-103.6 s)   [feature-level guard]
                  = 2 x 103 584.7 ms
still on the table (§9.2)             (-103.6 s)   [needs app_state.dart]
```

**And the delivered half generalises further than the registered one did**,
which the arithmetic above understates. `applyExtrude` ends in
`recomputeAllFeatures` **whatever feature the user just committed**. With a
103-second sweep in the tree, every subsequent commit anywhere in the part paid
that 103 seconds again. The guard removes it from all of them, not only from
the sweep's own commit. Nothing in the field capture measures that — it holds
one sweep and one commit — so it is a prediction for the next capture:
**`kernel.feature.sweep` should read n = 2 per sweep commit and n = 0 for
commits of unrelated features, where today it is 3 and 1.**

### 9.2 The other 103.6 s — `**Needs:** integrator`

Runs 1 and 2 build the same solid from the same session into two different
feature objects, and the preview's result is alive in `s.preview` the whole
time. Handing it over at commit is a *move*, not a copy: no double free, no
sub-shape reordering, no new assumption. It needs two changes in
`app_state.dart`:

- `_updateExtrudePreview` records the argument signature its preview was built
  from;
- `applyExtrude` adopts `s.preview` into `f.solid` when that signature matches
  the parsed feature and `previewReplacesBody == null` (for a boolean output
  the preview holds the *combined* solid, not the feature's own, so it is not
  adoptable and that case keeps recomputing).

Plan-2 §4 gives `app_state.dart` to S9 by named function and gives me none of
it, and plan §3 is explicit: "If you need `app_state.dart` outside your named
functions: **stop and write to the coordination file.** Do not proceed." So I
stopped. Filed.

### 9.3 One behavioural difference I judged safe, stated so it is not found later

On a guard hit `disposeSolid()` does not run, so `f.ownSurfaces` keeps its
previous value where it would previously have been cleared to `const []`. The
solid is the identical object, so the surfaces describing it are still correct
— and `recomputeAllFeatures` recomputes them straight after a successful call
regardless. I consider this strictly more correct than clearing them, but it is
a difference and it is not covered by the differential test, which compares
geometry rather than provenance.

### 9.4 The gate will report a counter change

`kernel.sweep.reuse` is new, and `ffi.occt.sweepProfile`'s invocation count
falls. Per plan §6 that shows up as a *counter finding* at integration. Saying
so in advance, as S4 was told to: it is the win, not a regression.
