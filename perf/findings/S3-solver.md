# S3 — the 2D solver: the cubic

Session 3 of `OPTIMIZATION_PLAN.md` §5. Owns `frontend/lib/solver.dart` and,
in `app_state.dart`, only the `analyzeSketch` call sites and any cache around
them.

Everything above the line "IMPLEMENTATION" was written **before any code
changed**, as §2 requires.

---

## 0. What I measured before predicting anything, and why

§2 says no session can produce a device measurement, and that is true of
*timings*. It is not true of **operation counts**. The number of multiply-add
operations the elimination executes on a given fixture is a deterministic
property of the algorithm and the input: it is the same number on an iPad, on
CI and on this container. Counting it is not a timing, needs no device, and has
no noise floor.

So before predicting, I instrumented the existing `_analyzeSketch` — a
throw-away copy of it, reverted before implementation — and ran it on the exact
`stress.analyze` ladder (`perf_scenarios_stress.dart`: `sketchFixture(n/2)` +
`constraintFixture(n/2)` at n = 64…1024).

| n (entities) | total | m | rank | dof | nnz(J) | nnz(RREF) | max nnz per RREF row | **executed** mul-adds | mul-adds if the inner loop skipped the pivot row's zeros |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 224 | 162 | 162 | 62 | 321 | 286 | 2 | 100 703 | 1 291 |
| 128 | 448 | 322 | 322 | 126 | 641 | 574 | 2 | 728 767 | 4 619 |
| 256 | 896 | 642 | 642 | 254 | 1 281 | 1 150 | 2 | 5 533 055 | 17 419 |
| 512 | 1792 | 1282 | 1282 | 510 | 2 561 | 2 302 | 2 | 43 096 831 | 67 595 |
| **1024** | **3584** | **2562** | **2562** | **1022** | **5 121** | **4 606** | **2** | **340 145 663** | **266 251** |

Fitted exponents over the five rungs: executed mul-adds **k = 2.933**, the
sparse count **k = 1.925**, nnz(J) **k = 0.999**.

Three things follow, and the third is the whole session.

### 0.1 The profile's fixture arithmetic is confirmed exactly

§5.5.2 derives total = 3584, m = 2562, rank = 2562, dof = 1022 at the top rung
from the fixture definition. The instrumented run reports precisely those four
numbers. The fixture is producing the system the profile says it is.

I can add one more closed number to that set. The Jacobian's nonzero count is
predictable from the constraint list: 511 `equal` rows × 2 + 1024 `coincident`
constraints × 2 rows × 2 + 2 `fix` rows × 1 + 1 `dimension` row × 1
= 1022 + 4096 + 2 + 1 = **5121**, against **5121** counted. The matrix has
**0.056 %** of its 9 180 928 cells occupied — an average of **two** nonzeros
per row.

### 0.2 A correction to §5.5.2's operation count — the mechanism holds, the number does not

§5.5.2 puts the RREF at `m · total · rank` = 2.35 × 10¹⁰ operations, and derives
from that an implied Dart throughput of 2.66 × 10⁹ elementary operations per
second.

`_rankAndPivots` already carries `if (f == 0) continue;` in its row loop, so it
never touches a row whose entry in the pivot column is exactly zero — and on a
Jacobian this sparse, almost every row is exactly zero there. The count it
actually executes at n = 1024 is **3.40 × 10⁸**, not 2.35 × 10¹⁰: the profile's
figure is **69× too high**. The implied throughput is therefore not 2.66 × 10⁹
op/s but **3.85 × 10⁷ op/s** (3.40 × 10⁸ ops in 8837 ms) — a much slower and,
for a doubly-indexed `List<List<double>>` inner loop on a mobile core, a more
believable rate.

**What survives:** the exponent, and the attribution. Executed mul-adds fit
k = 2.933, against the device's measured k = 3.198 [2.835, 3.561] — inside the
interval. The cost *is* cubic and the cubic *is* in step 2. Only the constant
was wrong, and it was wrong because the bound `m · total · rank` assumes a dense
matrix while the skip makes the code adaptive to sparsity.

I am not editing `PERFORMANCE_PROFILE.md` (§3 forbids it). This entry is where
that correction lives until integration folds it in.

### 0.3 The finding this session turns on: there is no fill-in

**`max nnz per RREF row` is 2 at every rung, and nnz(RREF) is *lower* than
nnz(J).** Gauss–Jordan on this system does not densify it. The reduced matrix
is as sparse as the input.

This is not a lucky property of the fixture; it is what a sketch Jacobian is.
Each constraint touches two or three entities, so each row starts with a handful
of nonzeros, and the elimination graph of a chain of coincidences produces
almost no new ones.

So the cubic is not paying for arithmetic on a matrix that has become dense. It
is paying **`total − col` per affected row when the pivot row has two nonzeros
in that range.** The dense inner loop `for (j = col; j < cols; j++)` walks up to
3584 columns to do, on average, **two** useful multiply-adds. That is the
entire defect, and at n = 1024 the waste factor is **340 145 663 / 266 251 =
1278×**.

---

## 1. Which of the two directions §5-S3 offers, and why

The brief offers "make it cost less" and "run it less often" and asks which I
took. **I am taking both, and the order matters:** cost first, frequency
second, because they multiply and because the second is the one that can be got
wrong.

- **Cost.** §0.3 makes this unusually clean. The change does not need a new
  algorithm, a sparse *solver*, or a rewrite of the analysis: it needs the same
  Gaussian elimination, in the same order, with the same pivots, storing rows
  as (column, value) pairs instead of as full-width arrays. Every arithmetic
  operation the dense code performs on a nonzero is performed identically; the
  operations it performs on zeros are skipped, and skipping them is **exact**,
  not approximate — `a − f·0.0` is `a` for every finite `a` and `f` in IEEE 754,
  including both signed zeros. This is the rare optimisation that is
  bit-identical by construction rather than by hope.

- **Frequency.** §5.5.3's "runs on every rebuild, every solve and every tab
  switch" is 16 `_reanalyze()` call sites plus the rebuild path. A cache keyed
  on a *full copy* of the packed geometry and the constraint list — compared for
  equality, not hashed — is provably sound, because `_analyzeSketch` is a pure
  function of `(gs, cs)`. It cannot hit during a drag (geometry changes every
  frame) and I do not claim it will. It hits on tab switches and on the
  `_reanalyze()`-then-rebuild pairs.

**What I am not doing, and why.** The brief suggests the rank alone might be
wanted rather than the RREF, and the null-space basis only for the carrier test.
Both are true and neither is worth the risk: the basis *is* needed (the carrier
test reads directions from it, not booleans), and once elimination is sparse the
RREF costs 266 251 operations at the top rung, which is not a quantity worth
attacking. **The cheaper win is now the Jacobian construction**, and §4 says
what I am deliberately leaving on the table there.

---

## 2. Pre-registered predictions

Baselines are `PERFORMANCE_PROFILE.md` §5.5.1 (device, reference arm, LPM off,
build `230f179`) and the host counts of §0. Host timings below are from this
container (x86-64, `flutter test`, JIT) and are quoted **only** as ratios; §13.3
forbids passing an off-device absolute off as an iPad millisecond and the same
logic applies to a Linux container, more so.

Host baseline at n = 1024: Jacobian construction **3.191 s**, elimination
**21.004 s**, total **24.195 s** — elimination **86.8 %**.

### Prediction P1 — the exponent of `stress.analyze` falls from cubic to quadratic

```
Target        : stress.analyze, fitted k over the 64→1024 ladder
Baseline      : k = 3.198 [2.835, 3.561], R2 = 0.9962   (§5.5.1, LPM off)
                k = 3.071 [2.629, 3.513]                (§5.5.1, LPM on)
Mechanism     : the cubic is step 2 walking `total - col` columns per affected
                row to perform ~2 useful multiply-adds (§0.3). Sparse rows
                perform exactly the useful ones. The remaining superlinear term
                is step 1, the finite-difference Jacobian: `total` calls to
                _residuals, each O(m), = O(m·total), quadratic by construction.
Change        : sparse (column, value) row storage through _rankAndPivots, the
                null-space basis and the carrier test.
Predicted     : k = 2.0 +/- 0.35, and the interval must EXCLUDE 3
Derivation    : post-change cost = a*(m*total) + b*(sparse mul-adds).
                m*total   fits k = 2.000 by construction (both linear in n).
                sparse ops fit k = 1.925 (measured, §0).
                Both terms are quadratic, so their sum is quadratic; no cubic
                term remains anywhere in the routine.
Falsifiable by: a fitted k above 2.5 on the new ladder, or a CI that still
                contains 3. Either means a cubic term I did not find survived.
Risk          : the fixture is one connected component by design
                (perf_scenarios.dart says so explicitly), so nothing here comes
                from block-splitting. If a real sketch's Jacobian DOES fill in
                under elimination, k rises back toward 3 for that sketch and
                this prediction is about the fixture only.
```

### Prediction P2 — `stress.analyze` at 1024 entities

```
Target        : stress.analyze, top rung (1024 entities)
Baseline      : 8837 ms (LPM off), 16 860 ms (LPM on)          (§5.5.1)
Mechanism     : as P1.
Change        : as P1.
Predicted     : 700 ms  [400, 1600]   (LPM off arm)
Derivation    : host split 3.191 s Jacobian + 21.004 s elimination.
                Elimination mul-adds 340 145 663 -> 266 251, a factor 1278.
                Sparse per-operation cost is HIGHER than dense (index
                indirection, list growth, no linear scan): charge it 4x, so the
                realised elimination factor is ~320x  ->  21.004 s -> 0.066 s.
                Jacobian construction keeps its `total` _residuals calls but
                loses the 73.5 MB dense allocation and its column-strided
                writes (stride 28 KB, a cache miss per write): charge a 1.8x
                improvement -> 3.191 s -> 1.77 s.
                New host total ~1.84 s against 24.195 s = 13.2x.
                Device: 8837 ms / 13.2 = 670 ms, rounded to 700 ms.
                The interval is wide because the 4x sparse-overhead and 1.8x
                cache charges are estimates, not measurements, and because the
                device/host cost mix need not be identical.
Falsifiable by: a device figure above 2500 ms, which would mean the elimination
                is not where the time went and §0.2's attribution is wrong too.
Risk          : if _residuals itself (not its storage) dominates on device, the
                Jacobian term is a floor I cannot go under and the result lands
                at the top of the interval.
```

### Prediction P3 — the 105 MB goes away, and this is the sharpest of the four

```
Target        : stress.analyze.rssDeltaMB, top rung
Baseline      : 105 MB measured; §5.5.2 predicts 102.8 MB of it structurally
                (dense Jacobian 73.5 MB + null-space basis 29.3 MB) and calls
                the 2.2 % agreement the confirmation of the mechanism.
Mechanism     : both structures are dense arrays over `total` columns.
Change        : both become sparse.
Predicted     : structural allocation < 1 MB; measured rssDeltaMB < 15 MB
Derivation    : sparse Jacobian: nnz = 5121 entries x (8 B double + 4 B int32)
                = 61 KB, plus 2562 row objects ~ 200 KB.
                sparse null-space basis: one entry per free column (1022) plus
                one per (pivot row, free column) nonzero, which is
                nnz(RREF) - rank = 4606 - 2562 = 2044; total 3066 entries
                = 37 KB, plus 1022 vector objects ~ 80 KB.
                Structural total ~ 380 KB, i.e. 0.36 % of 102.8 MB.
                The 15 MB allowance is for the `total` = 3584 transient
                List<double> residual buffers (20 KB each) that step 1 still
                allocates and discards; they are garbage, not live, but
                rssDeltaMB is a peak-RSS delta and depends on GC scheduling —
                §5.5.2 already notes the LPM arm recorded +315 MB for the same
                rung on the same allocation.
Falsifiable by: rssDeltaMB above 40 MB, which would mean a dense structure I
                did not find is still being built.
Risk          : none to the arithmetic; the risk is entirely that peak RSS is a
                noisy instrument for a change of this shape.
```

### Prediction P4 — the cache, stated as a counter, not a time

```
Target        : a new counter, analyze.cache.hit / analyze.cache.miss
Baseline      : does not exist; today every call computes.
Mechanism     : _analyzeSketch is a pure function of (gs, cs). Consecutive
                calls on unchanged inputs must return an equal result.
Change        : an exact-comparison cache at the analyzeSketch call sites.
Predicted     : ui.drag60      -> hit rate 0 %   (geometry moves every frame)
                a tab switch to an unmodified open sketch -> hit
                stress.* / ramp.*  -> hit rate 0 % (each rung is a fresh sketch)
Derivation    : the fixtures rebuild geometry per rung, so the key never
                repeats; a drag mutates packed geometry every frame, so it
                never repeats either. Only idempotent re-entry hits.
Falsifiable by: a non-zero hit rate during ui.drag60 — that would mean the key
                is NOT covering something that changed, i.e. the cache is
                unsound, and it must be reverted rather than celebrated.
Risk          : this is the one change here that can return a WRONG answer
                rather than a slow one. The falsification test above is
                therefore also the safety test.
```

**Note for integration (§8 step 3):** P4 is deliberately a prediction of *no
measurable win on the suite*. The suite has no scenario that re-analyses an
unchanged sketch. I am registering it anyway because a hit during `ui.drag60`
is evidence of a defect, and someone reading the gate output should know that in
advance.

---

## 3. What I pinned before changing anything

`SketchAnalysis` carries three fields and every one of them is read by the UI:
`dof` (the gauge and the browser text), `freePoints` (gates dragging), and
`looseCarriers` (the DOF colouring). §5-S3's correctness note asks for all three
to be pinned before the algorithm moves, so `m232_analyze_pin_test.dart` does
that: it records dof, the movable set and the carrier set on a spread of
fixtures and asserts them unchanged.

---

## IMPLEMENTATION

*(filled in below as the work lands)*
