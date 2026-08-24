# Optimisation — how five parallel sessions do this without wrecking each other

**Read this document to the end before you touch a single line of code.**

The measurement phase is finished. `PERFORMANCE_PROFILE.md` says what every part
of this application costs, how that cost scales, and with what confidence. This
document turns that into work, split across **five sessions running at the same
time**, and its main job is to make sure those five sessions do not destroy each
other's output.

---

## 0. The prime directive

**You are not working alone. Four other sessions are editing this repository
right now.**

Everything below follows from that. If you remember nothing else:

1. **Never touch a file another session owns.** The ownership table in §3 is
   binding. Not "try to avoid" — *never*.
2. **Never force-push. Never rebase a shared branch. Never `git checkout -B` a
   branch you do not own.** `git push --force`, `--force-with-lease`, `git reset
   --hard origin/...` on a shared branch, and `git rebase` of already-pushed
   commits are all forbidden. They silently delete work that another session
   spent hours on.
3. **Never re-record `perf/baseline.json`.** It is the shared reference for
   everyone's regression gate. A session that re-records it masks every other
   session's regression. Only the integration step (§8) does that, and only
   after a fresh device capture.
4. **Never edit `PERFORMANCE_PROFILE.md`.** Five sessions appending to one
   16-section document produces five conflicting versions of it. You write your
   results to **your own file** instead (§4).
5. **Resolve every merge conflict by keeping both sides.** If you cannot, stop
   and write to the coordination file (§7). Do not pick a winner on someone
   else's behalf.
6. **If you find a defect in another session's area, do not fix it.** Write it
   down (§7) and carry on with yours.

A merge conflict is recoverable. A force-push is not.

---

## 1. What you are optimising, and the one rule that governs it

The ranking is `PERFORMANCE_PROFILE.md` §4. It is measured, reproduced across
four builds and two clock states, and it is not a guess. Nothing in it needs
re-deriving before you start — but you do need to *understand* it, which is not
the same as reading it.

**The standing rule of this whole branch, which now changes for the first
time:** the analysis branch had "don't optimise anything, only analyse". That
rule is now lifted for the five sessions below, and replaced by a stricter one:

> **Behaviour does not change. Only cost changes.**
>
> Every optimisation here must produce *bit-identical* application behaviour —
> the same geometry, the same solve results, the same colours, the same
> selection. If your change alters what the user sees, it is not an
> optimisation, it is a feature change, and it does not belong in this work.
>
> You prove this with tests, not with confidence.

---

## 2. The constraint that shapes everything: you cannot measure your own work

**No session can produce a device measurement.** The suite runs on a physical
iPad, triggered by a human pressing the bug button. You have no iPad. The
simulator is not a substitute — `PERFORMANCE_PROFILE.md` §13 establishes it is
not a scaled device (spread of 63× between operations, CV 138 %).

This is not a reason to guess. It is a reason to work the way physics works when
the apparatus runs once:

### Pre-registration

**Before you change any code**, write your prediction into your own findings
file, in this exact form:

```
## Prediction P1 — <one-line description of the change>
Target        : <span or scenario name from the profile>
Baseline      : <the measured number, with its §reference>
Mechanism     : <why the cost exists, in terms of the code>
Change        : <what you will do>
Predicted     : <the new number> ± <interval>
Derivation    : <the arithmetic that produces that number from the cost model>
Falsifiable by: <what measurement would show this prediction was wrong>
Risk          : <what could make it not work>
```

A prediction with no arithmetic behind it is not a prediction. If your cost
model says `allEdges` is Θ(n²) with a per-call cost linear in shape size, then
replacing n calls with one gives a specific predicted number, not "faster".

**Then** implement. **Then** the user takes one device capture that adjudicates
all five sessions' predictions at once. A prediction that comes out wrong is a
result, and it gets written up as one — the profile is full of refuted
hypotheses (§11) and they are the most valuable entries in it.

### What you *can* verify yourself

| Available to you | Not available |
| --- | --- |
| `flutter analyze` — zero issues required | Device timings |
| `flutter test` — the full Dart suite must stay green | Device memory |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | Frame rates |
| The C++ shim's own tests, and Lane C once Session 1 lands it | Anything the profile calls a *measurement* |
| Reading `perf/baseline.json` for the exact baseline numbers | |
| Reasoning from the fitted cost models in §10 | |

**Session 1 exists specifically to lift part of this constraint** — see §5.

---

## 3. File ownership — binding

| Session | Owns exclusively | Must not touch |
| --- | --- | --- |
| **S1 — Bench harness** | `backend/bench/**` (new), `backend/CMakeLists.txt`, `.github/workflows/kernel-bench.yml` (new) | everything else |
| **S2 — OCCT shim** | `backend/occt/shim/**`, `frontend/lib/ffi/occt_engine.dart` | `part_model.dart`, `solver.dart` |
| **S3 — 2D solver** | `frontend/lib/solver.dart`, and in `app_state.dart` **only** the `analyzeSketch` call sites and any analysis cache | `viewport.dart`, `displayGeometry` |
| **S4 — Painter** | `frontend/lib/widgets/viewport.dart`, and in `app_state.dart` **only** `displayGeometry` | `solver.dart`, the analyze call sites |
| **S5 — Part model** | `frontend/lib/part_model.dart` | `occt_engine.dart`, `solver.dart` |

### The shared files, and the rules for them

`frontend/lib/app_state.dart` is 14 086 lines and holds work belonging to two
sessions. It is **shared, split by function**:

- **S3** may edit: the three `analyzeSketch(` call sites (currently near
  `:2454`, `:2474`, `:8826`) and any caching it introduces around them.
- **S4** may edit: `displayGeometry` (currently near `:8115`) and nothing else.
- **Neither** may reformat, reorder, or "tidy" any other part of the file. A
  whitespace change across a 14 k-line file turns every future merge into a
  conflict.

If you need `app_state.dart` outside your named functions: **stop and write to
the coordination file.** Do not proceed.

**Nobody** edits: `PERFORMANCE_PROFILE.md`, `perf/baseline.json`,
`PERF_ANALYSIS.md`, `frontend/lib/perf*.dart` (the measurement apparatus — if
the suite changes, the baseline is invalid and every comparison breaks).

> **Line numbers in this document and in the profile have already drifted.**
> The profile cites the shim's `edge_info` at `:1679`; it is now at `:2180`.
> **Always locate code by grepping for the symbol**, never by jumping to a line
> number. Treat every line number here as a hint, not an address.

---

## 4. Branches, and where your results go

```
main
 └── claude/perf-deep-analysis        ← the analysis (finished, do not modify)
      └── claude/perf-opt             ← INTEGRATION branch, shared
           ├── claude/perf-opt-bench      (S1)
           ├── claude/perf-opt-shim       (S2)
           ├── claude/perf-opt-solver     (S3)
           ├── claude/perf-opt-painter    (S4)
           └── claude/perf-opt-partmodel  (S5)
```

**Setup**, once, by whichever session starts first:

```bash
git fetch origin
git checkout -b claude/perf-opt origin/claude/perf-deep-analysis
git push -u origin claude/perf-opt
```

If it already exists on the remote, do **not** recreate it — just branch from it.

**Your loop:**

```bash
git fetch origin
git checkout -b claude/perf-opt-<yours> origin/claude/perf-opt   # first time only
# ... work, commit often, small commits ...
git push -u origin claude/perf-opt-<yours>
```

**Merging up**, when your work is complete and green:

```bash
git fetch origin
git merge origin/claude/perf-opt      # MERGE. Never rebase.
# resolve conflicts by keeping BOTH sides
flutter analyze && flutter test && python3 -m unittest discover -s ci -p 'test_*.py'
git push origin claude/perf-opt-<yours>
git checkout claude/perf-opt
git merge --no-ff claude/perf-opt-<yours>
git push origin claude/perf-opt
```

Merge up **early and often** — a session that works for hours without merging
is a session whose merge will be painful and whose conflicts will tempt someone
into resolving them destructively.

### Your findings file

Each session writes to **its own file**, which nobody else touches:

```
perf/findings/S1-bench.md
perf/findings/S2-shim.md
perf/findings/S3-solver.md
perf/findings/S4-painter.md
perf/findings/S5-partmodel.md
```

This holds your pre-registered predictions (§2), your reasoning, your measured
host-side results, and your conclusions. These get folded into
`PERFORMANCE_PROFILE.md` at integration (§8), by one session, once. Write them
as if they will be read by someone who was not here — because they will be.

---

## 5. The five sessions

Each brief gives you: what to read, what the measurement says, where the code
is, what to be careful of, and what "done" means. **Read your section of the
profile properly.** Not the summary — the section, with its evidence, its
confidence intervals and its threats to validity. You are about to change code
on the strength of it.

---

### Session 1 — Lane C: a measurement loop that does not need an iPad

**Read:** profile §15.5 (the retired plan's Lane C), §6 (the kernel results),
§13.3 (what simulator numbers may and may not be used for).

**Why you go first (and why the others can start without you):** every other
session is flying blind between now and the user's device run. You can fix that
for the kernel work, which is where the two largest wins are. A headless C++
benchmark against the shim needs no iOS, no Flutter and no device: it runs in
minutes, on CI, on `macos-14` (Apple Silicon, same ISA family as the iPad chip).
**Relative** costs transfer well; absolute values are optimistic (desktop clock,
no thermal ceiling) and must never be quoted as iPad milliseconds — that is the
M75 error in new clothing, and §13.3 spells it out.

**Build:**

- A `bench` CMake target under `backend/bench/` linking the C-ABI shim
  directly.
- Fixed fixtures at three sizes, matching the profile's axes so the numbers are
  comparable to §6: profile-arc rings at 120 / 240 / 480 profile points
  (= 360 / 720 / 1440 edges), which is exactly the `stress.allEdges` ladder.
- N repetitions with mean / stddev / p95 per operation, over at minimum:
  `occt_shape_edge_info` (the single call **and** the full enumeration),
  `occt_fuse`, `occt_cut`, `occt_fillet_edges_ex`, `occt_mesh_create`,
  `occt_extrude_profile_arcs`, `occt_ray_hits`.
- **Peak RSS and allocation count per operation**, not only time. For
  tessellation those often matter more, and §5.5.2 shows a case where the
  memory prediction was the thing that confirmed the mechanism.
- A CI workflow that runs it and publishes results the same way `sim-perf.yml`
  publishes to `ci-logs-perf` — a measurement with no delivery path is not a
  measurement (§13.1 is the cautionary tale: a green job whose numbers nobody
  could read for a dozen runs).

**The property that makes it useful to Session 2:** it must reproduce the
*shape* of the device finding before anyone trusts it for optimisation work.
Specifically it must show `edge_info` per-call cost rising linearly with shape
size (§6.5 evidence 2, k = 0.985) and full enumeration rising quadratically
(k = 2.012). If your harness does not reproduce those exponents, the harness is
wrong, not the device.

**Done when:** the bench runs in CI, publishes durable output, and its fitted
exponents for `edge_info` and `allEdges` agree with §6.5 within their confidence
intervals. Report the agreement explicitly in your findings file — that
comparison is the harness's validation.

---

### Session 2 — The OCCT shim: the quadratic

**Read:** profile §6.5 in full (all four lines of evidence), §6.3 (fillet and
chamfer), §6.1 (`sweepProfile`), §10.1, §12.5 item 1.

**What is measured, and it is the most reproducible finding in the branch:**

| | |
| --- | --- |
| `allEdges` | **k = 2.012** [1.910, 2.113], R² = 1.0000 |
| Control (`buildOnly`: build + `counts()` + full mesh) | **k = 1.063** [0.959, 1.167] |
| Ratio at 480 profile points | **200.3×** — and the control does *more* work |
| One `edgeInfo` against a growing shape | **k = 0.985**, R² = 0.9998, both clock arms |
| Terminal rung | 10 017 ms at 1440 edges |
| Extrapolated to the part that died in the field (≈3400 edges) | **56.4 s** [44.9, 70.8] |
| Model size where `allEdges` alone costs one second | **458 edges** |

**The mechanism, established three ways and quantitatively closed:** each call
to `occt_shape_edge_info` performs whole-shape work and throws it away —
`TopExp::MapShapes`, `TopExp::MapShapesAndAncestors` (currently near `:2244`),
`BRepBndLib::Add`, and construction of a `BRepClass3d_SolidClassifier`
(currently near `:2287`, in the convexity branch taken for any edge with two
adjacent faces — on a closed solid, most of them). `allEdges` issues one call
per edge, so n × Θ(n) = Θ(n²). The composition is exact: 0.985 + 1 = 1.985
against a measured 2.012, agreeing to 1.3 %.

**The fix belongs in the shim, not in Dart.** This is stated in the profile and
is worth repeating because the Dart-side option looks tempting: batching calls
from Dart would save the boundary crossings, which are **8.1 %** of the cost
(§6.5 evidence 3 closure check), and leave the quadratic entirely intact. The
shape of the fix is a **bulk entry point** — one traversal that fills an array
for all edges — and a Dart binding for it.

**Also yours, and cheaper to fix:**

- **Fillet and chamfer cost the same for 1, 4 or 12 edges** — 25.5 ms flat,
  k = 0.00, reproduced under both clocks and across two builds (§10.2). Flat
  cost against a swept axis means the work is not per-edge; find what the fixed
  cost is. The profile's §6.3 notes the candidate search (`allEdges`) costs 4.9×
  the actual blending at one edge, which points back at your main finding.
- **Fillet radius sensitivity**: 10 ms at r=1.0 against 658 ms at r=4.0 on the
  same solid — a 65× discontinuity (§6.3). Understand it before touching it;
  this may be OCCT's own behaviour and not fixable in the shim, which is a
  legitimate result to record.
- **`sweepProfile`**: 81.9 ms mean, 392 ms worst (§6.1). Absolute, not scaling.

**Correctness risk, and it is severe.** You are changing the geometry kernel
boundary. Edge indices, adjacency, convexity flags and the fingerprints built
from them feed feature reattachment across rebuilds — get one field wrong and
parts silently reattach fillets to the wrong edge on load. **Add a test that
pins the new bulk path against the old per-edge path for identical output on
several solids**, and keep the old entry point until that test exists.

**Done when:** the bulk path exists, is bound in `occt_engine.dart`, produces
provably identical results to the per-edge path, Lane C shows the exponent
drop, and your prediction for `stress.allEdges` at 480 points is registered.

---

### Session 3 — The 2D solver: the cubic

**Read:** profile §5.5 in full (including 5.5.1, 5.5.2, 5.5.3), §5.4 (the
solver), §3.2 (your noise floor is the worst in the app — 24–29 %), §10.1.

**What is measured — this is now the top of the ranking:**

| | |
| --- | --- |
| `analyzeSketch` | **k = 3.198** [2.835, 3.561], R² = 0.9962 |
| Independently, reduced clock | **k = 3.071** [2.629, 3.513] |
| At 1024 entities | **8 837 ms**, and **+105 MB** RSS |
| Against the solve it accompanies, at 1024 | **221×** |
| Runs on | every rebuild, every solve, every tab switch |

**The mechanism is closed arithmetically, so you are not guessing.** In
`_analyzeSketch` (`solver.dart`, currently near `:2470`):

1. A **dense** `m × total` Jacobian by finite differences — one full
   `_residuals` evaluation per parameter. O(m · total).
2. **`_rankAndPivots`** (currently near `:2517`) reduces it to RREF by Gaussian
   elimination. **O(m · total · rank)** — this is the cubic.
3. A null-space basis, O(total · rank).

At the top rung the fixture gives **total = 3584** parameters, **m = 2562**
residuals, rank = 2562, and dof = 3584 − 2562 = **1022**, which matches the
recorded gauge exactly. Step 2 costs 2.35 × 10¹⁰ operations against step 1's
9.18 × 10⁶ — a ratio of **2562 : 1**. The memory follows the same arithmetic:
the dense Jacobian is 73.5 MB and the null-space basis 29.3 MB, predicting
102.8 MB against **105 MB measured — 2.2 %**.

**So there are two independent directions, and you should evaluate both:**

- **Make it cost less.** The matrix is dense but a sketch's Jacobian is
  extremely sparse — each constraint touches two or three entities. Sparse
  storage changes both the exponent and the 105 MB. Alternatively the rank is
  what is wanted, not the RREF; and the null-space basis is only needed for the
  carrier test.
- **Run it less often.** Three call sites, on every rebuild, solve and tab
  switch, on a quantity that only changes when geometry or constraints change.
  This is the cheaper win and touches `app_state.dart` — remember you own only
  those call sites (§3).

**Also yours:** the **LM fallback**, §5.4. libslvs solves, Dart verifies against
its own residuals, rejects above 1e-4, and then the Dart Levenberg–Marquardt
runs — twice while dragging, 80 iterations over a 168-parameter system. Measured
50.4 ms against 0.271 ms on the fast path: **186×**, and only **0.4 %** of that
time is inside libslvs. Note the profile's warning: quote the *share*, not the
ratio — the ratio depends on the fixture's distance from satisfiability and has
been 334× and 245× on other runs.

**Correctness risk:** the DOF analysis drives the colouring users read to know
whether a sketch is fully constrained, and `freePoints` from it gates dragging.
A rank computed differently is a sketch that looks wrong or refuses to drag.
**Pin the analysis output — dof, movable set, carrier set — against the current
implementation on a range of fixtures before you change the algorithm.**

**Done when:** predictions registered with derivations, behaviour pinned by
test, `flutter test` green, and your findings file states plainly which of the
two directions you took and why.

---

### Session 4 — The painter: the double solve

**Read:** profile §5.1, §5.2 (the most consequential comparison in the 2D
path), §5.3, §8.6, §3.4.

**What is measured, by exact counters — the strongest evidence class there
is:**

| Counter, `ui.drag60` | Value |
| --- | --- |
| Frames painted | 60 |
| `2d.displayGeometry` invocations | **120** |
| `2d.displayGeometry.solves` | **120** |
| `solve.total` invocations | **120** |

Two solves per painted frame. And the regime inverts under drag: static painting
is 97.3 % drawing, painting during a drag is **86.8 % solving and 12.6 %
drawing**.

**The mechanism:** two call sites in `viewport.dart` (currently near `:2126`
and `:2734`, in the `ent.dofColour` and `constraints` paint phases) each call
`app.displayGeometry`, which solves. The two phases are 43.6 % and 43.2 % of
drag paint time respectively.

**Prefer the fix that stays inside your own file.** Computing the display
geometry once per paint and passing it to both phases is entirely within
`viewport.dart`. Memoising inside `displayGeometry` would work too but touches
`app_state.dart`, where you own only that one function — and a cache there needs
an invalidation story that a paint-local variable does not.

**This is the cheapest large win in the whole ranking** — it is a duplicated
call, not an algorithm. Which is also the warning: it is cheap enough that you
will be tempted to do it in ten minutes and move on. Don't. The two phases may
depend on state that changes between them; establish that they do not before
collapsing them.

**Correctness risk:** if the second call currently observes geometry mutated by
the first, reusing the first result changes what is drawn. Prove it does not,
with a test that paints both ways and compares the output geometry lists.

**Done when:** `2d.displayGeometry.solves` per 60 frames is predicted and
registered, the equivalence is pinned by test, and the counter change is
described in your findings file — the gate keys on counters (§15.4), so a
successful fix will show as a *counter* regression finding at integration.
Say so in advance, or someone will think you broke it.

---

### Session 5 — The part model: the composition, and the quadratic in provenance

**Read:** profile §8.2 in full, §8.1, §6.8, §10.2.

**What is measured — this was a derivation until the last run, and is now a
measurement:**

| | |
| --- | --- |
| `app.blendPattern.edgeQuery` | 285.98 / 571.68 / 1142.49 ms at 2 / 4 / 8 occurrences |
| Fit | **k = 0.999** [0.998, 1.001], R² = **1.0000** |
| Per occurrence | **142.9 ms**, constant to 0.13 % across a fourfold range |
| Of which edge enumeration | **97.6 %** |
| Boolean fold, 8 occurrences | 28.16 ms — the other **2.4 %** |

**The mechanism:** `applyBlendOccurrence` (currently near `:7817`) opens with
`final live = kernel.edgesOf(body);` (currently `:7819`), and `edgesOf`
(currently near `:6416`) is `shape.allEdges()` — Session 2's quadratic,
unmodified, **once per occurrence**. The two worst-scaling behaviours in the
codebase compose, and nothing in the UI suggests to a user that patterning a
fillet is what triggers it.

**Your fix is independent of Session 2's**, and they compound: hoisting the
enumeration out of the per-occurrence loop removes a factor of N here regardless
of what one enumeration costs. Do not wait for S2, and do not depend on their
bulk API — if it lands, adopting it is a follow-up, not a prerequisite.

**Also yours:**

- **`newSurfacesOf`** (currently near `:4801`), k = 1.96 — quadratic, predicted
  from source before measurement and confirmed twice. Runs once per feature on
  every rebuild, twice for a body-modifying feature. Face count ×13.9 produced
  time ×144.
- **`app.rebuildPart`**, k = 1.68 with a CI spanning [1.04, 2.39] — the profile
  marks this **indeterminate**, and it stays indeterminate until it is measured
  at more sizes. Do not optimise against an exponent whose interval spans linear
  to quadratic; if you want to work on it, first make it measurable.
- Note §8.1's structural finding: `featureOfFace` calls `faceSurfaces` a second
  time purely to produce a count for a log line. It is behind a cache, so it is
  cheap — but it is free to remove.

**Correctness risk:** feature reattachment across rebuilds depends on edge
fingerprints resolving against the live solid. Hoisting the enumeration means
occurrences now share one snapshot of the edge list — if any occurrence *mutates*
the body such that later occurrences must see the new edges, sharing the
snapshot is wrong and will silently misplace blends. **Establish whether the
body changes between occurrences before you hoist.** This is the single most
likely way to break a real part in this whole plan.

**Done when:** predictions registered, the hoist is proven safe by test on a
multi-occurrence patterned blend, and `flutter test` is green.

---

## 6. Definition of done, for every session

You are finished when **all** of these hold:

1. `flutter analyze` — zero issues.
2. `flutter test` — green, including tests you added.
3. `python3 -m unittest discover -s ci -p 'test_*.py'` — green (45 tests).
4. **Behaviour is pinned by a test that would fail if you changed it.**
5. Your predictions are written down *with their arithmetic*, before the
   change, in your findings file.
6. Your branch merges cleanly into `claude/perf-opt` and you have merged it.
7. Your findings file explains what you did, what you predicted, what you are
   uncertain about, and what you deliberately did not do.

**Not** on this list: "it is faster". You cannot know that yet (§2). Claiming it
without a device measurement is exactly the error this branch spent a week
building instruments to avoid.

---

## 7. When something goes wrong

**A merge conflict:** resolve by keeping both sides. If the two changes are
genuinely incompatible, do not choose — append to
`perf/findings/CONFLICTS.md` (append-only, never edit another entry) describing
both sides, and leave the conflict for the humans.

**You need a file you do not own:** stop. Append to
`perf/findings/CROSS-SESSION.md` (append-only) with: what you need, why, and
what you would change. Continue with the rest of your work.

**You find a defect in another session's area:** write it in
`perf/findings/CROSS-SESSION.md`. Do not fix it. A silent fix in someone else's
file is indistinguishable from a merge accident, and it will be reverted.

**Your prediction turns out to be unprovable:** say so. "This cannot be
established without a device run" is a finding. The profile contains several.

**You are tempted to re-record the baseline because the gate fails:** don't. The
gate failing is information. `perf/baseline.json` is re-recorded exactly once,
at integration, after a device capture, by one session (§8).

---

## 8. Integration — after all five are merged

This is a separate step, run **once**, by **one** session, after the other five
have merged into `claude/perf-opt`:

1. Verify `claude/perf-opt` is green on all three test suites.
2. Ask the user for **a paired device capture on a build of
   `claude/perf-opt`** — the validated protocol from §15.2: Low Power Mode on
   with `stress`, then off with `stress`, same session, device cool, thermal
   `nominal`, after a minute of real use.
3. Run the gate against the **existing** baseline:
   `python3 ci/perf_gate.py <bundle.zip>`. Expect it to report counter changes —
   those are the wins (Session 4's double solve in particular will show as a
   counter finding). Read every one and attribute it to a session.
4. Adjudicate each pre-registered prediction: measured against predicted, and
   write the comparison up. **Predictions that were wrong get reported as
   prominently as those that were right.**
5. Fold the five findings files into `PERFORMANCE_PROFILE.md` — new §4
   scoreboard, new longitudinal entry in §12, and the prediction adjudication
   as a new subsection of §11.
6. **Only then** re-record the baseline from the new uncapped arm:
   `python3 ci/perf_gate.py --record <uncapped-bundle.zip>`.
7. Update `HANDOFF.md`.

---

## 9. A last word on rigour

The measurement phase found real things and it also found **two claims this
project had made about its own data that were wrong** — Low Power Mode was not
a uniform scalar, and the 3D push path did not cost what its round-trip span
reported. Both errors came from small samples, and both were caught by going
back and checking rather than by being careful the first time.

Optimisation has the same failure mode, with worse consequences: a change that
looks obviously correct, that all the tests pass, and that quietly alters
geometry on one part in fifty. Take the time. Pin the behaviour. Write down what
you predicted before you find out.

And check `git log --oneline origin/claude/perf-opt` before you push. Someone
else has been working while you were reading this.
