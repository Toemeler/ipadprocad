# Brief — Session 20: the Dart side has never been audited away from its trivial values

**Branch from `2f2a308`** (= `claude/perf-opt2` = tag `build-477`/`build-478`).
Develop on the branch the harness assigns you. Do not push anywhere else.

**Identifiers: you are allocated none, deliberately.** You take **no shim
version** and **no smoke scenario**, because you touch no C or C++. If you
conclude you need shim work, that is a `**Needs:** integrator` entry in
`CROSS-SESSION.md`, **not** a patch — the same rule S7 worked under, and for the
same reason. Session 19 owns `backend/**` and is running in parallel.

**You own:** the chamfer feature path in `frontend/lib/part_model.dart`,
`frontend/lib/ffi/occt_engine.dart`, new test files under `frontend/test/`, and
`perf/findings/S20-dart-trivial.md`.

**You must not touch:** `backend/**`, `frontend/lib/perf*.dart` (the frozen
measurement apparatus — changing it invalidates `perf/baseline.json` and every
comparison built on it), `frontend/lib/solver.dart`, `viewport*.dart`,
`perf/baseline.json`, `PERFORMANCE_PROFILE.md`. Do not reformat
`part_model.dart`; a whitespace pass turns every future merge into a conflict.

---

## Read first

1. `OPTIMIZATION_PLAN_2.md` §1.2, **§1.3** (the three-clause rule), §1.4, §6.
2. `perf/findings/S17-oblique.md` **§5.1** and **§0.3** — the defect, and the
   triangle it comes from.
3. `perf/findings/S16-straight-audit.md` **§1.4** — this is the *shape of your
   deliverable*, not background. The integrator's ruling on S16 says so in as
   many words: "The deliverable I actually wanted is §1.4."
4. `backend/occt/shim/occt_capi.h:463` — v28's admissible range, `0 < angle_deg
   < 180 − θ`. Read it; do not edit it.

## Half one — the defect

`frontend/lib/part_model.dart:3707`, inside `ChamferFeature.kernelParams`:

```dart
2 => (distance1, 0.0, flip ? 90.0 - angleDeg : angleDeg),
```

Flip swaps which face the chamfer is measured from, so the flipped angle is the
triangle's **third** angle, `180° − θ − α`, with θ the edge's dihedral. `90 − α`
is that **only when θ = 90**. It is S17's defect 3 one layer up, and S17 routed
it rather than fixing it because its brief froze the Dart side.

**What v28 already did for you, and it is the right order:** on a
non-perpendicular edge a flipped mode-2 chamfer now draws a **clear refusal from
the shim's guard naming the edge's real bound**, instead of silently building a
wrong chamfer. The bug got loud. You are turning a loud refusal into a correct
answer.

**The pieces exist — this was checked before the brief was written, so you are
not being sent to find out whether it is possible:**

| | |
| --- | --- |
| the edge's dihedral, in Dart | `EdgeInfo.dihedralDeg`, `frontend/lib/ffi/occt_engine.dart:264` — shim edge field `[10]`, in degrees |
| the binding is **already per-edge** | `chamferEdges(..., {List<double> angleDeg})`, `occt_engine.dart:658`, validated `angleDeg.length == n` |
| where the edge ids are resolved | `part_model.dart:8073`, `final (d1, d2, ang) = f.kernelParams;` — `ids` are in hand at that point |

**And here is the crux, which is a design decision and not a one-liner.**
`kernelParams` is a *getter on the feature* with **no edge context at all**, and
it returns **one scalar angle** for the whole feature. A chamfer spanning edges
of different dihedral therefore has no single right flipped angle today. Resolve
per-edge at the call site where the ids already are, or refuse a mixed-dihedral
flip — **register the decision with its reasoning before you code it.** Do not
guess, and do not quietly pick the easier one.

**While you are there:** `occt_engine.dart:656` still documents `angleDeg` as
"which must be in (0, 90)". That is stale after v28 and is the same hardcoded 90
a third time, in the documentation.

## Half two — the deliverable I actually want

S16 audited the **shim's** entry points with one question: *has this parameter
ever been passed anything but its trivial value?* Eight had not. **Three of the
eight were wrong away from it**, and all three were reachable from the UI. They
had survived nine months and three device captures.

**Nobody has ever asked that question of the Dart feature layer**, and the
defect above is the first evidence that the answer is not "it is fine".

Produce S16 §1.4's table for it: per feature type, per parameter, *"is this
exercised away from its trivial value by any test?"*, answered per entry — with
honest **still untested** rows. S16 shipped three of those and the integrator
called them the honest empty regions; a table without them is worse than no
table.

You are auditing for the same *class* of assumption, not only for right angles:
a hardcoded 90; an axis assumed to be a world axis; a flag whose non-default
branch nothing has ever taken; a scalar standing in for something that varies
per element — which is exactly what the crux above turns out to be.

## This session may change behaviour, and the burden inverts

Fixing the flip changes what the application does: a flipped mode-2 chamfer on a
non-perpendicular edge currently refuses and afterwards builds. Under §1.2 that
is routed, not merged on your authority.

Every other session must prove it changed **nothing**. You must prove your change
is **correct**, which is harder. Pin the intended behaviour, show what it fixes,
show what else moves, and route the decision with `**Needs:** integrator` in
`CROSS-SESSION.md` **before** merging. A behaviour change is the human's call.

## Two rules about tests that this project learned the hard way

* **Differential, never a recorded golden** (§1.4). Four goldens broke the first
  IPA build; they pinned "this machine produced these digits", which was never
  the claim. Keep the old computation available as a test-only reference and
  compare old against new on the same machine in the same run.
* **Kernel-dependent Dart tests are SKIPPED on a host without OCCT**, which is
  most of CI. So pin the **arithmetic** — `180 − θ − α`, the mixed-dihedral
  decision, the bound — in a **pure-Dart test that needs no kernel**. S11 wrote
  the rule down: the ladders that need OCCT are skipped, "but the arrangement
  ladders must run on CI **or a break in them waits for a device**." A test that
  only runs where OCCT does is a test that will not tell you when you broke this.

## Definition of done

`OPTIMIZATION_PLAN_2.md` §6: `flutter analyze` zero new issues, `flutter test`
green including what you added, `python3 -m unittest discover -s ci -p 'test_*.py'`
green, predictions written down with their arithmetic before the change, your
findings file saying what you did, what you predicted, what you are unsure of,
and what you deliberately did not do.

**Check `git diff frontend/pubspec.lock` before every commit.** Anything that
resolves dependencies rewrites it — `flutter pub get`, and also `flutter
analyze`, which caught a previous integrator by surprise. A re-resolved lockfile
against a non-CI SDK has already cost this project a red build. CI runs Flutter
**3.47.1**.

**Anything you find outside this scope: write it down, do not fix it.**
