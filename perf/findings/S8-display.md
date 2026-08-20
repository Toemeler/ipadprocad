# S8 — the display path, and Track B

Session 8 of `OPTIMIZATION_PLAN_2.md`. Two jobs: first-scene construction
(§7.2.2's 419.67 ms) and Track B, which has been red since round one landed.

Working branch: `claude/first-scene-track-b-perf-qap2a2`, merged from
`claude/perf-opt` (round one's tip). Neither `perf-capture-round1` nor
`claude/perf-opt2` existed when this session started, and §5 says S8 is safe to
start immediately because nothing in the display path was touched by round one.
That is still true of everything below: no file this session changes is in any
other session's column in §4, and `perf/baseline.json`, `PERFORMANCE_PROFILE.md`
and `frontend/lib/perf*.dart` are untouched.

---

## 1. Job 1 — first-scene construction

### 1.1 What the 419.47 ms actually is, from the report's own numbers

§7.2.2 records the most expensive scene push of the session:

| Phase | worst in A (first scene) | worst in B (steady state) |
| --- | ---: | ---: |
| `rv.native.setScene` | 419.67 ms | 12.20 ms |
| └─ `rv.native.planes` | **419.47 ms** | 8.62 ms |

and §7.2.3 records the same phase's steady-state **mean** at **2.373 ms**.

§7.2.2 concludes: *"Mesh upload is not the cost of first displaying a part;
RealityKit entity and material construction for the origin planes is."*

**That is right about the trigger and wrong about the cause, and the two numbers
above are enough to show it.**

`rebuildPlanes` is not incremental. It destroys every `PlaneEntity` and rebuilds
it — three quads, three outline tubes, three axes, the centre point — on *every*
`setScene`. It did that 1 698 more times in the same session for 2.373 ms each.

> Work that costs 2.373 ms when it is repeated cannot cost 419 ms because of
> what it is.

So, writing the first call as one-time cost plus plane work:

```
T_first  = C_once + W_first  = 419.47 ms
T_steady =          W_steady =   2.373 ms
W_first ≈ W_steady            (same code, same three planes; if anything the
                               first scene is the CHEAPER one — see §1.2)
⇒ C_once = 419.47 − 2.373    = 417.10 ms   =  99.43 % of the first call
```

**At most 2.4 ms of the 419.47 ms is plane construction.** The other 417 ms is
RealityKit's first use of the process — shader library, Metal pipeline state,
the resource subsystem — which the origin planes pay only because they are the
first geometry the app ever builds.

### 1.1a The same result from the appendix, without the differencing

§1.1 leans on §7.2.3, which recovers the steady state by subtracting capture A
from capture B. That subtraction is sound but it is a step, and a step is
something to check. §16 A gives the same answer with no subtraction at all —
one row, session scope, reference arm, printed verbatim from the bundle:

| span | n | total ms | mean ms |
| --- | ---: | ---: | ---: |
| `rv.native.planes` | 66 | 641.52 | 9.720 |

The session accumulator contains capture A (§2.2), so the 419.47 ms first call
is inside that 641.52. Take it out:

```
rest       = 641.52 − 419.47 = 222.05 ms over 65 calls
mean(rest) =                     3.416 ms
first / mean(rest)             = 122.8×
C_once     = 419.47 − 3.416   = 416.05 ms  =  99.19 % of the first call
```

**416.05 ms against §1.1's 417.10 ms** — two routes through different parts of
the bundle, agreeing to 1.05 ms. The gap is exactly what it should be: 3.416 ms
is the mean over 65 calls including the earliest and coldest ones, 2.373 ms is
the mean over the later ones only.

Either way the conclusion is the same and it does not depend on which figure you
prefer: **99.2 % of the first call is not work the planes do.**

### 1.1b One row that does not add up, and it is worth someone's attention

In the table above `rv.native.planes` has **n = 66** while `rv.native.setScene`
has **n = 63**. The planes phase is timed *inside* `setScene`
(`RealityPartView.swift:415`), so those counts should be equal.

They are not, and the three extra calls are real: `RealityThumbRenderer.render`
(`RealityViewPlugin.swift:86`) builds a **fresh `PartRenderer`** per gallery
thumbnail and calls `renderer.setScene(scene)` directly, outside the
`RvPerf.time("rv.native.setScene")` wrapper the platform view goes through. So
three of the session's 66 plane rebuilds were thumbnails, not viewport pushes,
and no `rv.native.setScene` observation covers them.

Not a defect in the app, but it does mean `rv.native.setScene` is **not** the
whole of what happens past the boundary, and anyone reading the two rows as
parent and child — as §7.2.2's "└─" tree does — is off by three. Flagged for
whoever folds this in; `bug_capture.dart` and the profile are not mine to edit.

It also has one consequence for §1.4: a thumbnail render can be the first thing
in a process to build RealityKit geometry, so the warm-up may be paid there
instead. That is harmless and slightly preferable — a thumbnail is written on
save, not while the user waits for a viewport — and by §1.4's second property it
cannot cost the save anything either way.

This changes what is worth doing. Optimising `PlaneEntity` — caching the quad
mesh, not rebuilding on `setHot`, sharing the outline tube — is a real
inefficiency and it is worth **at most 2.4 ms**, once. It is not where the 419
went.

### 1.2 Why the planes and not the solids

`setScene` runs `rebuildSolids` **first** (`RealityPartView.swift:411`), before
`rv.native.planes`. Had the first scene contained a solid, the solid would have
paid the first-use cost and `rv.native.solids` would carry the 419 ms.

It does not: 10.02 ms in A against 6.22 ms in B, which is ordinary variation and
nothing like a first-use event. So the first scene ever pushed had **no solids
in it** — the empty document, origin planes and axes only — and that is why the
cost landed where it did. It is an accident of ordering, not a property of
planes.

### 1.3 A correction to §7.2.2's verdict: not "once per part"

§7.2 closes with *"**WATCH** for first-scene construction (419 ms, once per
part)"*. The evidence in the same section says otherwise.

`worstUs` is reset by each drain (§7.2.1), so capture B's gauges report the
worst **since A**. Across B's 31 further scene pushes — each one gated behind a
changed mesh signature, so each one a genuinely different scene — the worst
`rv.native.setScene` is **12.20 ms**. If the 419 ms recurred per part it would
appear there. It does not.

**It is once per renderer instance, and in practice once per process.** The
right reading of the verdict is "419 ms, once — the first time the app draws
anything in 3D".

### 1.4 The change: pay it where nobody is waiting for a part

`PartRenderer.commonInit()` builds the `ARView` and two lights and no geometry,
so the first `MeshResource` and the first `Material` in the process are the ones
`rebuildPlanes` makes. `RealityWarmup.run()` (`PartScene.swift`) now constructs
one throwaway mesh and one of every material the scene uses — `unlit`,
`unlitTransparent`, `unlitSoft` (which also builds `RampTexture`), `steel`,
`preview` — plus one swept tube, and discards them.

Three properties, each deliberate:

* **It cannot change a pixel.** Nothing built by the warm-up is ever parented to
  the scene graph, so no frame can catch it. An add-then-remove entity could.
* **It cannot make anything slower.** If it ever ran *after* the first
  `setScene`, the scene would already have paid the first-use cost and the
  warm-up would be the cheap case — the ~1 ms it costs on any later call.
* **It runs one runloop turn after view creation**
  (`DispatchQueue.main.async`), not inline. Inline would move the stall into
  platform-view creation, where the user waits just as long and the viewport has
  not painted its background yet. Deferred, the surface is up first, and the
  first `setScene` is still at least one Flutter frame away: `viewport3d.dart`'s
  `onCreated` schedules a post-frame `setState`, and the push happens in the
  build after that.

### 1.5 It is also the instrument that can refute §1.1

`rv.native.warmup` splits a number that has never been split. Until now
"first-use initialisation" and "plane construction" were one span and could only
be separated by the inference in §1.1. On the next paired capture they are two
spans, and the inference is falsifiable.

### 1.6 Pre-registered predictions

Registered **before** any device capture of this change, per plan §1.5.
Baseline figures are §7.2.2's and §7.2.3's, quoted above. Read them off the
first drain of the reference arm (`worstUs` gauges, not p50/p95 — §7.2.1).

**P8-1 — the cost moves.** First-call `rv.native.planes` falls from 419.47 ms to
**≤ 25 ms**.
*Arithmetic:* §1.1 puts plane work at 2.373 ms and steady-state worst at
8.62 ms; 25 ms allows ~3× the worst steady-state observation for cold
allocation on the first call, and is 6.0 % of 419.47.

**P8-2 — and reappears under its own name.** `rv.native.warmup` reports `n = 1`
with `worstMs ≥ 300 ms` on the first drain of a cold app, and does not appear
in any later drain.
*Arithmetic:* §1.1's C_once is 417.10 ms. 300 ms is 72 % of it, leaving room for
the part of first use that resource construction does not reach (§1.7).

**P8-3 — the falsifier, stated in advance.** If `rv.native.warmup` comes back
**< 50 ms** while first-call `rv.native.planes` is still **> 300 ms**, §1.1 is
wrong: the cost is genuinely in plane construction, this change buys nothing,
and it should be reverted rather than explained.

### 1.7 What I am unsure of

**Whether resource construction reaches all of the first-use cost.** RealityKit
may defer some of it to the first *draw* — pipeline state is often compiled when
a material is first rendered, not when it is created. The warm-up deliberately
does not render, because rendering means parenting an entity and that is the one
thing that could change a pixel. If P8-1 holds only partway — say planes fall to
150 ms — that residue is draw-time work, and the next step is a warm-up frame
rendered off-screen, which is a bigger and riskier change than this one and
should not be made before the capture says it is needed.

**Whether a launch-time warm-up would be better.** It would remove the cost from
the 3D path entirely rather than moving it a frame earlier. It would also spend
~417 ms of main thread in every session, including the many where the user never
opens 3D, and `launch.toFirstFrame` is 171 ms on device (§13.5) — a warm-up
there is more than three times the whole launch. Not proposed without a
measurement.

**The absolute figure.** 419.47 ms is one observation of one gauge on one
device. §7.2.2 itself notes the earlier run's single observation was an order of
magnitude low. The *ratio* argument in §1.1 does not depend on the absolute
value; P8-1's 25 ms bound does.

### 1.8 What I deliberately did not do

* **Did not make `rebuildPlanes` incremental, and this one is a real number.**
  It tears down all three planes, their outline tubes, the three axes and the
  centre point and rebuilds them on every `setScene`, whether the payload
  changed or not. §1.1a's arithmetic prices that: **222.05 ms across the
  session**, 3.416 ms per push on the platform thread — more, per push, than
  `rv.native.solids` spends on the actual part (2.457 ms mean). Skipping a plane
  whose payload is unchanged would recover most of it.

  I did not do it, and the reason is clause 4 rather than the size of the prize.
  The planes are sized to the part's bounding box (M83), so they genuinely do
  change as the model changes; the gate would have to key on `frame`, `origin`,
  `uMin/uMax/vMin/vMax`, `hot` and `visible`, and **missing one field is a
  rendering bug that nothing in this repository could catch** — no Swift test
  target, and Track B cannot exercise RealityKit. Shipping an unverifiable
  behaviour change to the render path to save 3.4 ms a push, on a path §7.1
  already calls SMOOTH, is the wrong trade. Written down for whoever can measure
  it.

* **Did not optimise `PlaneEntity` construction itself.** §1.1 caps that prize
  at 2.4 ms.
* **Did not touch `rv.native.*` recording.** §7.2.1's `n`-copies-of-a-mean
  synthesis is an apparatus defect (p50/p95 are meaningless for these spans),
  but `bug_capture.dart` is in the frozen zone and fixing it would invalidate
  `perf/baseline.json`. Written down, not fixed — plan §0 rule 6.
* **Did not quote a simulator millisecond as an iPad millisecond**, anywhere.
  Nothing in §1 comes from Track B; RealityKit is not meaningfully exercised on
  an x86_64 simulator under Rosetta, and §13.3 forbids the conversion in any
  case.

---

## 2. Job 2 — Track B

### 2.1 The record, corrected

The brief says the workflow failed three times, at runs #72, #73 and #75. The
run list says something slightly different, and the difference matters:

| Run | Commit | Branch | Conclusion | Where it died |
| ---: | --- | --- | --- | --- |
| 58 | `605a6f6c` | `claude/perf-opt` | **success** | — (last green on the integration branch) |
| 62, 66 | | `claude/perf-opt` | cancelled | never started |
| 67 | `8f9a42c6` | `claude/perf-opt-shim` | **success** | — |
| **68** | `56dfc4fb` | `claude/perf-opt` | **failure** | **launch — app died before `Log.init()`** |
| 71, 72 | | `claude/perf-opt` | cancelled | never started |
| **73** | `f0c20819` | `claude/perf-opt` | **failure** | `Host tests` — 2160 passed, 4 failed |
| 74 | `c5f7e216` | `claude/perf-opt-shim` | **success** | — |
| **75** | `f85eb74e` | `claude/perf-opt` | **failure** | `Host tests` — 2160 passed, 4 failed |

Three corrections:

1. **#72 is a cancellation, not a failure.** So is #71, #66 and #62. The
   workflow sets `cancel-in-progress: false`, which stops an *in-progress* run
   being killed but not a *pending* one: GitHub cancels the queued run when a
   newer push arrives in the same concurrency group. All four were superseded
   before they started. They are evidence of nothing.
2. **#68 is a failure the brief does not list, and it is the only real one.**
3. **The two kinds of failure are not the same failure**, and the later kind
   hides the earlier one.

### 2.2 Runs 73 and 75: the M232 pins, and they are not mine

Both died in `Host tests` — the macOS re-run of the Dart suite — with the four
pins the integrator already diagnosed on 2026-08-20 (`CROSS-SESSION.md`, "build
437 is red on four M232 pins"):

```
m232_lm_pin_test.dart          solve.overConstrained
m232_lm_pin_test.dart          an unsatisfied but SO… case
m232_no_accumulation_test.dart 100 successive drag+analyse cycles
m232_no_accumulation_test.dart the gap does not grow with N
```

Hardcoded golden strings, recorded on Linux + Flutter 3.44.9, compared on macOS
arm64 + Flutter 3.47.1. Nothing in production code is failing.

**Confirmed independently here, and the confirmation is clean.** Run 74 was
**green** on `claude/perf-opt-shim` at `c5f7e21`; run 75 was **red** on
`claude/perf-opt` at `f85eb74`, which is the merge of that same commit. The two
trees differ by S3's merge, and `m232_lm_pin_test.dart` and
`m232_no_accumulation_test.dart` **do not exist on the shim branch at all**:

```
$ git ls-tree --name-only origin/claude/perf-opt-shim frontend/test/ | grep m232
frontend/test/m232_blend_occurrence_test.dart
frontend/test/m232_provenance_index_test.dart
```

They entered `claude/perf-opt` with S3's merge (`af56ef2`, 17:57), between run
68 and run 73. Runs 68 and earlier never ran them.

**Not fixed here, on purpose.** These are S3's tests over S3's `solver.dart`,
which is S9's file in round two (§4). Making them differential — the fix the
integrator specified and §1.4 of the plan now requires of everybody — means
retaining the dense elimination as a test-only reference, which is a change
inside that solver, not inside a test I own. Plan §0 rule 6: write it down, do
not fix it. Escalated in `CROSS-SESSION.md`.

**And explicitly not weakened.** No golden was converted to a tolerance, no test
was skipped, marked flaky or excluded, and there is no `continue-on-error`
anywhere in this workflow.

### 2.3 Run 68: the failure that matters, and it is not a code regression

Run 68 got much further. It built the whole native stack, built the app, booted
an iPad Pro simulator, installed and launched:

```
created sim 'iPad Pro (12.9-inch) (6th generation)' -> E6A109EE-…
sim booted (~5s)
== launch ==
launch rc=0: com.prototype.prototype: 83451
== app Documents container ==
total 0
NOTE: no logs/ directory — the app did not reach Log.init()
PERF CAPTURE: FAIL (no performance log was produced)
== recent crash reports ==
== simulator system log for our bundle ==
```

The process spawned, got a pid, and died before the first line of the app's own
logging. No crash report. No system log. Nothing.

**It is not a regression from round one, and this is provable:**

```
$ git diff --stat 8f9a42c 56dfc4f
(empty)
```

Run 67 (`8f9a42c`, `claude/perf-opt-shim`) and run 68 (`56dfc4f`,
`claude/perf-opt`) are **byte-identical trees**. Run 67 launched, captured and
went green at 17:39. Run 68 launched, died and went red at 19:07. Same code,
same workflow, same runner image, ninety minutes apart.

So the launch is **non-deterministic**, and no commit in round one caused it.
Given §13.3's standing warning that an x86_64 binary under Rosetta on an arm64
runner was "still unproven, and the next thing likely to break", that is the
first place to look — but looking requires evidence, and there was none.

### 2.4 Why there was none: two diagnostics that could never have fired

Both are in the step's own failure branch, and both are mine to fix.

**The system log was collected from a shut-down simulator.** The order was
`xcrun simctl shutdown "$UDID"` … and then, inside the failure branch,
`xcrun simctl spawn "$SIMUDID" log show … 2>/dev/null`. `simctl spawn` fails on
a device that is not booted, and its stderr went to `/dev/null`. So
`== simulator system log for our bundle ==` printed an empty heading on every
failure it has ever had, and could never have printed anything else.

**The console log was never written.** The step ends with
`cp ../ci-sim-console.log "$GITHUB_WORKSPACE/perf-out/" 2>/dev/null || true`.
Nothing in this workflow writes that file. `simctl launch` without
`--console-pty` does not produce one. The workflow header advertises "the launch
console log" among what the job produces; it has never produced one.

This is §13.1 again — *a measurement with no delivery path is not a
measurement* — inside the step whose entire job is to explain why the app did
not run.

### 2.5 What this session changed in `sim-perf.yml`

**(a) The console is captured, from before the launch.** `xcrun simctl spawn …
log stream` starts *before* `simctl launch`, so it sees dyld failures, the
Flutter engine's own output and any abort message — all of which happen before
the app could write a file of its own. Killed after the hold, truncated to
4 000 lines, published with the capture.

**(b) The diagnostics run while the simulator is still booted.** The
crash-report scan and `log show` moved above `simctl shutdown`, and `log show`
no longer discards its stderr — if it fails now, it says so.

**(c) The macOS Dart checks moved to the end of the job.** They used to sit
between the xcconfig patch and the app build, so a red pin aborted the run
before it compiled or launched anything. That is why runs 73 and 75 tell us
nothing about whether the app still starts: **since 2026-08-19 this track has
not attempted the one thing §13.8 says it is good for.** Moved last, they still
fail the job — nothing is weakened — but the smoke test and the capture happen
first and are published either way.

  They are kept rather than deleted, and the reason is that they earn their
  place: `dart-checks` runs the same suite on ubuntu and passed all three times.
  The macOS steps are the only thing in this repository that caught the
  platform-locked goldens at all.

**(d) `claude/first-scene-**` added to the push trigger.** Track B is the only
instrument that can tell whether Track B is fixed, and `workflow_dispatch`
cannot reach it: GitHub only offers dispatch for workflows present on the
default branch, and `sim-perf.yml` has never been on `main`. Without this a
session that owns this workflow has no way to run it.

**(e) No retry was added, deliberately.** Runs 67 and 68 already establish that
the launch is non-deterministic; counting how often is worth much less than one
red run carrying the console log from (a), which no run has ever carried. A
retry can be added once there is something to retry *around*.

### 2.6 Was Track B fixed?

Honestly: **partly, and the part I could not fix is named.**

* The failure that hid everything else — a Dart pin aborting the job before the
  smoke test — cannot happen again. (c)
* The failure that matters — the app dying before `Log.init()` — is now
  diagnosable for the first time. (a), (b)
* The job will still go **red** while the four M232 pins are red, because they
  are still red and this session did not weaken them. Track B will build,
  launch, capture and publish, and then fail on the pins. That is the correct
  behaviour, and it is a different red from the one it has been showing.

Track B will be green when S9 or the integrator makes the pins differential.
Until then the redness has exactly one cause, it is named, it is escalated, and
it no longer blinds the smoke test.

### 2.7 The verification run — what it has shown so far

Run **78** (`13f58af`) and run **79** (`c070f6b`) on
`claude/first-scene-track-b-perf-qap2a2`. **Neither has finished**, and the
paragraphs above are still a claim about what the workflow will do rather than a
report of it doing so. What is established at 07:31 UTC:

**Confirmed.**

* **`dart-checks` is green on ubuntu** — `Perf tooling tests`, `Analyze Dart` and
  `Host tests` all pass at `13f58af`. No Dart changed this session and nothing
  in it regressed. It also re-demonstrates the platform split the whole M232
  problem rests on: the same suite that passes here fails on the macOS runner.
* **The reordering is live in the job definition.** `sim-app`'s steps now read
  20 `Build app for the simulator`, 21 `Boot simulator, launch the app, pull the
  perf log`, 22 `Analyze Dart (macOS host)`, 23 `Host tests (macOS host)`,
  24 `Which tests failed (macOS host)`, then the zip/upload/publish steps. The
  smoke test can no longer be aborted by a Dart pin.

**Not yet answered.** Whether the launch succeeds, whether `PERF CAPTURE` passes
or fails, whether the new console stream carries anything, and whether the Swift
compiles. Run 78 is in `Build OpenCASCADE (simulator, x86_64, cache miss only)`
and expects up to 150 minutes there.

**And an operational fact worth recording, because it will bite the next
session.** That step is a **cold** build: `Restore OpenCASCADE simulator install
tree` returned in under a second with nothing. GitHub Actions caches are scoped
to the branch that wrote them plus the default branch — a run on
`claude/first-scene-…` cannot read a cache written by `claude/perf-opt`, because
they are siblings and neither is `main`. So **any session that runs Track B from
its own branch pays one cold OCCT build first**, whatever the perf branches have
cached. That is a property of the cache scope, not of anything round one did,
and it is the difference between a 26-minute job and a two-and-a-half-hour one.

---

## 3. Definition of done (plan §6)

| | |
| --- | --- |
| 1. `flutter analyze` — zero issues | **CI.** No Dart changed this session. Both the ubuntu `dart-checks` job and the macOS step run it. No Flutter toolchain in this environment. |
| 2. `flutter test` — green | **CI, and see §2.2.** No Dart changed. The four M232 pins were red before this session and are red after it, for the reason the integrator gave. |
| 3. `python3 -m unittest discover -s ci -p 'test_*.py'` | **Green here.** 45 tests, OK. |
| 4. Behaviour pinned by a differential test | **Not achievable, and I will not pretend otherwise — see below.** |
| 5. Predictions with arithmetic, before the change | §1.6, written before any capture. |
| 6. Merged cleanly into `claude/perf-opt2` | Not possible: `claude/perf-opt2` does not exist, and neither does `perf-capture-round1`. This branch is merged from `claude/perf-opt`. |
| 7. Findings file | This file. |

**On clause 4.** The change is Swift. This repository has no Swift test target —
`find . -name '*.swift' -path '*test*'` is empty — and the one job that compiles
this Swift is Track B, which cannot exercise RealityKit meaningfully (x86_64
under Rosetta, and §13.3 forbids reading its timings anyway). A differential
test of `RealityWarmup` is not something I can write here.

What is available instead, and I would rather state it plainly than dress it up:

* The behaviour argument is **structural, not empirical**: `RealityWarmup.run()`
  returns `Void`, touches no renderer state, and parents nothing. No entity it
  builds is reachable from `arView.scene`. There is no path by which it can
  change what is drawn.
* The **compile** is checked — pushing this branch runs Track B, which builds
  these Swift files on macos-26.
* The **cost** claim is checked by the pre-registered predictions in §1.6,
  including a falsifier, on the next paired device capture. Per plan §6: *not on
  this list — "it is faster."* I do not claim it is. I claim §1.1's attribution,
  and I have registered what would prove me wrong.
