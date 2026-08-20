# S7 — the sampling profiler

Session 7 of `OPTIMIZATION_PLAN_2.md` §5. Owns `tools/profiler/**` and one CI
workflow of its own. **Owns no application code**, by §4 and on the merits: the
VM Service is an out-of-process debugger interface, so attaching from outside
is not a workaround for the prohibition, it is how the instrument is supposed to
work.

Everything above the line "MEASUREMENT" was written and committed **before any
capture was taken**, as §2 of `OPTIMIZATION_PLAN.md` requires. The git history
of this file is the evidence for that ordering.

---

## 0. What was asked for, and what "done" has to mean

`PERFORMANCE_PROFILE.md` §15.5 lists two instruments specified and never built.
Round one built one of them (Lane C). This is the other:

> **The sampling profiler** (VM Service `getCpuSamples` → Perfetto), plan item
> A4. The suite says which *operation* costs what; a profiler says which
> *line*. For `analyzeSketch` that is the difference between "rank reduction is
> cubic" (§5.5.2, established) and "this loop is". Still the largest unbuilt
> piece of apparatus.

`OPTIMIZATION_PLAN_2.md` §5-S7 adds two conditions that shape the whole
session, and they are worth restating because they are what makes this
different from "wrote a profiler":

1. **A delivery path, or it does not count.** §13.1 is the cautionary tale —
   `sim-perf.yml` ran green for a dozen runs while not one of its numbers was
   ever read, because artifacts are served from a host the agent proxy refuses.
   A capture that cannot be opened is not a capture.
2. **It must reproduce a known attribution before it is allowed an opinion
   about an unknown one.** This is the part that can fail, and §2 below
   registers what would count as failing before the first capture was taken.

## 1. Why the known attribution can be a strong test here, and not a circular one

The natural worry about validating a profiler is that the thing you check it
against was itself produced by a profiler. It was not.

Round one's Session 3 rewrote the DOF analysis, and in doing so measured the
two phases of `analyzeSketch` **with explicit `Stopwatch` timers around each
phase**, not by sampling (`perf/findings/S3-solver.md` §2):

> Host baseline at n = 1024: Jacobian construction **3.191 s**, elimination
> **21.004 s**, total **24.195 s** — elimination **86.8 %**.

That is a wall-clock decomposition of the same routine, on the same class of
machine, from an instrument with no relationship to `getCpuSamples`. It is a
number a sampling profiler either recovers or does not.

The fixture is the suite's own: `stress.sketch.analyze`'s top rung is
`sketchFixture(512)` + `constraintFixture(512)`
(`frontend/lib/perf_scenarios_stress.dart:107`), giving
**total = 3584** parameters, **m = 2562** residuals, rank 2562, **dof = 1022** —
the arithmetic `PERFORMANCE_PROFILE.md` §5.5.2 closes exactly against the
recorded gauge, and which S3 §0.1 confirmed a second time by instrumenting the
routine directly.

And the code being profiled is the code those numbers were taken on.
`frontend/lib/solver.dart` is **bit-identical** at build `230f179` — the build
of the paired device run — and at `4890f06`, round one's branch point:

```
$ git rev-parse 230f179:frontend/lib/solver.dart 4890f06:frontend/lib/solver.dart
615f45cda264ef0555ea2b9ce91fa3a4d38ba50e
615f45cda264ef0555ea2b9ce91fa3a4d38ba50e
```

So the validation has two halves, and the second is the point of the exercise:

* **Calibrate** against `4890f06`, where the split is published.
* **Then report** the same split on round one's tip, where it is not. §5-S7 is
  explicit that "five sessions have just rewritten the hot paths … and nobody
  knows what dominates any of them now". S3 §6 *asserts* an answer for this one
  from the mechanism — "the remaining second is almost entirely step 1, the
  finite-difference Jacobian" — but did not measure it by attribution. This
  does.

## 2. Pre-registered predictions

Registered before any capture, from the numbers above and nothing else. Shares
are of samples **inside `analyzeSketch`**, which is the denominator every table
in §6 states.

### Prediction P1 — the calibration: the dense elimination share

```
Target        : share of samples inside analyzeSketch whose path passes through
                _rankAndPivots, on the solver at 4890f06, at n = 1024
Source        : S3-solver.md §2 — Jacobian construction 3.191 s, elimination
                21.004 s, total 24.195 s, measured with Stopwatch timers
Point estimate: 21.004 / 24.195 = 0.8681  ->  86.8 %
Registered    : [78 %, 93 %]
Why that wide : three sources of disagreement, none of them the sampler's
                precision:
                (a) S3's timers are wall clock and charge GC and allocation to
                    whichever phase triggered them; the sampler counts only
                    samples whose stack reaches analyzeSketch, and a purely
                    native stack (a GC helper thread) reaches nothing. The
                    dense path allocates 73.5 MB per analysis (§5.5.2), so this
                    term is real and is not symmetric between the phases.
                (b) a different container, a different Dart SDK. S3's own §12
                    found the same code moved 1.24x-1.89x between two runs on
                    two bases of this same container class; a share is far more
                    stable than a ratio, but not perfectly.
                (c) binomial sampling error, which at ~10^4 samples in the root
                    is about +/-0.7 percentage points and is the SMALLEST of
                    the three.
Falsifiable by: a measured share outside [78 %, 93 %]. If that happens the
                instrument is not measuring what it claims to and nothing else
                in this file may be quoted.
```

### Prediction P2 — the unknown: where the cost went after round one

```
Target        : the same share, on round one's tip (S3's sparse elimination)
Source        : S3-solver.md §6 asserts "almost entirely step 1"; §2's
                derivation charges the sparse elimination ~0.066 s against
                ~1.77 s of Jacobian construction
Point estimate: 0.066 / 1.836 = 0.036  ->  3.6 % elimination
Registered    : elimination <= 25 %, and the _jacobian subtree >= 55 %
Why not tight : the point estimate comes from S3's own charge of "4x sparse
                per-operation overhead" and "1.8x cache improvement", which
                that entry labels estimates rather than measurements. The
                claim being tested is the DIRECTION and the DOMINANCE, not the
                digit.
Falsifiable by: an elimination share above 25 %, which would mean the cubic's
                successor still lives in the elimination and S3 §6 pointed at
                the wrong phase.
```

### Prediction P3 — the "which line" claim, checked against the source

```
Target        : the file:line the profiler resolves for _rankAndPivots
Predicted     : solver.dart:1099 on the dense tree, solver.dart:1198 on the
                sparse tree — the declaration sites, read out of the two files
Falsifiable by: any other line. This checks the tokenPosTable resolution, which
                is the only part of "a profiler says which line" that this
                instrument can honestly claim: the VM's sampler resolves to a
                FUNCTION, so the line is the function's declaration and never a
                statement inside it. Said plainly here so no reader assumes
                otherwise.
```

---

## MEASUREMENT

## 3. What was built

`tools/profiler/`, ~1 400 lines of standard-library Python plus two Dart
fixtures, and `.github/workflows/profiler.yml`. Nothing outside those two
paths was touched, and it is checkable rather than asserted — against round
one's tip, this branch changes no application, backend or apparatus file at
all:

```
$ git diff --stat claude/perf-opt HEAD -- frontend backend ci
$                       # no output
```

| | |
| --- | --- |
| `vmservice.py` | RFC 6455 websocket client and JSON-RPC 2.0, hand-rolled. No PyPI dependency, because a runner that has to `pip install` is one network failure away from a red job whose redness says nothing about the code. |
| `samples.py` | the sampling session: flags, `clearCpuSamples`, resume, a polling merge, and `@Function` → `file:line` through the script's `tokenPosTable`. |
| `attribution.py` | flat profile, phase split, 95 % Wilson intervals, and the census/coverage figures that say what a capture is worth. |
| `perfetto.py` | folds sampled stacks into a Chrome-JSON trace `ui.perfetto.dev` ingests natively, and into greppable folded stacks. |
| `targets.py` | attach / `flutter test` / plain `dart` / iOS simulator. |
| `expectations/` | the known attributions, as data. |
| `tests/` | 48 unit tests, analytic ground truth only, in the style `ci/test_perf_tools.py` set. |

Attachment is from outside in every case. `flutter test --start-paused` and
`dart --observe` both hand over a paused VM and a service URI; on the simulator
the app prints one to a console `simctl launch --console-pty` streams. No hook,
and none needed.

## 4. Three things had to be found before any number here was trustworthy

This is the part of the session that mattered. The first capture that ran
end to end produced a clean-looking report with confidence intervals on
everything, and its headline number was **wrong by 33 percentage points**. What
follows is how that was established, because the same three traps are waiting
for anyone who runs this tool.

### 4.1 `profile_vm=true`, which `flutter test` forces and nothing can undo

The Flutter engine starts the test VM with `--profile-vm`: *collect native
stack traces*. The Linux engine is built without frame pointers, so the native
unwinder gives up almost immediately. In the dense `analyzeSketch` capture,
**47 % of the samples came back one frame deep** — a single `[Native]` address,
no Dart stack, unattributable to anything.

`setFlag` cannot fix it, and the way it fails is worth recording on its own:

```
setFlag profile_vm = false -> {"type": "Error", "message": "Cannot set flag: cannot change at runtime"}
```

That is a **successful RPC carrying an Error object**, not a JSON-RPC error, so
a client that checks only the transport reports every refusal as a success.
Two captures were taken believing they had turned the flag off. `getFlagList`
before and after is the only honest check, and `samples.py` now does it.

A plain `dart` VM has `profile_vm=false` by default. `flutter test` cannot be
given VM flags — flutter_tools builds the `flutter_tester` command line and
does not forward any — and the engine's allow-list rejects the flag even when
`--dart-flags` reaches it:

```
Shell: [FATAL:flutter/shell/common/switches.cc(482)]
       Encountered disallowed Dart VM flag: --no-profile-vm
```

`--sample-buffer-duration` and `--profile_period` *are* allowed. Neither helps
enough to matter (§4.3).

### 4.2 A merge that admitted a sample twice when the second copy was worse

The first version keyed a sample on `(isolate, tid, timestamp, stack)`. Fetch a
window twice — which an overlapping poll loop does deliberately — and a code
object deoptimised between the two fetches comes back as
`<unknown Dart function>` (`kind: Collected`). Different stack, different key,
**admitted as a second independent sample**. One calibration run took on 2 257
phantom samples that way and its unattributed remainder went from 3 % to 39 %.

Identity is `(isolate, tid, timestamp)` and nothing else, first fetch wins —
the earliest fetch is the one taken when the VM still knew what the code was.
`tests/test_merge.py` pins it.

### 4.3 The sampler is blind for most of a wall-clock second, and says nothing

Coverage — the fraction of elapsed time with any sample in it — is computed
from the inter-sample gaps and printed above every table. It is **not** close
to 1:

| capture | observed | effective period vs nominal |
| --- | ---: | --- |
| `analyzeSketch`, dense (allocates 73.5 MB per analysis) | **32.0 %** | 376 µs / 250 µs |
| `analyzeSketch`, round one's sparse form | **74.0 %** | 372 µs / 250 µs |
| the calibration fixture, `Float64List` | **77–89 %** | ~370 µs / 250 µs |

Time inside the collector has no Dart stack to walk, so the sampler does not
see it — and the dense path's cost *is* largely allocation. Raising
`sample_buffer_duration` from 0 to 120 s moved coverage from 29.9 % to 35.3 %,
so the ring is not the binding constraint; the collector is.

The consequence is a standing caveat, not a bug: **this instrument measures a
share of Dart CPU time, and a `Stopwatch` measures wall clock.** They agree
only when garbage collection is proportional between the phases being compared.
Every report prints the coverage figure so a reader can see how far apart they
might be.

A fourth, smaller one: warming up the *wrong* variant of a function leaves the
first timed run in unoptimised code that the VM discards on reoptimisation, and
those samples come back unattributable. In the calibration fixture that alone
was ~40 % of the first phase's samples.

## 5. The calibration — PASS

`expectations/known_split.json`, run on a plain Dart VM (`profile_vm=false`).
A fixture builds a dense finite-difference Jacobian at **total = 3584,
m = 2562** — the dimensions `stress.sketch.analyze`'s top rung produces — and
then reduces it to RREF, with a `Stopwatch` and a `UserTag` around each phase.
The Stopwatch split is printed *by the run being profiled*; the sampler has to
recover it from stacks it took no part in producing. Repeat counts move the
true split so the instrument is tested across the scale rather than at one
lucky point.

| case | the run's own Stopwatch | the profiler, from samples | Δ | unattributed |
| --- | ---: | ---: | ---: | ---: |
| low-share | 14.46 % | **14.13 %** [13.17, 15.10] | 0.34 pp | 0.14 % |
| even-share | 44.95 % | **43.94 %** [42.13, 45.53] | 1.01 pp | 0.27 % |
| high-share | 75.54 % | **76.04 %** [74.74, 76.96] | 0.50 pp | 0.23 % |

Registered tolerance ±5 pp; worst error **1.01 pp**, and no sign of a slope
error across a 60-point sweep. This is a differential check in the sense
`OPTIMIZATION_PLAN_2.md` §1.4 requires — two instruments, same machine, same
run — so there is no recorded constant to go stale on another platform. It
gates in CI.

**Two confounds are removed from the fixture rather than argued about**: the
phase functions carry `@pragma('vm:never-inline')`, and storage is
`Float64List` rather than `List<double>`. Both removals are named in the
expectation file, and §4.3 is what the second one is avoiding.

## 6. P1 — REFUTED. The host lane cannot reproduce the published split

Registered: the elimination is 78–93 % of `analyzeSketch` on the solver at
`4890f06`, point estimate 86.8 % from `S3-solver.md` §2.

**Measured: 54.85 % [54.12, 55.59]**, with 34.87 % of the root unattributed —
above the 15 % cap, so the split is refused before it is compared. Coverage
32.0 %. P1 is refuted and the instrument, on this lane, is not to be believed.

It is refuted **because of the lane, not because the published number is
wrong.** Two independent checks establish that, both run in a scratch worktree
at `4890f06` and reverted (`S3-solver.md` §0 did the same, for the same
reason):

**(a) Wall clock, this machine, same code.** `Stopwatch`es around the two
phases, exactly S3's method:

| | |
| --- | ---: |
| Jacobian construction | 3 042.1 ms |
| elimination (`_rankAndPivots`) | 23 753.8 ms |
| everything else in the routine | 358.9 ms |
| **elimination, of the two phases** | **88.65 %** |

against S3 §2's 86.81 % on a different container and a different SDK. The
published split reproduces.

**(b) Per-sample ground truth.** A `UserTag` rides on *every* CPU sample,
including the ones whose stack cannot be unwound. Tagging the two phases labels
each sample with the phase it truly belongs to, and the stack-based attribution
can then be scored against it, sample by sample:

| truly in | unwind failed (native-only) | landed on the right function | landed on `_analyzeSketch` |
| --- | ---: | ---: | ---: |
| elimination (n = 23 573) | **51.6 %** | 31.3 % | 17.1 % |
| Jacobian (n = 5 566) | **52.3 %** | 23.9 % | 23.7 % |

Ground-truth split from the tags: elimination **78.07 %**, Jacobian 18.43 %,
rest 3.50 % (n = 30 195). The unwind failure rate is the same in both phases —
so it is unbiased, and it is not what breaks the split. What breaks it is the
17–24 % that lands on the enclosing function.

## 7. P2 — REFUTED, and so is the claim it was testing

Registered from `S3-solver.md` §6 — "at n = 1024 the remaining second is almost
entirely step 1, the finite-difference Jacobian" — as elimination ≤ 25 % and
the `_jacobian` subtree ≥ 55 %.

**Measured on round one's tip: elimination 48.98 % [48.11, 49.85], Jacobian
49.02 % [48.15, 49.89]**, unattributed 2.00 %, coverage 74.0 %.

Here the lane can be checked, because the sparse form gives both phases a named
function of their own and the enclosing routine almost nothing to absorb. The
same `UserTag` experiment on round one's solver:

| | ground truth (per-sample tag) | the stack-based attribution | Δ |
| --- | ---: | ---: | ---: |
| Jacobian | **58.92 %** | 54.96 % | 3.96 pp |
| elimination | **40.63 %** | 42.98 % | 2.35 pp |
| rest | 0.46 % | 2.06 % | — |

n = 22 668 tagged samples. Of the samples truly in the elimination, 75.5 % land
on `_rankAndPivots` and 0.2 % on `_analyzeSketch`; of those truly in the
Jacobian, 66.5 % land on `_jacobian` and 1.8 % on `_analyzeSketch`. The
enclosing-function leak that ruins the dense case is 0.2–1.8 % here.

So the measurement stands, and **S3 §6's "almost entirely step 1" does not.**
At n = 1024 the elimination is still **40.6 %** of `analyzeSketch`'s sampled
Dart CPU time. §2's derivation predicted 3.6 %; it is an order of magnitude
out. The mechanism is §9.

This is exactly the case `OPTIMIZATION_PLAN_2.md` §5-S7 said was open —
"five sessions have just rewritten the hot paths … and nobody knows what
dominates any of them now" — and it is the first quantitative answer for one of
them.

## 8. P3 — met, exactly

Predicted from reading the two files: `_rankAndPivots` declared at
`solver.dart:1099` on the dense tree and `solver.dart:1198` on the sparse one.
Both captures resolve those lines and no others. The `tokenPosTable` lookup
works, and "which line" means what §2 said it means: the line the function is
declared on, never a statement inside it.

## 9. What the profiler says about round one's code, which nobody knew

The flat profile of `analyzeSketch` at n = 1024 on `claude/perf-opt`, from
12 732 samples inside the routine (`perf/profiler/analyze/sparse-1024/`):

| | self | total | function |
| ---: | ---: | ---: | :--- |
| 1 | **24.73 %** [23.99, 25.49] | 46.54 % | `_GrowableList.add (growable_array.dart:283)` |
| 2 | **21.00 %** [20.30, 21.71] | 21.34 % | `_GrowableList._grow (growable_array.dart:387)` |
| 3 | 8.08 % | 39.99 % | `_residuals (solver.dart:601)` |
| 4 | 7.21 % | 45.83 % | `_spAxpy (solver.dart:1158)` |
| 5 | 7.07 % | 48.99 % | `_jacobian (solver.dart:1247)` |
| 6 | 6.98 % | 6.99 % | `_pointAt (solver.dart:174)` |
| 7 | 6.15 % | 6.15 % | `residualCount.pt (solver.dart:335)` |
| 8 | 4.08 % | 4.08 % | `_active (solver.dart:329)` |

**45.7 % of the self time inside `analyzeSketch` is growable-list growth.**
Not arithmetic — `_GrowableList.add` and `_GrowableList._grow`, the reallocate-
and-copy path of a `List` that was not given its length up front. It is split
across both phases: `_spAxpy` (elimination) and `_jacobian` both build sparse
rows by appending.

S3 named this as a risk and priced it as a guess. `S3-solver.md` §2's
Prediction P2 charges "4x sparse per-operation cost (index indirection, list
growth, no linear scan)" and §12 observes that "the sparse form is allocation-
and pointer-chasing-bound, and those are what a shared container starves
first". Neither statement is a measurement of *where*. This is: it is one
allocation pattern, in two functions, on lines 1158 and 1247 of `solver.dart`,
and it is the largest single item in the routine that replaced the cubic.

**I am not fixing it.** `solver.dart` is not mine (§4 of the plan gives it to
S9 for the drift, and round one's S3 owns the elimination). It is written up
as a cross-session entry instead.

Two things a reader should hold back on:

* the share is of **sampled Dart CPU time**, and 26 % of this capture's wall
  clock was unobserved (§4.3). List growth allocates, so if anything this
  *under*-states it.
* this is a Linux JIT host, not an iPad. §13.3's rule against quoting an
  off-device millisecond as a device one applies here with more force, not
  less. The **attribution** is what transfers; the milliseconds are not.

## 10. The delivery path

`.github/workflows/profiler.yml`, three jobs.

| job | runner | gates? | what it does |
| --- | --- | --- | --- |
| `calibrate` | ubuntu | **yes** | §5's three-point check, plus 48 unit tests and `ci/`'s own suite. Red here means nothing downstream may be quoted. |
| `analyze` | ubuntu | no | §6 and §7's captures. Checks out `4890f06` as a second worktree and verifies its `solver.dart` is still bit-identical to `230f179`'s before using it as the reference. |
| `simulator` | macos, manual | no | the lane §5-S7 asks for. |

Every job publishes to a **`ci-logs-profile` branch** as well as uploading an
artifact — `tools/profiler/publish.sh`, the same belt `ci-logs-perf` uses, for
the reason §13.1 gives: artifacts come from a host the agent proxy refuses, and
a measurement with no delivery path is not a measurement. `RUN.txt` on that
branch says how to read each file.

**About the simulator lane, plainly: I could not run it.** No macOS host. It
consumes the `simulator-app` artifact `sim-perf.yml` publishes rather than
building its own — Track B is red as of runs #72/#73/#75 and is S8's job — and
it is written to fail loudly instead of going green empty: no artifact is a
hard stop, and fewer than 500 usable samples is a hard stop. Whether the iOS
engine forces `--profile-vm` the way `flutter_tester` does is **unknown**; the
capture prints the flag, so its first run answers the question, and the report
refuses to be quoted if the answer is the bad one. iOS arm64 mandates frame
pointers, so there is reason to expect the native unwinder to work there where
it does not on Linux — that is a hypothesis, not a result.

## 11. What I am uncertain about

* **Whether the simulator lane runs at all.** Written, never executed. §10.
* **Why 17–24 % of the dense case's unwound samples land on the enclosing
  function.** Inlining explains the Jacobian half — its loop *is* inline in
  `_analyzeSketch` — but `_rankAndPivots` is a large separate function and
  should not be inlined into anything. Something else is going on in the
  native unwinder and I did not find it. It does not affect §7's measurement,
  where the leak is 0.2–1.8 %.
* **How much of the 26–68 % unobserved time belongs to which phase.** If the
  collector's work were attributed, §9's list-growth share would move, almost
  certainly upward. The tags cannot answer this: a sample the profiler never
  took carries no tag either.
* **Whether the calibration's ±5 pp transfers to a target with more threads.**
  Both calibration and app captures here are single-isolate and effectively
  single-threaded for Dart. A UI app is not.

## 12. What I deliberately did not do

* **No app code.** Not a hook, not a marker, not a `Perf.span`. The `UserTag`
  probes of §6 and §7 live in scratch worktrees, are never committed, and are
  measurement fixtures in the sense `S3-solver.md` §0 established.
* **No protobuf Perfetto trace.** The Chrome JSON format is ingested natively
  by `ui.perfetto.dev` and `trace_processor`, and — the deciding reason — a
  JSON document can be checked by a unit test that reads it back, while a
  hand-rolled protobuf can only be checked by the tool under test.
* **No fix for §9**, and no fix for anything else the profiler found.
* **No wrapper around the Flutter SDK.** Renaming `flutter_tester` and
  interposing a script does let `--sample-buffer-duration` through, and it was
  tried; it does not let `--profile-vm` through, it modifies a shared toolchain
  out from under other sessions, and the gain without the flag that matters is
  six points of coverage. Reverted, and recorded here so nobody re-derives it.
* **`profile.py capture --target simulator` is not wired into `sim-perf.yml`.**
  That file belongs to S8 (§4) and Track B is red; adding a step to it would be
  editing another session's file and betting on a broken build.

## 13. For the integrator

Three entries, also in `CROSS-SESSION.md`.

1. **`perf-capture-round1` does not exist**, so §3's instruction to create
   `claude/perf-opt2` from the tag cannot be followed. This session's work
   therefore sits on its own branch, merged from `claude/perf-opt` (round one's
   tip) plus `claude/perf-deep-analysis`'s plan commit. It contains no app-code
   change, so it cannot contaminate the capture whenever it is taken.
2. **`S3-solver.md` §6's attribution is refuted** (§7 above). The entry says
   the elimination is gone; it is 40.6 %.
3. **The largest single cost in round one's `analyzeSketch` is list growth**
   (§9), which nothing in `PERFORMANCE_PROFILE.md` or the findings predicts,
   and which is in a file this session does not own.
