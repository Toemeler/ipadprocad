# CPU sample attribution

* capture: `2026-08-20T11:39:54Z` target `flutter test` sha `2430e415e43e`
* sample period: **250 us**, max stack depth 128, total samples 19465 (duplicates merged away: 4391)
* selection: userTag `profiler.measure` -> **12740** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=analyze n=1024 repeats=3 wallMs=8057.196`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=true` `sample_buffer_duration=0` `max_profile_depth=128`
* **WARNING: `profile_vm=true`.** The profiler is collecting native stacks; on an engine built without frame pointers most samples come back one frame deep and cannot be attributed to any Dart function. Shares below are not trustworthy.

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **74.0 %** of the 9.69 s it was attached for (621 gaps wider than 3 periods, 2.52 s unobserved); effective period 372 us against a nominal 250 us
* **WARNING: under a quarter of the elapsed time is missing from this capture.** Poll more often (`--poll-interval`); the VM's sample ring is dropping samples between calls and the shares below are shares of what survived, not of what ran.

### Census — what the sampler caught

* samples in this view: **17603**
* with at least one Dart frame: **12740** (72.4 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 4863
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |
| `main#3759` | 17603 |

VM tags: `Dart` 12706, `DRT_InterruptOrStackOverflow` 4581, `DRT_AllocateArray` 148, `DRT_AllocateContext` 59, `DRT_AllocateObject` 41, `GCOldSpace` 25, `DRT_PatchStaticCall` 18, `DRT_AllocateDouble` 12

### Flat profile — samples with a Dart frame

Samples: **12740**, period 250 us (~3185.0 ms of sampled CPU time). Shares are of these 12740 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 3151 | 24.73 | [23.99, 25.49] | 5929 | 46.54 | `_GrowableList.add (growable_array.dart:283)` |
| 2 | 2675 | 21.00 | [20.30, 21.71] | 2719 | 21.34 | `_GrowableList._grow (growable_array.dart:387)` |
| 3 | 1029 | 8.08 | [7.62, 8.56] | 5095 | 39.99 | `_residuals (solver.dart:601)` |
| 4 | 918 | 7.21 | [6.77, 7.67] | 5839 | 45.83 | `_spAxpy (solver.dart:1158)` |
| 5 | 901 | 7.07 | [6.64, 7.53] | 6241 | 48.99 | `_jacobian (solver.dart:1247)` |
| 6 | 889 | 6.98 | [6.55, 7.43] | 891 | 6.99 | `_pointAt (solver.dart:174)` |
| 7 | 784 | 6.15 | [5.75, 6.58] | 784 | 6.15 | `residualCount.pt (solver.dart:335)` |
| 8 | 520 | 4.08 | [3.75, 4.44] | 520 | 4.08 | `_active (solver.dart:329)` |
| 9 | 447 | 3.51 | [3.20, 3.84] | 1880 | 14.76 | `residualCount (solver.dart:332)` |
| 10 | 416 | 3.27 | [2.97, 3.59] | 417 | 3.27 | `_circle (solver.dart:308)` |
| 11 | 345 | 2.71 | [2.44, 3.00] | 345 | 2.71 | `_SpMat.at (solver.dart:1105)` |
| 12 | 125 | 0.98 | [0.82, 1.17] | 125 | 0.98 | `residualCount.ent (solver.dart:334)` |
| 13 | 55 | 0.43 | [0.33, 0.56] | 64 | 0.50 | `_GrowableList._allocateData (growable_array.dart:372)` |
| 14 | 52 | 0.41 | [0.31, 0.53] | 2772 | 21.76 | `_GrowableList._growToNextCapacity (growable_array.dart:406)` |
| 15 | 40 | 0.31 | [0.23, 0.43] | 42 | 0.33 | `_IntegerImplementation.compareTo (integers.dart:213)` |
| 16 | 39 | 0.31 | [0.22, 0.42] | 73 | 0.57 | `__Set&_LinkedHashBase&SetMixin&_HashBase&_OperatorEqualsAndHashCode&_LinkedHashSetMixin._add (compact_hash.dart:1039)` |
| 17 | 32 | 0.25 | [0.18, 0.35] | 42 | 0.33 | `Sort._insertionSort (sort.dart:68)` |
| 18 | 29 | 0.23 | [0.16, 0.33] | 102 | 0.80 | `Sort._dualPivotQuicksort (sort.dart:85)` |
| 19 | 16 | 0.13 | [0.08, 0.20] | 6236 | 48.95 | `_rankAndPivots (solver.dart:1198)` |
| 20 | 15 | 0.12 | [0.07, 0.19] | 216 | 1.70 | `<unknown Dart function>` |
| 21 | 13 | 0.10 | [0.06, 0.17] | 43 | 0.34 | `__Set&_LinkedHashBase&SetMixin&_HashBase&_OperatorEqualsAndHashCode&_LinkedHashSetMixin._rehash (compact_hash.dart:996)` |
| 22 | 12 | 0.09 | [0.05, 0.16] | 12711 | 99.77 | `_analyzeSketch (solver.dart:2790)` |
| 23 | 12 | 0.09 | [0.05, 0.16] | 27 | 0.21 | `__Set&_LinkedHashBase&SetMixin&_HashBase&_OperatorEqualsAndHashCode&_LinkedHashSetMixin._init (compact_hash.dart:1014)` |
| 24 | 12 | 0.09 | [0.05, 0.16] | 25 | 0.20 | `_GrowableList._GrowableList.of (growable_array.dart:146)` |
| 25 | 11 | 0.09 | [0.05, 0.15] | 11 | 0.09 | `_GrowableList.elementAt (growable_array.dart:500)` |

### Inside `analyzeSketch`

Root `analyzeSketch`: **12732** samples of 12740 (~3183.0 ms). Shares below are of those 12732.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 6236 | 48.98 % | [48.11, 49.85] | 1559.0 |
| jacobian | 6241 | 49.02 % | [48.15, 49.89] | 1560.2 |
| other | 255 | 2.00 % | [1.77, 2.26] | 63.8 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `Geo.type (qcad_engine.dart:80)`, `List.List.of (array_patch.dart:36)`, `ListBase.any (list.dart:111)`, `ListBase.sort (list.dart:320)`, `ListIterator.current (iterable.dart:358)`, `Sort._dualPivotQuicksort (sort.dart:85)`, `Sort._insertionSort (sort.dart:68)`, `_CompactIterator.current (compact_hash.dart:855)`, `_Double.abs (double.dart:184)`, `_GrowableList._GrowableList._literal1 (growable_array.dart:569)`, `_GrowableList._GrowableList._literal2 (growable_array.dart:578)`

