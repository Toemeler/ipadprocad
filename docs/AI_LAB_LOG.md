# AI lab log

Read this first after a restart. Goal and rules: docs/AI_LAB_PROMPT.md, setup: docs/AI_LAB.md.

## Harness (frontend/test/bench)

- `ai_bench_test.dart` — 12 main + 5 hold-out scenarios (`scenarios.json`,
  `set: main|holdout`), each with `refSeconds` (pro time, ~8 s/op).
  Env: AI_BENCH=live|replay|setup, AI_BENCH_SET, AI_BENCH_ONLY,
  AI_BENCH_PARALLEL, AI_BENCH_REPEAT, AI_BENCH_OUT, AI_BENCH_RENDER.
- Driver: `tools/ai_lab/bench.py NAME [--set main|holdout|all] [--only ids]
  [--env AI_BENCH_THINK=none]` — snapshots frontend/, runs EVERY scenario in
  its own process (one isolate's kernel work stalled the others' clocks when
  they shared one), 6 at a time; writes /tmp/lab/runs/NAME.json and NAME_r/.
- `AI_BENCH=reference` scores the owner's own .ptp parts
  (test/bench/references/) with the same checks — the check is wrong if the
  owner's part fails it.
- Replays are harness fixtures written by the lab (not by the owner): they
  prove each check ACCEPTS a part meeting the stated numbers. They are not
  quality references and nothing in lib/ reads them.
- Design-quality verdicts: the owner's call. Asked the owner (2026-09-23)
  for reference parts (original motor STEP; spool, capstan wheel, case,
  tapered cup + angular handle, cable clip, plate, cups, gearbox, vase).

## DeepSeek physics (measured)

deepseek-flash: ~139 output tok/s; first token ~0.9 s with a cached 15k
prefix, ~1.7 s uncached. A round costs ~1 s + output/139.

## Results

| run | change | accurate | fast | notes |
|---|---|---|---|---|
| base1 | main @ dc80430 | 8/16 | 0/16 | every run asked a question first; first op 9–23 s; plate 20, handle 19, capstan 11 blocks rolled back |
| noask1 | + build first, never ask | (partial) | – | still 10–12 s to first op: 5 s thinking cut + big first block; models "announced" instead of building |
| v3none | + announce nudge, auto-flip cuts, numbers binding, thinking off (in-process, clocks contaminated) | 7/16 | 3/16 | first op 2–30 s (stalls from other runs' kernel work) |
| v5none | + lathe, shaft_bore; process-per-scenario driver | 7/16 | 8/16 | **first op 2.1–4.9 s in all 16**; vases 7–11 s via lathe; spool/capstan never used lathe; 105 brief_notes of bookkeeping |
| v6none | + recipes, no must-lists, read-only 'say' does not close | 7/16 | 6/16 | (6 per driver; timings partly contaminated) |
| v7none | + handle op, holdsMl, text keys fix; driver par 4 | 9/16 | 9/16 | both 7/16; sheet cover 3 s, plate 8 s, gearbox 15 s |
| v7first15 | same, thinking ONLY round 0 (≤15 s) | 8/16 | 1/16 | first op 7–21 s: thinking loses on speed with no accuracy gain → thinking OFF |
| v10 | + worked example → lathe/handle, capacity check, stricter checks | 11/16 | 8/16 | both 6/16 |
| v11compact | v10 + compact instructions | 9/16 | 6/16 | both 4/16 — compact loses |
| v8none | + interference check, post-measure nudge, handle-only recipe | 11/16 | 7/16 | both 6/16; angular handle 5 s; case passes |
| v9 | + no-think default, fn names as vars, sketch-id alias | 11/16 | 10/16 | both 8/16; gearbox passes. Review of v8 renders: clip is a tube on a disc (cable along the screw axis — wrong), cup-0 has no handle, hand-swept handles kinked → checks tightened |

### base1 detail (main set, 1 run + creative repeats)

| scenario | acc | first op s | total s | ref s | rounds | rolled back | failures |
|---|---|---|---|---|---|---|---|
| cup#0 | BAD | – | 10.8 | 50 | 2 | 0 | asked, then only described a plan |
| spool | BAD | – | 17.6 | 50 | 2 | 0 | asked twice for dims it could measure |
| teacup | OK | 11.2 | 22.0 | 50 | 4 | 0 | |
| sheet-cover | OK | 4.2 | 30.8 | 16 | 8 | 2 | |
| capstan | BAD | 14.0 | 45.6 | 40 | 12 | 11 | no groove, wrong height, cuts into spool |
| tapered-cup | BAD | 17.4 | 30.8 | 32 | 7 | 0 | 368 ml instead of 250 |
| case | OK | 19.0 | 40.5 | 65 | 8 | 0 | |
| plate-with-holes | OK | 9.3 | 117.3 | 32 | 22 | 20 | |
| vase (3 runs) | 2/3 | 11–15 | 19–162 | 32 | 4–28 | 0–6 | one built nothing |
| cup (runs 1,2) | OK | 11.6–14.2 | 44–45 | 50 | 4 | 0 | |
| gearbox-housing | BAD | 16.9 | 69.7 | 56 | 10 | 0 | wall 2.1 not 2.5, no Ø22 bores |
| cable-clip | BAD | 21.9 | 135.9 | 40 | 29 | 8 | no countersink |
| angular-handle | BAD | 23.1 | 264.8 | 24 | 42 | 19 | handle 9.8 mm off, no finger gap |

## Tried (kept unless marked)

1. Build first, never ask — assume FDM PLA, record assumptions. KEPT.
2. Announce nudge: a reply with no block, before anything was built, is sent
   back once ("reply with the block"). KEPT.
3. Auto-flip: a cut/hole that removes nothing, or a join that floats, is
   re-run in the other direction before it is refused (plate: 16 of 20
   failed blocks were this). KEPT, test in ai_real_kernel_test.
4. A number the user gave is binding; never "say" done with part missing. KEPT.
5. Thinking: off (`neverThink`) vs round-0-only (15 s) — v7: off 9/16 acc
   9/16 fast, round-0 8/16 acc 1/16 fast. OFF wins; to become the app default.
6. `lathe` (turned part in one op, about axis_at or a shaft's face) and
   `shaft_bore` (the shaft's own section, D kept, cut with a fit). KEPT,
   tests in ai_real_kernel_test.
7. Recipes (which op makes which common part), no must-lists, a "say" on a
   read-only block does not end the turn. KEPT.
8. `handle` op (measures the wall at both heights, ends mid-wall, round or
   angular) and `holdsMl` (capacity) in every block's state. KEPT.
9. Interference check (newest body vs the others) in problems; post-measure
   prose nudge; handle-only recipe; spool profile has flanges. KEPT (v8 11/16).
10. Thinking off as the app default; function names usable as vars; a
   re-used sketch id makes a fresh sketch (alias). KEPT (v9).
11. Worked cup example rewritten to lathe/shell/handle; round handle legs rise
   35°; stated capacity checked (±5 %); 'cut in empty space' message; revolve
   → lathe pointer; stricter cup/clip checks. KEPT (v10: 11/16 under stricter
   checks; tapered cup and teacup pass on capacity).
12. Compact instructions (7 KB instead of 42 KB): v11 9/16 acc, 4/16 both vs
   v10 11/16, 6/16 — LOST, more rollbacks. Off.
13. App speed: one lab cup replayed offline spent 191 s in the APP (0 s model):
   quadratic section chaining, capacity computed twice, a 0.05 mm stepping
   wall search in handle. Linear chaining + cache + ray intersection: 191 s →
   77 s, the rest real kernel work (two 23-edge fillets). Handle bends ≥ 0.8 ×
   tube Ø (a tighter bend made the sweep fail). KEPT.
14. Countersink/counterbore whose mouth cuts air is refused with where to put
   the sketch (cable clip failed 'no countersink' in v9, v10, v11). TESTING.

## Operational notes

- 4 cores / 16 GB: ONE benchmark at a time, --par 4. Two benchmarks plus the
  suite pushed the load to 58 and memory to the limit; timings worthless.
- Kill lab processes with /tmp/lab/killall.sh (pkill -f on a pattern that is
  in your own command line kills your own shell).

## App bugs found and fixed on the way

- Countersink/hole/cut pointed away from the body cut air silently → auto-flip.
- Native solver (SolveSpace) moved already-satisfied sketches: a trim of two
  crossing lines shifted untouched endpoints by up to 0.04 mm; fillet corners
  0.008 mm. Solves with nothing to do now return the sketch unchanged. Fixed
  trim_crossing_lines, trim_stacked_points, m187/m188/m191 trim, m197 fillet,
  m36 under the real lib.
- Suite (no native lib): m236 theme / l10n key caps — fixed on main in d57f1a1
  by another session (ARB keys, Palette shadows); the lab's own fix dropped.
- Still failing only with the release's native lib: m55/m56/m232/m213/m306/
  m320/device_replay (tests that assume NO kernel on the host — environment),
  s4_drag_accumulation (2) and s4_display_geometry_once (characterisation of
  the Dart solver's drag defect; numbers differ on SolveSpace). m232 "a failed
  import leaves no half-made document behind" looks like a real bug — TODO.

## Next ideas

- Opening view render before round 0 costs seconds: send without waiting.
- Rollback storms (plate 20, handle 19): read why; likely op semantics.
- Hole that cuts ~nothing (wrong face / flip): detect and auto-flip or report.
- Prompt ~67k chars resent each round; trim / split.
- Plan-once, stream-execute blocks as fences close.
