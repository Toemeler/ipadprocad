# Brief — Session 19: `finish_pipe` never checks its own result

**Work directly on `claude/perf-opt2`** (currently `2f2a308`, = tag
`build-477`/`build-478`). **Another session is committing to the same branch at
the same time** — read "You are sharing `claude/perf-opt2`" at the bottom of
this brief before your first push, not after your first rejected one.

**Allocated to you, with this brief, so they cannot collide** (three identifier
collisions have already happened on this project, and a fourth is sitting
unmerged on `claude/s18-corners-taper-j2cqqo` right now):

* shim version **v30** if you add ABI surface. **Not v29, and not 29 because
  the file says 28.** v28 is S17's and is the tip you can see; **v29 is already
  spoken for** by S18, which is complete on `claude/s18-corners-taper-j2cqqo`,
  is not merged yet, and is being renumbered from its own colliding v27. Do not
  read the next number off the file — the file cannot see S18.
* smoke scenarios **`[43a]`–`[43z]`**. `[39]` S15, `[40]` S16, `[41]` S17,
  `[42]` S18. Leave the gaps alone; closing a gap is how the fourth collision
  starts.

**You own:** `backend/occt/shim/**`, `backend/occt/tests/**`, `backend/bench/**`,
and `perf/findings/S19-validity.md`.

**You must not touch:** anything under `frontend/`, `ci/**`,
`perf/baseline.json`, `PERFORMANCE_PROFILE.md`, or `CALIBRATION.txt`.
Session 20 is running in parallel and owns the Dart side.

---

## Read first

1. `OPTIMIZATION_PLAN_2.md` §1.2 (behaviour changes are routed, not merged),
   §1.4 (differential comparison, never a recorded golden), §6.
2. `perf/findings/S18-corners.md` **§5** (three defects found and not fixed),
   **§7** (what it is unsure of, in cost order), **§8.2** and **§8.3**.
   S18 is on `claude/s18-corners-taper-j2cqqo` and is **not merged yet** — read
   it from that branch.
3. `perf/findings/S15-holes.md` **§5.5** and **§5.7**, and §19.2 of
   `PERFORMANCE_PROFILE.md` — the verification-cost numbers you are going to
   need and should not re-derive.
4. `perf/findings/S16-straight-audit.md` §1.4 and §2 — the equivariance
   instrument, which is the cheapest general check this project has found.

## The situation

`finish_pipe` returns whatever `MakeSolid` produced **without ever calling
`BRepCheck_Analyzer`.** That is how three separate defects stayed invisible for
nine months: a silently invalid solid is returned with no error and the
application accepts it and draws it.

S18 named the obvious response and correctly refused to take it alone:

> Adding a validity gate is a one-line change and a MUCH larger behaviour
> change than this session's: defect 1 above would start failing, and so would
> anything else in the field that is quietly invalid today. **The integrator's
> call, not mine.**

That call cannot be made without evidence, and producing the evidence is your
session. **Note that "a one-line change" is misleading on cost and you should
expect to say so with numbers:** S15 measured `occt_shape_valid` at
**8 817.1 ms** on a 2 402-face swept solid, and verification at **76.3 %** of
that staged total. A gate is not free at the sizes this operation reaches.

## The job

**1. What does the check cost, on the shipped path, at the sizes the app
actually reaches?** Not at S15's 1200-segment probe size only — across the
range. If the honest answer is "a gate doubles the cost of every sweep", that
is the finding and it decides the question on its own.

**2. What breaks?** A census, not an estimate: enumerate the sweep
configurations the application can actually produce — profile shapes, path
kinds (`OCCT_SWEEP_PATH_AUTO`/`POLY`/`SMOOTH`), taper, twist, orientation,
holes, section offset — and report how many are invalid **today**. Anything in
that set is something a user has that would start refusing.

**3. Chase S18 §5.1, which is a real open defect and is currently a guess.**
A sweep whose section is far off the spine goes INVALID on a many-jointed path
**with no taper involved**: the 16-edge polyline arc with a `[0,10]^2` square
whose corner sits on the spine gives 66 faces, 6553.070936, INVALID — while a
centred `[-5,5]^2` on the same path is 6000.000000 and valid, and a smaller
`[0,2]^2` is valid too. S18's reading is that adjacent mitre wedges collide
once the section reaches outside the path's curvature, which would make it
geometry rather than a kernel defect. **S18 says plainly it did not confirm
that.** Confirm or refute it. S18 §7.4 says the case most likely to hold the
answer — a section that is both **tilted and off-centre** at a drawn corner —
was never measured by anybody.

**4. Recommend.** Gate, gate with an opt-out, or do not gate — with the cost
and the break-count behind it, and with the alternative S15 §5.7 already
ranked: if only one of the two calls can be afforded, **drop
`occt_shape_volume` before `occt_shape_valid`**, because a solid that builds
and is invalid is the worst outcome available at that size.

## Pre-register, with arithmetic, before you write code

`OPTIMIZATION_PLAN.md` §2 has the form. Predict the cost of the check as a
fraction of construction at named sizes, and predict the break-count before you
run the census. Name what would make you stop.

## Instruments this project has already proven — use them, do not reinvent

* **`V = A·dz`** for any sweep of a section centred on its spine, in any corner
  mode, at any sampling density (S18 §3.5). It is a better analytic pin than
  anything S14 had and it costs nothing.
* **`V = A·L − 2·A·c_t·Σ tan(θ_i/2)`**, signed — a turn away from the centroid
  ADDS volume (S18 §8.3).
* **Face count is the cheapest corner diagnostic in the kernel** — 8 trimmed,
  10 untrimmed, 9 never treated (S18 §8.3).
* **Volume alone is not a discriminating invariant for a sweep** (S14-4). Use
  volume *and* validity *and* face count.
* **The differential smoke diff** (S17): build the pre-change tree and your tree
  on the same machine against the same OCCT and diff the smoke output. One
  `git archive`, one build. It is what caught the version-string drift that
  reading the file had missed.

## Traps that have each cost real time here

* **Run `gcc -fsyntax-only -I backend/occt/shim backend/occt/tests/smoke_occt.c`
  before every commit.** One second; it has caught a missing brace and an
  unterminated comment. It is a brace guard on the C fixture, **not** a build of
  the C++ shim — do not read a pass as more than that.
* **`occt-build.yml` is the only workflow that compiles `smoke_occt.c` or runs
  `occt_smoke`**, and it fires on push to `main`, on pull requests into `main`
  touching `backend/occt/**`, and on manual dispatch — **not** on a push to your
  branch. Dispatch it manually before you ask for a merge.
* **"Zero conflicts" hides silent breakage.** After every merge check brace
  balance, duplicate top-level declarations, and that every private identifier
  called has a definition. Two clean-reported merges have already carried a
  duplicated function and a call left on a renamed definition.
* **`git fetch origin '+refs/heads/*:refs/remotes/origin/*'` before you branch.**
  Stale remote-tracking refs have already produced a branch three commits behind
  and a rejected push that would have discarded work if forced.
* **Grab a CI log promptly.** The log branches are force-pushed per run and a
  force-pushed SHA cannot be fetched afterwards.

## Definition of done

`OPTIMIZATION_PLAN_2.md` §6, plus: `occt_smoke` PASS on real OCCT 7.9.3,
`occt_mesh_recon_test` green, `python3 -m unittest discover -s ci` green,
Lane C `LANE C: PASS`. State plainly what you could not run rather than
implying it passed — every session before you that hit the missing Flutter SDK
said so, and that is the standard.

**If the answer is "do not gate", say so and stop.** "This is not the right fix,
here is why" is a complete and valuable result. Do not manufacture a change for
a question that answers itself.

**Anything you find outside this scope: write it down, do not fix it.** Route it
in `CROSS-SESSION.md`, which is append-only.

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
