# M182 — "A system that cannot break" — Analysis & Plan

Root-cause analysis of the device session (log `prototype_log.txt`, build `29c203a`),
with the fix plan. All findings are evidenced by log lines or by the code paths that
produce them.

---

## The session, reconstructed from the log

1. Solid1 built: Extrusion1 (Sketch1, base) → Extrusion2 (Sketch2, join) → Extrusion3
   (Sketch3, join) → Chamfer1 (modify) → Extrusion4 (Sketch4, cut). Solid2 built:
   Revolution1 (Sketch5, yz plane, new) → Revolution2 (Sketch6, yz plane, join) →
   Extrusion5 (Sketch8, join→cut) → Extrusion6 (Sketch9, cut) → Fillet1 (4 picked
   edges, all `r=5 l=2.014 k=2` cylinders).
2. First failure at `23:53:20` (right after Extrusion6 committed):
   `feature: FAIL Chamfer1 (chamfer) body=Solid1 op=modify solid=null err=nothing to
   modify — no solid before this feature` — while Extrusion1–3 recomputed fine.
3. The fillet session (23:53:44–23:54:24) previewed OK repeatedly (`base=present`),
   then at the commit (`23:54:24.83`) the whole fold cascade went wrong in one pass:
   - `FAIL Chamfer1 … nothing to modify`
   - `loops: "Sketch5": 0 loop(s)` → `FAIL Revolution1 … no closed profile in "Sketch5"`
   - `loops: "Sketch6": 0 loop(s)` → `FAIL Revolution2 … no closed profile in "Sketch6"`
   - `WARN edge: sel[0..3] LOST … no confident match among 3 live edges`
   - `FAIL Fillet1 … none of the selected edges exist any more`
   - `WARN project: seg N ORPHANED/AMBIGUOUS … freezing` + `source CHANGED by 100.05`
   - `WARN part: face-anchored sketches STILL moving after 3 passes`
4. The broken state **persisted**: every later recompute reproduced it (`23:57:32`,
   after EOP drags, the revolutions still failed).
5. At `00:04:12` the part reopened intact (`sketches=9 features=10`), then the user
   deleted the broken Solid2 pieces via context menus (logged:
   `child sketch "Sketch9/Sketch7/Sketch6/Sketch5" deleted`; feature deletions are
   silent). The file was then saved with `sketches=5 features=6` — the second solid
   was gone for good. `Extrusion5` remained and recomputed as a phantom standalone
   "cut" (no predecessor, `op=cut` without `base=present`).

---

## Root causes (each maps to a fix)

### R1 — Visibility is coupled to geometry computation (the initial trigger)
`_recomputeAllFeaturesOnce` only advances the fold chain with
`if (f.visible) chainLast[f.bodyName] = f;`. Consequences:
- Hiding a feature removes its volume from the folded body (a *join* in the middle
  silently disappears from the result).
- Hiding the last feature of a chain leaves **no base** for the next
  body-modify feature → `Chamfer1 … nothing to modify`.
This is exactly the user report "if I only removed one extrusion by making it
invisible, the whole solid broke". Inventor's Visibility is a **display** property;
here it changed the **geometry**.

### R2 — A failed feature poisons the chain with a phantom
When Chamfer1 failed, the loop ran `chainLast.remove(f.bodyName)` and let the next
feature recompute with `base = null`:
- `Extrusion4 (cut)` printed `op=cut` **without** `base=present` — it materialised as
  a standalone prism floating in space (a *phantom*), which became the new "body".
- Solid1's shape then diverged from intent on every rebuild.

### R3 — Sketch projections follow the (broken) body and can open a closed profile
`syncSolidProjections` re-derives every `projSolid` segment from the current model
after each rebuild. Sketch5/6 (the revolve profiles) contain projected Solid1 edges.
Once Solid1's fold broke (R2), the projected segments jumped
(`seg … source CHANGED by 100.05`, `RENUMBERED -> 81`), the closed revolve profiles
**opened** (`loops: Sketch5: 0 loop(s)`), and Revolution1/2 failed —
taking Solid2's whole chain with them, including the fillet's edges.

### R4 — Recompute is not atomic and the broken state is persisted
Features are mutated in place one by one (`f.disposeSolid()` at the start of every
feature recompute destroys the last good solid *before* the new one is known to
work), and `savePart` runs after nearly every operation. A sideways recompute
therefore left a broken model in memory **and on disk** — "I couldn't get them back".

### R5 — Data loss was made permanent
Deleting a body / feature / sketch / "everything below EOP" is irreversible:
no part-level undo exists (the 2D sketches have a journal; the part has none), and
the native EOP menu offers "Delete all features below EOP" **without confirmation**.

### R6 — Native model browser: feature rows can never expand
`GlassRow(id: 'ft:${f.name}', …)` but `expanded: expanded.contains(f.name)` — the
host stores `ft:Extrusion1` in the expansion set, the row looks up `Extrusion1`.
The consumed-sketch child therefore never renders → "can't expand extrusions or
revolutions to reveal their sketches". (The Flutter fallback browser is correct.)

---

## The fix system ("cannot break")

| # | Fix | File(s) |
|---|-----|---------|
| F1 | **Visibility decoupled from computation.** The fold chain advances through every feature regardless of `visible`; visibility only gates drawing. Hiding can no longer alter or break geometry. | `part_model.dart` |
| F2 | **Non-destructive recompute.** `_recomputeFeature` keeps the last good solid on failure (disposes only on success, and only the replaced solid). | `part_model.dart` |
| F3 | **No phantoms, honest failures.** When a feature on a body fails, every later feature on that same body is marked failed ("an earlier feature on this body failed") instead of being computed with a null base. A non-`new` feature whose chain is broken fails with a clear error. | `part_model.dart` |
| F4 | **Atomic pass.** `recomputeAllFeatures` only runs the face-anchor settle when the feature pass succeeded; `_syncSolidProjections` is only called after a successful pass. A failed recompute changes nothing that is persisted. | `part_model.dart`, `app_state.dart` |
| F5 | **Projection closure guard.** Before a projection sync is committed into a sketch that a feature consumes, the sketch's closed-loop count is verified; an update that would open a loop is refused and the moved segments are frozen (`projBroken`), never pushed. Plus a tighter `_projTol` so a segment cannot jump onto a *different* edge. | `app_state.dart`, `part_model.dart` |
| F6 | **Native browser expansion key fix.** `expanded.contains('$kIdFeature${f.name}')`. | `widgets/native_browser.dart` |
| F7 | **Part-level undo for destructive operations** (delete feature / delete body / delete below EOP / delete sketch): snapshot journal + Ctrl+Z / Ctrl+Shift+Z in the 3D viewport, and a confirmation dialog on the native "Delete all features below EOP". | `app_state.dart`, `part_model.dart`, `widgets/viewport3d.dart`, `widgets/native_browser_host.dart` |
| F8 | **Honest logging** of feature deletion and of failed recomputes (what was kept), so a device session can always be reconstructed. | `app_state.dart`, `part_model.dart` |

Tests to add (`frontend/test/m182_cannot_break_test.dart`): visibility never changes
the fold; a failed feature poisons only its own body and keeps last-good geometry;
a phantom is never created after a failure; the projection guard refuses an update
that opens a consumed profile; the native-browser expansion key matches the row id.

---

## Implementation status (honest)
All fixes F1–F8 are implemented in the working tree on `m130-m145-kernel-features`
(HEAD `29c203a`), with a new host test file `frontend/test/m182_cannot_break_test.dart`
pinning the invariants. **Not yet compiled or run** — there is no Flutter/Dart SDK in
this session's sandbox, so `flutter analyze` / `flutter test` / the IPA build have
not been executed here. The changes are intentionally conservative and confined to
the paths above; CI (`dart-checks` + `m5-flutter-ipa`) is the gate, exactly as this
repo's rules demand. The device log is the regression fixture: the exact failure
cascade of this session must not be reproducible after the fixes.

Files touched:
- `frontend/lib/part_model.dart` — F1, F2, F3, F4 (fold decoupling, non-destructive
  recompute, downstream poisoning, honest null base, settle gating), F5 (tighter
  `_projTol` + `ProfileInput`/`profileLoopCount` + `freezeProjectionUpdatesThatBreakLoops`).
- `frontend/lib/app_state.dart` — F4 (projection sync gated on recompute success),
  F5 (guard applied in `_syncSolidProjectionsInner`), F7 (part-level undo journal:
  `PartSnap`, `undoPart`/`redoPart`, checkpoints in `deleteFeature`/`deleteBody`/
  `deleteBelowEndOfPart`/`deleteChildSketch`), F8 (deletion + restore logging).
- `frontend/lib/widgets/native_browser.dart` — F6 (expansion key = row id).
- `frontend/lib/widgets/native_browser_host.dart` — F7 (confirmation dialog for the
  native "Delete all features below EOP").
- `frontend/lib/widgets/viewport3d.dart` — F7 (Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z, Ctrl+Y
  in 3D → part undo/redo).
- `frontend/test/m182_cannot_break_test.dart` — new host tests.
- `M182_ANALYSIS.md` — this document.

Note: `backend/occt/upstream` shows as deleted in `git status` only because the OCCT
submodule was never initialized in this sandbox; it is untouched.
