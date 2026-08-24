# Round two — sessions 6 to 10

**Read this to the end before you touch anything.** If you have read
`OPTIMIZATION_PLAN.md`, read this anyway: three rules changed, one session has a
mandate no session has had before, and the sequencing constraint is new.

Round one (sessions 1–5) is merged on `claude/perf-opt`: 2160 tests passing on
CI, five findings files, and a set of pre-registered predictions that **have not
yet been measured on a device**. That last fact governs everything below.

---

## 0. The prime directive, unchanged

Four other sessions are editing this repository while you work.

1. **Never touch a file another session owns** (§4).
2. **Never force-push, never rebase a shared branch, never `checkout -B` a
   branch you do not own.** These delete other people's work irrecoverably; a
   merge conflict never does.
3. **Never re-record `perf/baseline.json`.** It is the shared reference for
   everyone's gate.
4. **Never edit `PERFORMANCE_PROFILE.md`.** Write to your own findings file.
5. **Resolve every conflict by keeping both sides.** If you cannot, escalate —
   do not pick a winner for someone else.
6. **Found a defect in another session's area? Write it down, do not fix it.**

---

## 1. What is different this time

### 1.1 Round one is still being measured — do not contaminate it

Five sessions registered predictions with arithmetic, and **one paired device
capture is meant to adjudicate all of them at once.** If round two changes the
same code before that capture is taken, the attribution is destroyed: a number
that moved could belong to either round.

So the capture point is **tagged**, and round two branches from the tag:

```
git fetch origin --tags
git tag --list 'perf-capture-round1'      # must exist before you start
```

If that tag does not exist yet, **the integrator has not taken the capture
point**. Sessions 7, 8 and 9 may still start (§5 says why each is safe); **S6
and S10 must not** — see §5 for the reason in each brief.

### 1.2 One session may change behaviour. Four may not.

Round one's standing rule was "behaviour does not change, only cost changes".
That still binds S6, S7, S8 and S10.

**Session 9 is exempt, deliberately.** It is investigating a finding that says
behaviour is *already wrong*. It is the first session on this branch permitted
to propose changing what the application does, and it carries a correspondingly
heavier burden of proof (§5, S9).

### 1.3 The rule, as round one left it

Refined twice under fire. Current form:

> **Bit-identical wherever the prior behaviour was well-defined.** Where a
> change alters a numerical result, it is in scope only if all three hold, each
> *proven by test*:
> **(a)** the constraint residual is no worse;
> **(b)** the difference lies inside the tolerance the code itself declares for
> that data path — a rendering tolerance covers rendering only, never
> persistence;
> **(c)** it introduces no accumulation of a *kind* the status quo lacks, and no
> increase in *rate* beyond a factor accepted explicitly on the record, both
> measured against the unmodified application on the same fixture.
>
> Fail any one and it is a behaviour change: stop and ask.

### 1.4 The lesson that cost us a build — no platform-locked goldens

Round one's first IPA build failed on four tests, and none of them was a code
defect. They were pins of this shape:

```dart
// Recorded from the implementation as it stood at 15dc9ae
const _goldOverConstrained = r'2:60.0,0.0,4.0;2:998.9999999999947,…';
```

A golden recorded on one machine pins **"this machine produced these digits"**.
It does not pin "the new path equals the old one", which was the claim. They
passed on Linux/Flutter 3.44.9 and failed on macOS arm64/Flutter 3.47.1, which
is what CI runs.

> **Standing rule for round two: an equivalence test must be differential.**
> Keep the old implementation available as a test-only reference and compare
> old against new **on the same machine, in the same run**. That proves the
> claim *and* is platform-independent. A recorded constant does neither.
>
> And never convert a failing equivalence pin to a tolerance to get a green
> build. That trades the strong claim for a weak one and hides the divergence
> the test exists to find.

### 1.5 You still cannot measure your own work on a device — but Lane C exists now

No session has an iPad. What changed is that **Session 1 built Lane C**: a
headless kernel benchmark that runs on `macos-14` in CI, in minutes, and whose
fitted exponents agree with the device's. It is green (`Kernel Bench (Lane C)`).

**If your work is in the kernel, Lane C can adjudicate it before any device
run.** It already refuted round one's largest prediction — see S6. Use it.

Everything else still goes through pre-registration: write the prediction, with
the arithmetic that derives it from the measured cost model, **before** you
change code. `OPTIMIZATION_PLAN.md` §2 has the form; it has not changed.

---

## 2. Where your results go

```
perf/findings/S6-shim2.md      S7-profiler.md    S8-display.md
perf/findings/S9-drift.md      S10-memory.md
```

Your own file, nobody else's. `CROSS-SESSION.md` and `CONFLICTS.md` are
append-only and shared; mark an entry `**Needs:** integrator` to reach the
session that watches this branch and can reach the human.

---

## 3. Branches

```
claude/perf-opt                     ← round one, tagged perf-capture-round1
 └── claude/perf-opt2               ← INTEGRATION branch for round two
      ├── claude/perf-opt2-shim2       (S6)
      ├── claude/perf-opt2-profiler    (S7)
      ├── claude/perf-opt2-display     (S8)
      ├── claude/perf-opt2-drift       (S9)
      └── claude/perf-opt2-memory      (S10)
```

First session to start creates the integration branch from the **tag**, not the
branch tip, so late round-one commits cannot slide in unmeasured:

```bash
git fetch origin --tags
git checkout -b claude/perf-opt2 perf-capture-round1
git push -u origin claude/perf-opt2
```

If it already exists on the remote, branch from it — do not recreate it. Merge
up early and often; merge, never rebase.

---

## 4. File ownership — binding

| Session | Owns exclusively | Must not touch |
| --- | --- | --- |
| **S6 — shim, round 2** | `backend/occt/shim/**`, `frontend/lib/ffi/occt_engine.dart` | `solver.dart`, `part_model.dart`, `backend/bench/**` |
| **S7 — profiler** | `tools/profiler/**` (new), a new CI workflow of its own | **all of `frontend/lib/`** — see below |
| **S8 — display** | `frontend/lib/widgets/viewport3d.dart`, `frontend/packages/reality_view/**`, `.github/workflows/sim-perf.yml` | `viewport.dart` (2D), the shim |
| **S9 — drift** | `frontend/lib/solver.dart`, and in `app_state.dart` **only** `endGripDrag` and the `_lastGoodDragGeo` warm start | the shim, `viewport3d.dart` |
| **S10 — memory** | `frontend/lib/perf_scenarios_stress.dart`, plus a new scenario file of its own | everything else in `lib/perf*.dart` |

### The frozen zone, and the one crack in it

`frontend/lib/perf*.dart` is the measurement apparatus. Changing it invalidates
`perf/baseline.json` and every comparison built on it, so it stays frozen —
**with one exception, granted only to S10 and only after the baseline has been
re-recorded** (§5, S10). If you are not S10, it is closed to you.

**S7 in particular owns no app code at all.** A sampling profiler attaches to
the VM Service from *outside* the process; it does not need a hook inside it. If
you conclude it does, that is a `**Needs:** integrator` entry, not a patch.

`app_state.dart` is shared by name-of-function again: **S9 may edit
`endGripDrag` and the warm start, and nothing else in that file.** Nobody
reformats it — a whitespace pass over 14 000 lines turns every future merge into
a conflict.

---

## 5. The five sessions

### Session 6 — The quadratic that survived

**Wait for `perf-capture-round1`.** You are changing code round one changed;
starting before the capture destroys its attribution.

**Read:** `perf/findings/S2-shim.md` in full — especially §7.1 and §7.2 —
then `PERFORMANCE_PROFILE.md` §6.5, §10.1.

**The situation.** Round one's S2 added a bulk enumeration entry point
(`occt_shape_edges_info`, shim v21) and predicted the quadratic would collapse
to linear. Lane C measured it:

| | |
| --- | --- |
| Cost | fell **20.7×** |
| Exponent, before | 2.054 [1.984, 2.123] |
| Exponent, after | **1.909** [1.887, 1.932], R² 0.9999 over an 8× range |
| Local exponents | 1.915 / 1.869 / 1.958 — no knee, no bend toward linear |

**P1 refuted.** The constant collapsed; the asymptotics did not. The defect that
killed a part in the field is still Θ(n²), just cheaper.

**S2 found the mechanism, and it is not what anyone assumed.** Not the solid
classifier — a `TopExp_Explorer` loop over each adjacent face's edges, run once
per edge, to determine orientation. That is Θ(shape) per edge.

**And the obvious fix is already known to fail.** S2 built a face-edge
orientation index, Lane C measured it as a *regression*, and S2 reverted it —
`c5f7e21`. Read that revert and its findings entry before you design anything:
you are starting where a competent attempt already failed, and repeating it
wastes the session.

**Your instrument is Lane C.** It adjudicated the last attempt without a device
and it will adjudicate yours. Register a predicted exponent with its interval,
not a predicted speed-up.

**Correctness risk is the same one S2 carried:** edge indices, adjacency and
orientation feed the fingerprints that reattach features across rebuilds. Get
one wrong and parts silently reattach fillets to the wrong edge on load. Your
equivalence test must be **differential** (§1.4) — old path against new, same
machine, same run.

---

### Session 7 — The sampling profiler

**Safe to start immediately.** Owns no app code, so it cannot contaminate the
capture.

**Read:** `PERFORMANCE_PROFILE.md` §15.5 (plan item A4), §1.1, §5.5.2.

**Why now rather than earlier.** The suite says which *operation* costs what. A
profiler says which *line*. Five sessions have just rewritten the hot paths —
the sparse elimination, the bulk enumeration, the memoised display geometry —
and **nobody knows what dominates any of them now.** For `analyzeSketch` this is
the difference between "rank reduction is cubic" (established) and "*this loop*
is" (unknown, and now unknown against new code).

**Build:** VM Service `getCpuSamples` → Perfetto trace, driven from
`tools/profiler/`, plus a CI workflow that captures a trace against the
simulator and publishes it durably the way `sim-perf.yml` publishes to
`ci-logs-perf`. A measurement with no delivery path is not a measurement —
§13.1 is the cautionary tale, a green job whose numbers nobody could read for a
dozen runs.

**The validation that makes it trustworthy:** profile a scenario whose cost
breakdown is already known from the suite and show the profiler agrees. If it
cannot reproduce a known attribution, it cannot be believed on an unknown one.
Say so explicitly in your findings.

**What you must not do:** add a hook to `frontend/lib/`. Attach from outside.

---

### Session 8 — The display path, and Track B

**Safe to start immediately.** Nothing here was touched by round one.

**Read:** `PERFORMANCE_PROFILE.md` §7 in full — 7.2.1 (the instrument caveat),
7.2.2, 7.2.3, 7.2.4 — plus §13.

**Two jobs.**

**(1) First-scene construction.** The most expensive scene push measured in a
session took **419.67 ms**, of which **419.47 ms — 99.95 % — was the three
origin planes.** Steady state afterwards is 2.373 ms, a 177-fold amortisation.
This is the entire cost of first displaying a part, it is untouched, and it is
the last large single number in the report with nobody's name on it.

Note the instrument caveat before you quote anything: `rv.native.*` values are
re-recorded as `n` copies of a mean, so **their p50 and p95 are meaningless** and
only `n`, `total`, `mean` and the separate `worstUs` gauge are exact.

**(2) Track B is red.** `Simulator app + perf capture` has failed three times
since the optimisation work landed (runs #72, #73, #75) where it used to be
green. It is a build and linkage smoke test rather than a performance track
(§13.8), but it is the only automated thing that builds the whole stack against
the simulator, and a red smoke test detects nothing. Find out what round one
broke and fix it, or report that it is unfixable and why.

**Do not** quote a simulator millisecond as an iPad millisecond. §13.3 sets out
what its numbers may and may not support; that error has a name in this repo
(M75) and repeating it is worse than not measuring.

---

### Session 9 — The drift. **This session may change behaviour.**

**Safe to start immediately, but do not merge into `claude/perf-opt2` until the
capture is taken** — your changes would move numbers round one is being judged
on.

**Read:** `perf/findings/S4-painter.md` §9 in full, the S4-3 entry and the
integrator's ruling in `CROSS-SESSION.md`, then `PERFORMANCE_PROFILE.md` §5.4.

**The finding.** Dragging a sketch around a **closed loop and back** leaves it
**14.64 units** from where it started — in the unmodified application, with no
regime change involved, on a sketch roughly 60 units across. Committed geometry
is not a function of the cursor path.

It was found incidentally, while S4 was proving something else, and every
session so far has correctly declined to chase it because it lives in
`endGripDrag`, `solveConstraints` and the warm start — and because chasing it
means changing behaviour, which nobody was allowed to do.

**You are allowed. That is the point of this session, and it comes with
conditions.**

**Before proposing any change, answer this, because it decides whether there is
a defect at all:** the fixture is two slots coupled by a tangent and a
coincident — **under-constrained**. On an under-constrained system a
warm-started solver *not* retracing its path is expected behaviour, not a bug:
the free parameters have somewhere to go. What decides whether 14.64 units is
alarming is whether it is **proportionate to the freedom the sketch actually
has**. So establish first:

* the **DOF after `analyzeSketch`** on that fixture, and the sketch's
  bounding-box extent;
* the same drift measurement on a **fully constrained** sketch — if a
  determined system also walks, that is a defect with no ambiguity left in it;
* whether the drift is bounded or unbounded in N.

**If it turns out to be expected behaviour, say so and stop.** "This is not a
defect, here is why" is a complete and valuable result, and it closes a question
that has been open since it was found. Do not manufacture a fix for a
non-problem.

**If it is a defect**, you may propose a change — and then the burden inverts.
Every other session must prove it changed nothing; you must prove your change is
*correct*, which is harder. Pin the intended behaviour, show what it fixes,
and show what else moves. Route the decision through `**Needs:** integrator`
before merging; a behaviour change on this branch is the human's call, not
yours and not mine.

---

### Session 10 — Memory, and the session nobody has ever run

**Wait for `perf-capture-round1` AND for the baseline re-record.** You are the
one session permitted into the frozen apparatus, and that permission only
exists once the baseline has been re-taken.

**Read:** `PERFORMANCE_PROFILE.md` §8.5, §9.3, §12.4, §3.5's closing section.

**The axis the whole branch has never covered.** The field crash was a
`phys_footprint` kill. Every device run since has had 3.4–3.9 GB of headroom,
and Low Power Mode — the proxy for weaker hardware — says *nothing* about
memory. Worse, §3.5 established it **under**-represents the penalty on
memory-bound paths (1.62 against 2.27 for compute).

**Two jobs.**

**(1) Catalogue scenario 18 — the 30-minute soak.** Specified, never built,
never run, and **the only instrument that can detect a leak.** A CAD session is
an hour, not a click; the longest capture this branch has is 293 seconds. Build
it as an opt-in tier like `stress`, reporting footprint drift, thermal state and
jank trend over time. What matters is the *slope*, not any single value.

**(2) The footprint question that is still open.** §8.5: the footprint-to-RSS
ratio is not a constant — 3.60, 2.52, 4.00, 2.47 across four probe points,
clustering near 4 before the suite and 2.5 after. **What allocates the footprint
is unknown**, and iOS terminates on footprint, not RSS. The known structural
figures are 14 bytes/triangle, 2 KB/solid, and the 105 MB dense-matrix
allocation of a 1024-entity DOF analysis — though note S3 rewrote that path in
round one, so **the 105 MB figure may no longer hold and is worth re-deriving.**

**Adding scenarios is allowed; changing existing ones is not.** A new scenario
extends the suite. Editing an existing one silently changes what every past
number meant.

---

## 6. Definition of done

1. `flutter analyze` — zero issues.
2. `flutter test` — green, including what you added.
3. `python3 -m unittest discover -s ci -p 'test_*.py'` — green.
4. **Behaviour pinned by a differential test** (§1.4) that would fail if you
   changed it. S9 substitutes: intended behaviour pinned, and what moved stated.
5. Predictions written down *with their arithmetic*, before the change.
6. Merged cleanly into `claude/perf-opt2`.
7. Your findings file says what you did, what you predicted, what you are
   unsure of, and what you deliberately did not do.

**Not on this list: "it is faster."** Unless Lane C measured it, you do not know
that yet.

---

## 7. Integration

Once all five are merged, one session runs it: verify green, request a second
paired device capture, run `ci/perf_gate.py` against the round-one baseline,
adjudicate every registered prediction, fold the findings into
`PERFORMANCE_PROFILE.md`, and only then re-record the baseline.

Round one's integration is the worked example, including its mistakes: a
lockfile that silently re-resolved, an apparatus constant that no longer matched
the code, and a ruling that accepted an argument as proven when it was only
argued. Read `CROSS-SESSION.md` end to end before running it.
