# Profiler validation — analyzeSketch phase split at 1024 entities

**FAIL** at `2430e415e43e`, 2026-08-20T11:39:56Z

Source of truth: perf/findings/S3-solver.md §2 (host baseline, wall-clock timers) and §6; PERFORMANCE_PROFILE.md §5.5.2

A sampling profiler that cannot reproduce a cost split somebody already measured by other means must not be believed on a split nobody has measured. Both cases below profile `stress.sketch.analyze`'s top rung — sketchFixture(512) + constraintFixture(512), total = 3584 parameters, m = 2562 residuals, dof = 1022, the arithmetic PERFORMANCE_PROFILE.md §5.5.2 closes exactly. The DENSE case runs the solver as it stood at 4890f06, which is bit-identical to build 230f179's solver.dart — the build the device numbers were taken on. The SPARSE case runs round one's tip. S3 measured the dense split with explicit Stopwatch timers around the two phases and stated the sparse one from the mechanism; neither number came from a sampler, so neither is circular. Both cases are run with the same profiler settings the calibration in expectations/known_split.json passes under, and with the same refusal rule: a split is not quotable from a capture whose unattributed remainder exceeds 15 % of the root.

## dense-1024 — FAIL

| check | verdict | detail |
| :--- | :--- | :--- |
| sample count | PASS | 17654 samples inside analyzeSketch |
| unattributed share | FAIL | `other` is 34.87 % of the root (cap 15 %) — a split is not quotable from a capture with a large unattributed remainder |
| elimination | FAIL | share 54.85 % [54.12, 55.59] vs registered [78.0, 93.0] %  (known: S3-solver.md §2: Jacobian construction 3.191 s, elimination 21.004 s, total 24.195 s -> 21.004/24.195 = 86.81 %) |

## sparse-1024 — FAIL

| check | verdict | detail |
| :--- | :--- | :--- |
| sample count | PASS | 12732 samples inside analyzeSketch |
| unattributed share | PASS | `other` is 2.00 % of the root (cap 15 %) — a split is not quotable from a capture with a large unattributed remainder |
| elimination | FAIL | share 48.98 % [48.11, 49.85] vs registered [0.0, 25.0] %  (known: S3-solver.md §6: 'At n = 1024 the remaining second is almost entirely step 1, the finite-difference Jacobian.' §2's derivation puts the sparse elimination at ~0.066 s against ~1.77 s of Jacobian construction = 3.6 %) |
| jacobian | FAIL | share 49.02 % [48.15, 49.89] vs registered [55.0, 100.0] %  (known: the complement of the above: step 1 is what is left) |

