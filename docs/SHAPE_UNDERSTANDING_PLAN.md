# Giving the assistant eyes

**Shape understanding for the CAD assistant · revision 2**

**Repository:** [Toemeler/ipadprocad](https://github.com/Toemeler/ipadprocad)
**Branch:** `claude/gallant-dirac-dwuge7`
**Code baseline:** `dbab0d7` (M441 — the assistant can edit the model)
**Status:** proposal. Nothing in this document is built. Every claim about what
the app already provides was checked against the source and carries a file
reference; every claim about what it does not have is stated as such.

This plan makes the assistant able to perceive the *shape* of a part, not just
read its authoring record — and to do it within a token and latency budget that
survives being used on every turn.

It does not promise parity with a person orbiting the model. §3 says exactly
which kinds of understanding are reachable and which are not, and §14 states the
residue plainly. A plan that claimed parity would be easier to approve and
wrong.

## Reading guide

- [1. The defect, reproduced](#1-the-defect-reproduced)
- [2. The recommendation](#2-the-recommendation)
- [3. What "understanding" has to mean](#3-what-understanding-has-to-mean)
- [4. Four channels and one routing rule](#4-four-channels-and-one-routing-rule)
- [5. What the build already provides](#5-what-the-build-already-provides)
- [6. Stage 1 — the shape digest](#6-stage-1--the-shape-digest)
- [7. Stage 2 — recognition](#7-stage-2--recognition)
- [8. Stage 3 — free-form shapes](#8-stage-3--free-form-shapes)
- [9. Stage 4 — inspection on demand](#9-stage-4--inspection-on-demand)
- [10. Stage 5 — active looking](#10-stage-5--active-looking)
- [11. Stage 6 — editing an imported body](#11-stage-6--editing-an-imported-body)
- [12. Stage 7 — intent](#12-stage-7--intent)
- [13. Identity, budgets and the honesty contract](#13-identity-budgets-and-the-honesty-contract)
- [14. Evaluation, delivery, and what stays unsolved](#14-evaluation-delivery-and-what-stays-unsolved)

## 1. The defect, reproduced

A STEP file is imported. The user asks the assistant what it can see. It answers:

> The active document shows a part named "Cable+holder+1 2" with a single
> imported extrusion (version 1) at 5.0 mm diameter.

Every part of that sentence after the document name is false, and the mechanism
is exact rather than mysterious.

`AiWorkspace.readContext` sends `PartModel.toJson()` — the **authoring record**
([`part_model.dart`](../frontend/lib/part_model.dart), `PartModel.toJson`). For
an imported body, `AppState.importStepIntoPart` writes a placeholder feature:

```dart
p.appendFeature(ExtrudeFeature(
  name: p.nextFeatureName('Import'),
  bodyName: body,
  sketchName: '',        // there is no sketch
  profiles: const [],    // there is no profile
  output: 'new',
)..imported = true ..importPath = rel ..importIndex = i ..solid = solids[i]);
```

Every field not named there keeps its constructor default — including
`distanceA: 5`, `exprA: '5 mm'`. So the JSON handed to the model literally
contains `"a": 5.0, "exprA": "5 mm"` on a feature that was never extruded. The
model read the one number present and wrote a sentence around it. "Diameter" was
invented to make the number mean something.

Note what this is *not*: it is not a weak model, and it is not a prompt problem.
The context contained no geometry, one misleading number, and an instruction to
be useful. **Any** model produces something like that sentence. The `solid`
field — the actual B-Rep, hundreds of faces of it — is runtime state, never
serialised, and never reaches the assistant.

Three consequences follow, and they set the requirements:

1. **Absence of data reads as data.** The fix is not to strip the placeholder
   fields; it is to send what the shape actually is, so there is something true
   to say.
2. **This is the normal case, not an edge case.** Every imported part, every
   part whose feature tree is thin, and every free-form body has the same
   problem in proportion.
3. **A feature tree is not a shape.** Even a fully authored part's tree
   describes *how it was made*, not *what it is*. "Extrusion1 at 12 mm, Fillet1
   at R2" does not tell you it is a bracket.

## 2. The recommendation

Compute a **shape digest** from the built B-Rep and put it in context on every
turn; let the model **ask** for detail it does not have; let it **aim a camera**
when the question is visual; and let it **edit what it can name**.

Four channels, tiered cheapest-first, with a routing rule that decides between
them from a number the digest computes about itself. The digest is always
present and small. Everything above it is pull, not push.

The design principle throughout: **the app owns measurement, the model owns
interpretation.** Every number the model sees was measured from the solid, and
carries how it was obtained. The model is never asked to estimate a dimension
from a picture, and never permitted to claim one it was not given.

## 3. What "understanding" has to mean

"Does it understand the model?" is five different questions with five different
answers. Separating them is the only way to plan honestly.

| Kind of question | Example | Reachable? |
|---|---|---|
| **Metric** | How thick is the thinnest wall, and where? | **Yes — better than looking.** Measured from the B-Rep, exact, never foreshortened. |
| **Topological** | How many holes, are they through, are they a pattern? | **Yes — better than looking.** Counting is what machines do not get wrong. |
| **Formal** | Does it narrow toward one end? Where does the groove run? | **Yes, mostly.** Cross-sections and silhouettes (§8) carry form in text; views (§10) carry the rest. |
| **Functional** | Is that a snap-fit? Will it eject from a mould? | **Partly.** Explicit recognisers (§7) catch what they were taught; a vision model reads the rest off a render with its own priors. Both miss things an engineer sees instantly. |
| **Intentional** | Is this right for *your* desk, *your* cable, *your* taste? | **No — and not a perception problem.** §12. |

The first two are the ones the current build fails hardest and fixes most
completely. The third is where your cable holder lives. The fourth is where the
plan buys a competent second opinion and not a colleague. The fifth is not about
eyes at all, and is the cheapest of the five to improve.

## 4. Four channels and one routing rule

| # | Channel | Answers | Cost | Cadence |
|---|---|---|---|---|
| A | **Digest** (§6–7) | What *is* this? | 150–400 tok | Every turn, in context |
| B | **Form summary** (§8) | What *shape* is it? | ~150 tok | When the digest says analytic coverage is low |
| C | **Inspection** (§9) | What exactly is *here*? | 50–300 tok/call | Model asks |
| D | **Views** (§10) | What does it *look* like? | ~900–1600 tok/image | Model aims, vision providers only |

**The routing rule.** The digest reports `analyticCoverage` — the fraction of
total surface area lying on planes, cylinders, cones, spheres and tori. That one
number decides the channel:

- **≥ 0.80** — a machined or printed mechanical part. The digest alone answers
  most questions. Views are for aesthetics only.
- **0.40 – 0.80** — mixed. Digest plus sections.
- **< 0.40** — free-form. The digest *says so in its own text* ("free-form:
  request sections or a view") and the model is expected to act on that.

Your cable holder is the third case. This is the mechanism that stops the
assistant from confidently describing a blob it cannot see, without paying for
a render on every turn for parts that do not need one.

## 5. What the build already provides

Verified against the source. This is the reason stages 1–4 need no C++ and no
OCCT run — the slow loop in this project.

| Capability | Where | Note |
|---|---|---|
| **Per-face analytic records** | `OcctMeshData.faceInfos` | 15 doubles per face. `[0]` surface type, `[1..3]` a point on the surface, `[4..6]` axis/normal, `[10]` radius. Decoded today in `measure_pick.dart:452`, `asm_pick.dart:297`, `part_render.dart:862`. **Read `occt_capi.h` for the remaining fields before relying on them** — this plan uses only the four above. |
| **Surface-type codes** | `part_render.dart:325` | `kFacePlane 0`, `kFaceCylinder 1`, `kFaceCone 2`, `kFaceSphere 3`, `kFaceTorus 4`, `kFaceOther 5`. |
| **Triangle → face map** | `OcctMeshData.triFaces`, `faceIds`, `faceCount`, `topoFaceId` | Lets any mesh quantity be aggregated per topological face. |
| **Per-edge records** | `OcctShape.allEdges()` → `OcctEdgeInfo` | `kind`, arc-length midpoint, unit tangent, `length`, `radius`, `faceCount`, `dihedralDeg`, `convexity` (+1 convex / −1 concave), `filletable`. |
| **Face adjacency** | `OcctShape.facesOfEdge(i)` | The graph §7 walks. |
| **Globals** | `OcctShape.counts()`, `.valid`, `.volume`, `.bbox()` | `volume` is negative on failure — the shim contract, not masked. |
| **Ray casting** | `OcctShape.rayHits(o, d)` | Wall thickness, through-vs-blind, cavity probing. |
| **Mesh measures** | `faceArea`, `faceLoopLength`, `frontFaceUnder` (`measure_pick.dart`) | Mesh-derived, therefore approximate. Must be labelled as such. |
| **Analytic measurement** | `MeasureRef.plane/axis/circle/arc/ellipse/curve/point/segment` (`measure.dart`) | Already distinguishes analytic from sampled results. §9 reuses it rather than writing a second measurer. |
| **Planar face extraction** | `planarFaceRecs(mesh)` → `FaceRec(id, centroid, normal, area)` | Already used by `reanchorFaceSketches`. |
| **Offscreen rendering** | `AppState._renderStill` + `stillEngines` (RealityKit → GPU) | Drives an arbitrary scene + camera payload. Used today for gallery stills. |
| **Camera payload** | `cameraPayload` (`reality_payload.dart:30`) | `az, pol, halfH, ox, oy, roll, w, h` — **orthographic**. This is a gift: no perspective foreshortening to misread. |
| **Sections** | `SectionView`, `SectionMode`, `SectionPlane` (`section_view.dart:139`) | Half / quarter / three-quarter cuts exist for display. |
| **Stable references** | `ProfileSel`, `EdgeSel`, `FaceSel` (`part_model.dart`) | The "remember the geometry, re-find the index" contract §13 extends. |
| **Direct modelling** | `OcctShape.deleteFaces`, `.moveFaces`; `DeleteFaceFeature`, `DirectEditFeature` | §11 surfaces these; it does not invent them. |
| **Transaction + undo** | `AiCad.run`, `AppState.aiSnapshot/aiRestore/aiJournal` (M441) | Every new editing op inherits this unchanged. |

**Not present, and therefore not promised:** mass and centre of mass (there is no
density record — `materials.dart` is appearance; the workflow plan §3.2 says the
same), exact analytic face areas (`BRepGProp` is not in the shim), and OCCT
boolean history.

## 6. Stage 1 — the shape digest

A fixed-ceiling description of a body, computed from its `KernelSolid`, cached
against the feature's `builtSig`, recomputed only when geometry changes.

### 6.1 Shape

```
SHAPE Solid1 — imported, valid, 1 body
bbox 62.0 × 41.5 × 18.0 mm · vol 21,430 mm³ · area ~9,810 mm² · fill 46%
faces 87 — 34 plane, 41 cylinder, 8 torus, 4 other · analytic 91% of area
symmetry mirror about YZ (±0.01)
holes 4× Ø5.00 through, 40.0 × 25.0 rectangular pattern, axis +Y
      1× Ø12.00 blind depth 9.0, axis +Y
rounds 22 edges R2.00 convex · 6 edges R0.50 concave
walls min 2.8 mm between F14 and F51
notable F03 plane 62×41 normal −Y (largest, base candidate)
        F27 plane normal +Y · F51 cylinder Ø12.0
measured from the B-Rep; areas are mesh-derived (±1%). No mass, strength,
clearance or manufacturing check is implied.
```

≈ 230 tokens. That is roughly half what the current placeholder JSON costs, and
unlike it, all of it is true.

### 6.2 The rules that keep it bounded and honest

1. **Group, never enumerate.** 41 cylindrical faces become one `holes` line plus
   outliers. A 900-face part and a 40-face part produce digests of the same
   length. The ceiling is structural, not a truncation.
2. **Order by information, then truncate.** Within each group, sort by area or
   count descending; keep the top *k* and state the remainder (`+ 12 more
   cylinders Ø1.5–3.0`). Never drop silently — §13.
3. **Measured, with provenance.** B-Rep quantities (`volume`, `bbox`, radii,
   axes) are exact; mesh quantities (areas, section outlines) are marked
   approximate. The two are never mixed in one number.
4. **`fill %`** = volume ÷ bbox volume. One token that separates a solid block
   (>70%) from a bracket (30–50%) from a shell or a frame (<15%).
5. **`analytic %`** is the routing signal of §4 and the digest's own confidence
   statement.
6. **Deterministic.** Same geometry ⇒ byte-identical digest. This is what makes
   caching sound and makes an evaluation suite (§14.1) possible at all.

### 6.3 Computation and caching

One pass over `faceInfos` (O(faces)), one over the triangles for per-face area
(O(triangles), already written as `faceArea`), one `allEdges()` call, and a
bounded set of ray casts for §7. Everything else is grouping.

Cached on the feature beside `solid`, keyed by `builtSig` — the same key the
rebuild already uses to decide whether a feature needs recomputing. A digest is
therefore computed at most once per geometry change, and turns that change
nothing cost nothing.

## 7. Stage 2 — recognition

Face adjacency plus the edge records, in Dart, no kernel round-trip. This is
what turns "87 faces" into "a bracket with four mounting holes".

| Feature | Rule | Evidence |
|---|---|---|
| **Hole** | Cylindrical face whose angular extent closes, bounded by circular edges | `rayHits` along the axis decides through vs blind and gives the depth |
| **Hole pattern** | Cluster hole axes; test for linear / rectangular / circular arrangement | Report the pattern, not the instances |
| **Round / fillet** | Cylinder or torus tangent to both neighbours (`dihedralDeg ≈ 0` across both shared edges) | `convexity` splits round (convex) from fillet (concave) |
| **Chamfer** | Narrow planar face between two faces at a consistent angle | Width from `faceLoopLength` / area |
| **Boss / pocket** | Planar face offset from a parent plane along its own normal, closed by a side wall | Sign of the offset splits boss from pocket |
| **Wall thickness** | Ray from face centroid along −normal; distance to first hit | Report the minimum and *which two faces* |
| **Symmetry** | Mirror the face-record set about each principal plane; match within tolerance | Report the plane and the tolerance that held |
| **Base / mounting candidate** | Largest planar face with outward normal opposing gravity, or the largest planar face overall | Stated as a candidate, never as a fact |

Two rules govern the recogniser, and they matter more than the list:

- **It reports its own coverage.** `recognised 78% of face area; 19 faces
  unclassified (mostly F60–F74, spline)`. A recogniser that quietly ignores what
  it cannot name teaches the model that nothing is there.
- **It never upgrades a guess to a fact.** "base candidate", "appears to be a
  through hole" — the hedge is in the data, not left to the model's manners.

## 8. Stage 3 — free-form shapes

Where `analyticCoverage < 0.40`, §6 and §7 have little to say and the part is
exactly the kind the user actually imported. Three cheap, purely mesh-based
descriptors carry real form in text:

**Cross-sections.** Plane/triangle intersection over the tessellation, at *n*
stations along the longest bbox axis, each outline simplified
(Ramer–Douglas–Peucker) to ≤ 12 points:

```
sections along X, 5 stations, outlines ≤12 pts (mesh, ±0.1 mm)
 x= 0.0  1 loop, 38.2 × 17.0, area 402 mm², convex
 x=15.5  1 loop, 41.0 × 18.0, area 470 mm², concave notch at (y 8.0, z 14.2)
 x=31.0  2 loops, outer 41.0 × 18.0, inner Ø6.2 — closed channel
 ...
```

**Silhouette triple.** Projected outline area from ±X, ±Y, ±Z, and the ratio
between them. Distinguishes a slab from a rod from a blob in three numbers.

**Curvature histogram.** Per-triangle dihedral against neighbours, bucketed.
Separates "soft, continuously curved" from "faceted" from "sharp-featured".

Together ≈ 150 tokens, and they answer "it narrows toward one end and carries a
groove that opens upward" — which is most of what orbiting tells you about a
shape like this one.

## 9. Stage 4 — inspection on demand

New read-only ops in the M441 `cad` protocol
([`ai_actions.dart`](../frontend/lib/ai/ai_actions.dart)). Each is bounded in
rows and therefore in tokens; each returns stable IDs (§13).

```
describe_shape { body?, detail?: "digest" | "sections" | "faces" }
faces_where    { type?, axis?, diameter?, area_gt?, near?, limit?≤20 }
measure        { from, to }          // reuses MeasureRef; keeps provenance
section        { plane: "xy"|"xz"|"yz"|face-id, at }
```

`faces_where` is the workhorse: it turns "the four Ø5 holes" into four IDs the
model can then measure, fillet or sketch on. `measure` is deliberately the
existing machinery — a second measurer would drift from the one the user's own
measurement tool uses, and then two parts of the app would disagree about a
dimension.

## 10. Stage 5 — active looking

**This is the revision's main addition, and it is the closest thing to orbiting
that is actually available.**

Fixed canonical views are the wrong model of looking. What a person does is
*orbit to the question* — move until the ambiguity resolves, hundreds of times a
minute, at zero cost. The app can give a version of that, because
`_renderStill` already accepts an arbitrary camera:

```
look { az, pol, roll?, zoom_to?: face-id | "all", style?: "shaded"|"depth"|"wire",
       annotate?: bool, size?: 320|512 }
```

`cameraPayload` is orthographic (`reality_payload.dart:30`), which is a real
advantage over a perspective render: no foreshortening for the model to
misjudge, and a stated `halfH` makes the image *metrically readable* rather than
merely suggestive.

Four refinements, each worth more than extra pixels:

1. **Annotated pairs.** The same view twice — clean, and with face IDs overlaid.
   The model sees the form *and* can name what it is looking at, so "round the
   edge between F14 and F27" refers to something it actually saw. This is what
   binds the visual channel to the editing channel; without it they are two
   disconnected conversations.
2. **Depth and normal styles.** A depth buffer reads curvature unambiguously
   where a grey shaded render is mush — precisely the failure mode on a
   free-form part. Cheaper per unit of information than beauty shading.
3. **One sheet, not six images.** When several views are wanted, composite them
   into a single labelled sprite sheet: one image cost, six viewpoints.
4. **A scale bar and the camera's own numbers** burned into the frame, so an
   image never has to be interpreted without its scale.

**Policy.** Views are sent only when the provider supports images *and* the
model asked *or* the task is aesthetic *or* `analyticCoverage < 0.40`. Never
automatically on every turn. Apple's on-device path takes no images at all
([`ai_backend.dart`](../frontend/lib/ai/ai_backend.dart)) and DeepSeek's chat
models are text-only — both fall back to §6–8, and the digest's coverage line is
what tells them to lean on sections instead.

## 11. Stage 6 — editing an imported body

Perception is worth little if the part is read-only, and an imported body has no
feature tree to edit. The kernel already does direct modelling; these ops surface
it, addressed by the fingerprints of §13:

```
delete_face  { face }              // OcctShape.deleteFaces → DeleteFaceFeature
move_face    { face, distance }    // OcctShape.moveFaces  → DirectEditFeature
offset_face  { face, distance }
fillet       { edges: query, radius }     // extends the M441 op to face queries
sketch_on_face { face }                   // then the existing sketch + extrude ops
```

All of it lands in the existing timeline, transaction and undo machinery
(`AiCad.run`) with no change: a block is still one transaction, still rolls back
whole, still one `Ctrl+Z`. `sketch_on_face` is the important one — it is what
lets the assistant put a boss, a rib or a hole onto an imported STEP body, which
is the thing users actually want after an import.

## 12. Stage 7 — intent

Even with perfect perception the assistant does not know the cable is 6 mm, that
it clamps to *your* desk edge, or that you want it to read soft rather than
technical. That is not a perception gap and no amount of pixels closes it.

It is the **design brief** element of
[`AGENT_WORKFLOW_PLAN.md`](AGENT_WORKFLOW_PLAN.md) §5 — requirements with a
source, an interpretation, a priority and a verification status, persisted with
the document. It is far cheaper than any stage above, and after stages 1–3 it is
the largest remaining gain per unit of work. It is listed last here because it
is a separate build, not because it matters least.

## 13. Identity, budgets and the honesty contract

### 13.1 Stable identity — the cross-cutting requirement

OCCT re-indexes faces and edges on every rebuild. A face named `F14` in one turn
must still be that face in the next, or every editing op built on perception is
a coin flip.

So an ID is a **fingerprint, not an index** — the contract `ProfileSel`,
`EdgeSel` and `FaceSel` already keep. A face ID resolves through surface type,
point, axis, radius and area, scored with the same position-dominates weighting
`EdgeSel.score` uses, with an ambiguity margin below which resolution **fails
rather than guesses**. `FacePick` today takes a nearest finite match without that
protection (workflow plan §3.2); this work should fix that rather than build on
it.

The digest publishes a `shapeRevision`. An inspection result or an edit quoting a
stale revision is refused, not silently re-resolved.

### 13.2 Token budget, per turn

| Case | Digest | Form | Inspection | Views | Total |
|---|---|---|---|---|---|
| Mechanical part, conversation | 230 | — | — | — | **230** |
| Mechanical part, editing | 230 | — | 300 | — | **530** |
| Free-form, conversation | 200 | 150 | — | — | **350** |
| Free-form, design critique | 200 | 150 | — | 1,400 | **1,750** |
| Today, imported part | — | — | — | — | ~400, all of it useless |

### 13.3 Latency budget

| Work | Target | Why it holds |
|---|---|---|
| Digest + recognition | < 50 ms, 2,000 faces | O(faces + triangles) + bounded ray casts; once per `builtSig` |
| Sections, 5 stations | < 20 ms | One pass over the tessellation per plane |
| `faces_where` | < 5 ms | Filter over the cached digest |
| `look` | 150–600 ms | `_renderStill`, unchanged from the gallery path |

Nothing here runs on the UI thread beyond what a rebuild already does.

### 13.4 The honesty contract

The M441 instructions already forbid claiming to see a render without an image.
This extends it:

- The digest **carries its own coverage line**; the model may not make claims
  outside it.
- **Mesh-derived numbers are labelled approximate** and may not be quoted as
  exact.
- **Nothing is dropped silently** — every truncation states what was omitted.
- **No mass, no strength, no clearance, no manufacturability** claims: there is
  no density record and no analysis, and §5 says so.
- **A failed resolution is an error, not a nearest guess.**
- When `analyticCoverage` is low and no view was provided, the model **says the
  shape is not fully characterised** rather than describing it anyway. This is
  the direct fix for §1.

## 14. Evaluation, delivery, and what stays unsolved

### 14.1 How we will know it works

A plan without an acceptance test is a wish. Build a fixture set of ten parts —
the corpus already in `M440_MESH_TO_CAD_AUDIT_AND_PLAN.md` plus a bracket, a
shaft, a moulded shell and this cable holder — with a hand-written ground truth
per part: hole count and diameters, minimum wall, symmetry, bbox, and a one-line
human description.

Three gates, run in CI against the digest (deterministic, so no model needed):

1. **Metric** — every stated dimension within tolerance of ground truth. Target
   100%; a miss is a bug, not a score.
2. **Topological** — hole/round/pocket counts exact; coverage ≥ 90% of face area
   classified on the mechanical parts.
3. **Budget** — digest ≤ 400 tokens and ≤ 50 ms on every fixture.

A fourth gate needs a model and is therefore advisory, run by hand: give the
digest alone to each provider and score the free-text answer to "what is this
part and what is it for" against the human description. This is the number that
actually tracks §3's fourth row, and it should be published as a measurement,
never as a guarantee.

### 14.2 Delivery order

| # | Deliverable | Depends on | Effect |
|---|---|---|---|
| 1 | Digest core + cache + context wiring | — | Kills the §1 defect outright |
| 2 | Recognition | 1 | "87 faces" becomes "a bracket with four holes" |
| 3 | Sections, silhouettes, curvature | 1 | Fixes the free-form case — the user's actual part |
| 4 | Inspection ops + face fingerprints | 1, 2 | The model can ask; IDs become nameable |
| 5 | `look` + annotated pairs + depth style | 4 | Orbiting, on request |
| 6 | Direct-edit ops | 4 | Imported bodies become editable |
| 7 | Design brief | — | Intent; independent of all the above |

Items 1–3 carry most of the benefit, need no C++ and no OCCT run, and are
independently shippable. Item 1 alone is worth shipping on its own day.

### 14.3 What needs shim work

Only two things, both optional and both deferrable past item 6:

- **`BRepGProp`** for exact face areas, surface area and centre of mass —
  replaces the mesh approximations of §5. One C++ addition, one OCCT run.
- **A material/density record** for mass. This is a document-model change, not a
  shim change, and is a larger question than this plan.

Everything else in stages 1–6 uses APIs that exist today.

### 14.4 What stays unsolved

Stated plainly, because the value of the rest depends on it being believed:

- **Sampling is not continuity.** The model looks when it decides to, at ~1,400
  tokens and a round-trip. You orbit reflexively at zero cost. It will therefore
  look less, and will sometimes conclude on thinner evidence than you would
  accept. `look` narrows this; it does not close it.
- **Recognition is a finite list.** Snap-fits, living hinges, draft angles,
  moulding and machining constraints are not in §7 and will be missed until each
  is taught. A vision model may catch some from a render; that is a different
  and less reliable mechanism than a measured fact.
- **Spatial reasoning from text remains weaker than from vision.** The study the
  workflow plan cites puts it near 62.5% against 85–97.5% with canonical
  alignment. This plan routes around that limit for anything expressible as a
  number; it does not repeal it.
- **Aesthetic judgement stays yours.** The assistant will hold an opinion worth
  hearing about proportion and stance. It is not a substitute for looking.
- **Mass, strength, clearance, manufacturability** are out of scope and must
  keep being refused.

The claim this plan does make: **for metric and topological understanding the
assistant becomes more reliable than a person orbiting the model; for form it
becomes genuinely capable; for function it becomes a useful, fallible
collaborator; and for intent it stays dependent on being told.** That is a real
improvement over an assistant that reads a default constructor value and calls
it a diameter — and it is not parity, and should not be sold as parity.
