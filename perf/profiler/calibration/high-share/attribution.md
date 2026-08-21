# CPU sample attribution

* capture: `2026-08-20T07:46:15Z` target `dart` sha `2430e415e43e`
* sample period: **250 us**, max stack depth 128, total samples 5724 (duplicates merged away: 5122)
* selection: userTag `profiler.measure` -> **5682** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=3500 rank=3500 jacRepeats=1 elimRepeats=3 storage=Float64List jacobianMs=611.0 eliminationMs=1886.757 elimShare=0.7553805274091915`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **79.6 %** of the 2.64 s it was attached for (83 gaps wider than 3 periods, 0.54 s unobserved); effective period 365 us against a nominal 250 us

### Census — what the sampler caught

* samples in this view: **0**
* with at least one Dart frame: **0** (0.0 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 0
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |

VM tags: 

### Flat profile — samples with a Dart frame

Samples: **5682**, period 250 us (~1420.5 ms of sampled CPU time). Shares are of these 5682 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 3427 | 60.31 | [59.03, 61.58] | 3990 | 70.22 | `phaseEliminationTyped (known_split.dart:102)` |
| 2 | 1031 | 18.15 | [17.16, 19.17] | 1358 | 23.90 | `phaseJacobianTyped (known_split.dart:67)` |
| 3 | 573 | 10.08 | [9.33, 10.89] | 573 | 10.08 | `_Double.abs (double.dart:184)` |
| 4 | 216 | 3.80 | [3.33, 4.33] | 216 | 3.80 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 5 | 210 | 3.70 | [3.24, 4.22] | 227 | 4.00 | `residualsInto (known_split.dart:92)` |
| 6 | 85 | 1.50 | [1.21, 1.85] | 97 | 1.71 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 7 | 61 | 1.07 | [0.84, 1.38] | 63 | 1.11 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 31 | 0.55 | [0.38, 0.77] | 93 | 1.64 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 9 | 11 | 0.19 | [0.11, 0.35] | 11 | 0.19 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 10 | 7 | 0.12 | [0.06, 0.25] | 7 | 0.12 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 11 | 3 | 0.05 | [0.02, 0.16] | 5681 | 99.98 | `main (known_split.dart:201)` |
| 12 | 3 | 0.05 | [0.02, 0.16] | 4 | 0.07 | `ListIterator.current (iterable.dart:358)` |
| 13 | 3 | 0.05 | [0.02, 0.16] | 3 | 0.05 | `<unknown Dart function>` |
| 14 | 2 | 0.04 | [0.01, 0.13] | 2 | 0.04 | `_Double.* (double.dart:44)` |
| 15 | 2 | 0.04 | [0.01, 0.13] | 2 | 0.04 | `_Double.- (double.dart:32)` |
| 16 | 2 | 0.04 | [0.01, 0.13] | 2 | 0.04 | `_sqrt (math_patch.dart:163)` |
| 17 | 1 | 0.02 | [0.00, 0.10] | 5682 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 18 | 1 | 0.02 | [0.00, 0.10] | 98 | 1.72 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 19 | 1 | 0.02 | [0.00, 0.10] | 2 | 0.04 | `_GrowableList.elementAt (growable_array.dart:500)` |
| 20 | 1 | 0.02 | [0.00, 0.10] | 1 | 0.02 | `ListIterator._current (iterable.dart:350)` |
| 21 | 1 | 0.02 | [0.00, 0.10] | 1 | 0.02 | `Lists.copy (internal_patch.dart:125)` |
| 22 | 1 | 0.02 | [0.00, 0.10] | 1 | 0.02 | `ThreadLocal.value= (_vm.dart:28)` |
| 23 | 1 | 0.02 | [0.00, 0.10] | 1 | 0.02 | `_Double./ (double.dart:60)` |
| 24 | 1 | 0.02 | [0.00, 0.10] | 1 | 0.02 | `_Double._add (double.dart:27)` |
| 25 | 1 | 0.02 | [0.00, 0.10] | 1 | 0.02 | `_Double._mulFromInteger (double.dart:149)` |

### Inside `main`

Root `main`: **5681** samples of 5682 (~1420.2 ms). Shares below are of those 5681.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 4310 | 75.87 % | [74.74, 76.96] | 1077.5 |
| jacobian | 1358 | 23.90 % | [22.81, 25.03] | 339.5 |
| other | 13 | 0.23 % | [0.13, 0.39] | 3.2 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `Float64List.Float64List (typed_data_patch.dart:2948)`, `Lists.copy (internal_patch.dart:125)`, `ThreadLocal.value= (_vm.dart:28)`, `_Double._mulFromInteger (double.dart:149)`, `_Float64List.[]= (typed_data_patch.dart:2975)`, `_TimerHeap.add (timer_impl.dart:35)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `main (known_split.dart:201)`

