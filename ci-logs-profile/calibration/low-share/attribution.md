# CPU sample attribution

* capture: `2026-08-24T18:09:48Z` target `dart` sha `c11faac6c945`
* sample period: **250 us**, max stack depth 128, total samples 2249 (duplicates merged away: 1643)
* selection: userTag `profiler.measure` -> **2229** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=2562 rank=2562 jacRepeats=5 elimRepeats=1 storage=Float64List jacobianMs=856.545 eliminationMs=139.97 elimShare=0.14045950136224744`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **67.6 %** of the 1.08 s it was attached for (63 gaps wider than 3 periods, 0.35 s unobserved); effective period 332 us against a nominal 250 us
* **WARNING: under a quarter of the elapsed time is missing from this capture.** Poll more often (`--poll-interval`); the VM's sample ring is dropping samples between calls and the shares below are shares of what survived, not of what ran.

### Census — what the sampler caught

* samples in this view: **0**
* with at least one Dart frame: **0** (0.0 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 0
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |

VM tags: 

### Flat profile — samples with a Dart frame

Samples: **2229**, period 250 us (~557.2 ms of sampled CPU time). Shares are of these 2229 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 886 | 39.75 | [37.74, 41.80] | 1894 | 84.97 | `phaseJacobianTyped (known_split.dart:67)` |
| 2 | 765 | 34.32 | [32.38, 36.32] | 834 | 37.42 | `residualsInto (known_split.dart:92)` |
| 3 | 205 | 9.20 | [8.07, 10.47] | 245 | 10.99 | `phaseEliminationTyped (known_split.dart:102)` |
| 4 | 136 | 6.10 | [5.18, 7.17] | 136 | 6.10 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 5 | 102 | 4.58 | [3.78, 5.52] | 102 | 4.58 | `_Double.abs (double.dart:184)` |
| 6 | 51 | 2.29 | [1.74, 3.00] | 171 | 7.67 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 7 | 20 | 0.90 | [0.58, 1.38] | 20 | 0.90 | `_Timer._createTimerHandler (timer_impl.dart:479)` |
| 8 | 16 | 0.72 | [0.44, 1.16] | 16 | 0.72 | `_GrowableList.add (growable_array.dart:283)` |
| 9 | 9 | 0.40 | [0.21, 0.77] | 9 | 0.40 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 10 | 7 | 0.31 | [0.15, 0.65] | 17 | 0.76 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 11 | 5 | 0.22 | [0.10, 0.52] | 5 | 0.22 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 12 | 3 | 0.13 | [0.05, 0.39] | 2227 | 99.91 | `main (known_split.dart:201)` |
| 13 | 2 | 0.09 | [0.02, 0.33] | 2229 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 14 | 2 | 0.09 | [0.02, 0.33] | 19 | 0.85 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 15 | 2 | 0.09 | [0.02, 0.33] | 2 | 0.09 | `<unknown Dart function>` |
| 16 | 2 | 0.09 | [0.02, 0.33] | 2 | 0.09 | `_Double.* (double.dart:44)` |
| 17 | 2 | 0.09 | [0.02, 0.33] | 2 | 0.09 | `_Double.- (double.dart:32)` |
| 18 | 1 | 0.04 | [0.01, 0.25] | 2 | 0.09 | `sqrt (math_patch.dart:129)` |
| 19 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `ListIterator._index= (iterable.dart:349)` |
| 20 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `ListIterator._iterable (iterable.dart:347)` |
| 21 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `ListIterator._length (iterable.dart:348)` |
| 22 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `ListIterator.current (iterable.dart:358)` |
| 23 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `Lists.copy (internal_patch.dart:125)` |
| 24 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `_Array.[] (array.dart:8)` |
| 25 | 1 | 0.04 | [0.01, 0.25] | 1 | 0.04 | `_Double./ (double.dart:60)` |

### Inside `main`

Root `main`: **2227** samples of 2229 (~556.8 ms). Shares below are of those 2227.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 299 | 13.43 % | [12.07, 14.91] | 74.8 |
| jacobian | 1894 | 85.05 % | [83.51, 86.47] | 473.5 |
| other | 34 | 1.53 % | [1.09, 2.13] | 8.5 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `Lists.copy (internal_patch.dart:125)`, `_Array.[] (array.dart:8)`, `_Float64List.[]= (typed_data_patch.dart:2975)`, `_GrowableList._GrowableList.generate (growable_array.dart:135)`, `_Timer._createTimerHandler (timer_impl.dart:479)`, `_Timer._heap (timer_impl.dart:143)`, `_TimerHeap.add (timer_impl.dart:35)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `main (known_split.dart:201)`, `main.<anonymous closure> (known_split.dart:217)`

