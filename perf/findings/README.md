# Session findings

One file per optimisation session, per `OPTIMIZATION_PLAN.md` §4. **Each session
writes only to its own file.** These are folded into `PERFORMANCE_PROFILE.md`
once, at integration (plan §8).

| File | Session | Owns |
| --- | --- | --- |
| `S1-bench.md` | Lane C bench harness | `backend/bench/**` |
| `S2-shim.md` | OCCT shim | `backend/occt/shim/**`, `ffi/occt_engine.dart` |
| `S3-solver.md` | 2D solver | `solver.dart` |
| `S4-painter.md` | Painter | `widgets/viewport.dart` |
| `S5-partmodel.md` | Part model | `part_model.dart` |

Round two (`OPTIMIZATION_PLAN_2.md` §2) adds five more:

| File | Session | Owns |
| --- | --- | --- |
| `S6-shim2.md` | OCCT shim, round 2 | `backend/occt/shim/**`, `ffi/occt_engine.dart` |
| `S7-profiler.md` | Sampling profiler | `tools/profiler/**` — no app code at all |
| `S8-display.md` | Display path, Track B | `widgets/viewport3d.dart`, `reality_view/**` |
| `S9-drift.md` | The drag drift | `solver.dart`, two functions in `app_state.dart` |
| `S10-memory.md` | Memory, the soak | `perf_scenarios_stress.dart` + one new scenario file |

`CROSS-SESSION.md` and `CONFLICTS.md` are **append-only**. Never edit an entry
you did not write.

Every prediction goes in before the code change, in the form given in
`OPTIMIZATION_PLAN.md` §2. A prediction without arithmetic behind it is not a
prediction.
