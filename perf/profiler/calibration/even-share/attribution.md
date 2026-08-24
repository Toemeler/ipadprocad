# CPU sample attribution

* capture: `2026-08-20T07:46:11Z` target `dart` sha `2430e415e43e`
* sample period: **250 us**, max stack depth 128, total samples 3323 (duplicates merged away: 2777)
* selection: userTag `profiler.measure` -> **3278** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=2562 rank=2562 jacRepeats=2 elimRepeats=2 storage=Float64List jacobianMs=808.988 eliminationMs=660.486 elimShare=0.44947103521396087`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **76.6 %** of the 1.60 s it was attached for (58 gaps wider than 3 periods, 0.37 s unobserved); effective period 368 us against a nominal 250 us

### Census — what the sampler caught

* samples in this view: **0**
* with at least one Dart frame: **0** (0.0 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 0
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |

VM tags: 

### Flat profile — samples with a Dart frame

Samples: **3278**, period 250 us (~819.5 ms of sampled CPU time). Shares are of these 3278 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 1385 | 42.25 | [40.57, 43.95] | 1832 | 55.89 | `phaseJacobianTyped (known_split.dart:67)` |
| 2 | 1094 | 33.37 | [31.78, 35.01] | 1269 | 38.71 | `phaseEliminationTyped (known_split.dart:102)` |
| 3 | 290 | 8.85 | [7.92, 9.87] | 319 | 9.73 | `residualsInto (known_split.dart:92)` |
| 4 | 191 | 5.83 | [5.08, 6.68] | 191 | 5.83 | `_Double.abs (double.dart:184)` |
| 5 | 148 | 4.51 | [3.86, 5.28] | 148 | 4.51 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 6 | 44 | 1.34 | [1.00, 1.80] | 126 | 3.84 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 7 | 40 | 1.22 | [0.90, 1.66] | 46 | 1.40 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 38 | 1.16 | [0.85, 1.59] | 49 | 1.49 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 9 | 11 | 0.34 | [0.19, 0.60] | 11 | 0.34 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 10 | 8 | 0.24 | [0.12, 0.48] | 8 | 0.24 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 11 | 4 | 0.12 | [0.05, 0.31] | 4 | 0.12 | `_List._setIndexed (array.dart:191)` |
| 12 | 3 | 0.09 | [0.03, 0.27] | 52 | 1.59 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 13 | 3 | 0.09 | [0.03, 0.27] | 4 | 0.12 | `_Double.- (double.dart:32)` |
| 14 | 2 | 0.06 | [0.02, 0.22] | 3277 | 99.97 | `main (known_split.dart:201)` |
| 15 | 2 | 0.06 | [0.02, 0.22] | 167 | 5.09 | `elimCopyTyped (known_split.dart:59)` |
| 16 | 2 | 0.06 | [0.02, 0.22] | 2 | 0.06 | `<unknown Dart function>` |
| 17 | 2 | 0.06 | [0.02, 0.22] | 2 | 0.06 | `_Double.* (double.dart:44)` |
| 18 | 2 | 0.06 | [0.02, 0.22] | 2 | 0.06 | `_Double.+ (double.dart:20)` |
| 19 | 1 | 0.03 | [0.01, 0.17] | 3278 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 20 | 1 | 0.03 | [0.01, 0.17] | 6 | 0.18 | `_GrowableList._growToNextCapacity (growable_array.dart:406)` |
| 21 | 1 | 0.03 | [0.01, 0.17] | 1 | 0.03 | `ListIterator._current= (iterable.dart:350)` |
| 22 | 1 | 0.03 | [0.01, 0.17] | 1 | 0.03 | `_Double._mulFromInteger (double.dart:149)` |
| 23 | 1 | 0.03 | [0.01, 0.17] | 1 | 0.03 | `_Double.toDouble (double.dart:237)` |
| 24 | 1 | 0.03 | [0.01, 0.17] | 1 | 0.03 | `_GrowableList.[] (growable_array.dart:269)` |
| 25 | 1 | 0.03 | [0.01, 0.17] | 1 | 0.03 | `_List._List (array.dart:83)` |

### Inside `main`

Root `main`: **3277** samples of 3278 (~819.2 ms). Shares below are of those 3277.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 1436 | 43.82 % | [42.13, 45.53] | 359.0 |
| jacobian | 1832 | 55.90 % | [54.20, 57.60] | 458.0 |
| other | 9 | 0.27 % | [0.14, 0.52] | 2.2 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `_Double.+ (double.dart:20)`, `_Double._mulFromInteger (double.dart:149)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `_printString (builtin.dart:27)`, `main (known_split.dart:201)`

