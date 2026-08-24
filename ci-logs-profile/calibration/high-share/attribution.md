# CPU sample attribution

* capture: `2026-08-24T18:09:51Z` target `dart` sha `c11faac6c945`
* sample period: **250 us**, max stack depth 128, total samples 2583 (duplicates merged away: 2014)
* selection: userTag `profiler.measure` -> **2548** samples
* scenario: `PROFILER_SCENARIO_RESULT scenario=known_split total=3584 m=3500 rank=3500 jacRepeats=1 elimRepeats=3 storage=Float64List jacobianMs=307.55 eliminationMs=753.232 elimShare=0.7100723805645269`
* VM profiler: `profiler=true` `profile_period=250` `profile_vm=false` `sample_buffer_duration=600` `max_profile_depth=128`

A sampling profiler measures a **share**, not a duration. Milliseconds below are `samples x period` and are an estimate; the sample counts are the measurement.
* coverage: the sampler observed **72.5 %** of the 1.15 s it was attached for (53 gaps wider than 3 periods, 0.32 s unobserved); effective period 329 us against a nominal 250 us
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

Samples: **2548**, period 250 us (~637.0 ms of sampled CPU time). Shares are of these 2548 samples.

| # | self | self % | 95 % CI | total | total % | function |
| ---: | ---: | ---: | :--- | ---: | ---: | :--- |
| 1 | 1345 | 52.79 | [50.85, 54.72] | 1599 | 62.76 | `phaseEliminationTyped (known_split.dart:102)` |
| 2 | 397 | 15.58 | [14.22, 17.04] | 728 | 28.57 | `phaseJacobianTyped (known_split.dart:67)` |
| 3 | 261 | 10.24 | [9.13, 11.48] | 261 | 10.24 | `_Double.abs (double.dart:184)` |
| 4 | 247 | 9.69 | [8.60, 10.90] | 261 | 10.24 | `residualsInto (known_split.dart:92)` |
| 5 | 176 | 6.91 | [5.99, 7.96] | 176 | 6.91 | `Float64List.Float64List (typed_data_patch.dart:2948)` |
| 6 | 35 | 1.37 | [0.99, 1.90] | 41 | 1.61 | `_TypedListBase._setRange (typed_data_patch.dart:105)` |
| 7 | 35 | 1.37 | [0.99, 1.90] | 35 | 1.37 | `_GrowableList.add (growable_array.dart:283)` |
| 8 | 22 | 0.86 | [0.57, 1.30] | 68 | 2.67 | `_GrowableList._GrowableList.generate (growable_array.dart:135)` |
| 9 | 8 | 0.31 | [0.16, 0.62] | 8 | 0.31 | `_Float64List.[] (typed_data_patch.dart:2969)` |
| 10 | 6 | 0.24 | [0.11, 0.51] | 6 | 0.24 | `_TypedListBase._memMove8 (typed_data_patch.dart:208)` |
| 11 | 2 | 0.08 | [0.02, 0.29] | 2547 | 99.96 | `main (known_split.dart:201)` |
| 12 | 2 | 0.08 | [0.02, 0.29] | 43 | 1.69 | `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)` |
| 13 | 2 | 0.08 | [0.02, 0.29] | 2 | 0.08 | `_Double.+ (double.dart:20)` |
| 14 | 1 | 0.04 | [0.01, 0.22] | 2548 | 100.00 | `_delayEntrypointInvocation.<anonymous closure> (isolate_patch.dart:305)` |
| 15 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `<unknown Dart function>` |
| 16 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `Duration.Duration (duration.dart:206)` |
| 17 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `ListIterator._current= (iterable.dart:350)` |
| 18 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_Double._div (double.dart:67)` |
| 19 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_Float64List.[]= (typed_data_patch.dart:2975)` |
| 20 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_GrowableList.[]= (growable_array.dart:274)` |
| 21 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `_tagJac (known_split.dart:32)` |
| 22 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `main.<anonymous closure> (known_split.dart:233)` |
| 23 | 1 | 0.04 | [0.01, 0.22] | 1 | 0.04 | `sqrt (math_patch.dart:129)` |
| 24 | 0 | 0.00 | [0.00, 0.15] | 2548 | 100.00 | `_RawReceivePort._handleMessage (isolate_patch.dart:184)` |
| 25 | 0 | 0.00 | [0.00, 0.15] | 211 | 8.28 | `elimCopyTyped (known_split.dart:59)` |

### Inside `main`

Root `main`: **2547** samples of 2548 (~636.8 ms). Shares below are of those 2547.

| phase | samples | share | 95 % CI | est. ms |
| :--- | ---: | ---: | :--- | ---: |
| elimination | 1810 | 71.06 % | [69.27, 72.79] | 452.5 |
| jacobian | 728 | 28.58 % | [26.86, 30.37] | 182.0 |
| other | 9 | 0.35 % | [0.19, 0.67] | 2.2 |

Leaves seen in `other` (up to 12): `<unknown Dart function>`, `Duration.Duration (duration.dart:206)`, `_Double.+ (double.dart:20)`, `_Float64List.[]= (typed_data_patch.dart:2975)`, `__Float64List&_TypedList&_DoubleListMixin.setRange (typed_data_patch.dart:844)`, `_tagJac (known_split.dart:32)`, `main (known_split.dart:201)`, `main.<anonymous closure> (known_split.dart:233)`

