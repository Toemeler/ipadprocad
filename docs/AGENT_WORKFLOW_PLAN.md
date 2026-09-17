# The Agent Layer — how an LLM models in this app

**Scope of this document.** The *workflow* only: what an AI can do, how it says it,
how it sees what it made, how it knows it is good, and how it works like a product
developer rather than a lucky guesser. No implementation, no file layout, no code.
That comes next, and only if this is right.

**Status.** Design proposal, round 5. Grounded in a full read of the codebase and in
the 2025–2026 literature on LLM-driven CAD (sources in Appendix D).

---

## Contents

**The case** — [0. Thesis](#0-the-one-paragraph-thesis) ·
[1. What the app already is](#1-what-this-app-already-is-and-why-it-is-unusually-well-suited) ·
[2. What LLMs are good and bad at](#2-what-llms-are-actually-good-and-bad-at) ·
[3. The eight laws](#3-the-eight-laws)

**The workflow** — [4. The loop](#4-the-loop) ·
[5. How the AI points at things](#5-how-the-ai-points-at-things) ·
[6. What the AI says — the verb set](#6-what-the-ai-says--the-verb-set) ·
[7. Sketching](#7-sketching--the-place-where-token-budgets-and-accuracy-go-to-die) ·
[8. How the AI sees](#8-how-the-ai-sees--the-perception-ladder) ·
[9. How the AI knows it is good](#9-how-the-ai-knows-it-is-good--the-proof-layer) ·
[10. The playbook](#10-the-playbook--modelling-like-a-product-developer) ·
[11. Errors and repair](#11-errors-repair-and-never-getting-stuck)

**The consequences** — [12. Structural decisions](#12-structural-decisions-workflow-level-not-implementation) ·
[13. Flash to Opus](#13-making-it-work-from-gemini-flash-to-opus-5) ·
[14. Risks and decisions I need from you](#14-risks-and-the-decisions-i-need-from-you) ·
[15. What is genuinely new](#15-what-is-genuinely-new-here) ·
[16. How we know it worked](#16-how-we-will-know-it-worked) ·
[17. Build phases](#17-the-shape-of-the-build-in-phases)

**Appendices** — [A. Rejected alternatives](#appendix-a--alternatives-considered-and-rejected) ·
[B. The critical passes](#appendix-b--the-critical-passes-this-document-survived) ·
[C. A worked session](#appendix-c--a-worked-session-end-to-end) ·
[D. Sources](#appendix-d--sources)

**If you read three sections:** §3 (the laws), §8 (how it sees), §9 (how it proves it).
**If you read one:** Appendix C.

---

## 0. The one-paragraph thesis

Every serious attempt to put an LLM in a CAD program has made the same bet: *give the
model a picture and a scripting API, and let it figure out the geometry.* The 2026
evidence says that bet loses. On mental-rotation tasks where humans score ~100 %, most
models score **under 10 %** and the best reach **50–62 %**; handing them a real 3D
render-and-rotate tool lifts them to **62.5 %** and no further; and **58 % of CAD code
that executes cleanly still violates the requirements the model was given**. The models
are not bad at CAD. They are bad at *being a pair of eyes in a 3D scene* — and that is
the job we keep giving them.

So this plan inverts it. **The app does the spatial reasoning. The model does the design
reasoning.** The app resolves "which edge", computes "did anything else move", measures
"is the wall thick enough", and hands back sentences and numbers. The model decides what
the part should be, declares what "correct" means for it in machine-checkable terms, and
drives a short, verified loop to get there. Pictures exist — annotated with the same
names the text uses — but they are the *gestalt check*, never the evidence.

That single inversion is what will make this fast, accurate, cheap, and usable by a
Gemini Flash as well as an Opus.

---

## 1. What this app already is (and why it is unusually well-suited)

This matters, because the plan below is not a bolt-on: it is mostly **exposing what is
already here.**

### 1.1 The modelling core

| Layer | Reality today |
|---|---|
| Kernel | OCCT via a C shim (`backend/occt/shim/occt_capi.h`), ~60 entry points: box, cylinder, extrude (polygon / profile-with-holes / arcs), revolve, sweep, loft, coil, boolean fuse/cut/common, fillet & chamfer (constant + variable, by topological edge id), delete/move faces, scale, mirror, transform, split solids, STEP import/export (with assembly tree), mesh→B-Rep, tessellation with **per-face ids, per-edge ids, face surface records and edge curve records** |
| Feature model | `PartModel` + 14 `PartFeature` subclasses (extrude, revolve, sweep, loft, coil, fillet, chamfer, hole, pattern, combine, split, derive, delete-face, direct-edit), each with `toJson`/`fromJson`, a rebuild signature, an End-of-Part marker, per-feature `computeError` |
| Sketcher | Full 2D: lines, arcs, circles, ellipses, splines (CV / fit / Bézier chains), slots, polygons, rectangles (4 construction methods), gears, text, points; **12 constraint tools + dimensions** (15 constraint types internally); a real solver (`solver.dart`, 3.4 k lines) |
| Parameters | `params.dart` — a complete expression language: named parameters, units (mm/cm/m/deg/rad/ul), `+ - * / ^ %`, precedence, parentheses, `PI`/`E`, 18 functions, and **cross-references between dimensions** |
| Profiles | Half-edge region detection (`ProfileRegion`) — outer loop + the loops directly inside it, exactly Inventor's pickable profile, plus a gap detector (`ProfileGap`) |
| Assemblies | Occurrences, joints, constraints (`asm_*.dart`), patterns, view reps, drive |
| Measure | `measure.dart` (2.8 k lines): length, distance, angle, area, volume, radius/diameter, extents, dual units, totals |
| Views | 6 canonical planes + trackball, section views (half/quarter/three-quarter), display modes, materials, **an off-screen still renderer** (`_renderStill` → PNG, GPU with a deterministic CPU fallback) |
| History | Per-sketch undo journal, per-part `PartSnap` undo/redo, End-of-Part rollback |
| Documents | Single-file `.ptp` / `.pts` / `.pas` containers; STEP/STL/OBJ/3MF/DXF I/O |
| Tests | 327 Dart test files that already drive `AppState` **headlessly with fake kernels** |

### 1.2 The three assets that make this different from every other host

**(a) The app already solved persistent naming — geometrically.**
`EdgeSel` and `FacePick` do not store "edge 7". They store a *fingerprint* — world
midpoint, length, curve kind, radius — and re-match it after every rebuild with a scored
search, a scale-aware tolerance, and an **explicit ambiguity refusal**: if the runner-up
is within margin, the selection is reported LOST rather than silently moved
(`part_model.dart`, M158/M373). That is precisely the discipline an LLM needs, and it is
already written, already battle-tested against real bug reports, and already the app's
idiom. We are not inventing a reference system; we are giving it a query front end.

**(b) The tessellation already carries semantics.**
`occt_mesh_face_infos` returns a 15-double record per face (type, axis, origin, normal,
radius…), `occt_mesh_face_ids` / `occt_mesh_edge_ids` map display entities back to
topology, `occt_shape_edges_info` returns 12 doubles per edge. The app can therefore
describe a body *in words and numbers* — "12 planar faces, 4 cylindrical (Ø8.0, axis
+Z), 24 straight edges, 8 circular" — without rendering anything.

**(c) Off-screen rendering already exists and is deterministic.**
`_renderStill(scene, camera, w, h)` with a GPU path and a pure-Dart `paintPartSolids`
fallback, plus `fitThumbCamera`. Annotated multi-view generation is a composition
problem, not a new subsystem.

### 1.3 The honest gaps

These are *findings*, not complaints. They shape the plan.

1. **There is no agent surface of any kind.** No API, no script host, no command layer.
   Every modelling operation is reached through a *dialog session* object
   (`ExtrudeSession`, `HoleSession`, `PatternSession`, …) that a finger fills in.
   `applyExtrude()` reads `extrudeSession` and nothing else. **This is the single
   biggest structural decision in the plan** (§12.1).
2. **The world is XYZ right-handed, but the camera is Y-up.**
   `planeFrame('xy')` has normal +Z; `PartCamera` derives polar angle from `n.y`
   (`acos(n.y)`), so *screen up is +Y* and the "top" view looks down −Y. Every LLM's
   prior says *Z is up and the top face's normal is +Z* (STEP, Fusion, SolidWorks,
   CadQuery, build123d). Left unaddressed this will silently produce parts lying on
   their side. It must be pinned, mapped, and conformance-tested (§5.4).
3. **No shell, no draft, no thread, no rib.** Shell in particular is required by almost
   every plastic or cast part. The agent cannot model what the app cannot build (§14.2).
4. **No interference / clash check.** Trivial to derive (`occt_common` → volume > 0) but
   it does not exist, and assemblies need it (§9.3).
5. **No mass properties beyond volume.** No density, no centre of mass, no inertia.
   "≤ 250 g" is the most natural requirement an engineer states and we cannot check it.

---

## 2. What LLMs are actually good and bad at

Everything below is an evidence-backed constraint, not an opinion. Sources in Appendix D.

### 2.1 Strong — build the workflow on these

| Capability | Evidence / note |
|---|---|
| Emitting **valid JSON against a schema** | Constrained decoding is universal; format choice moves accuracy only −7.7 %…+2.7 % |
| Writing **declarative, code-shaped** descriptions | CadQuery beat a low-level command DSL by **2.2×** on Chamfer Distance at L2 |
| **Naming** and maintaining a symbol table | Native strength; parameters, feature names, face names |
| **Explicit arithmetic** written out | Reliable when the numbers are in the transcript |
| **Following a checklist** with gates | The whole agentic-coding success story |
| Recalling **engineering idiom** | M4 clearance 4.5 mm, 3 mm min wall for FDM, 45° chamfer |
| Reading **tabular structured text** | Strong; far better than interpreting an image |
| **Repairing an error** given cause + fix | The dominant lever in every compile-test-repair paper |
| **Single-feature edits** | **99.6 % success** (CADEngBench L2-E) |

### 2.2 Weak — the workflow must route around these

| Weakness | Evidence | Consequence for us |
|---|---|---|
| **Mental rotation** | < 20 % vs ~100 % human; GPT-5.2 tier 50–62 % | Never ask "which face is this in the iso view" |
| **Perceiving change between two images** | Models predicted rotation *direction* backwards; treat frames as unrelated | Never send before/after pictures — send the diff |
| **Predicting a transformed state** | Image models output the input unchanged when asked to rotate 30° | Never ask the model to imagine a result |
| **Rendering tools do not rescue it** | Full 3D + render + rotate module → still only **62.5 %** | Vision is a gate, not evidence |
| **Index bookkeeping** | "Index ambiguity" is a named failure class | No entity is ever addressed by number |
| **Local vs global frames** | "Coordinate-frame errors" is a named failure class | One frame, declared, echoed on every coordinate |
| **Long chains without feedback** | L3 invalidity **68–93 %** | Short batches, verified each time |
| **Multi-feature / coupled edits** | **40–46 %** vs 99.6 % single-feature | Force one feature per edit + prove nothing else moved |
| **Knowing when it is done** | **58.1 %** of *executable* code violated stated requirements | Requirements must be machine-checked, not self-assessed |
| **Sweep / loft / path geometry** | Called out as the specific L3 collapse | Offer guided macros; treat raw sweep as expert-tier |
| **Parameter→feature binding** | "Named dimension controls the wrong feature" | Publish the binding table; test it by sweeping |

### 2.3 The one finding that decides the architecture

> LLMs perform **significantly better with quantitative feedback than with VLM judgements
> of 2D images** (SPADA). Test-driven CAD agents lifted assembly success **20.4 % → 41.9 %**
> and cut invalid single-part rate to **1.8 %**.

and, from the opposite direction:

> Multi-view render feedback shows **limited effectiveness**; visual information alone
> cannot compensate for missing parametric comprehension (BenchCAD).

**Therefore: numbers first, pictures second, always.**

---

## 3. The eight laws

Every decision in this document derives from one of these.

**Law 1 — The app reasons about space; the model reasons about design.**
Rotation, projection, adjacency, "which side", "does it break through", "what changed" —
all computed by the app and delivered as text. The model is never asked to visualise.

**Law 2 — Name everything; index nothing.**
Every parameter, sketch, feature, body, face and edge has a stable, meaningful,
*published* name. No op ever takes an ordinal. The model reads names from a table; it
never invents or counts them.

**Law 3 — Ambiguity is an error, never a guess.**
If a selector matches more or fewer entities than declared, the op fails and returns the
candidates with the properties that distinguish them, plus a refined selector that would
work. (The app's own `bestMatch` already refuses a coin toss — we surface that refusal.)

**Law 4 — Answer with the diff, not the state.**
Every op returns what *changed*: Δvolume, Δbounding box, faces gained and lost by name,
new warnings. Models cannot diff two states; we diff for them.

**Law 5 — Intent before geometry, as assertions the app keeps checking.**
The design contract (parameters + requirements) is written before or alongside the model,
stored *in the document*, and re-evaluated on every rebuild — forever, including after a
human edits the part by hand.

**Law 6 — One feature per edit; prove nothing else moved.**
Edits are serialised. After each, the app reports collateral change to every feature the
edit did not name. Silence is the success signal.

**Law 7 — Every error carries its own fix.**
`{code, what, where, numbers, why, fix}` where `fix` is a corrected call the model can
resubmit. No opaque kernel strings.

**Law 8 — Cheap by default, deep on request.**
The default response is the smallest thing that keeps the loop honest (~60–150 tokens).
Everything expensive — full inventories, sections, renders — is opt-in and paginated.

**And one guarantee, not a law:**

**Parity.** Anything a finger can do in this app, a verb can do; anything a verb can do,
the GUI can show and undo. Enforced by a test that enumerates both surfaces and fails on
a gap. The agent is not a side door into a subset of the app.

---

## 4. The loop

```
        ┌─────────────────────────────────────────────────────────────┐
        │                                                             │
   BRIEF ──▶ CONTRACT ──▶ PLAN ──▶ BUILD ──▶ SENSE ──▶ PROVE ──▶ SHIP │
     │          │                    │  ▲       │        │            │
     │          │                    │  └───────┘        │            │
     └──ask?────┘                    │   diff (auto)     │            │
                                     └───────────────────┘            │
                                        repair (typed error)          │
        └─────────────────────── contract violated ───────────────────┘
```

| Stage | Who acts | What crosses the wire |
|---|---|---|
| **BRIEF** | human | free text, optionally an image or a reference part |
| **CONTRACT** | model → app | parameters + requirements + orientation + material; stored in the document |
| **PLAN** | model | a named feature plan (no geometry yet) — cheap, reviewable, revisable |
| **BUILD** | model → app | batches of 1–5 ops; each independently validated and committed |
| **SENSE** | app → model | the diff (automatic) + targeted inspect/measure/section on demand |
| **PROVE** | app → model | contract check, flex sweep, collateral guard, hygiene audit |
| **SHIP** | app → human | export, thumbnail, a written report, a live editable feature tree |

Two repair edges, and they are different:

* **Op-level repair** — an op failed. The typed error carries the fix. The model
  resubmits. Budgeted (default 2 automatic attempts, then escalate to the human).
* **Contract-level repair** — everything built, but a requirement fails. This is a
  *design* problem, not a syntax problem: the model re-enters PLAN with the violating
  numbers in hand.

Keeping those two separate is what stops the classic death spiral where a model responds
to "wall too thin" by re-emitting the same op with different punctuation.

---

## 5. How the AI points at things

This is where most LLM-CAD systems die. Index-based references break on reorder;
coordinate-based references are imprecise; and "the top face" is meaningless after the
third feature. Three layers, working together.

### 5.1 Layer 1 — Published names

Every entity gets a **deterministic, human-readable name**, derived — never stored as an
index — from `(creating feature, role, orientation in the canonical frame, canonical
ordinal)`.

```
param     plate_t, bore_d, n_holes
sketch    sk_base, sk_bosses
feature   base_plate, mount_bosses, bore_1, edge_breaks
body      main, insert
face      base_plate.top          base_plate.bottom
          base_plate.side.+x      base_plate.side.-y
          bore_1.wall             bore_1.floor
          mount_bosses.wall#1..#4
edge      base_plate.top.edge.+x
          bore_1.rim.top
          base_plate.top.edges          (a set)
```

Three rules make this safe:

1. **The model never invents a name — it reads one.** `part.inspect` publishes the table.
   Guessing is impossible because the table is the only source.
2. **Names are re-derived on every rebuild**, so they track the model instead of drifting.
   A name that can no longer be derived is *reported as lost*, never silently reassigned.
3. **The agent may rename.** `base_plate` beats `Extrusion3` for the model, for the human,
   and for the model's next turn three thousand tokens later. Feature names are already
   free-form in `PartFeature.name`.

### 5.2 Layer 2 — Property selectors

Names are for things you already saw. Selectors are for things you are about to make.
A selector is a small JSON object — no query language to learn, no parser to fight.

```jsonc
// the four vertical edges of the base, by property
{ "edges": { "on": "base_plate", "orientation": "vertical",
             "kind": "line", "expect": 4 } }

// every Ø8 bore rim on the top face
{ "edges": { "on_face": "base_plate.top", "kind": "circle",
             "diameter": 8.0, "expect": "any" } }

// the largest planar face pointing up
{ "faces": { "facing": "up", "kind": "plane",
             "pick": "largest", "expect": 1 } }

// everything the last feature created
{ "faces": { "created_by": "mount_bosses" } }
```

Selector predicates, chosen because they are the ones an engineer would *say*:

| Group | Predicates |
|---|---|
| Scope | `on` (feature/body), `on_face`, `created_by`, `in_sketch` |
| Type | `kind`: plane / cylinder / cone / sphere / torus / spline · line / circle / arc / ellipse / spline |
| Orientation | `facing`: up / down / front / back / left / right / outward / inward / `[x,y,z]` · `orientation`: vertical / horizontal / axis-aligned |
| Size | `diameter`, `radius`, `length`, `area`, each with `±tol` or a range |
| Position | `extreme`: topmost / bottommost / leftmost … · `near: [x,y,z]` · `within: bbox` |
| Topology | `convexity`: convex / concave · `closed` · `adjacent_to` |
| Reduction | `pick`: all / largest / smallest / first-by-axis · `limit` |
| Contract | **`expect`: an exact count, a range, or `"any"` — mandatory** |

`expect` is the load-bearing field. It turns every selection into a **claim the model is
making**, which the app can falsify. That is what converts a silent wrong-face bug into a
loud, correctable message.

### 5.3 Layer 3 — Fingerprint anchoring (invisible, automatic)

Whatever a selector resolves to is *also* persisted as the app's existing geometric
fingerprint (`EdgeSel` / `FacePick`). On every rebuild both are evaluated:

| Selector | Fingerprint | Result |
|---|---|---|
| resolves, agrees | resolves | silent success |
| resolves, disagrees | resolves | **warning**: "fillet `edge_breaks` now sits on a different edge than when created" |
| fails | resolves | fingerprint wins, selector reported stale |
| resolves | fails | selector wins, fingerprint re-anchored |
| both fail | | feature reports LOST — the app's existing honest failure |

This is the belt-and-braces that makes parametric edits survivable, and it costs the
model nothing: it never sees a fingerprint.

### 5.4 The canonical frame — decide once, echo forever

**The problem, concretely.** `planeFrame('xy')` has normal `+Z`. `PartCamera` computes
polar angle as `acos(n.y)`. So the app's *screen up* is `+Y`, while every LLM's prior
(STEP, CadQuery, build123d, Fusion, SolidWorks, and the app's own STL exporter, which uses
`MeshUpAxis.z`) says *up is +Z*. A model told "extrude the base upward" will do the right
thing in world coordinates and then see its part lying on its side.

**The resolution — three parts, all required:**

1. **The agent frame is declared: Z-up, right-handed, millimetres, degrees.** It is stated
   in the tool description, restated in every state report header, and it is the frame in
   which every coordinate the model sends or receives is expressed.
2. **Direction is spoken semantically first.** `"up"`, `"down"`, `"outward"`,
   `"normal_of: base_plate.top"`, `"along: bore_axis"`. Raw axes are legal but are always
   echoed with their meaning: `"+Z (up)"`. Views are named — `top`, `front`, `right`,
   `iso` — never expressed as camera angles.
3. **A conformance test pins it.** Build a 10×20×30 box via the agent surface; assert its
   `top` face normal is agent-`+Z`; assert the `top` *view* image shows the 10×20
   footprint. If the bridge ever drifts, that test fails, not a user's part.

Whether the bridge is a transform or a redefinition of the app's camera-up is an
implementation choice (§14.1). The *contract* above is not.

---

## 6. What the AI says — the verb set

### 6.1 The shape of a turn

One tool, `part.apply`, carrying **a batch of 1–5 ops**. Batching is transport only:
each op is validated, committed and reported **independently**, and a failure stops the
batch at that op (everything before it stays committed, everything after is returned
untried). The whole batch is **one undo step**.

Why this shape, and not the alternatives:

| Alternative | Why rejected |
|---|---|
| One MCP tool per operation (~60 tools) | Tool definitions alone cost 6–15 k tokens before a word of work; selection confusion rises with count |
| One call per operation | Round-trip per feature; a 14-feature part costs 14 turns and 14 full context replays |
| A new textual DSL the model must learn | Violates "without much learning"; every grammar error is a wasted turn; nothing in pretraining |
| A Python/JS sandbox with a CAD API | Strongest for Opus-class, unusable for Flash-class; huge security and lifecycle surface on an iPad |
| **Batched, schema'd JSON ops** ✅ | Constrained decoding guarantees validity; zero grammar to learn; amortises round-trips; per-op semantics keeps the 99.6 % single-feature regime |

**Optional second door for strong models (phase 2, not phase 1):** `part.script`, which
accepts the *text projection* of the feature tree — the exact artefact `part.read`
returns — parses it into the same ops, and runs the same validator. This gives an
Opus-class model the read-edit-write workflow it is best at, with no separate semantics.
A weak model never sees it.

### 6.2 An op

```jsonc
{
  "op": "extrude",
  "name": "base_plate",                 // the model names its own work
  "sketch": "sk_base",
  "profile": { "pick": "largest", "expect": 1 },
  "distance": "plate_t",                // an expression, not a number
  "direction": "up",
  "output": "new",
  "note": "main body, 6 mm plate"       // rides into the feature's description
}
```

Every op carries `name`. Every dimension accepts a **parameter expression**
(`"plate_t"`, `"bore_d/2 + 0.5"`, `"12 mm"`) because `params.dart` already evaluates
them — so parametric intent is the default path, not an advanced one.

### 6.3 The catalogue

Organised so a model can hold it in working memory. Counts are the target surface.

**Document & session (7)**
`doc.new` · `doc.open` · `doc.save` · `doc.export` (STEP/STL/OBJ/3MF/DXF) ·
`doc.import` (STEP/mesh) · `doc.list` · `doc.thumbnail`

**Contract & parameters (6)**
`spec.set` (parameters + requirements + material + orientation) · `spec.get` ·
`param.define` · `param.set` · `param.delete` · `param.bindings` *(which features each
parameter drives — the antidote to "named dimension controls the wrong feature")*

**Sketch (11)** — profile primitives first, raw entities last
`sketch.new` (on an origin plane, a work plane, or a named face) ·
`sketch.rect` · `sketch.circle` · `sketch.slot` · `sketch.polygon` · `sketch.ellipse` ·
`sketch.rounded_rect` · `sketch.path` (turtle: `line_to` / `arc_to` / `close`) ·
`sketch.text` · `sketch.project` (model edges onto the plane) · `sketch.edit`

Constraints and dimensions exist as `sketch.constrain` / `sketch.dimension` but are
**not on the normal path** — see §7.

**Features from a sketch (5)**
`extrude` · `revolve` · `sweep` · `loft` · `coil`
Each takes `output: new | join | cut | intersect` and an extent
(`distance | symmetric | asymmetric | to_face | to_next | through_all`).

**Body modification (9)**
`hole` (simple / counterbore / countersink / spotface, by position list or by sketch
points) · `fillet` · `chamfer` · `delete_face` · `move_face` · `scale_body` ·
`split` · `combine` · `derive`

**Patterns & mirrors (4)**
`pattern.rect` · `pattern.circular` · `pattern.sketch_driven` · `mirror`

**Work geometry (3)**
`work.plane` (offset / midplane / angle / three-point / tangent) · `work.axis` ·
`work.point`

**Assembly (8)**
`asm.new` · `asm.place` · `asm.joint` · `asm.constrain` · `asm.pattern` ·
`asm.ground` · `asm.drive` · `asm.make_part`

**History (8)**
`history.undo` · `history.redo` · `history.checkpoint` · `history.revert` ·
`history.list` · `feature.suppress` · `feature.delete` · `feature.reorder`

**Sense — read-only (7)**  ·  **Prove — read-only (5)**  ·  **View (3)**
Detailed in §8 and §9.

**Escape hatch (1, gated)**
`raw.kernel` — a direct call into the OCCT shim. Off by default; enabled per session by
the human. Exists so an expert model is never *blocked*, and so we learn from the logs
which macro to add next.

**Total: ~77 verbs, one entry point, four schemas to learn (op, selector, expression,
error).**

### 6.4 Macros — the weak-model lane

A macro is a single op that expands, *deterministically and visibly*, into a documented
feature sequence. The expansion is written into the feature tree with real names, so the
human can edit any of it and the model can inspect all of it. Nothing is hidden.

```jsonc
{ "op": "macro.mounting_plate",
  "name": "plate",
  "size": [120, 80], "thickness": "plate_t",
  "corner_radius": 5,
  "holes": { "pattern": "corners", "inset": 10, "type": "M4_clearance" } }
```

Starter set (the shapes that are 80 % of real parts and 100 % of L3 pain):
`mounting_plate` · `bracket_L` · `boss` · `rib` · `standoff` · `flange` ·
`hex_pocket` · `bearing_seat` · `slot_array` · `keyway` · `cable_gland`.

Each macro also has a **fastener knowledge table** behind it — `M4_clearance` = Ø4.5,
`M4_tap` = Ø3.3, counterbore Ø8 × 4.4 deep — so the model states intent, not machinist
arithmetic. This is the single highest-leverage accuracy feature for Flash-class models,
because it removes the exact numbers they are most likely to get subtly wrong.

Macros are transparent, not magic: `macro.explain` returns the ops it would emit, so a
strong model can take the expansion and modify it instead.

---

## 7. Sketching — the place where token budgets and accuracy go to die

A 2D profile is the most verbose and most error-prone thing an LLM emits. Four decisions.

### 7.1 Profile primitives, not entity soup

Never `line(0,0,60,0); line(60,0,60,40); …`. Always `rect(60, 40, center)`.
A rectangle is 1 op instead of 4, cannot fail to close, and carries its own parameters.
Raw entity drawing stays available for genuinely free-form work.

### 7.2 The app closes loops; the model does not have to

`ProfileRegion` already finds closed regions by half-edge walking, and `ProfileGap`
already finds near-misses. So:

* the model draws entities; the app finds regions;
* a gap under `heal` (default 0.05 mm) is closed automatically **and reported**:
  `healed 1 gap of 0.031 mm between sk_base/line#3 and sk_base/arc#1`;
* a gap over `heal` is a typed error carrying both endpoints and a `fix` op that snaps
  them — not "extrude failed".

### 7.3 Constraints are optional, and normally skipped

This is counter-intuitive but it is the right call. Sketch constraints exist so a *human*
can drag geometry and have it behave. An LLM does not drag. For an LLM, **the parametric
primitive is the constraint system**: `rect(w: "plate_w", h: "plate_h", center: [0,0])`
is already fully constrained, symmetric, and parametric — with zero solver involvement
and zero over-constraint risk.

So the default path emits **no constraints at all**. `sketch.constrain` remains for the
cases that need it (tangent chains, a sketch that must stay editable by hand, a
driven/reference dimension) and for parity with the GUI.

Payoff: we delete the largest source of LLM sketch failure — redundant and conflicting
constraints — by not requiring the model to enter that space.

### 7.4 The sketch frame is stated every single time

`sketch.new` returns, and every later reference repeats:

```
sk_top on face base_plate.top
  origin  world (0, 0, 6)
  +u = world +X      +v = world +Y      normal = world +Z (up)
  extent of the host face: u ∈ [-60, 60], v ∈ [-40, 40]
```

That block is ~40 tokens and it eliminates the entire "coordinate-frame error" failure
class. The model never converts a frame; it is told the conversion.

---

## 8. How the AI sees — the perception ladder

**The principle:** the model is given *the answer to a spatial question*, not the raw
material to answer it from. Ordered cheapest first; nothing expensive happens unasked.

### L0 — The change report (automatic, free, ~60–150 tokens)

Returned by **every** mutating op. This is the workhorse, and it is the direct answer to
"models cannot compare two states".

```
✓ bore_1  hole ⌀8.0 through, 4 places
  Δvolume   −2 010 mm³  (−4.2 %)   now 45 790 mm³
  Δbbox     none                    120.0 × 80.0 × 6.0
  +faces    bore_1.wall#1..#4 (cylinder ⌀8.0, axis +Z)
  −faces    none
  selectors bore positions resolved from sk_holes: 4 of 4 expected
  warnings  none
  contract  6/6 pass
```

Note what is *not* here: no full face list, no feature tree, no image. Under 150 tokens,
and it answers "did that do what I meant" completely.

### L1 — `part.tree` (~200–600 tokens)

The feature tree as a readable script: names, types, key parameters, errors, the
End-of-Part marker, suppression state. This is also the text projection `part.script`
would consume — one artefact, two uses.

```
part "sensor_bracket"   frame: Z-up, mm   material: AL6061 (2.70 g/cm³)
params  plate_t = 6 mm · plate_w = 120 mm · plate_h = 80 mm
        bore_d = 8 mm · n_holes = 4 ul · web_t = plate_t * 0.6   → 3.6 mm

 1  sk_base      sketch on XY            rect(plate_w, plate_h, center)
 2  base_plate   extrude sk_base         plate_t, up, new           → body main
 3  sk_holes     sketch on base_plate.top 4 points, rect array 100×60
 4  bore_1       hole ⌀bore_d through    from sk_holes (4)
 5  upright      extrude sk_web          40 mm, up, join
 6  edge_breaks  fillet r2               base_plate.top.edges (4)   ⚠ 1 edge lost
    ── End of Part ──
```

### L2 — `part.inspect` (paginated, ~300–1500 tokens)

The name table, and the only place names come from.

```
body main   volume 45 790 mm³   area 34 120 mm²   mass 123.6 g
            bbox 120.0 × 80.0 × 46.0   centre of mass (0.0, 0.0, 11.3)
            solid: yes   closed: yes   errors: none

faces  22 total — 14 plane, 8 cylinder
  base_plate.top        plane    n +Z (up)   9 540 mm²   at z = 6.0
  base_plate.bottom     plane    n −Z        9 600 mm²   at z = 0.0
  base_plate.side.+x    plane    n +X          720 mm²   at x = +60.0
  …
  bore_1.wall#1         cylinder ⌀8.0 axis +Z  centre (−50, −30)
  …

edges  (request explicitly — 48 entries)
```

`filter`, `group_by` and `limit` mean the model asks for *the four bore rims*, not for
forty-eight edges.

### L3 — `part.measure` (~40–80 tokens)

Named entity to named entity, the way a person asks:

```
measure { from: "bore_1.wall#1", to: "bore_1.wall#2" }
  → centre distance 100.000 mm · parallel axes · both ⌀8.000

measure { thickness_at: "base_plate.top", direction: "down" }
  → 6.000 mm to base_plate.bottom

measure { clearance: ["upright", "bore_1.wall#3"] }
  → 12.400 mm (minimum, between upright.side.-y and bore_1.wall#3)
```

### L4 — `part.section` (~200–600 tokens) — **the underrated one**

A symbolic cross-section. The app cuts the solid with a named plane and returns the
*profile of the cut* as dimensioned polylines, plus derived facts.

```
section at plane "midplane_yz" (x = 0)
  1 closed region, area 396 mm², perimeter 244 mm
  extents  y ∈ [−40, +40]   z ∈ [0, 46]
  wall thicknesses measured normal to the boundary:
      min 3.60 mm at (y=+18.0, z=22.0)   max 6.00 mm   mean 5.1 mm
  no voids, no self-intersections
```

This is how an LLM answers "is it thick enough", "is it hollow where I meant", "does the
rib actually reach the floor" — questions that are *unanswerable from a render* and
trivial from a section. It is a direct application of Law 1, and the app already has
section views.

### L5 — `part.view` (~800–1600 tokens per image) — the gestalt gate

Rendered images, **always annotated**, never bare. Every view carries, burned in:

* a title stating the direction **in words**:
  `FRONT — looking along +Y; screen right = +X, screen up = +Z`;
* an axis triad and a scale bar;
* the bounding-box dimensions;
* **the same names the text uses**, as leader-line labels (capped at ~12 per view);
* optional **highlight set** — the entities a selector resolved to, in a single strong
  colour, with a legend.

Sets: `iso` (default single), `ortho4` (front/right/top/iso), `ortho8` (the canonical
six + two isometrics).

**The rule that keeps this honest:** a view may never be the *only* evidence for a claim.
`part.check` results and measurements are the evidence; the view catches the things
numbers do not — "this is a bracket, not a blob", "the boss is on the wrong side",
"this looks nothing like what was asked for".

**The best use of vision here is the highlight render.** "Here, in red, is exactly what
your selector selected." That is a coarse, whole-image judgement — precisely the kind of
visual task models *are* reliable at — and it also serves the human watching.

### L6 — `part.diff` (explicit, ~100–400 tokens)

The change report between two named checkpoints, for when a repair loop has drifted:
features added/removed/changed, parameter deltas, volume/bbox deltas, contract deltas.

### Cost ladder, summarised

| Level | Typical tokens | When |
|---|---|---|
| L0 diff | 60–150 | every op, automatic |
| L1 tree | 200–600 | start of a session, after a plan change |
| L2 inspect | 300–1500 | before a selector-heavy op |
| L3 measure | 40–80 | to settle one number |
| L4 section | 200–600 | wall thickness, internals, "is it hollow" |
| L5 view | 800–1600 /image | milestone gate, final report, human hand-off |
| L6 diff | 100–400 | after a messy repair |

A well-behaved session spends **~70 % of its perception budget at L0**, which is the
whole point.

---

## 9. How the AI knows it is good — the proof layer

Perception tells the model what *is*. Proof tells it whether that is *right*. This is the
layer that separates "it compiled" from "it works", and the evidence is unambiguous that
without it, **58 % of executable models violate their own stated requirements.**

### 9.1 The design contract

Written in `spec.set`, stored **in the `.ptp` document**, re-evaluated on every rebuild —
including rebuilds triggered by a human dragging a dimension six months later.

```jsonc
{
  "op": "spec.set",
  "intent": "Bracket mounting a 30 mm sensor to 40×40 extrusion, 2 kg static load",
  "orientation": "mounting face down (−Z), sensor axis along +Y",
  "material": { "id": "AL6061", "density": 2.70 },
  "process": "3-axis milling, 6 mm end mill",
  "params": [
    { "name": "plate_t",  "value": 6,   "unit": "mm", "role": "driving",
      "range": [4, 10], "why": "stiffness vs. mass" },
    { "name": "bore_d",   "value": 8,   "unit": "mm", "role": "interface",
      "fixed": true,    "why": "M8 clearance for extrusion T-nut" }
  ],
  "requires": [
    { "id": "envelope",   "bbox_max": [120, 80, 50] },
    { "id": "mass",       "mass_max_g": 250 },
    { "id": "wall",       "min_wall_mm": 3.0 },
    { "id": "mount",      "holes_through": { "select": {"edges": {"kind":"circle","diameter":8}},
                                             "count": 4, "spacing_mm": 100 } },
    { "id": "tooling",    "min_internal_radius_mm": 3.0,
                          "why": "6 mm end mill cannot cut a sharper inside corner" },
    { "id": "buildable",  "no_feature_errors": true, "manifold": true }
  ]
}
```

**Assertion vocabulary** (each returns actual vs. required, never just pass/fail):

| Family | Assertions |
|---|---|
| Envelope | `bbox_max`, `bbox_min`, `fits_in`, `footprint` |
| Mass | `mass_max_g`, `mass_min_g`, `volume`, `centre_of_mass_within` |
| Thickness | `min_wall_mm`, `max_wall_mm`, `uniform_wall_within` |
| Features | `holes_through`, `hole_count`, `hole_pattern`, `feature_exists`, `face_count_by_kind` |
| Manufacturability | `min_internal_radius_mm`, `min_hole_diameter_mm`, `min_feature_mm`, `draft_min_deg`*, `overhang_max_deg`, `no_trapped_volume` |
| Assembly | `clearance_min_mm`, `no_interference`, `mates_with` |
| Integrity | `manifold`, `no_feature_errors`, `no_lost_selections`, `single_body` |
| Relations | `param_drives(param, feature)`, `symmetric_about(plane)` |

\* requires a draft feature — see §14.2.

### 9.2 `part.check` — the verdict

```
contract check — sensor_bracket                         5 pass · 1 FAIL

  ✓ envelope   bbox 118.0 × 76.0 × 46.0   ≤ 120 × 80 × 50
  ✓ mass       123.6 g                    ≤ 250 g
  ✗ wall       min 2.4 mm at (0.0, 18.0, 22.0)   requires ≥ 3.0 mm
               → the web between upright and bore_1.wall#2
               → driven by: web_t = plate_t * 0.6
               → fix: raise web_t to ≥ 3.0, e.g. plate_t * 0.5 + 0.6
  ✓ mount      4 through holes ⌀8.0, spacing 100.0 × 60.0
  ✓ tooling    min internal radius 3.0 mm
  ✓ buildable  manifold, 0 feature errors, 0 lost selections
```

Every failure names the **location**, the **number**, the **parameter that drives it**,
and a **candidate fix**. That is Law 7 applied to design rather than syntax, and it is
what turns a failure into one cheap corrective turn instead of a guessing spiral.

### 9.3 `part.guard` — the collateral-damage report (automatic on every edit)

The documented #1 edit failure mode: multi-feature and coupled edits succeed only
**40–46 %** of the time, and the damage is invisible — "an edit damages a mounting hole".

So: before any edit, the app snapshots an invariant signature of **every feature the edit
did not name** (bbox, volume, face count by kind, selector resolution status). After the
rebuild it compares. Anything that moved and should not have is reported *unprompted*:

```
⚠ collateral change from editing "upright"
   bore_1        4 → 3 faces        one bore no longer breaks through
   edge_breaks   selector lost 1 edge (base_plate.top.edge.+y no longer straight)
   suggest: history.undo, then raise plate_h instead of moving the web
```

Nobody ships this. It is cheap here — `builtSig` already tells us which features
rebuilt — and it converts the hardest, most silent failure class into a loud one.

### 9.4 `part.flex` — the parameter sweep

The other documented silent killer: *a named dimension controls the wrong feature*, and
it only shows when the value changes.

```
flex { plate_t: [4, 6, 10], bore_d: [6, 8, 10] }

  plate_t=4  ✓ builds   mass  82 g   contract 6/6
  plate_t=6  ✓ builds   mass 124 g   contract 6/6      (nominal)
  plate_t=10 ✗ FAILS    edge_breaks: r2 fillet exceeds available face
             → at plate_t=10 the top chamfer consumes the fillet's run-out
             → fix: make the fillet radius a function: r = min(2, plate_t/3)

  bore_d=6   ✓ builds   contract 6/6
  bore_d=8   ✓ builds   contract 6/6
  bore_d=10  ✗ wall     min 1.8 mm  < 3.0 mm at the plate edge
```

Cheap because rebuilds are already incremental and signature-cached. This is how a model
delivers a part that is *parametric in truth*, not just parametric in name — which is
exactly the gap CADEngBench measures and every current system fails.

### 9.5 `part.audit` — modelling hygiene

Correct is not the same as good. A part a human cannot edit afterwards is a failure of the
brief, even if every dimension is right. The audit encodes the
**Resilient Modelling Strategy**, which is the documented industry answer to fragile
feature trees:

```
hygiene audit — sensor_bracket                              score 7/9

  ✓ reference geometry first (2 work planes at the top)
  ✓ fillets and chamfers last (1 group, position 6 of 6)
  ✓ every feature named meaningfully
  ✓ no feature depends on more than 2 upstream features
  ✗ 3 hard-coded dimensions that should be parameters:
        upright.distance = 40        → suggest param "upright_h"
        sk_web offset    = 12        → suggest param "web_offset"
        bore spacing y   = 60        → suggest param "mount_pitch_y"
  ✗ "upright" is parented to a face created by "edge_breaks" (a detail feature)
        → detail features should not be parents; re-anchor to base_plate.top
  ✓ no suppressed features left behind
  ✓ no orphan sketches
```

RMS in one line, and the ordering the audit enforces:
**reference → construct → core → detail → modify → finish (fillets/chamfers last).**
Fillets and chamfers are fragile and must be the final group; core features may depend
only on reference geometry; detail features may not depend on each other.

This is what makes the output look like a product developer made it. It is also
self-serving: a model that follows RMS produces trees that survive its own later edits.

### 9.6 The gate

`part.check` + `part.guard` + `part.audit` (+ `part.flex` at the end) are the exit gates
between workflow phases. **The model is not permitted to declare success on its own
judgement.** It declares success by showing a passing check. That single rule is the
difference between a demo and a tool.

---

## 10. The playbook — modelling like a product developer

A product developer does not start by drawing. This is the procedure the system prompt
teaches, and the phase gates the app enforces.

### Phase 0 — Brief & clarify *(0–1 round-trips)*

Underspecified briefs are the norm, and making unwarranted assumptions is a documented
source of bad outcomes — but so is interrogating the user. The rule:

> **Ask only about ambiguities that change the geometry and that a sensible default
> cannot cover. Never more than three questions, in one message, each with a proposed
> default so the human can answer by saying "all defaults".**

Blocking (ask): the interface the part must mate with · load/duty if it decides
thickness · the manufacturing process if it changes the whole shape · a hard envelope.
Non-blocking (assume and declare): fillet radii · cosmetic proportions · material grade
within a family · hole types when a standard exists.

Everything assumed is written into the contract's `why` fields, so it is visible,
auditable and cheap to overturn.

### Phase 1 — Contract *(1 op)*

`spec.set`. Parameters with roles and ranges, requirements as assertions, canonical
orientation, material, process. **Gate:** the contract must contain at least one
envelope, one integrity and one manufacturability assertion. A contract that cannot fail
is not a contract.

### Phase 2 — Plan *(0 ops, pure text)*

A named feature plan before any geometry:

```
1 datums      work.plane mid_yz (symmetry)
2 core        base_plate   extrude sk_base (120×80) up plate_t
3 core        upright      extrude sk_web  up 40, join
4 detail      bore_1       4× ⌀8 through, 100×60 pattern
5 detail      sensor_bore  ⌀30 H7 in upright
6 finish      edge_breaks  r2 on all outer top edges
7 finish      break_sharp  0.5×45° on all remaining sharp edges
```

Cheap (~120 tokens), reviewable by the human before anything is built, and it is the
artefact the repair loop returns to when the *design* is wrong rather than the syntax.
**Gate:** the plan must be ordered reference → core → detail → finish.

### Phase 3 — Datums and core *(1–3 batches)*

The mass of the part. One or two extrudes/revolves. **Gate:** `part.check` passes the
envelope assertion; body is manifold; a single `iso` view for the gestalt.

### Phase 4 — Detail *(2–5 batches)*

Holes, pockets, bosses, patterns. Each batch followed by its automatic L0 diff.
**Gate:** all `holes_through` / feature assertions pass; `part.guard` silent.

### Phase 5 — Finish *(1–2 batches)*

Fillets and chamfers, **always last, grouped**. This is enforced, not suggested: a fillet
op before all detail features are placed produces a warning in the audit and a hint in
the response.
**Gate:** `part.check` fully green.

### Phase 6 — Prove *(2–3 calls)*

`part.check` · `part.flex` on every driving parameter's declared range ·
`part.audit` · `part.view ortho4`.
**Gate:** contract green at every flex point, audit ≥ 8/9, no collateral warnings.

### Phase 7 — Ship *(2 ops + a report)*

`doc.export` (STEP + STL) · `doc.thumbnail` · and a written report the human actually
reads:

```
sensor_bracket — done

  What it is      120 × 80 × 46 mm AL6061 bracket, 124 g
  Interfaces      4× ⌀8 through, 100 × 60 pitch, for M8 T-nuts
                  ⌀30 H7 bore on +Y axis, 12 mm deep
  Contract        6/6 pass, and still passes at plate_t 4–10 and bore_d 6–10
  Assumed         fillet r2 (not specified); AL6061 (you said "aluminium")
  Watch           at plate_t = 10 the r2 fillet is close to its run-out limit;
                  it is parameterised as min(2, plate_t/3) so it stays safe
  Edit it         plate_t, plate_w, plate_h, bore_d, mount_pitch_x/y, upright_h
  Files           sensor_bracket.ptp · .step · .stl
```

### Why phases, and not "just let it model"

L3 invalidity runs **68–93 %** when a model free-runs. Gates convert one long fragile
chain into five short verified ones. Each gate is ~200–400 tokens and saves a multi-turn
unwind. This is the same reason software agents run tests between edits.

---

## 11. Errors, repair, and never getting stuck

### 11.1 The error object

```jsonc
{
  "code": "SELECTOR_AMBIGUOUS",
  "op_index": 2,
  "what": "fillet: selector matched 8 edges, expect was 4",
  "where": "body main, feature base_plate",
  "candidates": [
    { "name": "base_plate.top.edge.+x", "kind": "line", "length": 120.0, "z": 6.0 },
    { "name": "base_plate.bottom.edge.+x", "kind": "line", "length": 120.0, "z": 0.0 }
    /* … 6 more, each with the property that distinguishes it … */
  ],
  "why": "both the top and bottom rims are horizontal lines of the same length",
  "fix": { "op": "fillet", "radius": 2,
           "select": { "edges": { "on_face": "base_plate.top", "kind": "line", "expect": 4 } } }
}
```

`fix` is a **runnable op**, not prose. That is the difference between one corrective turn
and four.

### 11.2 The taxonomy — and the different treatment each gets

| Class | Example | Treatment |
|---|---|---|
| **Schema** | wrong enum, missing field, `"6mm"` where a number was wanted | **Auto-repaired inside the app** where unambiguous (units, enum case, known synonyms), applied, and *reported*: `note: read "6mm" as 6 mm`. Costs the model nothing. |
| **Selector** | ambiguous, empty, wrong count | Returned with candidates + a refined selector. Never guessed. |
| **Geometric** | profile not closed, self-intersecting, zero-thickness | Returned with the offending coordinates + a heal or snap `fix` |
| **Kernel** | boolean failed, fillet exceeds face | Translated out of OCCT-speak into a cause and a suggested smaller value or reordering |
| **Policy** | fillet before details, feature depends on a detail feature | Warning, not an error — it still builds, the audit records it |
| **Contract** | a requirement fails | **Not an op error.** Routed to Phase 2 (re-plan), never to blind op retry |

### 11.3 The repair budget

* Op-level: **2 automatic attempts**, then stop and ask the human, showing both attempts.
* Contract-level: **2 re-plan cycles**, then report the conflict honestly —
  *"a 3 mm minimum wall and a 250 g maximum are not simultaneously satisfiable at
  120 × 80; which gives?"* That is the right answer, and a system that keeps grinding
  instead of saying it is a worse system.
* A hard **op-count and token ceiling** per request, surfaced in the UI, with a resume
  option. No runaway bills.

### 11.4 The anti-spiral rules

1. The same op failing twice with the same code stops the loop.
2. An op that undoes the previous op stops the loop.
3. Volume oscillating between the same two values across three checkpoints stops the loop.
4. The model may not claim success without a `part.check` result in the same turn.

---

## 12. Structural decisions (workflow-level, not implementation)

### 12.1 The verbs must not be a second implementation of the app

The single most dangerous way to build this is: a new module that constructs
`PartFeature` objects itself. It would work on day one and diverge by month three — two
validators, two naming schemes, two undo paths, two sets of bugs, and the parity
guarantee quietly dead.

**The workflow requirement is therefore:** the dialog sessions and the agent ops must
produce features through **one shared path**. Whatever the eventual shape, the test that
proves it is the same one that proves parity:

> For every feature-creating command in the GUI, an agent op exists that produces a
> byte-identical feature; for every agent op, the GUI can display, edit and undo the
> result. Enumerated by a test that fails when either surface grows without the other.

This is also what makes "the AI can do every single thing in the app" a fact rather than a
claim — and what makes a human able to pick up, mid-session, exactly what the AI built.

### 12.2 Where the agent runs

Both, over one core:

* **In-app** — the user pastes an API token in Settings, types in a chat panel, and
  watches the model build in the live viewport. This is the headline experience and the
  thing the user asked for.
* **As an MCP server** — so Claude Code, Claude Desktop, Cursor or any agent host can
  drive the running app. Thin adapter over the same verbs. Costs little and buys the
  entire external agent ecosystem.

Both are adapters. The verbs, the validator, the perception ladder and the proof layer
are one core, exercised headlessly by the existing 327-file test harness.

### 12.3 Synchronous, with progress

Kernel ops take 10 ms to a few seconds. Every op is synchronous with a deadline and a
progress channel (the mesh pipeline already reports stage/permille). A long op returns a
partial result with a continuation token rather than blocking a chat turn. Nothing about
the workflow is async; the model always gets its diff before it speaks again.

### 12.4 The human is never locked out

The AI's edits land on the same undo stack as the human's. The human can undo an AI step,
edit a dimension by hand, and the AI's next `part.tree` reflects it. The contract keeps
checking after the AI has stopped talking. **The AI is a collaborator in the document,
not a generator that hands over a file.**

---

## 13. Making it work from Gemini Flash to Opus 5

One core, two profiles, chosen automatically from the model id and adjustable by hand.

| | **lite** (Flash / Haiku class) | **full** (Opus / GPT-5 class) |
|---|---|---|
| Verbs exposed | ~24 (macros + core features + sense + check) | all ~77 |
| Ops per batch | 1–2 | up to 5 |
| Macros | preferred; suggested in every error | available, expansion inspectable |
| Raw entity sketching | off | on |
| `raw.kernel` | off | opt-in |
| `part.script` | off | on (phase 2) |
| Auto-repair of schema slips | aggressive | aggressive (same) |
| Perception default | `concise` | `normal` |
| Views | auto at phase gates | on request |
| Clarifying questions | max 2 | max 3 |
| Plan phase | template-filled | free-form |
| Contract | pre-seeded from a template by part class | authored |

Three things do the heavy lifting for weak models, and none of them weaken strong ones:

1. **Macros with a fastener/standards table** — removes the arithmetic they get wrong.
2. **Aggressive in-app schema repair** — a unit-string slip costs zero turns.
3. **`expect` on every selector** — a weak model's wrong guess becomes a caught error
   with a ready-made fix instead of a silently wrong part.

**The design target:** a Flash-class model completes a bracket-class part, contract-green,
in **≤ 12 ops, ≤ 3 minutes, ≤ 15 k tokens, with zero human corrections.** An Opus-class
model does the same part in ≤ 8 ops and handles a swept, lofted, multi-body part that a
Flash-class model should decline rather than botch.

---

## 14. Risks and the decisions I need from you

### 14.1 Decide: the canonical agent frame *(blocking)*

The app's world is XYZ right-handed but its camera is Y-up (§5.4). Three options:

| Option | Cost | Risk |
|---|---|---|
| **A. Agent speaks Z-up; the bridge transposes** | small, contained in one mapping | one place to get wrong; caught by a conformance test |
| **B. Agent speaks the app's world (already XYZ); only *views* are mapped** | smallest — no transform at all | the model's "up" is +Z in geometry but +Y on screen; every render contradicts the numbers unless view naming is airtight |
| **C. Change the app's camera to Z-up** | touches the viewport, view cube, sketch cameras, saved documents | large blast radius in a shipped app |

**My recommendation: B**, with semantic direction names as the only vocabulary the model
uses (`up`/`down`/`front`/…) and named views only. It requires no geometric transform,
keeps the document untouched, and the "screen up" mismatch never reaches the model
because the model never names a camera axis. A is the fallback if renders prove confusing
in practice. C only if you want Z-up for human reasons anyway.

### 14.2 Decide: fill the feature gaps before or after *(shapes the first demo)*

Missing today: **shell**, **draft**, **thread**, **rib**, **interference check**,
**mass properties (density / centre of mass / inertia)**.

* **Shell** is the biggest. Almost every enclosure, housing and plastic part needs it, and
  an agent that cannot shell will fake it with a boolean subtraction of an offset solid —
  slow, fragile, and unlike anything a human would have in their tree. OCCT has
  `BRepOffsetAPI_MakeThickSolid`; this is a shim addition, not a research project.
* **Mass properties** are needed because "under 250 g" is the most natural requirement an
  engineer states, and without density we can only check volume. OCCT's `BRepGProp`
  gives mass, centre of mass and inertia in one call.
* **Interference** is `occt_common` → volume > 0. Near-free, and assemblies need it.
* **Draft / thread / rib** can wait; macros can approximate rib, and threads are usually
  cosmetic or a note on the drawing.

**My recommendation:** shell + mass properties + interference **before** the first agent
demo; draft, thread, rib after. Without them the contract vocabulary has holes in exactly
the places engineers care about.

### 14.3 Decide: privacy and cost posture *(policy, needs your call)*

Driving a model means geometry summaries — and, if views are used, images of the part —
leave the device. Needed:

* an explicit, visible statement of what is sent (and a "numbers only, no images" mode);
* a per-request and per-day token/cost ceiling shown in the UI;
* a full transcript log per session, stored with the document, so any AI-built feature
  can be traced to the words that made it;
* bring-your-own-key, stored in the platform keychain, never in the document.

### 14.4 Open questions I could not settle from the code alone

1. **Profile region identity.** Regions are recomputed from the half-edge graph each
   time. Are they stably ordered across sketch edits? If not, `profile: {pick: "largest"}`
   and `inside_point` are safe but `index` is not — which is fine, but it must be
   confirmed before the selector set is frozen.
2. **Rebuild latency at scale.** `PERFORMANCE_PROFILE.md` exists; I have not measured a
   30-feature part on an iPad. The flex sweep's cost is `rebuilds × parameters × values`,
   and if a rebuild is 800 ms a 3-parameter sweep is ~7 s — acceptable — but at 4 s it is
   not, and flex becomes an explicit, opt-in final step rather than a phase gate.
3. **Assembly scope for v1.** Parts are a clean, complete story. Assemblies add joints,
   constraint solving, occurrence transforms and a second selection space. My instinct is
   **parts first, assemblies as phase 3** — the part workflow must be excellent before it
   is generalised.
4. **Image token cost on the iPad path.** If the in-app chat pays per image, the phase
   gates that auto-render need a budget switch.

### 14.5 Risks I am watching

| Risk | Mitigation already in the plan |
|---|---|
| The agent layer becomes a second app | §12.1 shared path + enforced parity test |
| Selector language grows into a query language nobody can learn | Frozen predicate list; `expect` mandatory; every error ships a working selector |
| Perception costs blow the budget | L0 default; everything else opt-in and paginated |
| Contract becomes ceremony the model skips | It is a *gate*, not a suggestion: no success claim without a check result |
| Macros hide geometry the human cannot edit | Macros expand into real, named features; `macro.explain` shows the ops |
| Weak models produce plausible garbage | `expect` + contract + flex catch it; the model is never the judge of its own work |
| We optimise for benchmarks instead of real parts | Eval suite is real parts with real contracts (§16) |

---

## 15. What is genuinely new here

Measured against every system in Appendix D — the Fusion/FreeCAD/Onshape MCP servers,
Zoo's KCL, Text2CAD, SPADA, Embodied CAD, CADMorph, BenchCAD — this is what nobody has
put together:

1. **Symbolic-first perception.** Every other system leads with "render it and let the
   VLM look". The evidence says that caps out around 62 %. Here the app answers the
   spatial question and the model gets a sentence. The render is the gestalt gate.
2. **Cross-modal binding.** When there *is* a picture, it is labelled with the *same
   names* the text uses, and it can highlight exactly what a selector resolved to. The
   model never has to establish correspondence between what it reads and what it sees —
   the thing it is provably worst at.
3. **`expect` on every selection.** Selection becomes a falsifiable claim. Ambiguity is a
   typed error with candidates and a ready-made refinement, never a coin toss. This
   single field converts the most common silent wrong-part bug into a caught one.
4. **A design contract that lives in the document.** Not a prompt, not a test file — a
   first-class part of the `.ptp`, re-checked on every rebuild forever, visible to the
   human, and the only thing the model is allowed to declare success on.
5. **Automatic collateral-damage reporting on every edit.** The documented 40–46 %
   failure mode becomes loud instead of silent, and it costs almost nothing because the
   rebuild signatures already know which features moved.
6. **`part.flex` as a first-class verb.** Parametric integrity is *tested*, not assumed.
   This is the difference between a model that is parametric and one that merely has
   parameters — and it is exactly what current benchmarks show every system failing.
7. **A hygiene audit that enforces Resilient Modelling.** The output is not just correct,
   it is *maintainable by a human afterwards*. That is what "like a product developer"
   actually means, and no LLM-CAD system does it.
8. **Symbolic sections.** Wall thickness, internal voids and "does the rib reach the
   floor" answered as numbers. Unanswerable from a render, trivial from a section, and
   the app already has the machinery.
9. **Enforced parity with the GUI.** The agent is not a subset or a side door. Anything a
   finger can do, a verb can do — proven by a test, not by a README.
10. **The change report as the default response.** Not the new state — the delta. Because
    models cannot diff, and we can.

Individually several of these exist in research prototypes. **Together, in a shipping,
touch-native parametric CAD app, with a live GUI the human shares with the agent — that
combination does not exist.**

---

## 16. How we will know it worked

Not a vibe. A suite, run on every change, across three model tiers.

**The corpus: 40 real parts with real contracts**, spread across
L1 prismatic (plate, spacer, cover) · L2 featured (bracket, housing, clamp, manifold) ·
L3 advanced (swept handle, lofted duct, coiled spring, revolved knob) ·
L4 applied ("a mount for this sensor on 40×40 extrusion").
Each with a written brief, a contract, and a human-built reference part.

**Metrics — generation**

| Metric | Flash-class target | Opus-class target |
|---|---|---|
| Builds without error, first pass | ≥ 85 % | ≥ 95 % |
| Contract green, first pass | ≥ 60 % | ≥ 85 % |
| Contract green within 2 repair cycles | ≥ 85 % | ≥ 97 % |
| Ops per part (L2) | ≤ 14 | ≤ 10 |
| Tokens per part (L2, end to end) | ≤ 15 k | ≤ 25 k |
| Wall-clock per part (L2) | ≤ 3 min | ≤ 3 min |
| Human corrections needed | 0 | 0 |

**Metrics — the things everyone else fails** *(these are the real scoreboard)*

| Metric | Target |
|---|---|
| Edits with zero collateral damage | ≥ 95 % (industry baseline: 40–46 %) |
| Parts still contract-green across their declared flex ranges | ≥ 90 % |
| Selector resolved the intended entity (human-verified) | ≥ 98 % |
| Hygiene audit ≥ 8/9 | ≥ 90 % |
| Silent wrong-entity selections | **0** — by construction, `expect` makes it impossible |

**Metrics — the human**

* Time from "I want X" to a part they would actually use.
* Fraction of AI-built parts a human then edits by hand successfully (the real test of
  the hygiene audit).
* Fraction of sessions where the AI correctly refused or asked instead of guessing.

**Ablations we should run**, because they tell us what to invest in next:
with/without `expect` · with/without contract · with/without views ·
with/without macros · with/without the collateral guard.
My prediction, from the literature: `expect` and the contract dominate; views contribute
least per token; macros dominate for Flash-class only.

---

## 17. The shape of the build, in phases

Workflow-level sequencing only — the detailed plan comes after you approve this one.

| Phase | Delivers | Proves |
|---|---|---|
| **0. Foundations** | shared feature path + parity test; canonical frame + conformance test; mass properties, shell, interference in the shim | The agent can do what a finger can, and the contract vocabulary has no holes |
| **1. Act** | op schema, validator, auto-repair, batch runner, undo integration, the ~30 core verbs | A scripted sequence builds a bracket headlessly |
| **2. Sense** | L0 diff, `part.tree`, `part.inspect`, `part.measure`, name derivation, selector engine with `expect` | A model can find and name anything without an index |
| **3. Prove** | contract storage + `part.check`, `part.guard`, `part.audit` | A model cannot claim success falsely |
| **4. Drive** | in-app chat + BYO token; system prompt encoding the playbook; the eval corpus | End-to-end: type a sentence, get a contract-green part |
| **5. See** | annotated views, highlight renders, `part.section` | The human and the model agree on what is on screen |
| **6. Extend** | `part.flex`, macros + standards tables, MCP adapter, `part.script` | Parametric integrity, weak-model performance, external hosts |
| **7. Assemble** | assembly verbs, joints, clearance and interference contracts | Multi-part products |

The ordering is deliberate: **Prove before Drive.** The moment a model can drive the app
it will produce plausible garbage, and if the proof layer is not already there we will
spend weeks chasing it by eye.

---

## Appendix A — Alternatives considered and rejected

| Option | Why it loses |
|---|---|
| **Generate CadQuery / build123d and import the result** | Loses the feature tree — the human gets a dumb solid they cannot edit. Kills the whole premise. Also a second kernel to ship. |
| **A new textual CAD language (KCL-style)** | Strongest for Opus, but the user's requirement is "without much learning" and Flash-class models will fight the grammar. Revisit as the phase-2 `part.script` door, sharing one semantics. |
| **Computer use / drive the GUI** | Every documented weakness at once: mental rotation, image diffing, coordinate estimation. Orders of magnitude slower. Fragile against any UI change. |
| **One MCP tool per operation (~60 tools)** | 6–15 k tokens of definitions before work starts; selection confusion grows with count. |
| **Let the model pick faces from a rendered image** | The single most-documented failure mode in the field. |
| **Fine-tune a CAD-specific model** | Fixes nothing about the interaction design, and locks us out of "swap in whatever model is best next year". The interface is the product. |
| **Auto-constrain every sketch the model draws** | Adds the over-constraint failure class for zero benefit — parametric primitives already encode the intent. |
| **Multi-agent (requirements / CAD / QA agents)** | The role split is real and useful, but it is a *prompt* decision, not an architecture decision. The contract + gates give the same discipline in one agent at a third of the cost. Keep as a later option for hard parts. |
| **Store selections as indices, resolve at build time** | The documented failure mode. Also the one this codebase already rejected in M158. |

---

## Appendix B — The critical passes this document survived

Recorded because the reasoning matters more than the conclusions.

**Pass 1 — "Code beats command-DSL, so write code."** Wrong inference. The measured 2.2×
was *CadQuery vs. a low-level command DSL*, and the confound is pretraining familiarity
and abstraction level, not syntax. The lesson that survives is **be declarative, be
high-level, be familiar** — which schema'd JSON ops with named parameters satisfy, with
guaranteed validity that free text cannot offer.

**Pass 2 — "Batch everything for token efficiency."** Half wrong. Batching *transport* is
free; batching *semantics* walks into the 40–46 % multi-feature edit failure. Resolution:
batch the wire, serialise the commit, report per op.

**Pass 3 — "Show it renders, let it judge."** Directly contradicted. Mental rotation
< 20 %; an imagery module only reaches 62.5 %; multi-view feedback shows limited
effectiveness; quantitative feedback beats VLM judgement. Renders survive only as an
annotated, cross-bound gestalt gate — and the highlight render, which is the one visual
task models are actually good at.

**Pass 4 — "Robust selection means good selectors."** Necessary, not sufficient. build123d
itself warns against static indices *inside* its selector chains. What actually closes the
gap is `expect` — turning selection into a falsifiable claim — plus echo-back of what was
resolved, plus the fingerprint anchor underneath. Three layers, not one.

**Pass 5 — "A correct part is the goal."** Too low a bar. CADEngBench shows 58 % of
executable models violate their requirements, and a correct part with an unmaintainable
tree fails the human anyway. Hence the contract (correct), flex (correct when changed) and
audit (correct and editable). Three different kinds of "good", checked separately.

**Pass 6 — "Just expose the app's existing session API."** Tempting and wrong: it is
dialog-shaped (fill a session, press apply), carries UI state, and would force the model
into a stateful interaction with a modal panel. The verbs must be stateless and
declarative. But the *feature construction path* underneath must be shared, or we get two
apps (§12.1).

**Pass 7 — "The frame is a detail."** No. `acos(n.y)` in `PartCamera` means screen-up is
+Y while every model's prior says +Z, and the app's own STL export says Z. Unaddressed,
every part comes out lying on its side and nobody can tell why. It is §5.4 and a blocking
decision, not a footnote.

---

## Appendix C — A worked session, end to end

**Human:** *"I need a bracket to mount a 30 mm sensor onto 40×40 aluminium extrusion.
Aluminium, as light as you can, under 250 g."*

```
① CLARIFY (1 message, 2 questions, defaults offered)
   – Sensor bolt pattern? default: ⌀30 H7 press bore, no bolts
   – Sensor axis horizontal (along the extrusion) or vertical? default: horizontal
   Human: "defaults"

② spec.set                                          ~400 tok
   params   plate_t=6 [4..10] · bore_d=8 fixed · sensor_d=30 fixed
            mount_pitch=100 · upright_h=40 [30..60]
   requires envelope ≤120×80×50 · mass ≤250 g · min_wall ≥3
            4 through ⌀8 @100 pitch · min internal radius ≥3 · manifold
   material AL6061 2.70 g/cm³        process 3-axis mill, 6 mm cutter

③ PLAN (text only)                                  ~120 tok
   datums → base_plate → upright → bore_1 → sensor_bore → edge_breaks → break_sharp

④ BUILD batch 1  [work.plane mid_yz, sketch.rect, extrude]        3 ops
   ✓ base_plate   Δvol +57 600 mm³   bbox 120×80×6   +6 faces
   ✓ contract 3/6 pass, 3 pending (no holes yet)                  ~150 tok

⑤ BUILD batch 2  [sketch.rect on mid_yz, extrude join]            2 ops
   ✓ upright      Δvol +9 600 mm³    bbox 120×80×46  +5 faces
   guard: silent                                                  ~140 tok

⑥ BUILD batch 3  [sketch points, hole ×4, hole sensor]            3 ops
   ✓ bore_1       4× ⌀8 through, resolved 4 of 4 expected
   ✓ sensor_bore  ⌀30 × 12 deep in upright.face.+y
   guard: silent                                                  ~180 tok

⑦ part.check                                                      ~250 tok
   ✗ wall  min 2.4 mm between sensor_bore and upright.side.-x  (≥3.0 required)
           driven by upright_w = 40;  fix: upright_w ≥ 42, or sensor_bore depth ≤ 10

⑧ REPAIR — contract-level, so back to PLAN, one op                ~90 tok
   param.set upright_w = 44
   ✓ rebuild   Δvol +1 920 mm³   guard: silent   contract 6/6 pass

⑨ BUILD batch 4  [fillet r=min(2,plate_t/3), chamfer 0.5×45°]     2 ops
   ✓ edge_breaks  resolved 4 of 4 · break_sharp resolved 18 of 18
   ✓ contract 6/6 pass                                            ~160 tok

⑩ PROVE                                                           ~700 tok
   flex  plate_t 4/6/10 ✓✓✓ · upright_h 30/40/60 ✓✓✓  all contract-green
   audit 9/9
   view  ortho4, annotated — bracket reads correctly, sensor bore on +Y

⑪ SHIP                                                            ~250 tok
   STEP + STL exported · thumbnail written · report to the human

   Totals   13 ops · 1 repair cycle · ~2 900 tokens of traffic
            + ~2 400 system/tools + ~3 200 for 4 annotated views
            ≈ 8.5 k tokens · ~95 s wall-clock · 0 human corrections
```

For contrast, the same part through a naive "60 MCP tools + dump the whole model after
every call + let the VLM look at renders" design: **~14 k tokens of tool definitions,
~6 k per state dump × 13, ~10 images**, and — on the published numbers — a coin-flip
chance the sensor bore ends up on the wrong face with nothing to catch it.

**≈ 8.5 k tokens versus ≈ 110 k, with a proof instead of a hope.** That is the plan.

---

## Appendix D — Sources

**Benchmarks and failure analysis**
- [Text2CAD-Bench: A Benchmark for LLM-based Text-to-Parametric CAD Generation](https://arxiv.org/abs/2605.18430) — CadQuery vs. command sequences (2.2×); L1–L4 invalidity 11 %→93 %; capability independence
- [BenchCAD: A Comprehensive, Industry-Standard Benchmark for Programmatic CAD](https://arxiv.org/pdf/2605.10865) — geometric similarity ≠ parametric understanding; editing harder than creating; multi-view feedback of limited effectiveness
- [CADEngBench: It Looks Like CAD, but Does It Work?](https://arxiv.org/html/2608.09296) — 58.1 % of executable code violates requirements; single-feature edits 99.6 % vs multi-feature 40–46 %; parameter misdirection; edit cascade failures
- [P3D-Bench: Benchmarking MLLMs for Parametric 3D Generation and Structural Reasoning](https://arxiv.org/pdf/2606.11152)

**Agent architectures**
- [Embodied CAD: Solver-Grounded LLM Agents for Parametric B-Rep Assembly Modeling](https://arxiv.org/html/2606.31252) — L0–L4 action stratification; operation-family prediction + deterministic resolver; family confusion / index ambiguity / coordinate-frame errors / reward sparsity
- [SPADA: A Verifiable Test-Driven Agent for Controllable Parametric CAD Assembly Generation](https://icml.cc/virtual/2026/poster/62308) — quantitative feedback beats VLM judgement; assembly 20.4 %→41.9 %; invalid rate 1.8 %
- [CADMorph: Geometry-Driven Parametric CAD Editing via a Plan-Generate-Verify Loop](https://arxiv.org/html/2512.11480) — edit only the segments that cause the discrepancy
- [Generating CAD Code with Vision-Language Models for 3D Designs (CADCodeVerify)](https://arxiv.org/abs/2410.05340) — four-angle visual verification; +5.0 % success, −7.3 % point-cloud distance
- [From Idea to CAD: A Language Model-Driven Multi-Agent System for Collaborative Design](https://arxiv.org/abs/2503.04417) — requirements / CAD / QA role split, V-model
- [Clarify Before You Draw: Proactive Agents for Robust Text-to-CAD Generation](https://arxiv.org/pdf/2602.03045) — ambiguity taxonomy; selective clarification
- [TOOLCAD: Tool-Using LLMs in Text-to-CAD with RL](https://arxiv.org/pdf/2604.07960) · [Seek-CAD](https://arxiv.org/pdf/2505.17702) · [Large Language Models for CAD: A Survey](https://arxiv.org/pdf/2505.08137)

**Spatial reasoning limits**
- [Limits of Spatial Imagery Reasoning in Frontier LLM Models](https://arxiv.org/html/2603.26779v2) — mental rotation 50–62.5 % vs ~79 % human; insensitivity to movement; imagery module reaches only 62.5 %
- [SpatialViz-Bench](https://arxiv.org/pdf/2507.07610) · [LRR-Bench](https://arxiv.org/pdf/2507.20174) · [Spatial Reasoning in MLLMs: A Survey](https://arxiv.org/pdf/2511.15722)

**Reference and selection**
- [Pointer-CAD: Unifying B-Rep and Command Sequences via Pointer-based Edges & Faces Selection](https://arxiv.org/pdf/2603.04337) — why index- and coordinate-based references both fail
- [build123d Selector Tutorial](https://build123d.readthedocs.io/en/latest/tutorial_selectors.html) and [Topology Selection](https://build123d.readthedocs.io/en/latest/topology_selection.html) — property-based selection; the warning against static indices

**Tool and context design**
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents) — consolidation, namespacing, response formats (65 % token reduction), actionable errors, evaluation
- [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Code execution with MCP — token reduction pattern](https://particula.tech/blog/code-execution-mcp-token-reduction-pattern) — up to 98.7 % reduction by batching work into code
- [Notation Matters: Token-Optimized Formats in Agentic AI Systems](https://arxiv.org/pdf/2605.29676) — format moves accuracy only −7.7 %…+2.7 %; JSON for constrained output

**Existing CAD-agent integrations**
- [autodesk-fusion-mcp](https://github.com/frankhommers/autodesk-fusion-mcp) — 13 tools; viewport capture, selection, script storage; no documented verification strategy
- [9 MCP Servers for CAD with AI](https://snyk.io/articles/9-mcp-servers-for-computer-aided-drafting-cad-with-ai/) · [AI in Onshape](https://www.onshape.com/en/blog/ai-artificial-intelligence-cloud-native-cad-pdm-platform)
- [Zoo — KCL: A Programming Language for Parametric CAD](https://zoo.dev/research/introducing-kcl) — text as the editable, machine-readable source of truth

**Modelling methodology**
- [The Resilient Modeling Strategy](https://www.engineering.com/the-resilient-modeling-strategy-2/) and [Review of Resilient Modeling](https://blogs.sw.siemens.com/solidedge/review-of-resilient-modeling/) — feature groups; fillets last; limiting parent/child chains
- [Parametric CAD modeling: An analysis of strategies for design reusability](https://www.sciencedirect.com/science/article/abs/pii/S0010448516000051)

---

*Prepared for review. Nothing here is built yet. If the workflow is right, the next
document turns §17 into an implementation plan with file-level detail.*
