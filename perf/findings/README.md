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
| `S9-drift.md` | Sketch drag drift (round 2) | `solver.dart`, `endGripDrag` + warm start |
| `S11-sweep.md` | Sweep + loop detection (round 2) | the sweep feature path and loop detection in `part_model.dart`, `perf_scenarios_profile.dart` (new) |

`CROSS-SESSION.md` and `CONFLICTS.md` are **append-only**. Never edit an entry
you did not write.

Every prediction goes in before the code change, in the form given in
`OPTIMIZATION_PLAN.md` §2. A prediction without arithmetic behind it is not a
prediction.

## Round two (sessions 6–10) — `OPTIMIZATION_PLAN_2.md`

This is the **plan's** ownership table, as `OPTIMIZATION_PLAN_2.md` §4
wrote it. The table above is the live registry and is the one to trust
when they disagree: it has picked up sessions the plan never named (S11,
S12), and S8 and S9 therefore appear in both. Nothing here overrides an
entry up there; it is kept because §4 is what each round-two session was
briefed against.

| File | Session | Owns |
| --- | --- | --- |
| `S6-shim2.md` | the quadratic that survived | `backend/occt/shim/**`, `ffi/occt_engine.dart` |
| `S7-profiler.md` | sampling profiler | `tools/profiler/**` — no app code at all |
| `S8-display.md` | display path + Track B | `viewport3d.dart`, `packages/reality_view/**`, `sim-perf.yml` |
| `S9-drift.md` | the 14.64-unit drift | `solver.dart`, `endGripDrag` + warm start only |
| `S10-memory.md` | memory + the 30-minute soak | `perf_scenarios_stress.dart` + a new scenario file |

Two rules round two added, both learned the hard way:

* **Equivalence tests must be differential** — old path against new, same
  machine, same run. A recorded golden pins the machine, not the claim, and
  four of them broke the first IPA build.
* **S9 may change behaviour.** No other session may. It is investigating a
  finding that says behaviour is already wrong.
