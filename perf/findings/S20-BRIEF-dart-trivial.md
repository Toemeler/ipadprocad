# Brief — Session 20: the Dart side has never been audited away from its trivial values

**Work directly on `claude/perf-opt2`** (currently `2f2a308`, = tag
`build-477`/`build-478`). **Another session is committing to the same branch at
the same time** — read "You are sharing `claude/perf-opt2`" at the bottom of
this brief before your first push, not after your first rejected one.

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

---

## You are sharing `claude/perf-opt2` with the other session

Both sessions commit **directly to `claude/perf-opt2`**, at the same time. There
is no session branch to hide in and no merge at the end where someone else
reconciles you. Read this part twice.

**This works only because your file sets are disjoint.** File ownership stops
being administrative here and becomes the thing that makes concurrent commits
survivable — git can merge two sessions that never touch the same file, and
cannot merge two that do. S19 owns `backend/**`. S20 owns the chamfer path in
`frontend/lib/part_model.dart`, `frontend/lib/ffi/occt_engine.dart` and new
files under `frontend/test/`. **Found something wrong in the other session's
area? Write it down, do not fix it** (`OPTIMIZATION_PLAN_2.md` §0.6). A patch
into their files is how a shared branch turns into a lost afternoon.

**Never force-push. Never rebase. Never `checkout -B`.** This is §0.2 of the
prime directive and it exists because those three delete other people's work
irrecoverably, while a merge conflict never does. A rejected non-fast-forward
push is **not an obstacle — it is the branch protecting the other session**. The
fix is always to fetch and merge, never `--force` and never `--force-with-lease`.
This has already happened once on this project: a branch cut from a stale
`origin/claude/perf-opt2` was three commits behind and the push was rejected,
which was lucky, because forcing would have discarded them.

**So, every time, before you branch and before you push:**

```
git fetch origin '+refs/heads/*:refs/remotes/origin/*'
```

A plain `git fetch` after pushing with a refspec leaves remote-tracking refs
stale, and stale refs are how the above happened.

**Pull before every push, and expect to do it more than once.** Merge, never
rebase.

**Commit small and push often.** On a private branch, holding 800 lines back for
a day costs nobody anything. Here it makes the other session's merge worse every
hour you wait.

**Keep the branch green.** On your own branch you can be red for an afternoon.
Here a broken commit blocks the other session, so run your checks *before you
push*, not before you ask for a merge. For S19 that includes
`gcc -fsyntax-only -I backend/occt/shim backend/occt/tests/smoke_occt.c`, which
takes one second and has already caught a missing brace and an unterminated
comment.

### The one file you will both touch, and its resolution is not a judgement call

`perf/findings/CROSS-SESSION.md` is **append-only**, you will both append to it,
and it **will** conflict. The resolution is fixed:

> **Keep BOTH blocks, in chronological order.** Never drop, edit, reorder or
> rewrite an entry you did not write — including to "tidy" it.

That is exactly how the integrator resolved the same conflict on the S6 merge,
and it is the only resolution this file admits. Your own findings file is yours
alone and nobody else writes to it.

### Three things neither of you may do, whatever your work seems to need

* **Do not re-record `perf/baseline.json`** (§0.3). It is the shared reference
  every regression check runs against.
* **Do not edit `PERFORMANCE_PROFILE.md`** (§0.4). Write to your findings file;
  it is folded in once, at integration.
* **Do not touch `frontend/lib/perf*.dart`.** It is the frozen measurement
  apparatus and changing it silently changes what every past number meant.

### Two things about timing you should know rather than discover

**The device capture cannot be contaminated by you, and you should not work
around it.** `build-477` and `build-478` are **tags** at `2f2a308`; the branch
moving underneath them does not move a tag. So commit freely. The corollary is
the part to keep straight: **your work will not be in that capture**, and that
is correct and expected — it is adjudicated on desktop, on Lane C, and on the
host test suites, and a later capture picks it up.

**S18 may land on this branch mid-session.** It is complete on
`claude/s18-corners-taper-j2cqqo`, touches `backend/occt/shim/**`,
`backend/occt/tests/**` and `backend/bench/**`, and is waiting on one owner
decision. If it merges while you are working, treat it as any other merge — and
S19 in particular should expect it, since it lands in your files. **After any
merge that reports "zero conflicts", check three things anyway:** brace balance,
duplicate top-level declarations, and that every private identifier called still
has a definition. Two merges on this project reported clean and contained
neither — one carried a duplicated top-level function, the other a call left on
a name that main had renamed.
