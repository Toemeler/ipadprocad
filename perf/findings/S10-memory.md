# S10 — memory: the soak that was never built, and where the footprint goes

**Session 10 of `OPTIMIZATION_PLAN_2.md`.** Two jobs, both from §5's S10 entry,
and one standing exemption: this is the only session permitted into
`frontend/lib/perf*.dart`, and the permission is to **add** scenarios, never to
change an existing one.

Nothing in this session optimises anything. Every change is apparatus. That is
deliberate: the axis this branch has never covered is memory, the failure it
exists to explain is a `phys_footprint` kill, and there is no point tuning a
quantity nobody can yet observe.

---

## 0. Summary — what is now true that was not

1. **Catalogue scenario 18 exists.** `frontend/lib/perf_scenarios_soak.dart`, a
   thirty-minute soak on the `soak` keyword, reporting the **slope** of the
   footprint, of RSS, of the jank rate and of event-loop lateness — each beside
   the smallest slope that run could have resolved.
2. **It is calibrated against a leak of known size**, in-process, differentially,
   against no recorded constant. A leak detector that has never seen a leak is
   an assertion; this one is checked in both directions (it finds an injected
   leak, and it does not invent one on a clean run).
3. **The footprint is decomposed.** `PerfProbe.swift` now publishes `internal`,
   `compressed`, `device` and `external` beside `phys_footprint`. §8.5's open
   question — *what allocates the footprint* — could not be answered from Dart
   at all, and the four numbers that answer it were one struct away the whole
   time.
4. **The 105 MB is re-derived, and it no longer holds.** §5.5.2's figure is a
   property of a dense algorithm S3 replaced. Measured differentially at the
   same top rung, in one process: **dense 324 MiB peak, sparse 25 MiB peak**,
   both returning an identical analysis.
5. **What allocates the DOF path now is not a matrix, it is churn** — 210 MiB of
   transient residual vectors per top-rung analysis, which S3 did not change
   and which no longer has a 98 MiB matrix standing in front of it.

---

## 1. Job one — catalogue scenario 18

### 1.1 Why a soak is a different instrument, not a longer one

Seventeen of the plan's eighteen catalogue entries are covered. Number 18 is
the thirty-minute session, and §15.5 records why it keeps being skipped: it is
the only one that takes thirty minutes. The longest capture this branch has is
293 seconds (§3.4).

The reason it cannot be substituted is not that 293 seconds is short. It is
that **every other tier measures a value and a leak is not a value.** A
footprint of 1233 MB after a suite and 1325 MB before it (§8.5) are the same
measurement of two different moments; neither is evidence of anything until
there is a series. A leak is a *slope under fixed work*, and a slope needs
duration on the x-axis.

So the tier is built as a series, not as a long scenario:

* one **fixed work cycle** — five drag solves, one DOF analysis, one cold gear
  outline, and (with a kernel) one extrude, one mesh, one edge enumeration, one
  fuse, all disposed — repeated for the whole run;
* a **sample** on a fixed cadence (default 20 s), carrying the machine's state
  and the app's counters;
* an **OLS fit** per quantity, reported as a rate;
* a **settle phase** at the end: the same sampling with no work at all.

The cycle is deliberately small — tens of milliseconds, not seconds. The stress
tier already owns *how big before it breaks*; this one owns *how long before it
drifts*, and that wants many identical repetitions rather than large ones.

### 1.2 The floor is half the result

The failure mode a leak test invites is to report a flat slope and let it be
read as "nothing leaks". It does not mean that. It means *this run could not
resolve a leak of that size*, and those are only the same statement when the
run's sensitivity is stated.

Every trend therefore ships with `halfWidth` = 1.96 × the standard error of the
slope — the same 1.96 convention `ci/perf_profile.py` uses for every interval in
the profile, so an interval printed here means what an interval printed there
means. The report prints slope and floor side by side and labels each row
`RESOLVED` or `below its own floor`, and it ends with the rule in words:

> a slope is a leak only if it exceeds its own floor **and** the settle phase
> did not give it back.

The settle phase is what separates the two remaining possibilities. A heap
reaching its working size rises and then hands memory back when the work stops.
A leak does not.

### 1.3 The calibration, which is the part I would want to see first

`soakLeakBytes` retains a fixed number of bytes per cycle. The test then
requires the fit to recover the rate that was injected — computed from what the
run itself retained, in the same process, on the same machine. No golden, no
recorded megabyte count; §1.4 of the plan is explicit that a recorded constant
proves neither the claim nor portability, and this branch has already lost a
build to four of them.

Both directions are checked:

| | assertion |
| --- | --- |
| 512 KB/cycle injected | fitted slope within [0.45×, 2.5×] of the injected rate, and `resolved` |
| nothing injected | the same run does not report a runaway slope |

The bounds are wide on purpose. RSS moves in pages, the collector is not asked
permission, and a tight bound here would be a flaky test asserting something
about the Linux VM rather than about the fit. What the bounds do exclude is the
two failures that matter: an instrument that misses a leak it was handed, and
one that reports a leak twice the size of the one it was handed.

The pure arithmetic is tested separately against series whose answer is known by
construction — an exact line, a flat line, deterministic scatter, and a series
with absent samples in it. One of those tests found a real error while being
written: the obvious "alternating ±5" scatter fixture is **not** orthogonal to
x over an even number of points, and it biases the recovered slope by 3.8 %. The
fixture is a period-4 pattern now, and the reason is in the test.

### 1.4 What it samples, and the one thing that needed help

Per sample: elapsed minutes, cycles, Dart RSS, `phys_footprint` and its four
parts, headroom to jetsam, thermal ordinal, cumulative frame counters, the 95th
percentile of event-loop lateness in that window, and the size of the event log
on disk.

Two of those need a word.

**Jank needed a nudge.** An idle Flutter app schedules no frames, and the bug
capture runs behind a dialog with nothing animating. Sampling `Perf.jankFrames`
for half an hour of that would have produced a flat series through no frames at
all and a "jank trend" fitted from nothing. So the soak calls back into the
caller once per cycle, and `bug_capture.dart` passes
`WidgetsBinding.instance.scheduleFrame`. The frames the trend is fitted from are
therefore frames the soak asked for, which is the right instrument for the
question: a frame that lands while a cycle is running is late by exactly the
amount the cycle blocked the UI thread.

**Lateness works everywhere.** The scenario file has no Flutter dependency and
must run headless, so beside the frame counters there is a probe that always
populates: each cycle awaits a fixed delay and records how late it came back.
That is a direct measurement of event-loop responsiveness and needs no render
pipeline. Where frames flow, both are reported; where they do not, the report
says `not sampled` for jank rather than printing a zero.

**The log is sampled because it worried me.** The app logs per solve, so a
half-hour session appends a file all run — see §5.1. Rather than assert it does
not matter, the soak measures it, and the decomposition in §2.1 is what makes
the answer checkable: log pages are `external`, and `external` is not charged to
the footprint.

### 1.5 Delivery — because a measurement with no delivery path is not one

§13.1 is the cautionary tale on this branch: a green job whose numbers nobody
could read for a dozen runs. So:

* `bug_capture.dart` writes `perf_suite_soak.json` and `perf_suite_memory.json`
  into the bundle, on the `soak` and `memory` keywords;
* `ci/perf_report.py` grows sections **2b** (the soak) and **2c** (the memory
  family), both of which say so explicitly when the bundle does not carry them;
* `ci/perf_profile.py` reads both new members, so the appendix that claims to
  print everything still does — the same hole that once dropped the entire
  stress tier;
* the raw series ships in the JSON beside the fits, so every number in the
  report is re-derivable rather than merely asserted.

### 1.6 What the tier cannot do

* **It cannot run itself.** Nobody on this branch has an iPad. Everything above
  is apparatus and arithmetic; the first real series does not exist yet.
* **It does not decide.** It reports a slope, a floor and what the settle phase
  returned. Whether that is a leak is a reading, and the rule it should be read
  by is printed with it.
* **A thirty-minute soak is not an eight-hour one.** A leak below the run's
  floor is still a leak on a working day. The floor is published so that limit
  is visible rather than implied.
* **It exercises the headless paths only.** No widget tree, no gestures, no
  document I/O, no RealityKit scene beyond what the app already holds. A leak
  in the display path will show only through `device` and the footprint total,
  not through anything the cycle drives.

---

## 2. Job two — the footprint

### 2.1 The ratio: 3.60 / 2.52 / 4.00 / 2.47, and why no fifth number would have helped

§8.5 records the footprint-to-RSS ratio at four probe points and closes,
correctly, that **the ratio is a function of what the process has recently
allocated, not a constant of the app**, and that nothing should rest on a single
value of it. It also records that *what allocates the footprint is unknown*.

That second sentence was not a measurement problem. It was a **reporting**
problem: `phys_footprint` is a total, and a total cannot say which of its parts
moved. Taking more totals — a fifth probe point, a sixth — would have produced
more ratios and no more understanding.

The same `task_vm_info` that carries `phys_footprint` carries its parts, and
they were one struct field away the whole time. `PerfProbe.swift` now reports:

| field | what it is | charged to the footprint? |
| --- | --- | --- |
| `internal` | dirty anonymous pages — the heap | **yes** |
| `compressed` | pages the memory compressor took out of residency | **yes** |
| `device` | IOKit / device mappings — GPU, RealityKit surfaces | **yes** |
| `external` | file-backed pages | **no** |

All four are rev0 fields of the struct, i.e. present in every revision that
carries `phys_footprint` at all, so no version gate is needed beyond the
`KERN_SUCCESS` the existing code already requires. A fifth key,
`footprintUnexplainedMB`, publishes `phys_footprint − (internal + compressed +
device)`: if the ledger adjustments the struct does not expose are carrying real
weight, the report says so rather than presenting an incomplete decomposition as
a complete one.

**One risk I am naming rather than hiding.** I have no macOS SDK in this
environment, so the Swift above is **written but never compiled**, and §1.4 of
the plan is this branch's record of what an untested platform assumption costs.
Two specific things a Mac would settle in thirty seconds:

* `internal` is a Swift keyword, so the field is read as ``info.`internal` ``.
  Backticks are the documented escape for exactly this and are a no-op where
  unnecessary, so this should be right either way — but "should be" is doing
  work in that sentence.
* the four field names are read from the `task_vm_info` layout, in the same
  struct and the same call the existing code already reads `phys_footprint`
  from successfully.

If either is wrong the iOS build fails loudly at compile time — it cannot
produce a wrong *number*, only a red build — and the fix is a one-line rename.
**Whoever builds this first should build the iOS target before anything else.**
That is the entire risk surface of this session outside Dart.

**With that said: this is the shape the answer will take, and it is a
prediction, not a result.** With those four numbers, §8.5's observation stops
being a curiosity:

* a footprint near 4× RSS *before* the suite, with a large `compressed`, is a
  process that has been idle and had its heap compressed out of residency —
  memory it is still paying for and `currentRss` cannot see;
* a footprint near 2.5× RSS *after* the suite is the same heap decompressed and
  resident, plus fresh allocations that were never compressed;
* a footprint that exceeds `internal + compressed` by a wide margin is GPU and
  RealityKit surfaces, which is a display-path finding, not a heap one.

Which of those it is, is what the soak's series will say — and it will say it
over ninety samples rather than four. The prediction is registered in §3.

### 2.2 The 105 MB, re-derived

§5.5.2 predicted the memory of a 1024-entity DOF analysis from the dimensions of
the two **dense** structures the algorithm built:

| structure | dimensions | bytes |
| --- | --- | ---: |
| dense Jacobian | 2562 × 3584 × 8 B | 73.5 MB |
| null-space basis | 1022 × 3584 × 8 B | 29.3 MB |
| predicted | | **102.8 MB** |
| measured `stress.analyze.rssDeltaMB` | | **105 MB** |

S3 replaced both structures with sparse ones in round one. The figure is
therefore a property of code that no longer ships, and OPTIMIZATION_PLAN_2 §5 is
right that it is worth re-deriving.

#### The algebra still closes exactly

First, the part that did not change. On the current code, at the top rung
(`sketchFixture(512)` / `constraintFixture(512)`):

```
total = 512·3 + 512·4                  = 3584 parameters
m     = 511·1 + 1024·2 + 2 + 1         = 2562 residuals
rank  = 2562  (full row rank)
dof   = 3584 − 2562                    = 1022
```

Measured via `debugRank`: **3584 / 2562 / 2562 / 1022**. §5.5.2's arithmetic is
reproduced exactly. The fixture still produces the system the model assumes, so
any byte figure derived from it is derived from the right system.

*(One unit note, so nobody chases a discrepancy: 102.8 MB in §5.5.2 is decimal
megabytes. The same byte count is 98.0 MiB. They agree; only the prefix
differs.)*

#### The measurement — differential, one process, one machine

`solver.dart` still carries the dense algorithm as a frozen, test-only
reference behind `denseReferenceForTests`, kept by S3 for exactly this kind of
question. So the comparison needs no recorded constant at all: both algorithms
run on the same fixture, in the same process, in the same run.

Host, Linux x64, Dart 3.9.2 (JIT), delta measured the instant the call returns:

| top rung, 1024 entities | dense reference | sparse (shipping) |
| --- | ---: | ---: |
| wall clock | 30 833 ms | **2 274 ms** |
| RSS delta | 324.3 MiB | **25.1 MiB** |
| `dof` / free points / loose carriers | 1022 / 1533 / 1023 | 1022 / 1533 / 1023 |

**12.9× less memory and 13.6× less time, for an identical analysis.**

At 256 entities the same comparison gives 6.1 MiB of predicted dense pointer
array against 13.2 MiB measured — see §2.3, which is where that factor of two
comes from.

**Provenance, so nobody mistakes which of these a test guards.** The 1024-entity
row is a one-off run of the protocol above: the dense arm alone is 31 seconds,
which is too much to put in `flutter test` on every commit. The committed test,
`s10_analyze_memory_test.dart`, runs the identical protocol at **512 entities**
— the ladder's second-highest rung, about two seconds of dense arm — and asserts
the two things that carry the claim: that the dense arm exceeds half its own
predicted pointer array, and that the sparse arm is at least 4× cheaper. Both
assertions are one-sided and unit-free, so neither is a golden. The 1024 figures
are quoted here as measurements, not as pins.

#### The conclusion, stated carefully

**The 105 MB figure no longer holds and must not be carried into any headroom
argument for a memory-constrained device.** §9.3 lists it as one of three
transferable structural figures; after S3 the transferable list is 14 bytes per
triangle, 2 KB per solid, and — for the DOF path — a *churn* figure rather than
a matrix.

Two caveats I would rather state than have someone else find.

**On what the 105 MB actually measured.** `_ladder` records
`stress.<name>.rssDeltaMB` as RSS *after the whole ladder finished* minus RSS
before it started. That is retained heap across a ladder that climbed 64 → 1024,
not the peak of the top rung. §5.5.2 read it as the top rung's live allocation.
Both readings are defensible; they are not the same quantity, and the "agreement
to 2.2 %" rests on identifying them.

**On the byte model.** A `List<double>` in the Dart VM is an array of *pointers*
to boxed doubles, so a double in one costs 8 + 16 bytes, not 8. §5.5.2 counted
only the pointer array. That makes 102.8 MB a **lower bound** on the dense
structures, not an estimate of them — and it is visible in the numbers: at 256
entities the pointer array is 6.1 MiB and the measured delta is 13.2 MiB.

Neither caveat changes the conclusion. Both mean the 2.2 % agreement should be
read as two approximations meeting rather than as a confirmation of the model,
and I would not want the next person to build on it as though it were the
latter.

### 2.3 What allocates the DOF path now — and it is not a matrix

The dense measurement above is 324 MiB against 98 MiB of pointer arrays. The
excess is not fill-in and not boxing alone. It is the part §5.5.2 never counted,
because the dense matrices dwarfed it:

`_jacobian` differentiates by finite differences, which means **one full
`_residuals` evaluation per parameter**, each returning a fresh growable
`List<double>` of length `m`. At the top rung:

```
per call : 2562 doubles × (8 B pointer + 16 B box)   =   61.5 KB
calls    : 3584 (one per parameter)
total    : 3584 × 2562 × 24 B  =  220.4 MB  =  210.2 MiB
```

**Per DOF analysis. Unchanged by S3** — that loop is the same in both paths. It
is O(n²) in entities, and it is now the only superlinear allocation term left on
this path.

What it costs in resident memory depends entirely on whether it survives a
scavenge, and the two arms measure that directly: with a live set of ~1 MiB the
sparse path absorbs the same 210 MiB of churn in **25 MiB** of RSS high-water,
because the buffers die in new space. With 98 MiB of matrices live throughout,
the dense path's churn is promoted instead, and the total is 324 MiB.

That is a mechanism, and it is the mechanism that matters for iOS: **the process
is charged for the heap it grows to absorb an allocation rate, not for the data
it keeps.** It is also, incidentally, why footprint and RSS drift apart the way
§8.5 records — a heap that has recently absorbed a burst has pages the
compressor will take back later.

I am not proposing a change to it. `_jacobian` is `solver.dart`, which is S9's,
and §0 rule 6 says to write it down rather than fix it. §5.2 does.

### 2.4 A caveat that applies to every RSS figure in this report, including §8.5's

Everything above is measured with `ProcessInfo.currentRss`, which is what the
apparatus has always used (`quality.memPer*`, `stress.*.rssDeltaMB`). It is
worth one paragraph on what that instrument can and cannot do, because I
watched it fail.

RSS is what the kernel has given the process, not what the program is using. A
Dart heap that already has spare capacity **absorbs a large allocation without
asking for a page**, and a collector that decides to compact **hands pages back
in the middle of a measurement**. Both happen at the sizes this branch works at.
Two observations from building the test above:

* An earlier version of the dense-versus-sparse comparison ran in a process
  whose heap was already 288 MB, and measured the dense algorithm at **minus
  65 MB**. Not noise around a small number — a large negative, because the VM
  returned pages during the call.
* A 100 MB allocation in a warm standalone VM moved `ProcessInfo.maxRss` by
  1.3 MB and moved `currentRss` **down** by 10 MB. `maxRss` is monotone, which
  makes it safe, and useless in a warm process for the same reason.

The consequence for §2.2 is that the comparison had to be moved into its own
test file, so `flutter test` gives it a cold process; there it is decisive and
stable. The consequence for the report generally is narrower than it sounds:
the figures §8.5 rests on — 14 bytes per triangle from 12 solids held, 2 KB per
solid, 0 MB net across 64 held-and-released solids — are deltas around **large,
held** allocations, which is the case RSS handles best. They stand.

What does not survive is reading a small single-call `rssDeltaMB` as an
allocation figure. `mem.analyze.*` publishes one anyway, because it is what the
tier can measure, and its note says in the report what it is. The number in that
family that is exact is `churnMB`, and it is exact because it is arithmetic.

---

## 3. Predictions, registered before the first device run

Nothing here has run on a device. These are pre-registered so the paired capture
adjudicates them rather than confirming them.

### P1 — the footprint decomposition accounts for the total

```
Target        : PerfProbe footprintUnexplainedMB, any probe point
Baseline      : does not exist; today only the total is reported.
Mechanism     : phys_footprint is the ledger sum of internal + compressed +
                iokit/device plus adjustments the struct does not expose.
Predicted     : |footprintUnexplainedMB| < 0.15 × footprintMB at every probe.
Derivation    : the unexposed adjustments (purgeable ledgers, page tables,
                alternate accounting) are small for a process with no large
                purgeable pool. A 1233 MB footprint should decompose to within
                ~185 MB.
Falsifiable by: a residual above 15 %, which would mean the decomposition is
                NOT the answer to 8.5 and the table in 2.1 must not be read as
                one.
Risk          : the four fields are rev0 and always filled, so this is a
                question about the ledger, not about the read.
```

### P2 — the pre-suite ratio near 4 is the compressor

```
Target        : compressedMB at the preSuite probe, against the same at post.
Baseline      : 8.5 — ratio 3.60 and 4.00 BEFORE the suite, 2.52 and 2.47
                after; RSS roughly doubles across the suite while the
                footprint stays flat or falls.
Mechanism     : an app that has been idle has had its heap compressed out of
                residency. Compressed pages are charged to the footprint and
                are NOT in resident_size, which is exactly a footprint that
                exceeds RSS. Running the suite touches that memory, which
                decompresses it: RSS rises, the footprint does not, and the
                ratio falls.
Predicted     : compressedMB(preSuite) > compressedMB(postSuite), and
                compressedMB(preSuite) > 0.4 × (footprintMB − residentMB)
                at the same probe.
Falsifiable by: compressed being small at both ends, which would put the gap
                on `device` instead — a display-path answer, not a heap one,
                and a more interesting result than the one predicted.
Risk          : the two arms of the paired run differ in Low Power Mode, which
                changes compressor behaviour. Compare within an arm.
```

### P3 — the soak finds no leak, at a floor worth stating

```
Target        : soak.footprintSlopeKBPerHour and soak.footprintFloorKBPerHour
Baseline      : none — never run.
Mechanism     : the cycle allocates and releases the same objects every
                iteration; 12.4 already measured 64 solids held and released
                at 0 MB net RSS, k = 0.984, so the OCCT side is known clean
                across a 16x range.
Predicted     : |slope| < floor — i.e. NOT resolved — with a floor below
                20 MB/h.
Derivation    : 90 samples over 30 minutes. At the ±2 MB sample-to-sample
                scatter a 1 MB-resolution footprint gauge gives, the standard
                error of the slope over a 30-minute span is about
                2 / (sqrt(90) · 8.7 min) ≈ 0.024 MB/min, so 1.96 se ≈ 2.8
                MB/h. A 20 MB/h floor is a 7x allowance for real drift.
Falsifiable by: a resolved positive slope the settle phase does not return —
                which would be the first leak this project has ever measured
                and is the outcome the tier exists for.
Risk          : if the floor comes back ABOVE 20 MB/h the run has proved
                nothing and the answer is a longer soak or a denser cadence,
                not a smaller claim. That is a result too, and the report is
                built to say it.
```

### P4 — the jank trend is flat and the thermal trend is not

```
Target        : soak.jankSlopePerKFramePerHour, soak.thermalStart/Max
Baseline      : 3.1 — the device sat at nominal through a 293 s suite.
Mechanism     : thirty minutes of continuous work on a fanless iPad is a
                sustained load; 3.5 established that this device throttles
                measurably under one.
Predicted     : thermalMax > thermalStart (the device heats up), while the
                jank rate stays below its own floor.
Derivation    : the cycle is tens of milliseconds of work against a 16 ms
                frame; it cannot saturate the UI thread. What rises should be
                the temperature, not the drop rate.
Falsifiable by: a resolved rising jank slope, which given a flat footprint
                would point at the frame pipeline rather than at memory — and
                would belong to S8, not to me.
```

### P5 — `mem.analyze` is quadratic in RSS, not cubic

```
Target        : mem.analyze.{64,128,256}.rssDeltaMB
Baseline      : 5.5.2 — the DENSE allocation was O(n^2) and dominated by two
                matrices.
Mechanism     : the matrices are gone. What remains that grows superlinearly
                is the churn: params x residuals x 24 B, and both factors are
                linear in entities, so the churn is O(n^2). The live sparse
                structures are O(nnz), which is linear in this fixture.
Predicted     : the fitted exponent of rssDeltaMB against entity count is
                nearer 2 than 1, while settledDeltaMB grows about linearly.
Derivation    : churn at 256/512/1024 entities is 3.3 / 13.1 / 52.6 / 210 MiB
                — a factor of 4 per doubling, i.e. exponent 2.
Falsifiable by: a cubic RSS exponent, which would mean a dense structure I
                did not find is still being built.
Risk          : RSS is a poor instrument for this — it moves in pages and the
                collector is not asked permission — so a failure here is more
                likely to indict the instrument than the model. Read it with
                the churn arithmetic beside it, which is exact.
```

---

## 4. What I deliberately did not do

* **I did not change a single existing scenario.** The exemption is to add;
  editing one would silently change what every past number meant. `baseline.json`
  is untouched, and every name in it still means what it meant.
* **I did not touch `solver.dart`.** §2.3 identifies a 210 MiB per-call
  allocation there and stops at identifying it. It is S9's file and, in round
  two, S9's session.
* **I did not read the `ledger_tag_*` fields.** `ledger_tag_graphics_nonvolatile`
  would attribute the GPU share of the footprint exactly rather than by way of
  `device`, and I wanted it. It is a rev3 field, I have no macOS SDK here to
  compile against, and reading a struct field the kernel did not fill returns
  whatever was on the stack. A memory report that prints stack garbage as a
  measurement is worse than one that prints four fields instead of six. If
  someone with a Mac wants it, the gate is a `count` check against
  `MemoryLayout.offset(of:)`, and the four fields shipping now are rev0 and need
  no gate at all.
* **I did not force a garbage collection**, because Dart cannot. The first
  version of `_gcNudge` allocated and dropped 48 MB rounds, which grows the
  resident set of the very measurement it was cleaning up; every "settled"
  figure it produced was noise. It churns small objects now, and both the code
  and the report say a settled figure is a lower bound on the live set and never
  the live set.
* **I did not run the soak for thirty minutes anywhere.** The tests run it for
  three to six seconds, which exercises every path in it but measures nothing
  about this application's memory over half an hour.
* **I did not re-record `perf/baseline.json`.** §5's S10 entry makes my
  exemption conditional on the re-record having happened; it has not. Nothing
  here depends on it — the new tiers are opt-in, produce their own files, and
  add no name the existing gate compares.

---

## 5. Defects found in other sessions' areas — written down, not fixed

### 5.1 The solver logs per solve, and a soak turns that into megabytes

`solveConstraints` and `_lm` each write a `Log.d` line per call. A thirty-minute
soak at the cycle rate this file uses is of the order of 10^5 lines, so:

* the event log grows past its 8 MB rotation threshold **during** a session, and
  the rotation check only runs at `Log.init` — so it grows unbounded within one
  run;
* every line is also a `print`, which on device is an `os_log` round trip.

It does not invalidate the soak — log pages are file-backed, and file-backed
pages are `external`, which is *not* charged to `phys_footprint` — and the soak
now measures the growth so that claim is checkable rather than asserted. But a
long session writes a large file and pays for it in wall clock, and neither
`log.dart` nor `solver.dart` is mine. Owners: `solver.dart` is S9's;
`log.dart` is unassigned.

**Needs:** integrator — only to decide whether it wants an owner. There is no
correctness issue here and no urgency.

### 5.2 `_jacobian` allocates a residual vector per parameter

§2.3. 210 MiB of transient allocation per top-rung DOF analysis, O(n²), in
`solver.dart`. The obvious remedy — differencing into a reused buffer instead of
returning a fresh list — is a `solver.dart` change and therefore S9's or a later
session's. I record the arithmetic and the measurement; I propose nothing.

### 5.3 `_ladder`'s `rssDeltaMB` is a ladder-wide retained figure, quoted as a rung figure

§2.2. `perf_scenarios_stress.dart` is mine to edit under the exemption, and I
have **not** edited it: changing what `stress.analyze.rssDeltaMB` measures would
retroactively change what every recorded value of it meant, which is exactly
what the exemption forbids. The fix is a note in `PERFORMANCE_PROFILE.md` §5.5.2
at integration, not a code change.

---

## 6. Verification

Run on the host (Linux x64, Flutter 3.35.7 stable, Dart 3.9.2) — the same
combination `dart-checks` uses on `ubuntu-latest`.

| gate | result |
| --- | --- |
| `flutter analyze` | **zero issues in every file this session touched.** The repository carries 55 pre-existing infos and warnings, none of them mine; CI runs `--no-fatal-infos --no-fatal-warnings` and the run exits 0 with no `error •` line anywhere |
| `flutter test` | **green — 2182 tests**, 15 of them new |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | **green — 49 tests**, 4 of them new |
| behaviour pinned by a differential test | §1.3 (the leak calibration) and §2.2 (dense vs sparse, one process, identical results) |
| predictions with arithmetic, before the change | §3 |

Nothing here has run on an iPad, on a simulator, or under Lane C. Lane C
benches the C++ shim and this session touched no C++; the soak is by
construction a device instrument. Every host figure in §2.2 is a JIT VM on x64
and is quoted as a **ratio between two arms measured together**, never as a
number that transfers — §13.3's rule, applied to a host rather than a
simulator.

**Not claimed: "it is faster."** Nothing here was meant to be. Nothing here has
run on a device, and the first thing the next device capture should do with this
session is type `soak` and wait half an hour.

---

## 7. Files

| file | change |
| --- | --- |
| `frontend/lib/perf_scenarios_soak.dart` | **new** — the soak, the fit, the memory family |
| `frontend/test/s10_soak_test.dart` | **new** — 14 tests |
| `frontend/test/s10_analyze_memory_test.dart` | **new** — the dense-vs-sparse re-derivation, alone in its own process (§2.4 says why) |
| `frontend/lib/bug_capture.dart` | two opt-in keywords, additive |
| `frontend/packages/native_menu/ios/Classes/PerfProbe.swift` | five new keys, additive |
| `ci/perf_report.py` | sections 2b and 2c, two new bundle members |
| `ci/perf_profile.py` | two new bundle members |
| `ci/test_perf_tools.py` | four new tests |
| `perf/findings/S10-memory.md` | this |
| `perf/findings/CROSS-SESSION.md` | one appended entry (S10-1a … S10-1e) |
| `perf/findings/README.md` | a round-two ownership table beside round one's |

**Branch.** §3 puts this session on `claude/perf-opt2-memory`, off an
integration branch `claude/perf-opt2` that does not exist on the remote yet —
nobody in round two has created it. This work is on
`claude/scenario-18-footprint-analysis-czgcp1`, branched from the pin
(`perf-capture-round1` @ `b2de0c2`) exactly as §3 requires, and it fast-forwards
from `main` rather than diverging from it. **It should be merged into
`claude/perf-opt2` when that branch exists**, and it will merge cleanly: every
change is additive, and the only shared files it touches are the two
append-only ones and the findings README.

Nothing here has been merged anywhere, and nothing here is on the critical path
for the round-one capture — §1.1's pin is untouched, no code round one changed
has been changed again, and the two new tiers are opt-in, so a capture taken
without typing `soak` or `memory` produces byte-identical output to one taken
before this session.
