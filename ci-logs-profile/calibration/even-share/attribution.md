# CPU sample attribution

* capture: `2026-08-21T00:11:09Z` target `dart` sha `67f77646d7a4`
* sample period: **250 us**, max stack depth 128, total samples 1789 (duplicates merged away: 953)
* selection: userTag `profiler.measure` -> **1751** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=2562 rank=2562 jacRepeats=2 elimRepeats=2 storage=Float64List jacobianMs=450.545 eliminationMs=284.865 elimShare=0.38735535279639927`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **70.4 %** of the 0.83 s it was attached for (46 gaps wider than 3 periods, 0.24 s unobserved); effective period 331 us against a nominal 250 us
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

Samples: **1751**, period 250 us (~437.8 ms of sampled CPU time). Shares are of these 1751 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 506 | 28.90 | [26.82, 31.07] | 593 | 33.87 | `phaseEliminationTyped (known_split.dart:102)` |
| 2 | 496 | 28.33 | [26.27, 30.48] | 527 | 30.10 | `residualsInto (known_split.dart:92)` |
| 3 | 437 | 24.96 | [22.99, 27.04] | 1056 | 60.31 | `phaseJacobianTyped (known_split.dart:67)` |
| 4 | 120 | 6.85 | [5.76, 8.13] | 120 | 6.85 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 5 | 115 | 6.57 | [5.50, 7.83] | 115 | 6.57 | `_Double.abs (double.dart:184)` |
| 6 | 34 | 1.94 | [1.39, 2.70] | 92 | 5.25 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 7 | 16 | 0.91 | [0.56, 1.48] | 24 | 1.37 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 8 | 7 | 0.40 | [0.19, 0.82] | 7 | 0.40 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 9 | 3 | 0.17 | [0.06, 0.50] | 3 | 0.17 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 10 | 2 | 0.11 | [0.03, 0.42] | 1750 | 99.94 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 11 | 1 | 0.06 | [0.01, 0.32] | 1748 | 99.83 | `main (known_split.dart:201)` |
| 12 | 1 | 0.06 | [0.01, 0.32] | 90 | 5.14 | `elimCopyTyped (known_split.dart:59)` |
| 13 | 1 | 0.06 | [0.01, 0.32] | 25 | 1.43 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 14 | 1 | 0.06 | [0.01, 0.32] | 3 | 0.17 | `_GrowableList.add (growable_array.dart:283)` |
| 15 | 1 | 0.06 | [0.01, 0.32] | 2 | 0.11 | `_Double.toString (double.dart:250)` |
| 16 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `<unknown Dart function>` |
| 17 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `ListIterator._iterable (iterable.dart:347)` |
| 18 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `Lists.copy (internal_patch.dart:125)` |
| 19 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `_Double.+ (double.dart:20)` |
| 20 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `_Double._mulFromInteger (double.dart:149)` |
| 21 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `_DoubleToStringCache.store (double.dart:408)` |
| 22 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `_GrowableList.[]= (growable_array.dart:274)` |
| 23 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `_List.[]= (array.dart:186)` |
| 24 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `_Timer._nextId (timer_impl.dart:171)` |
| 25 | 1 | 0.06 | [0.01, 0.32] | 1 | 0.06 | `__Map&_LinkedHashBase&MapMixin&_HashBase&_OperatorEqualsAndHashCode&_LinkedHashMapMixin._getValueOrData (compact_hash.dart:671)` |

### Inside `main`

Root `main`: **1748** samples of 1751 (~437.0 ms). Shares below are of those 1748.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 683 | 39.07 % | [36.81, 41.38] | 170.8 |
| jacobian | 1056 | 60.41 % | [58.10, 62.68] | 264.0 |
| other | 9 | 0.51 % | [0.27, 0.98] | 2.2 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `Lists.copy (internal_patch.dart:125)`, `_Double._mulFromInteger (double.dart:149)`, `_Double.toString (double.dart:250)`, `_DoubleToStringCache.store (double.dart:408)`, `_GrowableList.add (growable_array.dart:283)`, `_Timer._nextId (timer_impl.dart:171)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `main (known_split.dart:201)`

