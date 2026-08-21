# CPU sample attribution

* capture: `2026-08-21T00:11:07Z` target `dart` sha `67f77646d7a4`
* sample period: **250 us**, max stack depth 128, total samples 2417 (duplicates merged away: 1714)
* selection: userTag `profiler.measure` -> **2375** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=2562 rank=2562 jacRepeats=5 elimRepeats=1 storage=Float64List jacobianMs=870.018 eliminationMs=150.466 elimShare=0.1474457218339533`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **70.2 %** of the 1.12 s it was attached for (45 gaps wider than 3 periods, 0.33 s unobserved); effective period 330 us against a nominal 250 us
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

Samples: **2375**, period 250 us (~593.8 ms of sampled CPU time). Shares are of these 2375 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 1014 | 42.69 | [40.72, 44.69] | 2041 | 85.94 | `phaseJacobianTyped (known_split.dart:67)` |
| 2 | 803 | 33.81 | [31.94, 35.74] | 853 | 35.92 | `residualsInto (known_split.dart:92)` |
| 3 | 230 | 9.68 | [8.56, 10.94] | 269 | 11.33 | `phaseEliminationTyped (known_split.dart:102)` |
| 4 | 152 | 6.40 | [5.48, 7.46] | 152 | 6.40 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 5 | 80 | 3.37 | [2.71, 4.17] | 80 | 3.37 | `_Double.abs (double.dart:184)` |
| 6 | 35 | 1.47 | [1.06, 2.04] | 167 | 7.03 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 7 | 15 | 0.63 | [0.38, 1.04] | 16 | 0.67 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 10 | 0.42 | [0.23, 0.77] | 10 | 0.42 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 9 | 7 | 0.29 | [0.14, 0.61] | 7 | 0.29 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 10 | 5 | 0.21 | [0.09, 0.49] | 13 | 0.55 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 11 | 3 | 0.13 | [0.04, 0.37] | 2373 | 99.92 | `main (known_split.dart:201)` |
| 12 | 3 | 0.13 | [0.04, 0.37] | 3 | 0.13 | `_Double.- (double.dart:32)` |
| 13 | 2 | 0.08 | [0.02, 0.31] | 15 | 0.63 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 14 | 2 | 0.08 | [0.02, 0.31] | 2 | 0.08 | `sqrt (math_patch.dart:129)` |
| 15 | 1 | 0.04 | [0.01, 0.24] | 2375 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 16 | 1 | 0.04 | [0.01, 0.24] | 53 | 2.23 | `elimCopyTyped (known_split.dart:59)` |
| 17 | 1 | 0.04 | [0.01, 0.24] | 37 | 1.56 | `Float64List.Float64List.fromList (typed_data_patch.dart:2954)` |
| 18 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `<unknown Dart function>` |
| 19 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `ListIterator._current (iterable.dart:350)` |
| 20 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `Lists.copy (internal_patch.dart:125)` |
| 21 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `_Double.* (double.dart:44)` |
| 22 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `_Double./ (double.dart:60)` |
| 23 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `_DoubleToStringCache.store (double.dart:408)` |
| 24 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `_GrowableList._GrowableList._withData (growable_array.dart:213)` |
| 25 | 1 | 0.04 | [0.01, 0.24] | 1 | 0.04 | `_GrowableList._grow (growable_array.dart:387)` |

### Inside `main`

Root `main`: **2373** samples of 2375 (~593.2 ms). Shares below are of those 2373.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 322 | 13.57 % | [12.25, 15.01] | 80.5 |
| jacobian | 2041 | 86.01 % | [84.56, 87.35] | 510.2 |
| other | 10 | 0.42 % | [0.23, 0.77] | 2.5 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `Lists.copy (internal_patch.dart:125)`, `_DoubleToStringCache.store (double.dart:408)`, `_List.[]= (array.dart:186)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `main (known_split.dart:201)`, `main.<anonymous closure> (known_split.dart:217)`

