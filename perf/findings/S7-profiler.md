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
