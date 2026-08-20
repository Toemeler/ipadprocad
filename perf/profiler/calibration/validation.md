# Profiler validation — profiler calibration against a ground truth measured in the same run

**PASS** at `2430e415e43e`, 2026-08-20T07:46:15Z

Source of truth: tools/profiler/scenarios/known_split.dart — a Stopwatch around each phase, printed by the run itself

OPTIMIZATION_PLAN_2.md §1.4 requires an equivalence test to be DIFFERENTIAL: old against new, on the same machine, in the same run, never a constant recorded elsewhere. Applied to an instrument rather than to an optimisation, that means the profiler must recover a split that the profiled process measured for itself, while it was being profiled. The fixture is the shape of PERFORMANCE_PROFILE.md §5.5.2 — a dense finite-difference Jacobian at total = 3584, m = 2562, then a Gauss-Jordan reduction of it, the same dimensions stress.sketch.analyze's top rung produces. The two phases are run different numbers of times so the true share sweeps low, middling and high: a single point can be hit by an instrument with a constant bias, a three-point sweep cannot. Storage is Float64List rather than List<double> deliberately — boxed doubles make the collector, which the Dart sampler cannot see at all, the dominant confound, and calibrating an instrument against a confound measures the confound. Two confounds are removed rather than argued about: the phase functions carry @pragma('vm:never-inline'), because getCpuSamples reports the PHYSICAL code object and an inlined callee is charged to its caller; and the matrix copies each repeat needs are made outside both timed regions, so no untimed work can be mistaken for a profiler error. `maxOther` caps the samples inside the root that fall in neither phase — a split may not be quoted from a capture where a fifth of the root is unaccounted for.

## low-share — PASS

| check | verdict | detail |
| :--- | :--- | :--- |
| sample count | PASS | 4991 samples inside main |
| unattributed share | PASS | `other` is 0.14 % of the root (cap 15 %) — a split is not quotable from a capture with a large unattributed remainder |
| elimination vs measured elimShare | PASS | profiler 14.13 % [13.17, 15.10] vs the run's own Stopwatch 14.46 % (|delta| 0.34 pp, tolerance 5.0 pp) |

## even-share — PASS

| check | verdict | detail |
| :--- | :--- | :--- |
| sample count | PASS | 3277 samples inside main |
| unattributed share | PASS | `other` is 0.27 % of the root (cap 15 %) — a split is not quotable from a capture with a large unattributed remainder |
| elimination vs measured elimShare | PASS | profiler 43.94 % [42.13, 45.53] vs the run's own Stopwatch 44.95 % (|delta| 1.01 pp, tolerance 5.0 pp) |

## high-share — PASS

| check | verdict | detail |
| :--- | :--- | :--- |
| sample count | PASS | 5681 samples inside main |
| unattributed share | PASS | `other` is 0.23 % of the root (cap 15 %) — a split is not quotable from a capture with a large unattributed remainder |
| elimination vs measured elimShare | PASS | profiler 76.04 % [74.74, 76.96] vs the run's own Stopwatch 75.54 % (|delta| 0.50 pp, tolerance 5.0 pp) |

