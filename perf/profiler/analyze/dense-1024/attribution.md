# CPU sample attribution

* capture: `2026-08-20T11:39:34Z` target `flutter test` sha `2430e415e43e`
* sample period: **250 us**, max stack depth 128, total samples 37769 (duplicates merged away: 10510)
* selection: userTag `profiler.measure` -> **17657** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=analyze n=1024 repeats=1 wallMs=42749.415`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=true` `sample_buffer_duration=0` `max_profile_depth=128`
* **WARNING: `profile_vm=true`.** The profiler is collecting native stacks; on an engine built without frame pointers most samples come back one frame deep and cannot be attributed to any Dart function. Shares below are not trustworthy.

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **32.0 %** of the 44.17 s it was attached for (1193 gaps wider than 3 periods, 30.03 s unobserved); effective period 376 us against a nominal 250 us
* **WARNING: under a quarter of the elapsed time is missing from this capture.** Poll more often (`--poll-interval`); the VM's sample ring is dropping samples between calls and the shares below are shares of what survived, not of what ran.

### Census — what the sampler caught

* samples in this view: **35949**
* with at least one Dart frame: **17657** (49.1 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 18292
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |
| `main#2958` | 35949 |

VM tags: `Dart` 16043, `DRT_InterruptOrStackOverflow` 11725, `DRT_AllocateDouble` 6404, `DLRT_NewMarkingStackBlockProcess` 1561, `DRT_AllocateArray` 75, `DRT_AllocateObject` 55, `DRT_AllocateContext` 50, `DRT_AllocateSmallRecord` 22

### Flat profile — samples with a Dart frame

Samples: **17657**, period 250 us (~4414.2 ms of sampled CPU time). Shares are of these 17657 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 9622 | 54.49 | [53.76, 55.23] | 9684 | 54.85 | `_rankAndPivots (solver.dart:1099)` |
| 2 | 4213 | 23.86 | [23.24, 24.49] | 17568 | 99.50 | `_analyzeSketch (solver.dart:2470)` |
| 3 | 714 | 4.04 | [3.76, 4.34] | 714 | 4.04 | `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x98f70` |
| 4 | 492 | 2.79 | [2.55, 3.04] | 1814 | 10.27 | `_residuals (solver.dart:601)` |
| 5 | 320 | 1.81 | [1.63, 2.02] | 320 | 1.81 | `residualCount.pt (solver.dart:335)` |
| 6 | 281 | 1.59 | [1.42, 1.79] | 281 | 1.59 | `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x98fd7` |
| 7 | 224 | 1.27 | [1.11, 1.44] | 224 | 1.27 | `_pointAt (solver.dart:174)` |
| 8 | 223 | 1.26 | [1.11, 1.44] | 226 | 1.28 | `_GrowableList._grow (growable_array.dart:387)` |
| 9 | 194 | 1.10 | [0.96, 1.26] | 421 | 2.38 | `_GrowableList.add (growable_array.dart:283)` |
| 10 | 149 | 0.84 | [0.72, 0.99] | 592 | 3.35 | `residualCount (solver.dart:332)` |
| 11 | 137 | 0.78 | [0.66, 0.92] | 137 | 0.78 | `pthread_mutex_lock` |
| 12 | 115 | 0.65 | [0.54, 0.78] | 115 | 0.65 | `__pthread_mutex_unlock` |
| 13 | 105 | 0.59 | [0.49, 0.72] | 106 | 0.60 | `_circle (solver.dart:308)` |
| 14 | 90 | 0.51 | [0.41, 0.63] | 90 | 0.51 | `residualCount.ent (solver.dart:334)` |
| 15 | 78 | 0.44 | [0.35, 0.55] | 78 | 0.44 | `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x98f6e` |
| 16 | 77 | 0.44 | [0.35, 0.54] | 116 | 0.66 | `malloc` |
| 17 | 72 | 0.41 | [0.32, 0.51] | 17654 | 99.98 | `analyzeSketch.<anonymous closure> (solver.dart:2465)` |
| 18 | 66 | 0.37 | [0.29, 0.48] | 67 | 0.38 | `_List._List.filled (array.dart:101)` |
| 19 | 56 | 0.32 | [0.24, 0.41] | 56 | 0.32 | `_Double.abs (double.dart:184)` |
| 20 | 35 | 0.20 | [0.14, 0.28] | 35 | 0.20 | `[Native] /opt/fl/flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester+0x15ba2f9` |
| 21 | 33 | 0.19 | [0.13, 0.26] | 33 | 0.19 | `[Native] /opt/fl/flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester+0x15ba155` |
| 22 | 32 | 0.18 | [0.13, 0.26] | 33 | 0.19 | `_Record.hashCode (record_patch.dart:42)` |
| 23 | 31 | 0.18 | [0.12, 0.25] | 90 | 0.51 | `__Set&_LinkedHashBase&SetMixin&_HashBase&_OperatorEqualsAndHashCode&_LinkedHashSetMixin._getKeyOrData (compact_hash.dart:1075)` |
| 24 | 28 | 0.16 | [0.11, 0.23] | 28 | 0.16 | `_active (solver.dart:329)` |
| 25 | 18 | 0.10 | [0.06, 0.16] | 18 | 0.10 | `_ArrayIterator.moveNext (array.dart:285)` |

### Inside `analyzeSketch`

Root `analyzeSketch`: **17654** samples of 17657 (~4413.5 ms). Shares below are of those 17654.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 9684 | 54.85 % | [54.12, 55.59] | 2421.0 |
| jacobian | 1814 | 10.28 % | [9.84, 10.73] | 453.5 |
| other | 6156 | 34.87 % | [34.17, 35.58] | 1539.0 |

Leaves seen in `other` (up to 12): `ListIterator._current (iterable.dart:350)`, `ListIterator._index (iterable.dart:349)`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x1993c0`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x19944f`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x19946b`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x199486`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x19949f`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x1994b1`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x1994b8`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x98d6f`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x98d71`, `[Native] /lib/x86_64-linux-gnu/libc.so.6+0x98f40`

