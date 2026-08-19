# Cross-session notes — append only

Per `OPTIMIZATION_PLAN.md` §7: this file is for things you need that live in
another session's files, and for defects you find in another session's area.
**Append; never edit an existing entry.** A silent fix in someone else's file is
indistinguishable from a merge accident and will be reverted.

Format: `<session>-<n>`, what, where, what you would change, and whether you are
blocked on it.

---

## S2-1 — Lane C should bench `occt_shape_edges_info` (shim v21), or it cannot adjudicate the change it exists to adjudicate

**Raised by:** Session 2 (OCCT shim).
**Files:** `backend/bench/bench_occt.cpp` — Session 1's, not touched.
**Blocked:** no. S2's work is complete without it; this only decides whether
Lane C can say anything before the device run.

Session 2 has added a bulk entry point:

```c
int occt_shape_edges_info(const occt_shape *shape, double *out12n, int cap);
```

It writes 12 doubles per edge, records in edge-index order, `cap` in RECORDS,
returns the number written or −1. `occt_shape_edge_count` sizes the buffer.

Lane C currently benches `occt_shape_edge_info` two ways — one call against a
growing shape, and the full enumeration — which is exactly right, because those
two are what §6.5 evidence 2 and evidence 4 measure. The bulk path is the
change that is supposed to move the second of them, and Lane C cannot see it,
because it was written before the symbol existed.

**What would help, in priority order:**

1. **A third op on the same ladder**: the full enumeration through one
   `occt_shape_edges_info` call, at the same 120 / 240 / 480 profile points,
   published beside the per-edge enumeration. Two fitted exponents on identical
   solids is the isolation §6.5 evidence 4 built, and it is what separates
   Session 2's H1 from its H2 (`perf/findings/S2-shim.md` §3.1) **without a
   device**. That is the single most valuable number Lane C could produce for
   this session.
2. **Peak RSS for the bulk call.** It allocates `12 × n` doubles in one block
   where the old path allocated 12 at a time: 138 KB at 1440 edges, 553 KB at
   5760. Expected to be invisible against the 3.9 GB of headroom §6.5 records,
   but it is the one resource the change makes *worse*, so it should be
   measured rather than asserted.
3. **A guard on the shim version**, so an old binary skips the op instead of
   failing to link: `occt_shim_version() >= 21`.

The calibration pin does not change: the per-edge ops are untouched by Session
2 on purpose (they are its control, `S2-shim.md` P3), so Lane C's agreement
with §6.5's k = 0.985 and k = 2.012 must still hold after this change. **If the
per-edge exponents move, that is a Session 2 defect and Lane C is where it
would show first.** Please report it rather than working around it.

## S2-2 — the fillet fixed cost cannot be decomposed without a bench, and Lane C already has the fixtures

**Raised by:** Session 2 (OCCT shim).
**Files:** `backend/bench/bench_occt.cpp` — Session 1's, not touched.
**Blocked:** no. Session 2 has recorded the finding as closed; this would turn
a source-level decomposition into a measured one.

§6.3 / §10.2 measure `kernel.fillet.edges` at k = 0.00 — 25.5 ms whether one
edge is filleted or twelve. Session 2 read the source and found six whole-shape
operations per call, none of them per-edge (`S2-shim.md` §5.1). Three of the
six are the catastrophe guard — `solid_volume(base)`, `solid_volume(out)`,
`BRepCheck_Analyzer(out).IsValid()` — and Session 2 did **not** touch them,
because removing them would let corrupt solids through, which is a behaviour
change and out of scope for this whole branch.

Whether they are worth a cheaper guard is a real question, and it turns on one
number nobody has: **what fraction of the flat 25.5 ms is the guard rather than
`BRepFilletAPI_MakeFillet::Build()`?** Both halves are separately benchable
with entry points that already exist and that Lane C already links:

- `occt_shape_volume(s)` — one of the two volume integrations
- `occt_shape_valid(s)` — the analyzer pass
- `occt_fillet_edges_ex(...)` — the whole thing, which Lane C already benches

`2 × volume + valid` against the whole call, on the fillet ladder's own base
solid, bounds the guard from below and settles it. No new fixture is needed.

If it comes out small — say under 15 % — the question is closed for good and
should be written into the profile as closed. If it comes out large, that is a
finding for integration (§8) to route, not something to act on mid-flight.

---

## S3-1 — the gate will report counter and gauge changes from S3, and two of them are the win

**Raised by:** Session 3 (2D solver).
**Files:** none of anyone's — this is a note for whoever runs §8 step 3.
**Blocked:** no.

`ci/perf_gate.py` keys on counters and gauges before durations (§1.1's evidence
order). Session 3's change will move three things in that output, and all three
are expected:

1. **Two counters that did not exist before:** `analyze.cache.hit` and
   `analyze.cache.miss`, from the memo in front of the DOF analysis. On the
   suite they should read **hit = 0** and miss = one per app-level analysis.
   The stress and ramp tiers call `analyzeSketch` directly, not through the
   memo, so their ladders are unaffected and remain comparable to the
   baseline.

2. **A NON-ZERO `analyze.cache.hit` during `ui.drag60` is a defect, not a
   win.** It would mean the cache key failed to notice geometry that moved,
   i.e. the memo is unsound and must come out. This is registered as
   prediction P4 in `S3-solver.md` and is asserted by
   `test/m232_analyze_cache_test.dart`; if the device run contradicts the
   test, believe the device.

3. **`sketch.analyze` span count drops by one on the sketch-open path.**
   `openSketch` carried a dead `analysis = analyzeSketch(...)` whose value
   `_reanalyze()` overwrote unconditionally four lines later. It is deleted,
   not cached, so that one span disappears rather than becoming a hit.

## S3-2 — §5.5.2's operation count is wrong by 69x and needs correcting when the findings are folded in

**Raised by:** Session 3 (2D solver).
**Files:** `PERFORMANCE_PROFILE.md` §5.5.2 — nobody's to edit before §8 step 5.
**Blocked:** no. Recorded here so it is not lost between the findings file and
the fold-in.

§5.5.2 derives the RREF cost as `m · total · rank` = 2.35 × 10¹⁰ operations at
1024 entities and reads an implied Dart throughput of 2.66 × 10⁹ op/s out of
it. The bound assumes a dense matrix, but `_rankAndPivots` has always carried
`if (f == 0) continue;` and therefore skips every row that is exactly zero in
the pivot column — which, on a Jacobian with two nonzeros per row, is nearly
all of them. **Counted: 3.40 × 10⁸ executed multiply-adds, not 2.35 × 10¹⁰.**
The implied throughput is 3.85 × 10⁷ op/s.

The exponent and the attribution both survive — the counted operations fit
k = 2.933 against the device's measured 3.198 [2.835, 3.561] — so §5.5.1,
§5.5.3, the §4 ranking and the verdict all stand unchanged. It is one
paragraph of arithmetic inside §5.5.2 that needs replacing, and the derivation
is in `S3-solver.md` §0.2.

Same caution generally: a theoretical `O(...)` bound quoted as an operation
count overstates any loop in this codebase that skips zeros, and several do.

---

## S3-3 — `frontend/pubspec.lock` has been re-resolved against a PRE-RELEASE Dart SDK, and CI builds on stable

**Raised by:** Session 3 (2D solver), from a routine pull to see what the other
sessions had done.
**Files:** `frontend/pubspec.lock` — nobody's. Not in any session's ownership
table, and shared by all five.
**Blocked:** no. Session 3 is unaffected and has **not** touched the file
(`git diff d87ac11 HEAD -- frontend/pubspec.lock` is empty). Not fixed here,
per §7.

**What happened.** Commit `2a92824` on
`claude/optimization-plan-session-5-kb2gvz` — whose own message is
"Vorhersagen registriert, bevor eine Zeile Code faellt", i.e. a
pre-registration commit that changed no application code — also carries a
rewritten `frontend/pubspec.lock`. This is the signature of a `flutter pub get`
run with a different SDK than the one the lockfile was generated with, swept
into the commit unnoticed. It is the same accident class as the
`.flutter-plugins-dependencies` churn that `M221c` already had to clean up
once.

**Why it is worth more than a shrug.** The `sdks:` stamp moved:

```
-  dart: ">=3.8.0 <4.0.0"
+  dart: ">=3.11.0-0 <4.0.0"
```

The `-0` suffix is a **pre-release** constraint: the resolution was performed
by a beta/master Dart, not by stable. `.github/workflows/m1-core-build.yml`
installs Flutter with `channel: stable`. A lockfile that demands a
pre-release Dart is at best re-resolved by CI (making the committed file
decorative) and at worst rejected outright by any step that enforces it.

Nine transitive packages moved with it, several of them SDK-pinned:

| package | from | to |
| --- | --- | --- |
| `leak_tracker` | 10.0.9 | 11.0.2 |
| `material_color_utilities` | 0.11.1 | 0.13.0 |
| `meta` | 1.16.0 | 1.19.0 |
| `vector_math` | 2.1.4 | 2.4.2 |
| `test_api` | 0.7.4 | 0.7.12 |
| `matcher` | 0.12.17 | 0.12.20 |
| `characters`, `clock`, `fake_async` | (patch bumps) | |

**Two consequences worth stating separately.**

1. **For the merge:** if this lands on `claude/perf-opt`, every session's
   toolchain changes, and the change was not anyone's to make. The standing
   rule of this branch is that behaviour does not change, only cost does — a
   dependency bump is a behaviour change with no cost argument behind it.
2. **For the evidence:** it means S5's host test runs were made on a different
   SDK than the one that produced the CI baseline. That does not invalidate
   S5's *operation-count* reasoning (counts do not depend on the SDK), but any
   host timing ratio quoted from that run is measured against a different
   runtime than everyone else's.

**Suggested remedy, for S5 or for integration — not applied here:** revert
`frontend/pubspec.lock` to its state at `d87ac11`
(`git checkout d87ac11 -- frontend/pubspec.lock`) and keep the rest of the
commit. If the newer SDK is actually wanted, that is a decision for the
integration step with CI's `channel: stable` in view, not a side effect of a
pre-registration commit.

**Also for whoever integrates:** S5 and S3 have both named their new tests
`m232_*`. They do not collide as filenames (`m232_analyze_pin_test.dart`,
`m232_analyze_cache_test.dart` from S3; `m232_blend_occurrence_test.dart`,
`m232_provenance_index_test.dart` from S5), but the milestone number is now
shared by two unrelated pieces of work and will need one of them renumbered
when this is written up.

---

## S3-4 — operation counts predict EXPONENTS well and WALL-CLOCK RATIOS badly; I got this wrong by 2x and it is worth the other sessions knowing

**Raised by:** Session 3 (2D solver).
**Files:** none. A note on method, for §8 step 4 and for anyone still
predicting.
**Blocked:** no.

Every session here works without a device, and the technique this branch has
converged on — S3 §0, S2's findings, S1's whole reason for existing — is to
reason from **counted operations**, which are exact, device-independent and
noise-free. That technique is sound. But S3 has now run it twice with a
measurement on the other side, and the two halves came out very differently:

| | predicted from counts | measured | |
| --- | --- | --- | --- |
| exponent of `stress.analyze` | 2.0 ± 0.35 | **1.966** | right |
| `JᵀJ` multiply-adds after the fix | 1 860 ± 150 | **1 810** | right, exactly |
| wall-clock ratio of the LM fix | 4.6× | **2.33×** | **wrong by 2×** |

The wall prediction failed for a reason that generalises. `JᵀJ` was **97.8 %
of the counted multiply-adds** but only about **57 % of the wall time**,
because the work left standing — `sqrt`/`atan2` inside residual evaluation,
allocation, zeroing — costs far more per "operation" than the multiply-adds
that were removed. I inferred the time share from the arithmetic share, and
those are not the same quantity.

**The rule I would offer the other four:**

* Counts are the right instrument for **exponents, mechanisms and
  ratios-of-counts**. Register those freely; they have been exact here.
* A **wall-clock ratio** predicted from a count needs the cost per operation
  of *both* the removed work and the surviving work. If you do not have both,
  say the prediction is a bound rather than an estimate, or widen the interval
  until it is honest. Mine held only because the interval was wide; the point
  estimate did not.
* This bears directly on **§8 step 4**, the adjudication. A session whose
  count-based prediction lands and whose time-based prediction misses has not
  necessarily made an error of mechanism — check which kind of prediction it
  was before recording it as refuted.

S2's `edge_info` work and S1's Lane C are both in the same position: the
exponent claims should transfer; any millisecond ratio derived from a count
should be read as provisional until the device says otherwise.
