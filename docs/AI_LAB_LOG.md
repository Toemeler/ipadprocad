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
| v12 | + lathe base_y, no worked examples in knowledge (owner: examples steal creativity), op choice by shape not object; repeat 2 | 11/26 | – | both 6/26: removing examples cost accuracy on the tuned set, as expected |
| genA_actions | 20 UNSEEN prompts (generalization.json, seed 1), actions mode | 18/20 | – | both 12/20; median total 21.4 s, first op 2.57 s, 31 rollbacks |
| genA_program | same 20, PROGRAM mode (whole part in world coords, replaced when resent, expect checks) | **20/20** | – | both 12/20; median total **14.4 s**, first op 2.07 s; 59 rollbacks: 37 "does not touch the body it joins", 15 invalid JSON |
| genB_program | 20 NEW unseen (seed 2), program mode + stand-alone steps + JSON repairs | 18/20 | 9/20 | both 9/20; 61 "removed no material" (a box cut auto-FLIPPED through a coaster — app bug, fixed; model read box `base` as a corner); soap dish renamed its part 6× (no location for loose pieces) |
| genC_program | 20 NEW unseen (seed 3), + no flip in programs, body span in refusals, options beside the shape key | 18/20 | 14/20 | **both 14/20** (best); star cutter chased its own impossible expectation 41 rounds; L-bracket: 39 hole misses (3D placement) |
| genD_program | 20 NEW unseen (seed 4), + loose-piece extents, section expect, sanitised names, hole flip in programs | 19/20 | 13/20 | both 13/20; the 1 BAD is a native SEGFAULT in a 22-edge fillet (whistle) — not reproduced in 3 reruns; steps now logged before they run |
| mainP1 | main + holdout (owner-derived, 23 runs), PROGRAM mode | 11/23 | 5/23 | both 4/23 (actions v12: 11/26, 6/26). Edits of the user's own body failed: a program could only build a NEW body (sheet cover rebuilt beside the original; handle as a 2nd body); spool typed coordinates 1 mm off the shaft |
| mainP2 | + program "on" an existing body, round features with positions in the shape context, holdsMl in reports | (6/23) | – | INVALID: DeepSeek balance ran out mid-run (HTTP 402) — 15 runs never reached the model. Sheet cover now 3.6 s one round |
| mainP3 | + speed work, "on", round features, holdsMl (balance restored) | 12/23 | 9/23 | both 7/23 (best on the owner set; v12 actions 6/26). Knob: 48 repeated sphere cuts = 46-178 s per block; cable clip: 36 rollbacks from cuts in empty space; cup: a failed rim fillet threw the cup away, then DeepSeek's own tool-call markup ended the turn |
| mainP4 | + skip-and-report no-op cuts/failed blends, repeats as patterns, DSML markup | 13/23 | 13/23 | **both 10/23** (best). cup#2 = the native SEGFAULT (invalid shell + handle fuse) — fixed after |
| mainP5 | + native crash fix (invalid shell), handle retries, round-feature spans, var eviction, smooth profiles | **15/23** | 10/23 | both 8/23; cable clip passed for the first time; l-bracket = a SECOND native segfault (fillet next to a blind hole whose floor lies on the far face) — fixed after |
| mainP6 | + outline-first principle, body removal, crash fix 2, version supersede | 11/23 | 8/23 | both 5/23 — two HANGS: a smoothed cup section crossed itself (chamfer hung 14 min), and a streamed repeat of 12 near-coincident slots ran copy by copy (hung). Both fixed after; smooth shells now fall back to straight segments |
| mainP7 | + smooth fallback, streamed repeats as patterns, handle-step rule | **15/23** | **13/23** | **both 10/23** (best on all three); creativity: cup, vase, pen holder 3/3 passing runs, no two alike. l-bracket = third native crash (chamfer) — gone on the build with the shim fault fix (build-58273e7), which the lab uses from here on |
| genE_program | 20 NEW unseen (seed 5), all fixes to mainP7, new native lib | 17/20 | 8/20 | both 8/20; slow runs chased expectations: a bike-bar phone clamp "hole" counted as not a hole (C-shaped) -> 26 rounds. A bore that wraps >= 200° now counts |
| mainP8 | + clamp bores count as holes; native fault-catching build | **17/23** | 11/23 | both 8/23; no crashes; l-bracket and gearbox pass. Still failing: cable-clip channel, teacup overhang (handle leg), spool on the D-shaft, capstan ratio, case around contents, knob hex pocket |
| mainP9 | + relations report for new parts, "on" only to change that body, enclose documented | 15/23 | 13/23 | both 10/23; the SPOOL on the D-shaft passes for the first time; misses: capacity near limits (513 ml mug, 95 ml pen holder), capstan ratio, case clearance, knob hex (ngon added after), cable-clip countersink |
| mainP10 | + ngon outline | 15/23 | 11/23 | both 10/23; cup#2 39 rounds / 605 s and teacup: the HANDLE STEP ITSELF made overhangs (legs flattened to ~20° in silence when from_y..to_y was short) — the model chased it 20 times; case 70 rounds; knob 41 rounds chasing a bbox size under flutes; l-bracket LEFT OUT the requested holes because horizontal screw holes were reported unprintable |
| genF_program | 20 NEW unseen (seed 6), snapshot mid-way through the fixes below | 18/20 | 9/20 | both 9/20; 27 of the rolled-back blocks were programs that START BY CUTTING for a part already there ("hole needs material", "first shape must ADD"); 8 "segment ends where it starts"; 8 shells finding no flat top |
| mainP11 | + bores report, cut-first resends append, slips accepted, orientation fix, biarc smooth, printable round handles, round-hole bridges, overhangs only for this request's bodies | 16/23 | 12/23 | both 9/23; cable clip, cup#2, case, l-bracket now pass; vase#2 and towel hook ended with NO BODY — "steps": [] + a corrected expect was read as "remove" (fixed after); cup blocks 12-65 s = handle fuse onto the smooth cup |
| mainP12 | + re-measure instead of remove, FDM check on by default, hole hex nut trap | **18/23** | 11/23 | both 9/23 (best accuracy); KNOB passes for the first time (hex), teacup and case pass; angular handle 26 rounds on ceilings the step itself drew, towel hook 41 rounds on an upright-only overhang judgement (both fixed after) |
| genG_program | 20 NEW unseen (seed 7), snapshot = mainP12 + angular handle fix | 18/20 | 11/20 | both 10/20; g51 whistle deleted by {"steps": [], "say"} (fixed after); g59 spout: overhang judged upright only (fixed after: best orientation) |

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
   the sketch (cable clip failed 'no countersink' in v9, v10, v11). KEPT
   (kernel test).
15. lathe base_y: the profile's y 0 on a height or ON a flat face (a mate):
   spools were turned at y 0 or sank into the motor's boss. KEPT (test);
   measuring in v12 (2 runs per scenario).

16. PIVOT — program mode (owner: "use what an LLM is very good at"; "it must
   work for anything I can imagine"). What a language model does well: write
   a whole program at once, name parameters, write expressions, compare a
   checklist against measurements. What it does badly: 3D frames and signs,
   arithmetic, tracking state across many small steps, following a huge
   instruction set. So a part is ONE program in world coordinates (Y up,
   planes xz/xy/yz with fixed (u,v)), resent whole to change it (replaces the
   part, nothing to delete), with model-stated `expect` (size, holdsMl,
   volume, pieces, holes, clear_of) measured by the app. Bare expressions
   (`D/2 - t`) are read as formulas. Steps execute while the reply streams
   (first op ~2 s). Measured on UNSEEN prompts only (generalization pool,
   sampled per run) so nothing is tuned on the test. genA: 20/20 vs 18/20.
17. In a program a shape may stand alone until a later step joins it (legs
   then top); the per-step floating-join refusal is off there and the finished
   part is checked for loose pieces instead. JSON slips seen in genA repaired:
   names quoted inside a formula, a stray quote after a number, an extra
   closing brace. Measuring in genB (seed 2).
18. From genB/genC transcripts (all generic, none about one object): a cut is
   never auto-flipped inside a program (a hole may be — it stays on its
   line); refusals name the body's span and which repeat copy missed; loose
   pieces are reported WITH their extents; `expect.section: [{y, openings}]`
   counts compartments/cells/pockets at a height (a 6-compartment tray passed
   with 1 mm ridges as dividers); part names sanitised, `steps: []` removes a
   part and a new name lists the other parts; program sketches hidden (stray
   lines in renders); expectations only from the user's numbers.

Pushed to main through 650d8f8 (suite 5000/0).

19. RENDER REVIEW of genC (all four "accurate" by the generic checks): phone
   stand = an upright plate on a base; bearing holder's M5 holes cut into
   the bearing bore; pipe clamp's "screw holes" are grooves along the
   flanges; jar lid = an open ring with no top. The generic checks are far
   too lenient, and the model cannot see its part. So: holes count only
   when round all the way (the clamp's grooves counted as holes); every
   program report carries a "sections" digest (material / separate areas /
   openings at 5 heights) — numbers the model compares with its intent;
   EXPECT asks for what makes the part WORK (closed/open, through, holds).
   Also: a mistyped var gets "did you mean"; a QUESTION after the model's own
   failed first block is sent back (a whistle ended asking "which whistle?").

20. From mainP3: in a program a cut that removes nothing and a blend that
   cannot be built are SKIPPED and reported (problems), not a rollback of
   the whole part; a repeat of 3+ shapes is the first copy plus ONE pattern
   feature (batched boolean; "around" now turns the copies, as a circular
   pattern does); "on" naming the program's own body is a plain resend;
   DeepSeek's native `<｜DSML｜invoke>` markup is read as the action.
   Sweep twist + taper together now build (section scaled per station).

21. From mainP10/genF (numbers first, then the fix):
   - report "bores": every hole/bore/channel in any direction, its axis and
     how far the material wraps it; section expectations cut along x or z
     (the cable clip's sideways channel was invisible to the y sections);
   - a program for an existing part that starts by cutting is ADDED to the
     part (27 rollbacks); repeated path points skipped (10); swapped box
     corners and {"path": ...} outlines accepted; a zero-area profile up the
     wall is the outline (closed through the axis), a profile that never
     reaches the axis is noted as a ring; notes travel with later errors;
   - round handle: for FDM its ends move apart until the legs rise 40°, and
     it says so; otherwise it states the span needed (was: silently ~20°);
   - smooth revolve = biarcs (tangent torus bands, Bolton/Meek-Walton), not
     near-tangent cone polylines that crashed the shell; corners at >45°;
     a profile touching the axis at one end closes along it (a diagonal
     closure hid a cone inside a cup);
   - overhang check: a concave round ceiling up to 12 mm across (the top of
     a horizontal screw hole) is a bridge; the first 0.5 mm is the bed;
   - instructions: never leave out a requested feature to quiet a check.

22. From mainP11/P12/genG:
   - "steps": [] + "expect" re-measures the part unchanged; + "say" leaves it
     as it is; only "remove": true (or bare "steps": []) removes a part;
   - FDM is the check's default unless another process is named (the
     instructions already told the model so);
   - hole "hex": [af, depth] = a nut trap at the mouth;
   - angular handle: sloped lower arm for FDM; a flat ceiling held at both
     ends of its long side (<= 25 mm) is a bridge;
   - PRINTABILITY IN THE BEST ORIENTATION: as modelled, or lying on any
     flat face (>= 50 mm² and 1/6 of the footprint) that needs no support;
     the report names the side. The bench grader uses the same rule (it had
     judged upright only, which no one slicing a wall hook would do).
   - Tried and reverted: a round handle swept piece by piece (5 one-segment
     sweeps fuse in ~1.5 s against 8-12 s for one pipe), but the arc pieces
     are B-spline approximations whose end caps half-overlap the straight
     pieces and leave ledges. Needs analytic pipes in the shim.

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
- Sweep TWIST was refused everywhere ("not supported yet" in the panel, the
  shim has no twist law). Now built as a loft through the section placed
  along the path on rotation-minimising frames (Wang et al., ACM TOG 2008),
  the twist shared out by length; holes lofted and cut; twist+taper refused
  with a reason. Volume of a twisted square stays area x length (test).
- Native solver: dragging a circle's grip did not hold its radius (only
  points carry SolveSpace's drag wish) — trimmed ends bound to the circle
  stopped at 23.3 of 30. The grip now holds the radius as the Dart solver does.
- Counterbore/countersink "cut nothing" check compared volumes from a test
  fixture kernel too; now only on the real kernel.
- Tests that pin the NO-native-lib host behaviour skip on a native host
  (test/support/native_host.dart) instead of failing there.
- sketch_gear reported "boreMm" and never drew the bore (a solid disc);
  "holes" edges took a gear's tooth-root fillet arcs (concave, so "empty
  inside") for hole mouths. The bore is drawn; a mouth must close a circle.
- A sweep of 24 ordinary operations (fillet/chamfer/shell on boxes, rounded
  boxes, cylinders, cones; revolve with arcs; extrude with hole shapes;
  countersink/counterbore; polar repeat; sweep; handles; common; lathe) all
  build on the real kernel with volumes checked by hand where closed-form.
- NATIVE CRASH FOUND (mainP4, cup#2, reproducible): a revolved cup whose rim
  folds back, shelled 2.4 mm, then a handle — the shell "succeeded" with an
  INVALID solid (walls through each other) and OCCT segfaulted fusing the
  handle onto it. A shell whose result is invalid (from a valid input) is
  now refused with the reason; regression test in ai_real_kernel_test.
- NATIVE CRASH 2 (mainP5, l-bracket, reproducible): a blind hole whose depth
  equals the wall (depth 4 in a 4 mm leg; after the flip) leaves a
  zero-thickness floor; a fillet over its two floor arcs at r 1.25
  segfaults OCCT (the body is "valid"). Programs now drill such a hole
  through. The same geometry made by hand in the UI can still crash the
  fillet: the shim needs OSD signal handling on every entry point.
- BOTH NATIVE CRASHES CLOSED IN THE SHIM: every OCCT_TRY now sets an
  OCC_CATCH_SIGNALS jump point, and a fault inside OCCT during a shim call
  comes back as "occt_fuse: SIGSEGV ..." instead of killing the app. Not
  OSD::SetSignal: the shim's own handler claims only faults on a thread inside
  a shim call and passes every other fault to the previous handler, and it
  leaves SIGINT/SIGHUP/SIGQUIT alone. The two crashes are driven through the
  raw FFI (below the Dart guards) in frontend/test/kernel_fault_test.dart:
  they segfault on the old library and fail with a message on the new one.
- DeepSeek balance ran out 2026-09-29 00:00 UTC (HTTP 402): live runs paused.
- SPEED (measured on the real kernel):
  - every feature the assistant made was built TWICE (a check-build, then
    the rebuild recomputed it): now one build through the rebuild;
  - a repeated program hole is ONE hole feature with many places;
  - many profiles in one extrude, and pattern copies, are fused in a
    balanced tree (pattern: copies united, then ONE boolean with the body);
  - capacity (ml) sliced the body 120 times with string-keyed chaining and
    pairwise point-in-polygon: integer keys, box pre-checks, a 24-station
    pre-pass for non-vessels.
  40-hole plate program 15.2 s -> 2.0 s; 8x8 hole pattern 20 s -> 3.1 s;
  capacity of a 144-hole plate 8.2 s -> 0.5 s.
- CAPACITY SEMANTICS: every enclosed opening in a section counted as held
  water, so a plate with through-holes "held" ml. An opening now holds water
  only when what is below it is material or an opening that holds.
- A signed axis ("-z") in an AI argument was evaluated as "minus z" (pattern
  direction2 failed with "unknown name z").
- Previously: still failing only with the release's native lib: m55/m56/m232/m213/m306/
  m320/device_replay (tests that assume NO kernel on the host — environment),
  s4_drag_accumulation (2) and s4_display_geometry_once (characterisation of
  the Dart solver's drag defect; numbers differ on SolveSpace). m232 "a failed
  import leaves no half-made document behind" looks like a real bug — TODO.
- FLAT FACES FACING THE WRONG WAY: the shim signed a plane's normal by a
  face flag relative to the SURFACE parametrisation; on a revolved part's
  flat ends that is not the plane axis, so a cup's bottom read +Y (and with
  arcs its top -Y): "open top" found nothing, a sketch on such a face would
  face into the part. Corrected in Dart from the triangles' winding (all
  consumers) and at the source in the shim.
- fillet "near" a round edge's CENTRE (the rim given as [0, H, 0]) matched
  nothing; now it picks that ring, and "near" + "edges" filters.
- shell "open" accepted top/bottom/left/... only; +x..-z now too, and a
  round side names the flat ends there are.
- 58273e7 had deleted occt_mesh_progress/_stage_name/_overall/_cancel from
  the shim (the mesh-to-CAD wait card polls them; OCCT Kernel Build red on
  the bar_watch link): restored.
- The ai-bench workflow's summary step failed on a missing "rounds" key
  (red on every push): reads the keys it needs defensively now.
- SPEED, open: fusing the handle sweep (a B-spline pipe) onto a smooth cup
  takes 12 s (4 s onto a straight one) inside OCCT's boolean. Fix needs the
  shim to build a round sweep along lines/arcs from analytic pieces.

## Next ideas

- Opening view render before round 0 costs seconds: send without waiting.
- Rollback storms (plate 20, handle 19): read why; likely op semantics.
- Hole that cuts ~nothing (wrong face / flip): detect and auto-flip or report.
- Prompt ~67k chars resent each round; trim / split.
- Plan-once, stream-execute blocks as fences close.
