# CPU sample attribution

* capture: `2026-08-21T00:11:10Z` target `dart` sha `67f77646d7a4`
* sample period: **250 us**, max stack depth 128, total samples 2560 (duplicates merged away: 2043)
* selection: userTag `profiler.measure` -> **2560** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=3500 rank=3500 jacRepeats=1 elimRepeats=3 storage=Float64List jacobianMs=301.076 eliminationMs=770.246 elimShare=0.7189677799951835`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **75.5 %** of the 1.10 s it was attached for (35 gaps wider than 3 periods, 0.27 s unobserved); effective period 327 us against a nominal 250 us

### Census — what the sampler caught

* samples in this view: **0**
* with at least one Dart frame: **0** (0.0 %)
* native-only stacks (idle threads, GC helpers, the engine's own threads): 0
* stacks truncated at the depth limit: 0

| thread | samples |
| :--- | ---: |

VM tags: 

### Flat profile — samples with a Dart frame

Samples: **2560**, period 250 us (~640.0 ms of sampled CPU time). Shares are of these 2560 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 1348 | 52.66 | [50.72, 54.58] | 1625 | 63.48 | `phaseEliminationTyped (known_split.dart:102)` |
| 2 | 327 | 12.77 | [11.54, 14.12] | 349 | 13.63 | `residualsInto (known_split.dart:92)` |
| 3 | 315 | 12.30 | [11.09, 13.63] | 731 | 28.55 | `phaseJacobianTyped (known_split.dart:67)` |
| 4 | 292 | 11.41 | [10.23, 12.70] | 292 | 11.41 | `_Double.abs (double.dart:184)` |
| 5 | 143 | 5.59 | [4.76, 6.54] | 143 | 5.59 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 6 | 41 | 1.60 | [1.18, 2.17] | 48 | 1.88 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 7 | 35 | 1.37 | [0.98, 1.90] | 40 | 1.56 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 21 | 0.82 | [0.54, 1.25] | 64 | 2.50 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 9 | 6 | 0.23 | [0.11, 0.51] | 6 | 0.23 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 10 | 6 | 0.23 | [0.11, 0.51] | 6 | 0.23 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 11 | 3 | 0.12 | [0.04, 0.34] | 51 | 1.99 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 12 | 2 | 0.08 | [0.02, 0.28] | 194 | 7.58 | `elimCopyTyped (known_split.dart:59)` |
| 13 | 2 | 0.08 | [0.02, 0.28] | 2 | 0.08 | `_List._setIndexed (array.dart:191)` |
| 14 | 1 | 0.04 | [0.01, 0.22] | 2560 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 15 | 1 | 0.04 | [0.01, 0.22] | 154 | 6.02 | `Float64List.Float64List.fromList (typed_data_patch.dart:2954)` |
| 16 | 1 | 0.04 | [0.01, 0.22] | 4 | 0.16 | `_GrowableList._grow (growable_array.dart:387)` |
| 17 | 1 | 0.04 | [0.01, 0.22] | 2 | 0.08 | `ListIterator.moveNext (iterable.dart:361)` |
| 18 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `<unknown Dart function>` |
| 19 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_Double.* (double.dart:44)` |
| 20 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_Double.+ (double.dart:20)` |
| 21 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_Double.- (double.dart:32)` |
| 22 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_Double./ (double.dart:60)` |
| 23 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_GrowableList.[] (growable_array.dart:269)` |
| 24 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_GrowableList._capacity (growable_array.dart:221)` |
| 25 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_GrowableList.elementAt (growable_array.dart:500)` |

### Inside `main`

Root `main`: **2559** samples of 2560 (~639.8 ms). Shares below are of those 2559.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 1819 | 71.08 % | [69.30, 72.81] | 454.8 |
| jacobian | 731 | 28.57 % | [26.85, 30.35] | 182.8 |
| other | 9 | 0.35 % | [0.19, 0.67] | 2.2 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `_IntegerImplementation.* (integers.dart:17)`, `_Smi.toString (integers.dart:639)`, `_TypedListBase._setRange (typed_data_patch.dart:105)`, `_UserTag.makeCurrent (profiler.dart:23)`, `__Float64List&_TypedList&_DoubleListMixin&_TypedDoubleListMixin._slowSetRange (typed_data_patch.dart:858)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `main.<anonymous closure> (known_split.dart:217)`

