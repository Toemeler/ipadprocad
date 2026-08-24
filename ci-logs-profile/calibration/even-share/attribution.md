# CPU sample attribution

* capture: `2026-08-24T18:09:49Z` target `dart` sha `c11faac6c945`
* sample period: **250 us**, max stack depth 128, total samples 1645 (duplicates merged away: 1021)
* selection: userTag `profiler.measure` -> **1607** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=2562 rank=2562 jacRepeats=2 elimRepeats=2 storage=Float64List jacobianMs=390.174 eliminationMs=259.433 elimShare=0.3993691570441821`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **71.6 %** of the 0.74 s it was attached for (36 gaps wider than 3 periods, 0.21 s unobserved); effective period 328 us against a nominal 250 us
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

Samples: **1607**, period 250 us (~401.8 ms of sampled CPU time). Shares are of these 1607 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 469 | 29.18 | [27.01, 31.46] | 949 | 59.05 | `phaseJacobianTyped (known_split.dart:67)` |
| 2 | 447 | 27.82 | [25.68, 30.06] | 550 | 34.23 | `phaseEliminationTyped (known_split.dart:102)` |
| 3 | 362 | 22.53 | [20.55, 24.63] | 383 | 23.83 | `residualsInto (known_split.dart:92)` |
| 4 | 118 | 7.34 | [6.17, 8.72] | 118 | 7.34 | `_Double.abs (double.dart:184)` |
| 5 | 117 | 7.28 | [6.11, 8.66] | 117 | 7.28 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 6 | 31 | 1.93 | [1.36, 2.73] | 95 | 5.91 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 7 | 17 | 1.06 | [0.66, 1.69] | 20 | 1.24 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 14 | 0.87 | [0.52, 1.46] | 21 | 1.31 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 9 | 6 | 0.37 | [0.17, 0.81] | 6 | 0.37 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 10 | 4 | 0.25 | [0.10, 0.64] | 4 | 0.25 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 11 | 3 | 0.19 | [0.06, 0.55] | 99 | 6.16 | `elimCopyTyped (known_split.dart:59)` |
| 12 | 3 | 0.19 | [0.06, 0.55] | 4 | 0.25 | `_Double.* (double.dart:44)` |
| 13 | 2 | 0.12 | [0.03, 0.45] | 1606 | 99.94 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 14 | 2 | 0.12 | [0.03, 0.45] | 2 | 0.12 | `ListIterator.moveNext (iterable.dart:361)` |
| 15 | 1 | 0.06 | [0.01, 0.35] | 1607 | 100.00 | `_RawReceivePort._handleMessage (isolate_patch.dart:184)` |
| 16 | 1 | 0.06 | [0.01, 0.35] | 1604 | 99.81 | `main (known_split.dart:201)` |
| 17 | 1 | 0.06 | [0.01, 0.35] | 76 | 4.73 | `Float64List.Float64List.fromList (typed_data_patch.dart:2954)` |
| 18 | 1 | 0.06 | [0.01, 0.35] | 22 | 1.37 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 19 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_Double.- (double.dart:32)` |
| 20 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_Double._mul (double.dart:51)` |
| 21 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_Float64List.[]= (typed_data_patch.dart:2975)` |
| 22 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_GrowableList.[]= (growable_array.dart:274)` |
| 23 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_GrowableList._grow (growable_array.dart:387)` |
| 24 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_GrowableList._setLength (growable_array.dart:261)` |
| 25 | 1 | 0.06 | [0.01, 0.35] | 1 | 0.06 | `_Timer._enqueue (timer_impl.dart:268)` |

### Inside `main`

Root `main`: **1604** samples of 1607 (~401.0 ms). Shares below are of those 1604.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 649 | 40.46 % | [38.08, 42.88] | 162.2 |
| jacobian | 949 | 59.16 % | [56.74, 61.55] | 237.2 |
| other | 6 | 0.37 % | [0.17, 0.81] | 1.5 |

Leaves seen in `other` (up to 12): `_Float64List.[]= (typed_data_patch.dart:2975)`, `_GrowableList._GrowableList.generate (growable_array.dart:135)`, `_Timer._enqueue (timer_impl.dart:268)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `_printString (builtin.dart:27)`, `main (known_split.dart:201)`

