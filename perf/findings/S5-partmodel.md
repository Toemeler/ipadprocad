# S5 — the part model

Scope per `OPTIMIZATION_PLAN.md` §5, Session 5. Owns `frontend/lib/part_model.dart`.

Reading behind this file: profile §8.2 (part patterns), §8.1 (face provenance),
§6.8 (feature rebuild), §10.2 (headless/UI cost table), §6.5 (the shim
quadratic, which §8.2 composes with).

**Everything below the "Pre-registration" heading was written before any code
was changed.** The commit that adds this file contains no source edit.

---

## 0. What this session did, in one paragraph

The brief gave S5 three items. One of them — hoisting the per-occurrence edge
enumeration out of a patterned blend — **turned out to be unsound**, and the
plan named that exact possibility as "the single most likely way to break a
real part in this whole plan". Establishing it was unsound, with the mechanism
and a test that fails if anyone hoists it later, is the main result here and it
is a negative one. The second item — the quadratic in `newSurfacesOf` — is real,
was fixed, and its cost model closed to ±5 % before the fix, which is what makes
the prediction below worth anything. The third — `app.rebuildPart` — was left
alone deliberately, because the plan says not to optimise against an exponent
whose interval spans linear to quadratic, and nothing in this session made it
measurable.

---

## 1. Pre-registration

### Prediction P1 — a direction index for `newSurfacesOf`

```
Target        : provenance.newSurfaces, in scenario app.provenance.newSurfaces.360
Baseline      : 0.3986 ms per call
                (perf/baseline.json scenarioSpans
                 "app.provenance.newSurfaces.360::provenance.newSurfaces",
                 meanMs 0.3986, n = 10; profile §10.2 quotes the 10-rep totals
                 24:0.02 / 120:0.49 / 360:3.99, k = 1.96 [profile §8.1])
Mechanism     : see below — R x B calls to FaceSurface.sameSurfaceAs
Change        : bucket the base list; probe only the buckets that can match
Predicted     : 0.027 ms +- 0.008   (14.6x, interval 10x .. 22x)
Derivation    : below
Falsifiable by: the measured span at the 360 rung; and by the exponent, which
                must NOT drop — see "what would refute this"
Risk          : below
```

**Mechanism, and the cost model closed against three rungs.**

`newSurfacesOf(result, base)` is

```dart
for (final f in result)
  if (!base.any((b) => b.sameSurfaceAs(f, kFaceMatchTol))) f
```

so it performs one `sameSurfaceAs` per (result, base) pair, short-circuiting on
the first match. The fixture is `_buildPart(2, pts)`
(`perf_scenarios_app.dart`): two *independent* extruded regular polygons, radius
30 and radius 38, height 10, `pts` sides. `mine` is the r=30 body, `base` the
r=38 body. Every face is planar (`ringProfile` emits zero bulge, so the profile
is an n-gon of straight segments): `pts` side walls plus 2 caps.

The gauges say exactly how many pairs are evaluated:
`provenance.newSurfaces.in.360 = 362`, `out.360 = 360`. So **2 of 362 result
faces match** — the two caps, which lie in the planes z=0 and z=10 for both
rings, and `sameSurfaceAs` for a plane tests the *infinite* plane. The other 360
find nothing and therefore scan the whole base list:

| rung | R | B | matches | evaluations E₀ | measured T₀ | **T₀/E₀** |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 24 | 26 | 26 | 2 | 637 | 2.0 µs | **3.14 ns** |
| 120 | 122 | 122 | 2 | 14 701 | 49.0 µs | **3.33 ns** |
| 360 | 362 | 362 | 2 | 130 501 | 398.6 µs | **3.05 ns** |

E₀ = (R−2)·B + 2·(B+1)/2, the second term being the expected position of the
first match for the two matching faces.

**The per-evaluation cost is constant to ±5 % across a 205× range in E₀.** That
is what makes this a cost model rather than a curve fit, and it is the number
the prediction is built on: **c = 3.15 ns per `sameSurfaceAs`**.

*Independent check on the reading of §10.2:* the session-wide entry in
`baseline.json` is `provenance.newSurfaces` meanMs 0.149967 over n = 30, i.e.
4.499 ms total. The three §10.2 figures sum to 0.02 + 0.49 + 3.99 = 4.50 ms.
They are 10-rep totals, and the per-call figures above are right.

**The change.** `sameSurfaceAs` can only return true if the two faces have the
same `type`, and for planes (type 0) and cylinders (type 1) only if their axes
are parallel to within `|d·o.d| ≥ 1 − 1e-6`. Both are *necessary* conditions, so
an index built on them and followed by the original predicate returns the
identical boolean. The index is a counting sort of the base list into cells of a
scalar direction key

```
dk(d) = |d.x| + 2|d.y| + 4|d.z|
```

with a ±1 cell probe. Absolute values are used because the match ignores normal
orientation, and taking |·| componentwise is continuous — a sign-canonicalised
key is not, and would put two nearly-parallel normals in distant cells.

**Why a ±1 probe is exact.** For unit u, v with |u·v| ≥ 1 − 1e-6, put
s = sign(u·v). Then

    |u − s·v|² = |u|² + |v|² − 2|u·v| ≤ 2 − 2(1 − 1e-6) = 2e-6
    |u − s·v|  ≤ 1.4143e-3

and componentwise ‖|uᵢ| − |vᵢ|‖ ≤ |uᵢ − s·vᵢ| ≤ 1.4143e-3, so by Cauchy–Schwarz

    |dk(u) − dk(v)| ≤ √(1² + 2² + 4²) · 1.4143e-3 = 4.5826 · 1.4143e-3
                    = **6.4808e-3**

A cell width C ≥ 6.4808e-3 therefore puts any matching pair in the same cell or
in adjacent ones. **C = 7e-3 is used — an 8 % margin**, and the key's range is
[0, √21] = [0, 4.5826], giving 655 cells, a fixed 2.6 kB `Int32List`.

Faces whose `d` is not a unit vector (`Vec3.normalized()` returns the input
unchanged when its length is below 1e-12) break that derivation, so they are
held outside the index and scanned by every query; a *query* face with a
non-unit `d` falls back to scanning the whole base list. Types ≥ 2 (cone,
sphere, torus, spline) match by bounding-box containment, which has no direction
condition at all, so those base faces are also scanned by every query.

**Predicted evaluation counts**, computed by simulating the index over the exact
fixture normals (side face *i* of the n-gon has outward normal
(cos φᵢ, sin φᵢ, 0), φᵢ = 2π(i+½)/n; caps (0,0,±1)):

| rung | E₀ | E₁ | ratio |
| ---: | ---: | ---: | ---: |
| 24 | 637 | *not indexed* (B < 64) | 1.00 |
| 120 | 14 701 | 900 | 16.3× |
| 360 | 130 501 | 5 924 | 22.0× |
| 720 | 520 201 | 23 204 | 22.4× |
| 1440 | 2 077 201 | 93 636 | 22.2× |

**Predicted time at the 360 rung:**

| term | arithmetic | µs |
| --- | --- | ---: |
| predicate | 5 924 × 3.15 ns | 18.7 |
| index build | 655-cell zero-fill + 2 passes over 362 ≈ 1 379 int ops @ ~1 ns | 1.4 |
| per-query probe | 362 × (key + 3 range set-ups) ≈ 362 × 20 ns | 7.2 |
| **total** | | **27.3** |

**Predicted: 0.027 ms ± 0.008**, i.e. **14.6× faster [10×, 22×]**. The interval
is dominated by the two overhead constants, which are estimates, not
measurements — the predicate term is the one with a measured constant behind it.

**Control, and it is part of the prediction.** The 24 rung has B = 26, below the
`B ≥ 64` threshold at which the index is built. **`app.provenance.newSurfaces.24`
must not move** — same code path, same arithmetic. Its noise floor (§3.2) is the
only thing that should show.

**What would refute this.**

1. The 360 rung not landing in [0.019, 0.035] ms.
2. The 24 rung moving by more than its repeatability band — that would mean the
   threshold is not doing what this says it does.
3. **The exponent dropping.** This is a constant-factor fix, *not* an exponent
   fix, and saying so in advance is the point. E₁ still grows as ≈ n² (5 924 →
   23 204 → 93 636 for n = 360 → 720 → 1440, k = 2.00). Any scalar key on the
   unit sphere has stationary points, and near one the cell occupancy grows as
   √n, which is exactly where the residual quadratic lives. A fit that comes
   back near 1.0 means the mechanism is not what is claimed here, even though
   the number got better.

**Risk.** (a) The 3.15 ns constant was fitted on a scan that walks the base list
in memory order; the indexed scan hops, so locality is worse and c may rise —
the predicted interval covers c up to 4.6 ns. (b) The index allocates two typed
lists per call; at B just above the threshold that could cost more than it
saves, which is what the threshold is for and why the 24-rung control is
registered. (c) A body whose faces are mostly type ≥ 2 gets no win at all,
because those faces all sit in the always-scanned tail. That is a correctness-
preserving degradation to today's cost, not a regression.

---

### Prediction P2 — `faceSurfaces` without the per-triangle allocations

```
Target        : provenance.faceSurfaces, scenario app.provenance.faceSurfaces.360
Baseline      : 0.0704 ms per call (perf/baseline.json scenarioSpans, n = 10),
                1436 triangles, 362 faces (gauges provenance.tris.360,
                provenance.faces.360); k = 1.05 linear (§10.2)
Mechanism     : ~16 heap objects allocated per triangle, ~23 000 per call
Change        : accumulate into Float64List instead of Vec3, same IEEE order
Predicted     : 0.050 ms +- 0.015   (a 15-50 % reduction)
Derivation    : below
Falsifiable by: the measured span; and by the fit, which must stay linear
Risk          : the allocator constant is not measured on this device
```

**Mechanism.** The triangle loop allocates, per triangle: three `Vec3` for the
corners, two for the edge vectors, one for the cross product, one `List<Vec3>`
for `[a, b, c]`, one for `(a+b+c)`, one for the scaled centroid contribution,
one for the running centroid sum, and up to six for the `lo`/`hi` updates —
**about 16 heap objects, 1436 triangles, ≈ 23 000 allocations per call at the
360 rung**. The arithmetic itself is about 60 flops per triangle, ≈ 86 000
flops per call, which at 1 flop/ns would be 86 µs against a measured 70.4 µs —
so the call is *already* running at better than 1 flop/ns and the allocation
traffic is not free but is not the whole story either.

This is the weakest-derived prediction in this file and it is stated as such:
Dart's young-generation bump allocation plus amortised scavenge is roughly
1–3 ns per object, which puts the removable term at 23–69 µs against a 70.4 µs
total. The lower end of that range is credible, the upper end exceeds the whole
measurement and therefore cannot be right. **Predicted 0.050 ms ± 0.015** — a
15–50 % reduction, with the interval deliberately wide because the constant is
borrowed, not measured.

**What would refute this:** no movement at all (the allocations were already
being scalar-replaced by the AOT compiler), or the fit ceasing to be linear.

---

### P3 — the per-occurrence edge enumeration: *no prediction, because the change is unsound*

The brief's headline item for S5 was to hoist `kernel.edgesOf(body)` out of
`applyBlendOccurrence` so that a patterned blend enumerates once instead of once
per occurrence — 97.6 % of a patterned blend's cost (§8.2). **It cannot be
done, and §7 of the plan says that saying so is a finding.** The evidence is in
§3 below. No time prediction is registered because no such change is being
made.

---

## 2. Results

*(written after the changes; the device run adjudicates the numbers)*

### 2.1 What was changed

| Change | File | Predicted | Pinned by |
| --- | --- | --- | --- |
| direction index in `newSurfacesOf` | `part_model.dart` | P1 | `m232_provenance_index_test.dart` |
| allocation-free `faceSurfaces` loop | `part_model.dart` | P2 | `m232_provenance_index_test.dart` |
| *(nothing — see §3)* | `applyBlendOccurrence` | — | `m232_blend_occurrence_test.dart` |

### 2.2 Host-side verification

Host-side is all that S5 can produce (§2 of the plan). What was run:

- `flutter analyze` — no issue introduced (see §5 for the environment caveat).
- `flutter test` — full suite green, including the new tests.
- `python3 -m unittest discover -s ci -p 'test_*.py'` — 45 tests green.
- An **exhaustive equivalence test** for the index: the indexed
  `newSurfacesOf` is compared element-by-element against a reference
  implementation of the original `base.any(...)` loop, over randomised face
  sets that include all four `sameSurfaceAs` branches, degenerate normals,
  faces sitting exactly on the cell boundaries of the direction key, and pairs
  separated by exactly the parallelism threshold. This is the test that would
  fail if the filter were not a superset.

No timing claim is made from the host. Per §2 of the plan, host timings on a
desktop-class machine are not iPad milliseconds and are not quoted here.

---

## 3. The finding: a patterned blend cannot share one edge enumeration

**Claim: the body changes between occurrences, so the hoist named in
`OPTIMIZATION_PLAN.md` §5 (Session 5) is unsound and must not be made.**

### 3.1 The evidence

`_recomputePattern` folds occurrences onto a running `result`. For a blend tool
the fold is not a boolean — it *replaces* the body:

```dart
final out = applyBlendOccurrence(kernel, result, blend, occ, plane);
...
if (resultOwned) result.dispose();
result = out;                       // <- the body for the NEXT occurrence
resultOwned = true;
```

So occurrence *k+1* is applied to the solid that occurrence *k* produced, not to
the solid the loop started with. A fillet rebuilds the shape; OCCT re-enumerates
its topology; the edge indices are not preserved.

That matters because the indices are *positional*. `applyBlendOccurrence` does

```dart
final live = kernel.edgesOf(body);
...
final (ids, src, _) = moved.resolveEdges(live);
...
return kernel.filletEdges(body, ids, radii, radii2: radii2);
```

and `resolveEdges` returns `m.index` — the index the shim reported **for that
enumeration of that shape**. Those ids go straight back into
`filletEdges(body, ids, …)`. The correspondence `live ↔ body` is what makes
them mean anything.

Hoisting `live` out of the loop breaks that correspondence for every occurrence
after the first: the fingerprints would be matched against a snapshot of a shape
that no longer exists, and the resulting indices would be handed to a *different*
shape. The failure is silent — `filletEdges` would happily blend whichever edges
those indices now name. That is the "silently misplace blends" outcome the plan
warned about, and it is not a hypothetical: it follows from three lines of code.

### 3.2 What was actually checked, and how

`m232_blend_occurrence_test.dart` pins the behaviour rather than the reasoning:

1. **The body is re-enumerated per occurrence.** With a recording kernel, an
   8-occurrence patterned fillet issues **8** `edgesOf` calls, each on a
   *different* `KernelSolid` instance — asserted by identity, not by count
   alone, so a future hoist fails the test rather than quietly passing it.
2. **The enumerated body is the one that gets filleted.** The kernel records
   which solid each `edgesOf` and each `filletEdges` saw; the test asserts they
   are the same instance within an occurrence and different across occurrences.
3. **Stale indices would change the outcome.** The recording kernel returns a
   different edge list per solid, and the test asserts the filleted ids follow
   the live list — which is exactly what a hoisted snapshot would break.

### 3.3 What could still be done, and by whom

The cost does not go away; it moves.

- **The fix belongs where §6.5 puts it.** One `allEdges` costs Θ(n²) because
  each `occt_shape_edge_info` does whole-shape work (profile §6.5). Session 2's
  bulk entry point makes each of the N enumerations cheap; N stays N. At the
  measured 180-edge body that turns 8 × 142.9 ms into 8 × (whatever the bulk
  path costs), which is the whole of the 97.6 %.
- **Collapsing N fillets into one is the only way to remove the factor of N**,
  and it is a behaviour change, not an optimisation. Resolving every
  occurrence's fingerprints against one enumeration of the *base* body and
  issuing a single `filletEdges` with all the ids would cost one enumeration and
  — per §10.2, where `kernel.fillet.edges` is flat at k = 0.00, 25.5 ms for 1 or
  12 edges — one blend. It is registered in `CROSS-SESSION.md` as a proposal and
  **not implemented**, because:
  - a multi-edge fillet is not the same OCCT operation as a sequence of
    single-edge fillets where blends interact;
  - the face ids and edge indices of the result would differ from the sequential
    ones, and those feed provenance and fingerprint reattachment across
    rebuilds;
  - per-occurrence failure attribution ("occurrence 3: … could not be applied")
    would be lost;
  - and none of that can be settled on a host with no OCCT. It needs either
    Lane C (S1) or a device run.

That last point is the honest summary: **this is unprovable from where S5
sits**, which the plan's §7 anticipates.

---

## 4. What was deliberately not done

- **`app.rebuildPart`.** k = 1.68, CI [1.04, 2.39] — the profile marks it
  indeterminate and the plan says not to optimise against an interval spanning
  linear to quadratic. Making it measurable means more rungs in the scenario
  suite, and the suite is `perf*.dart`, which **nobody** may edit (plan §3).
  Registered in `CROSS-SESSION.md`.
- **`featureOfFace`'s duplicate `faceSurfaces` call** (profile §8.1, structural
  note). It is in `app_state.dart`, which S5 does not own — S3 and S4 own named
  functions in it and this is neither. Registered in `CROSS-SESSION.md`; it is
  behind a cache and costs one extra linear pass per mesh identity.
- **A sub-quadratic `newSurfacesOf`.** P1 is a ~22× constant factor and leaves
  the exponent at 2. Getting to linear needs a key that resolves the unit sphere
  at the matching tolerance, i.e. a hash grid at ~1.4e-3 cells — 9 hash probes
  per face, which at these face counts costs more than it saves. A 2-D grid at
  √B resolution was modelled and is *worse* below 1440 faces (9.6× at 360
  against 22.0×) and better above it. If a device run ever shows bodies past
  ~1500 faces mattering, that is the crossover to revisit.
- **Any change to `edgesOf` itself.** It is one line — `shape.allEdges()` — and
  the cost is behind the FFI boundary in S2's file.

---

## 5. Uncertainties, and one caveat about the environment

- **Every number in §1 is a prediction.** S5 cannot measure an iPad (plan §2).
  The cost model behind P1 is closed to ±5 % against three measured rungs, which
  is the strongest footing available without a device; P2's is not, and says so.
- **`flutter analyze` was run against a newer stable SDK than CI pins.** That
  SDK reports 55 pre-existing `info` diagnostics in this repository (20
  `deprecated_member_use` from the newer framework, 19 `unnecessary_import`, 8
  `unused_import`, …) which CI's pinned SDK does not. The comparison made here
  is therefore **before-versus-after on the same SDK**: the set of diagnostics is
  unchanged by this session's edits. It is not the same statement as "zero
  issues", and it should be re-checked on CI's SDK at integration.
- **The equivalence test is exhaustive over generated inputs, not over all
  possible meshes.** The superset argument in §1 is what covers the rest, and it
  is written out so it can be checked rather than believed.
