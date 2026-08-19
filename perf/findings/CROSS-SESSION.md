# CROSS-SESSION

**Append-only.** Add entries at the end. Never edit or delete an entry written
by another session — see `OPTIMIZATION_PLAN.md` §7.

Format: `## <date> — <session> — <one line>` then the detail.

---

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
