# CPU sample attribution

* capture: `2026-08-20T07:46:09Z` target `dart` sha `2430e415e43e`
* sample period: **250 us**, max stack depth 128, total samples 5033 (duplicates merged away: 4586)
* selection: userTag `profiler.measure` -> **4992** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=2562 rank=2562 jacRepeats=5 elimRepeats=1 storage=Float64List jacobianMs=1921.51 eliminationMs=324.903 elimShare=0.14463190873628315`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **78.3 %** of the 2.38 s it was attached for (70 gaps wider than 3 periods, 0.52 s unobserved); effective period 368 us against a nominal 250 us

### Census — what the sampler caught

* samples in this view: **0**
* with at least one Dart frame: **0** (0.0 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 0
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |

VM tags: 

### Flat profile — samples with a Dart frame

Samples: **4992**, period 250 us (~1248.0 ms of sampled CPU time). Shares are of these 4992 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 3119 | 62.48 | [61.13, 63.81] | 4280 | 85.74 | `phaseJacobianTyped (known_split.dart:67)` |
| 2 | 845 | 16.93 | [15.91, 17.99] | 883 | 17.69 | `residualsInto (known_split.dart:92)` |
| 3 | 542 | 10.86 | [10.02, 11.75] | 625 | 12.52 | `phaseEliminationTyped (known_split.dart:102)` |
| 4 | 227 | 4.55 | [4.00, 5.16] | 227 | 4.55 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 5 | 112 | 2.24 | [1.87, 2.69] | 112 | 2.24 | `_Double.abs (double.dart:184)` |
| 6 | 77 | 1.54 | [1.24, 1.92] | 271 | 5.43 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 7 | 16 | 0.32 | [0.20, 0.52] | 18 | 0.36 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 15 | 0.30 | [0.18, 0.50] | 24 | 0.48 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 9 | 9 | 0.18 | [0.09, 0.34] | 9 | 0.18 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 10 | 9 | 0.18 | [0.09, 0.34] | 9 | 0.18 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 11 | 4 | 0.08 | [0.03, 0.21] | 4 | 0.08 | `_Double.* (double.dart:44)` |
| 12 | 3 | 0.06 | [0.02, 0.18] | 3 | 0.06 | `<unknown Dart function>` |
| 13 | 2 | 0.04 | [0.01, 0.15] | 3 | 0.06 | `_Double.- (double.dart:32)` |
| 14 | 2 | 0.04 | [0.01, 0.15] | 2 | 0.04 | `_Double.+ (double.dart:20)` |
| 15 | 2 | 0.04 | [0.01, 0.15] | 2 | 0.04 | `_List._setIndexed (array.dart:191)` |
| 16 | 1 | 0.02 | [0.00, 0.11] | 4992 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 17 | 1 | 0.02 | [0.00, 0.11] | 25 | 0.50 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 18 | 1 | 0.02 | [0.00, 0.11] | 2 | 0.04 | `ListIterator.moveNext (iterable.dart:361)` |
| 19 | 1 | 0.02 | [0.00, 0.11] | 1 | 0.02 | `ListIterator._current (iterable.dart:350)` |
| 20 | 1 | 0.02 | [0.00, 0.11] | 1 | 0.02 | `_Array.length (array.dart:13)` |
| 21 | 1 | 0.02 | [0.00, 0.11] | 1 | 0.02 | `_Double._sub (double.dart:39)` |
| 22 | 1 | 0.02 | [0.00, 0.11] | 1 | 0.02 | `_EventHandler._sendData (eventhandler_patch.dart:9)` |
| 23 | 1 | 0.02 | [0.00, 0.11] | 1 | 0.02 | `_GrowableList.elementAt (growable_array.dart:500)` |
| 24 | 0 | 0.00 | [0.00, 0.08] | 4992 | 100.00 | `_RawReceivePort._handleMessage (isolate_patch.dart:184)` |
| 25 | 0 | 0.00 | [0.00, 0.08] | 4991 | 99.98 | `main (known_split.dart:201)` |

### Inside `main`

Root `main`: **4991** samples of 4992 (~1247.8 ms). Shares below are of those 4991.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 704 | 14.11 % | [13.17, 15.10] | 176.0 |
| jacobian | 4280 | 85.75 % | [84.76, 86.70] | 1070.0 |
| other | 7 | 0.14 % | [0.07, 0.29] | 1.8 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `_Array.length (array.dart:13)`, `_Double.+ (double.dart:20)`, `_EventHandler._sendData (eventhandler_patch.dart:9)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`

