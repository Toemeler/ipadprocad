# `tools/profiler` — the sampling profiler (plan item A4)

> **PERFORMANCE_PROFILE.md §15.5** — "The sampling profiler (VM Service
> `getCpuSamples` → Perfetto), plan item A4. The suite says which *operation*
> costs what; a profiler says which *line*. … Still the largest unbuilt piece
> of apparatus."

Attaches to a Dart VM from **outside the process**, samples it, and writes a
trace Perfetto can open plus an attribution table with confidence intervals.
It contains no application code and requires no hook inside one —
`OPTIMIZATION_PLAN_2.md` §4 forbids that, and the VM Service is an
out-of-process debugger interface, so nothing is lost by it.

Standard-library Python only. `ci/` has no dependency file and no runner in
this repository installs one.

## Quick start

```bash
# 1. Is the instrument working? Three captures, ~4 minutes, gating in CI.
python3 tools/profiler/profile.py validate \
    --expectation tools/profiler/expectations/known_split.json \
    --out /tmp/prof/calibration

# 2. Profile the app's DOF analysis on the host.
python3 tools/profiler/profile.py capture \
    --target flutter-test --scenario analyze --n 1024 \
    --root analyzeSketch \
    --bucket 'elimination=_rankAndPivots' \
    --bucket 'jacobian=_jacobian,_residuals' \
    --out /tmp/prof/analyze

# 3. Attach to something already running (flutter run, a simulator, anything).
python3 tools/profiler/profile.py capture \
    --target attach --uri 'http://127.0.0.1:PORT/TOKEN=/' \
    --duration 60 --out /tmp/prof/live

# 4. Re-read a capture later. No VM needed.
python3 tools/profiler/profile.py report /tmp/prof/analyze/samples.json.gz \
    --root analyzeSketch --top 40
```

## What comes out

| file | what it is |
| --- | --- |
| `attribution.md` | flat profile and phase split, with 95 % Wilson intervals, plus the census and coverage lines that say what the capture is worth |
| `attribution.json` | the same, for a script |
| `trace.json.gz` | `gunzip`, then open at **ui.perfetto.dev**. Chrome JSON trace format, which Perfetto ingests natively |
| `stacks.folded.txt` | `root;middle;leaf <count>` — one line per distinct stack. The form that survives being read out of a git branch with `grep` |
| `samples.json.gz` | the normalised capture, replayable through `report` |
| `RUN.txt` | run id, sha, ref, period, sample count |

## Read the header before the tables

Every report opens with three lines that decide whether the numbers below them
mean anything. They are there because each one was, at some point in this
session, the difference between a believable profile and a wrong one.

* **`coverage`** — what fraction of the elapsed time the sampler actually
  observed. A sampling profiler is unbiased only over the intervals it
  sampled; the VM's sample ring cannot be resized at runtime, and time inside
  the garbage collector has no Dart stack to walk. Captures in this repository
  have ranged from 29 % to 89 %.
* **`profile_vm`** — if this says `true`, the VM is collecting **native**
  stacks. On an engine built without frame pointers, roughly half the samples
  then come back one frame deep and cannot be attributed to any Dart function.
  The report says so in bold and the shares below it must not be quoted.
  `flutter test` always sets it; a plain `dart` VM does not.
* **the census** — how many samples had a Dart frame at all, and on which
  threads. Idle engine threads sitting in `pthread_cond_timedwait` were 63 % of
  the samples in the first capture taken with this tool.

## What it resolves to, and what it does not

The VM's sampler resolves to a **function**, never to a statement inside one.
`file:line` here is the line the function is *declared* on, recovered from the
script's `tokenPosTable`. That is the same granularity `PERFORMANCE_PROFILE.md`
already speaks in when it cites `solver.dart:2517`, and stating the limit is
cheaper than letting a reader assume otherwise.

Two further limits, both measured rather than supposed
(`perf/findings/S7-profiler.md` §4):

* **Inlining.** `getCpuSamples` reports the physical code object, so a callee
  inlined into its caller is charged to the caller.
* **Collected code.** A code object deoptimised and collected between the
  sample and the fetch comes back as `<unknown Dart function>`. Polling often
  is the mitigation; the merge keeps the first, best-symbolicated copy of every
  sample.

## Layout

```
profile.py       the CLI: capture / report / validate
vmservice.py     RFC 6455 websocket + JSON-RPC, stdlib only
samples.py       the sampling session; getCpuSamples -> a normalised SampleSet
attribution.py   flat profile, phase split, Wilson intervals, census
perfetto.py      SampleSet -> Perfetto-ingestible JSON, and folded stacks
targets.py       where the VM Service comes from: attach / flutter test / dart / simulator
scenarios/       Dart drivers, materialised into frontend/build/ (gitignored)
expectations/    the known attributions `validate` checks against
tests/           python3 -m unittest discover -s tools/profiler/tests -p 'test_*.py'
publish.sh       put a capture on the ci-logs-profile branch (§13.1's lesson)
```

## The rule this tool is built around

An instrument that cannot reproduce a cost split somebody already measured by
other means must not be believed on a split nobody has measured. So the known
splits live in `expectations/` **as data**, and `validate` exits non-zero when
the profiler disagrees with one. `expectations/known_split.json` is the gating
one: the fixture measures its own phase split with a `Stopwatch` *while being
profiled*, so the check is differential in the sense `OPTIMIZATION_PLAN_2.md`
§1.4 requires — two instruments, same machine, same run — and there is no
recorded constant to go stale on another platform.
