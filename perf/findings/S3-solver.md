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

### 4. What changed

Three changes, in `solver.dart` except where noted.

**(a) The elimination is sparse.** `_SpMat` stores rows as ascending
(column, value) pairs; `_rankAndPivots` takes one and reduces it in place.
Pivot choice, pivot order, normalisation range and the elimination range are
the dense algorithm's, unchanged — the only difference is that operations on
zeros are not performed. A column index (column → occupying rows) replaces the
full-row scan; it is kept exact by never dropping an entry that cancels to
zero, which removes the need for a removal path and any risk of it going
stale.

**(b) The null-space basis and the carrier test are sparse.** The basis is
built by walking the RREF's occupied entries instead of probing
(total − rank) × rank cells for them — 2 044 answers behind 2.6 million probes
at the top rung. The vectors are then scattered one at a time into a single
reusable full-width buffer, so the carrier test's reads (`v[oa]`, `v[o + 2]`,
…) are the same expressions on the same values, while the
(total − rank) × total allocation is gone. Only the entities a vector actually
touches are examined; an untouched entity reads all-zero, and every test is
`|component| > tol · vmax` with `vmax > 0` guaranteed by the guard above it, so
it can never come back loose. That skip is a proof, not a heuristic.

`debugRank` and `wouldOverconstrain` built the same dense Jacobian and called
the same reducer; both now share `_jacobian` and the sparse reducer.

**(c) The memo, and one dead store.** `SketchAnalysisCache` (capacity 4, LRU)
keyed on `analysisKey` — a full value snapshot of geometry and constraints,
compared for equality. `app_state.dart` gains the field and two call sites
route through it.

The third call site is **deleted**: `openSketch` computed
`analysis = analyzeSketch(...)` on the load path, and `_reanalyze()` at the end
of the same function overwrote it unconditionally a few lines later. Nothing
between the two reads `analysis`, and nothing mutates the sketch, so the
value never reached anything. It was not a cache candidate; it was dead. When
a part's child sketch is open it was worse than dead — `current` is the child,
so the call analysed a sketch whose result was then replaced by a different
one's.

### 5. Host result

> **Superseded by §12.** The figures below were taken on the OLD base
> (`claude/perf-opt` @ `d87ac11`). §12 re-measures both sides on the
> integration base with the same harness and reports 13.53x rather than
> 20.69x. The exponents agree; the ratio does not. Read §12 first.


Same machine, same test, uninstrumented, `analyzeSketch` on the
`stress.analyze` ladder. The "before" column is the implementation as it stood
at `4890f06`, measured the same way (not the instrumented copy of §0, whose
counters inflated it).

| n (entities) | before | after | speedup |
| ---: | ---: | ---: | ---: |
| 64 | 31.5 ms | 27.8 ms | 1.14x |
| 128 | 73.6 ms | 49.3 ms | 1.49x |
| 256 | 184.7 ms | 65.6 ms | 2.82x |
| 512 | 1 229.2 ms | 167.3 ms | 7.35x |
| **1024** | **20 701.4 ms** | **1 000.6 ms** | **20.69x** |

Fitted over the top three rungs — the range where the ladder is out of the
fixed-cost floor that dominates n = 64 (both columns are ~30 ms there, which is
JIT warm-up, not the algorithm):

| | *k* | R² |
| --- | ---: | ---: |
| before | **3.404** | 0.9873 |
| after | **1.966** | 0.9684 |

The "before" exponent is the device's finding reproduced on a different CPU
and a different runtime: 3.404 against the measured 3.198 [2.835, 3.561]. That
agreement is what licenses reading the "after" column at all.

**P1 is met on the host.** k = 1.966 against a predicted 2.0 ± 0.35. It is not
yet met on the *device* — that is what the §8 capture adjudicates, and nothing
here substitutes for it.

**P2 projects to 8837 / 20.69 = 427 ms**, inside the registered
[400, 1600] but near its floor: I charged sparse indexing 4x the dense
per-operation cost and it evidently costs less than that. **This is a
projection from a host ratio, not a device measurement**, and the ratio need
not transfer exactly: this container runs the Dart VM in JIT, the iPad runs
AOT, and the two phases that remain need not shift by the same factor between
them.

**P3 is met by construction**, though not yet by measurement. Both structures
§5.5.2 identified — the `m × total` Jacobian (73.5 MB) and the
`(total − rank) × total` basis (29.3 MB) — are gone from every one of the three
sites that built them. What replaces them is nnz-proportional plus one
full-width scratch buffer of `total` doubles (28 KB at the top rung). Only
`rssDeltaMB` from a device run can close it.

**P4 stands as registered.** The memo is not in the perf suite's path — the
stress and ramp scenarios call `analyzeSketch` directly — so the ladder numbers
above are the raw path, unaffected. `analysisKey` costs about 2 ms at 1024
entities against the ~956 ms it may avoid (0.2 %), and is linear in sketch
size.

### 6. What is now the bottleneck, and what I deliberately left

At n = 1024 the remaining second is almost entirely **step 1**, the
finite-difference Jacobian: `total` = 3584 calls to `_residuals`, each O(m).
That is quadratic by construction and it is what the fitted 1.966 is
measuring.

It could be made near-linear — for parameter *k*, only the constraints
referencing *k*'s entity can change — and **I did not do it.** The reason is
specific rather than general: that optimisation needs a map from constraint to
the parameters it can depend on, and a residual here can reach geometry its
own `ents`/`pts` do not name. Two cases in this file do: the point-on-curve
branch reads a frame frozen in `_prepare` (`ctx.onCurve[i]`, indexing a
carrier's vertex block), and `CType.pattern` ties a copy to a source. A map
that misses one of those records a zero where a nonzero belongs, which lowers
the rank, which raises the reported DOF, which paints a constrained sketch as
free and lets the user drag what should be pinned. Nothing throws.

The present code takes no such risk: `_jacobian` *discovers* the zero
structure by perturbing and observing, so a dependency it does not know about
cannot be missed. Anyone taking the next step should pin the sparse Jacobian
against the dense one, entry for entry, on every constraint type before
trusting it — and the 35 cases of `m232_analyze_pin_test.dart` are the fixture
set for that.

I also did not touch the **LM fallback** (§5.4), the second item in the S3
brief. It is untouched and unmeasured by me, and it remains what §5.4 says it
is: 3.9 % of solves, 0.4 % of that time inside libslvs, all the rest Dart-side.
Sizing it properly needs the counter `solve.path.lm` from a device run, and
the fixture-dependence the profile warns about (the ratio has been 186x, 245x
and 334x on different runs) means the *share*, not the ratio, is the quantity —
which is a device measurement. Doing it would also have meant a second, larger
change to `solveConstraints` in the same session as this one, and a merge into
`claude/perf-opt` that mixed the two.

### 7. What I am uncertain about

- **Whether the device shows the host's 20.7x.** The exponent should transfer;
  the constant may not.
- **Whether a real sketch's Jacobian fills in.** The measured zero fill-in is
  the profile's fixture, which is one connected component of coincidences and
  radii. A sketch whose constraint graph is denser could fill in under
  elimination, and there the exponent would climb back toward 3. Nothing in
  this change is *wrong* in that case — the output is identical either way —
  but the win would shrink.
- **The n = 64 and n = 128 rungs barely move** (1.14x, 1.49x). Both are ~30 ms
  of fixed cost on this host, and the fixed cost is not the elimination. On a
  device, where §5.5.1 records 1 ms and 10 ms for those rungs, the fixed cost
  is a different fraction and these two rungs may behave differently.

### 8. Verification

- `flutter analyze`: 0 errors, 55 issues — the count `HANDOFF.md` records as
  the standing baseline since M220, and none of them in the changed code.
- `flutter test`: **2116 green**, against 2050 before this session — the 66
  added are this session's two files. Run twice: once on S3 alone, once after
  merging `claude/perf-opt` at `d87ac11` (S1's bench branch and S2's shim v21),
  where it is **2122 green** — the same 2116 plus S2's six; and **2128** once
  §9's LM work and its six pin cases landed. The merge had no
  conflict: S2 changes `occt_capi`/`occt_engine.dart`, S3 `solver.dart` and
  twelve lines of `app_state.dart`.
- `python3 -m unittest discover -s ci -p 'test_*.py'`: 45 green.
- Behaviour pinned by `m232_analyze_pin_test.dart` (35 golden cases + purity +
  no-mutation) recorded against the OLD implementation and unchanged by the
  new one, and by `m232_analyze_cache_test.dart` (the key's field coverage by
  mutation, the memo's equivalence and eviction, and P4's must-never-hit).
- `perf/baseline.json` untouched. `PERFORMANCE_PROFILE.md` untouched.

---

## 9. Addendum — the LM fallback, reopened

**Registered after the analysis change had already landed (`15dc9ae`), and
before any line of `_lm` moved.** §2 asks for pre-registration; this is
pre-registration of the *second* change, not of the first, and saying so is
part of the record. §6 above deferred this item, and the deferral was wrong on
the merits — the reason it gave ("sizing it needs a device counter") is a
reason not to quote a speedup share, not a reason not to look. §0 of this same
file argues that operation counts need no device. I did not apply my own
argument to the second half of my own brief until asked whether the session
was finished.

### 9.1 What the count says

Instrumented copy of `_lm`, reverted before implementation, on the profile's
own `solve.overConstrained` fixture (`sketchFixture(24)` +
`constraintFixture(24)` + a conflicting `fix` — the 168-parameter system §5.4
names):

| | |
| --- | ---: |
| parameters *n* / residuals *m* | 168 / 124 |
| LM iterations actually run | 5 |
| Jacobian nonzeros, summed over iterations | 1 215 (≈243 of 20 832 cells, **1.2 %**) |
| **`JᵀJ` multiply-adds executed** | **8 801 520** |
| …of which both factors are nonzero | **1 810** |
| **waste factor** | **4 863×** |
| `_solveDense` multiply-adds | 91 475 |
| Jacobian construction (residual evaluations) | 104 160 |
| host wall | 557 ms |

**`JᵀJ` formation is 97.8 % of the LM's arithmetic, and 99.98 % of it
multiplies at least one zero.** It is the same defect as §0.3 — a dense triple
loop over a sparse matrix — with a worse ratio than the one already fixed
(4 863× against 1 278×).

Two things this also settles, both negative and both worth recording:

* **The second LM run is not a duplicate.** §5.4 describes "twice while
  dragging". Reading `_solveConstraintsInner`, the relaxed run is
  `else`-guarded: it happens only when the frozen run fails. There is no
  double call to collapse, and the two-stage strategy is deliberate — a drag
  is a wish, not a command. Nothing to do here.
* **`_solveDense` is not the problem.** At 91 475 operations it is 1.0 % of
  the total, and it already skips exact zeros. It becomes the largest
  *arithmetic* term after the fix and is still an order of magnitude below the
  residual evaluations.

### 9.2 Prediction P5

```
Target        : (a) JtJ multiply-adds at solve.overConstrained  [host-verifiable]
                (b) host wall for that scenario                 [host-measurable]
                (c) device solve.lm mean, and solve.overConstrained total
Baseline      : (a) 8 801 520 executed, 1 810 useful   (measured above)
                (b) 557 ms                             (this container)
                (c) solve.lm mean 50.4 ms, n = 28; solve.overConstrained
                    solve.total 66.4 ms of which solve.lm 64.2 ms  (§5.4)
Mechanism     : jtj[a][b] = sum_i j[i][a]*j[i][b] is computed by iterating
                every (a, b, i) triple: n*(n+1)/2 * m per iteration. The
                Jacobian is 1.2 % occupied, so nearly every product has a zero
                factor and contributes exactly 0.0.
Change        : accumulate row-major over the Jacobian's NONZEROS instead —
                for each residual row i, for each pair (a, b) of columns
                occupied in that row, jtj[a][b] += j[i][a]*j[i][b].
Predicted     : (a) 1 860 +/- 150     (b) 120 ms [60, 250]
                (c) solve.lm mean 15 ms [7, 30]; solve.overConstrained
                    solve.total 20 ms [10, 40]
Derivation    : (a) cost becomes sum over rows of nnz_i*(nnz_i+1)/2. Measured
                    nnz is ~243 per iteration over m = 124 rows, i.e. ~2 per
                    row, giving 124 * (2*3/2) = 372 per iteration and 1 860
                    over the 5 iterations. That the independently counted
                    "useful" figure is 1 810 is the cross-check: the two agree
                    to 2.7 %.
                (b) total counted arithmetic 8 997 155 -> 197 495, a factor
                    45.6. Wall cannot follow that, because what REMAINS is
                    dominated by the 845 _residuals calls, which carry sqrt
                    and atan2 rather than plain multiply-adds and were never
                    part of the 45.6x. Charging the surviving work the whole
                    557 ms minus the JtJ share, and allowing that the JtJ
                    share is not measured separately, gives a wide interval
                    around ~120 ms.
                (c) 66.4 / (557/120) = 14.3 ms, rounded up to 20 ms because
                    the device's mix of the surviving terms need not match
                    this container's.
Falsifiable by: (a) a count outside [1710, 2010] — that would mean the
                    sparsity model of the LM Jacobian is wrong, and (b) and
                    (c) should not then be believed either.
                (c) a device solve.lm mean above 35 ms.
Risk          : the win scales with how sparse the Jacobian rows are. A sketch
                coupling many entities per constraint — patterns, chains of
                tangency — has wider rows, and nnz_i^2 grows faster than the
                dense form falls. The fix can never be SLOWER than a
                fully-dense row (it degenerates to the same triple loop), but
                on such a sketch the factor could be single digits rather
                than thousands.
Correctness   : bit-identical, and by a stricter argument than §1's. For a
                fixed (a, b) the surviving terms arrive in ascending i, the
                same order as the original inner loop, so the accumulation
                sequence is unchanged and only exact-zero addends are dropped.
                `jtr` keeps its original shape — accumulate positively, negate
                once at the end — so that an all-zero column still produces
                -0.0 rather than +0.0, which the row-major form would
                otherwise change.
```

**The pin, written before the change:** `m232_lm_pin_test.dart` records the
full solved parameter vector, digit for digit, for all three LM entry paths
(`lm`, `lm-frozen`, `lm-relaxed`), for the profile's unsatisfiable fixture,
and for a tangency; plus `debugRank`'s triple. No tolerances anywhere — `_lm`
moves geometry, and after eighty damped iterations a difference in the
fifteenth decimal is not guaranteed to stay in the fifteenth decimal, because
the λ schedule branches on `e2 < err`.

### 9.3 Adjudication of P5 — one prediction exact, one nearly refuted

Measured on the same harness with the same warm-up on both sides (the 557 ms
quoted in §9.1 had no warm-up; re-measured with one it is 575 ms, so the two
figures are the same number and the warm-up was not what moved).

| | before | after | |
| --- | ---: | ---: | ---: |
| `JᵀJ` multiply-adds | 8 801 520 | **1 810** | **4 863×** |
| host wall, `solve.overConstrained` | 575 ms | **247 ms** | **2.33×** |
| solved geometry | — | — | **bit-identical** |

**P5(a): exact, and better evidence than "inside the interval" suggests.**
Predicted 1 860 ± 150 from the row occupancy; measured **1 810**. That number
is not merely close to the prediction — it is *identical to the independently
counted 1 810 products that had two nonzero factors* in the before-run. The
new formulation performs precisely the multiplications that were doing work
and not one more. There is nothing left to remove from that loop.

**P5(b): met only at the ceiling of its interval, and the point estimate was
wrong by a factor of two.** Predicted 120 ms [60, 250]; measured **247 ms**.
I will not dress that up: the interval held, the estimate did not, and the
reason is a methodological error worth more than the prediction.

I inferred the wall-time share from the *arithmetic* share. `JᵀJ` was 97.8 %
of the counted multiply-adds, so I charged the surviving work only what was
left over. Solving backwards from the measurement, `JᵀJ` was in fact about
**57 %** of the wall time:

&nbsp;&nbsp;&nbsp;&nbsp;575 × (1 − f) = 247 → f ≈ 0.57

**A counted multiply-add is not a unit of time.** What survives here — 845
`_residuals` evaluations carrying `sqrt` and `atan2`, the per-iteration
allocation and zeroing of an n × n matrix, `_solveDense` — costs far more per
"operation" than the multiply-adds that were removed. §9.2's derivation named
this caveat and then under-weighted it by about half.

This matters beyond S3, because reasoning from operation counts is the
technique this whole branch has adopted in the absence of a device (§0, and
S2's findings do the same). The counts remain the right tool for **exponents
and mechanisms** — they are exact, device-independent and noise-free, and
they were exactly right about both here. They are a **poor proxy for
wall-clock ratios** whenever the work left standing is transcendental-heavy or
allocation-heavy. Predicting a *ratio* from a count requires knowing the cost
per operation of both the removed work and the surviving work, and I knew
neither.

**P5(c) is untouched by this** — it was a device prediction and only a device
run adjudicates it. But it was derived from P5(b)'s point estimate, so it
should be read down accordingly: with the measured 2.33× rather than the
predicted 4.6×, `solve.overConstrained` projects to 66.4 / 2.33 ≈ **28.5 ms**
rather than 20 ms, and `solve.lm` to 50.4 / 2.33 ≈ **21.6 ms** rather than
15 ms. Both are still inside their registered intervals ([10, 40] and [7, 30]).
I am recording the revision rather than quietly reusing the intervals.

### 9.4 What is left in the LM, and why I am stopping here

The remaining 247 ms is dominated by the `_residuals` calls that build the
Jacobian — n + 1 of them per iteration, each O(m), each carrying real
trigonometry. That is **the same problem as §6**: making it cheaper needs a
constraint → parameter dependency map, and the same two hazards apply
(`ctx.onCurve`'s frozen frame, `CType.pattern`). The boundary is drawn in the
same place for the same reason, and drawing it consistently is the point: both
Jacobian builders in this file discover their sparsity by perturbing, so
neither can miss a dependency nobody declared.

The other survivor is the per-iteration `List.generate(n, ...)` for `JᵀJ` —
O(n²) allocated and zeroed five times here. It could be hoisted and
selectively re-zeroed from the sparsity pattern, since `_solveDense` destroys
it in place. I have not done it: it is a smaller term than the residuals, and
it would trade a clearly-correct allocation for a reuse whose invalidation I
would then have to argue. If the device run shows the LM still hot after this
change, that is the next thing to take, and it is cheap.

---

## 10. Against the noise floor (§3.2), which is the worst in the app

The S3 brief points at §3.2 specifically: `analyze` has a 13 % IQR and a 17 %
full spread, `solve` 4 % and 18 %. **A change below ~17 % in either is not a
signal.** That is the bar every claim here has to clear before a device run
can even see it.

| quantity | change | noise floor | readable? |
| --- | ---: | ---: | --- |
| `stress.analyze` @ 1024 | **−95.2 %** (20.7×) | ~17 % | yes — 5.6× the floor |
| `stress.analyze` @ 512 | −86.4 % (7.35×) | ~17 % | yes |
| `stress.analyze` @ 256 | −64.5 % (2.82×) | ~17 % | yes |
| `stress.analyze` @ 128 | −33.0 % (1.49×) | ~17 % | yes, but not comfortably |
| `stress.analyze` @ 64 | −11.7 % (1.14×) | ~17 % | **no — inside the noise** |
| `solve.overConstrained` | −57.0 % (2.33×) | ~18 % | yes |
| `JᵀJ` multiply-adds | −99.98 % | none (exact count) | yes |
| `stress.analyze.rssDeltaMB` | −99 % predicted | not characterised | probably |

Two consequences I want on the record before the device run, so that neither
is read as a surprise afterwards:

1. **The 64-entity rung will not show this change**, and may come back either
   side of its baseline. That is not a regression and not a failure of P1 — it
   is an 11.7 % move against a 17 % floor, on a rung the device records as
   1 ms against a 1 µs quantum (§5.5.1's own footnote declines to use it in
   any ratio). The exponent fit is what carries P1, and §5 fits it over the
   top three rungs for exactly this reason.
2. **The counters carry more weight than the durations here**, which is also
   §1.1's stated evidence order. `analyze.cache.hit`/`miss` and the
   `sketch.analyze` span count are exact; the `JᵀJ` count is exact. If the
   device durations come back muddy, those still adjudicate the mechanism.

---

## 11. The integrator's narrowed rule, and where S3 sits under it

The integrator's ruling on S4-2 replaces plan §1's literal "bit-identical"
with:

> Bit-identical wherever the prior behaviour was well-defined. Where a change
> **alters a numerical result**, it is in scope only if all three hold, each
> proven by test: (a) the residual is no worse; (b) the difference is inside
> the tolerance the code declares for that data path; (c) it does not
> accumulate under repetition.

**S3 does not alter a numerical result, so it never reaches (a), (b) or (c).**
It sits in the first branch, and the reason is structural rather than
fortunate: the sparse elimination performs exactly the operations the dense
form performed on nonzeros, in the same order, with the same pivots, and skips
only additions of exact zero. `a − f·0.0` is `a` for every finite `a` and `f`
in IEEE 754, both signed zeros included. The same holds for the LM's normal
equations: for a fixed (a, b) the surviving products still arrive in ascending
i, so the accumulation sequence is untouched.

That is an argument. Here is the evidence, all of it recorded against the
implementation as it stands on `claude/perf-opt` @ `2921d3f` — the dense one:

| test | what it pins | result |
| --- | --- | --- |
| `m232_analyze_pin_test` | dof, movable set, carrier colouring — 35 cases, exact strings | unchanged |
| `m232_lm_pin_test` | the full solved parameter vector, digit for digit, all three LM paths | unchanged |
| `m232_no_accumulation_test` | 100 successive drag+analyse cycles: final geometry, final analysis, final residual | unchanged |

No tolerances appear in any of them.

### Why I wrote the (c) test anyway

Determinism makes it redundant: if one call is bit-identical then any sequence
of calls is, and the single-call goldens already prove the former. I wrote it
for two reasons the ruling itself implies.

First, the integrator asked for **tests**, and "it follows by determinism" is a
proof. Proofs about floating point are the ones that turn out to have an
unconsidered case, and the cheapest way to find out is to run it.

Second, S3 is the change with the most to lose from drift that only appears
late. `freePoints` gates whether a point can be dragged at all and
`looseCarriers` drives the colouring users read to decide whether a sketch is
finished. A divergence that showed up only after fifty edits would be invisible
to every other test in this branch — and it is exactly the failure mode
plan §9 warns about: "a change that looks obviously correct, that all the tests
pass, and that quietly alters geometry on one part in fifty."

The test therefore reports **three** quantities at N = 100 — geometry,
analysis and residual — and pins geometry at N = 10, 50 and 100 as well, so
that a *growing* gap fails at the longest N first and a constant offset fails
at all three. All land exactly. Clause (a) is satisfied trivially in the
strongest possible form: the residual is not merely "no worse", it is the same
number, `3.070905054045597e-10`.

### One caveat I want on the record

The bit-identity argument is about **arithmetic**, not about iteration counts.
It holds because no comparison in either routine changes outcome: the pivot
test `|v| < 1e-7`, the LM's `e2 < err`, the null-space thresholds `1e-9` and
`1e-6` all see the same values they saw before. If a future change made the
sparse path skip an operation whose result was *near* zero rather than exactly
zero, none of that would hold and all three clauses would come back into
force. The distinction is exact zero versus small, and it is the whole
foundation of this session's correctness claim.

---

## 12. Re-measured on the integration base — the ratio moved, and this is the authoritative table

§5's host figures were taken on the **old** base
(`claude/perf-opt` @ `d87ac11`). After landing on `claude/perf-opt-solver`
(@ `2921d3f`, with S1, S2, S4 and S5 in it) the same rung measured about twice
as long. That was not CPU contention — I checked, and it reproduces on an idle
machine — so I re-ran **both sides** here: same base, same harness, same
warm-up ladder, nothing else running. This table supersedes §5's.

| n (entities) | dense | sparse | speedup |
| ---: | ---: | ---: | ---: |
| 64 | 41.3 ms | 35.3 ms | 1.17x |
| 128 | 111.1 ms | 60.4 ms | 1.84x |
| 256 | 266.2 ms | 76.4 ms | 3.49x |
| 512 | 1 618.8 ms | 239.6 ms | 6.76x |
| **1024** | **25 593.1 ms** | **1 891.6 ms** | **13.53x** |

Fitted over the top three rungs:

| | *k* | R² |
| --- | ---: | ---: |
| dense | **3.293** | 0.9856 |
| sparse | **2.315** | 0.9732 |

### What moved, and what did not

| | old base | this base |
| --- | ---: | ---: |
| dense @ 1024 | 20 701 ms | 25 593 ms (×1.24) |
| sparse @ 1024 | 1 001 ms | 1 892 ms (×1.89) |
| speedup | 20.69x | **13.53x** |
| dense *k* (top three) | 3.404 | 3.293 |
| sparse *k* (top three) | 1.966 | 2.315 |

**The exponents held; the ratio did not.** Both runs reproduce the device's
cubic on the dense side (3.404 and 3.293 against the measured 3.198
[2.835, 3.561]), and both put the sparse side firmly between quadratic and
cubic-excluded. The *ratio*, which is the quantity §5 led with, moved by a
third between two runs of identical code.

**The sparse side is the host-sensitive one** — it moved 1.89× between runs
while the dense side moved 1.24×. That is the expected direction and worth
stating as a finding rather than an annoyance: the dense form is
compute-bound, a long arithmetic loop over a resident array; the sparse form
is allocation- and pointer-chasing-bound, and those are what a shared container
starves first. On a device with a fixed clock and no neighbours the spread
should be narrower, but I cannot show that from here.

### Consequences for the registered predictions

**P1 holds on both runs, but less comfortably than §5 implied.** Predicted
k = 2.0 ± 0.35, i.e. [1.65, 2.35]. Measured 1.966 (old base) and **2.315**
(this base) — the second is inside, with 0.035 to spare. The claim that
survives without qualification is the weaker and more important one: **both
intervals exclude 3, and the cubic is gone.**

**P2 is better supported by this run than by the last.** Registered:
700 ms [400, 1600] for the device's top rung.

&nbsp;&nbsp;&nbsp;&nbsp;8 837 / 13.53 = **653 ms** (this base)
&nbsp;&nbsp;&nbsp;&nbsp;8 837 / 20.69 = 427 ms (old base)

The point estimate of 700 ms was derived before either measurement, and 653 ms
is within 7 % of it. §5 reported 427 ms and called the estimate "too optimistic
by ~2×"; on this evidence that self-criticism was itself wrong, and the
original derivation was closer to right than the first measurement suggested.
Both figures are inside the registered interval, which is the only thing a
device run will adjudicate.

**This is S3-4's own lesson landing on S3.** That entry warned the other
sessions that a wall-clock ratio predicted from an operation count is a bound,
not an estimate. The same caution applies to a wall-clock ratio *measured* on
a shared host: 20.69× and 13.53× are the same code. The exponent is the claim
to carry into §8; the ratio is an indication, and I have now quoted it two
ways.

### §10's table, corrected to this run

| quantity | change | noise floor | readable? |
| --- | ---: | ---: | --- |
| `stress.analyze` @ 1024 | −92.6 % | ~17 % | yes |
| @ 512 | −85.2 % | ~17 % | yes |
| @ 256 | −71.3 % | ~17 % | yes |
| @ 128 | −45.6 % | ~17 % | yes |
| @ 64 | −14.5 % | ~17 % | **no — still inside the noise** |

The conclusion §10 drew is unchanged, including the one that matters: **the
64-entity rung remains unreadable** and may land either side of its baseline.
