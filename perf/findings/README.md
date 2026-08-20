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
| `S8-display.md` | Display path + Track B (round 2) | `widgets/viewport3d.dart`, `packages/reality_view/**`, `.github/workflows/sim-perf.yml` |

`CROSS-SESSION.md` and `CONFLICTS.md` are **append-only**. Never edit an entry
you did not write.

Every prediction goes in before the code change, in the form given in
`OPTIMIZATION_PLAN.md` §2. A prediction without arithmetic behind it is not a
prediction.
