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

## 2026-08-19 — S5 — `featureOfFace` calls `faceSurfaces` twice, and the second one is only a log line

**What I need:** a one-line change in `app_state.dart`, near `featureOfFace`
(grep for `faces attributed`).

**Why:** profile §8.1's structural note. `featureOfFace` calls
`attributeFaces(...)`, which computes `faceSurfaces(solid.mesh)` internally, and
then calls `faceSurfaces(solid.mesh)` a second time purely to obtain
`.length` for a log message. It is behind the per-mesh-identity cache, so it
runs once per mesh rather than per frame — but it is a whole extra linear pass
over every triangle (0.0704 ms at 1436 triangles, §10.2) for a number nobody
reads unless logging is on.

**What I would change:** have `attributeFaces` report the face count it already
computed (or drop the count from the log line). Either is behaviour-preserving;
the log text would have to stay identical if anything asserts on it.

**Why I am not doing it:** `app_state.dart` is shared and split by function
(plan §3). S3 owns the `analyzeSketch` call sites, S4 owns `displayGeometry`.
`featureOfFace` is neither, so nobody owns it and S5 must not touch it.

---

## 2026-08-19 — S5 — to S2: the patterned-blend path needs *N* enumerations, not one

**Context:** profile §8.2. `applyBlendOccurrence` performs one
`kernel.edgesOf(body)` per pattern occurrence, and that is 97.6 % of a patterned
blend's measured cost (1 142.49 ms of 1 170.65 ms at 8 occurrences).

**The plan's §5 brief for S5 says to hoist that enumeration out of the loop.
It cannot be hoisted.** The body is *replaced* by each occurrence's blend
result, and the edge ids `resolveEdges` returns are positional indices into the
enumeration of the body they were resolved against; they are handed straight to
`filletEdges` on that same body. A shared snapshot would blend whichever edges
those indices happen to name in a later, differently-enumerated shape —
silently. Detail and the pinning test are in `perf/findings/S5-partmodel.md` §3.

**What this means for S2:** the factor of *N* here is not removable in Dart, so
the whole 97.6 % rides on the per-enumeration cost. S2's bulk entry point is the
fix for this path too, and it is worth `applyBlendOccurrence` adopting it as
soon as it lands. S5 has deliberately not depended on it (plan §5: "do not wait
for S2"), and `applyBlendOccurrence` is unchanged, so adopting the bulk API
there is a small follow-up against a stable call site.

---

## 2026-08-19 — S5 — a proposal that needs a device or Lane C to adjudicate

**Proposal:** collapse a patterned blend's *N* sequential single-occurrence
fillets into **one** `filletEdges` call — resolve every occurrence's placed
fingerprints against one enumeration of the base body, then issue one blend with
all the ids. Cost would fall from N × (enumeration + blend) to one of each; per
§10.2 `kernel.fillet.edges` is flat at k = 0.00 (25.5 ms for 1 edge or 12), so
the blend term collapses too. At the measured 8-occurrence fixture that is
1 170.65 ms → ≈ 168 ms.

**Why S5 did not do it:** it is a behaviour change, not an optimisation, and the
branch rule is bit-identical behaviour proven by test. A multi-edge OCCT fillet
is not a sequence of single-edge fillets where blends interact; the result's
face ids and edge indices would differ from the sequential ones, and those feed
provenance and cross-rebuild fingerprint reattachment; and per-occurrence
failure attribution would be lost. None of it can be settled on a host with no
OCCT.

**Who could settle it:** S1's Lane C could measure the cost side directly
against the shim. The identity side needs a comparison of the two shapes'
topology — a natural thing to add to a kernel bench that already links the shim.
Recorded here rather than acted on.
