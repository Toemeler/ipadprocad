# An AI modeling workflow for iPadProCAD

**Recommended workflow design · 18 September 2026 · revision 2**

**Repository:** [Toemeler/ipadprocad](https://github.com/Toemeler/ipadprocad)  
**Requested branch:** `claude/gallant-dirac-dwuge7`  
**Code baseline reviewed:** [`8141d2c5f3f8e6a1f96c4422523ed913e3f013c5`](https://github.com/Toemeler/ipadprocad/commit/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5)

This document replaces the supplied workflow proposal. It specifies what the AI can do, how it expresses intent, how it observes geometry, how it edits and recovers, and what evidence supports completion. It does **not** authorize or describe a file-by-file implementation. API names and examples below specify proposed behavior; they are not existing commands.

The review combined five successive research/design/critique passes, independent evidence and CAD workflow reviews, and inspection of the branch's principal app subsystems. The repository tree was inventoried; core source paths were inspected in depth. This was not a line-by-line audit of every file, a running-app test, or an executed CAD-agent benchmark. The worked examples are explicitly illustrative.

## Implementation status

**M441 shipped the first executable slice of this design.** What exists in the app today, and where:

| Element of the design | Status | Where |
|---|---|---|
| A declared operation set the model writes and the app executes | Built — 13 operations, fenced `cad` blocks, strict parse | `frontend/lib/ai/ai_actions.dart` |
| Native features, not an agent-only representation | Built — sketches, extrude, revolve, fillet, chamfer, feature edit/rename/delete go through the same `PartFeature` timeline and `recomputeAllFeatures` as the user's own tools | `frontend/lib/ai/ai_cad.dart` |
| Reversible, coherent changes: one intention, one transaction, one undo | Built — a block is snapshotted, rolled back whole on any failure, and journalled as one `Ctrl+Z` | `AiCad.run`, `AppState.aiSnapshot`/`aiRestore`/`aiJournal` |
| Question-directed observation | Partial — `describe_part` plus a measured report (timeline, bodies, volumes, bounding box) after every block. No sections, no aligned inspection views, no witness geometry | `AiCad._state` |
| Explicit evidence for completion | Partial — the report separates what was asked for from what the kernel built, and states its own coverage. There is no checker framework, no brief, no requirement traceability | `AiCad._commitFeature` |
| A persistent design brief | Not built | — |
| A typed document-wide parameter graph | Not built | — |
| Interfaces, protected geometry, damage reports | Not built | — |

References survive edits the way the app's own selections do (`ProfileSel`, `EdgeSel` fingerprints); the agent never names a topological index, for the reason §8 gives. Everything below the line in the table is still a plan, and the sections that describe it are written as design, not as description of the code.

## Reading guide

- [1. The recommendation](#1-the-recommendation)
- [2. What changes from the supplied plan](#2-what-changes-from-the-supplied-plan)
- [3. What the branch actually provides](#3-what-the-branch-actually-provides)
- [4. The division of work](#4-the-division-of-work)
- [5. From an idea to a design brief](#5-from-an-idea-to-a-design-brief)
- [6. The modeling loop](#6-the-modeling-loop)
- [7. What the AI can do](#7-what-the-ai-can-do)
- [8. References that survive edits](#8-references-that-survive-edits)
- [9. Frames, units, and tolerances](#9-frames-units-and-tolerances)
- [10. Native sketches, parameters, and recipes](#10-native-sketches-parameters-and-recipes)
- [11. How the AI sees and senses](#11-how-the-ai-sees-and-senses)
- [12. What a successful check means](#12-what-a-successful-check-means)
- [13. Editing without unnoticed damage](#13-editing-without-unnoticed-damage)
- [14. Failures and recovery](#14-failures-and-recovery)
- [15. Advanced geometry and assemblies](#15-advanced-geometry-and-assemblies)
- [16. Product development and human collaboration](#16-product-development-and-human-collaboration)
- [17. Efficiency across model sizes](#17-efficiency-across-model-sizes)
- [18. Worked creation and edit](#18-worked-creation-and-edit)
- [19. Harder workflow walkthroughs](#19-harder-workflow-walkthroughs)
- [20. Evaluation and acceptance](#20-evaluation-and-acceptance)
- [21. Workflow delivery order](#21-workflow-delivery-order)
- [22. Decisions and remaining uncertainty](#22-decisions-and-remaining-uncertainty)
- [Appendix A. Five review rounds](#appendix-a-five-review-rounds)
- [Appendix B. Research corrections and sources](#appendix-b-research-corrections-and-sources)
- [Appendix C. Source inspection map](#appendix-c-source-inspection-map)

## 1. The recommendation

Build a **native, inspectable design workspace** in which an AI can express a coherent modeling intention, have the app execute it deterministically, inspect the resulting geometry through targeted measurements and aligned views, and accept or revise the result without losing the last good model.

The central interaction is:

> **Describe the intended change and what must stay true → build a candidate → receive evidence about the actual result → commit it or repair it.**

The model chooses a design strategy. The app owns geometry, units, reference resolution, computation, transaction boundaries, and evidence provenance. The user owns the brief and design preferences. The app does not magically understand engineering intent; the model does not become an accurate geometric solver merely because it can call tools.

The recommended system has five closely connected elements:

1. **A persistent design brief.** User requirements, assumptions, protected interfaces, editable parameters, and unresolved decisions remain available across sessions.
2. **Native modeling operations at several levels.** Compact primitives and reusable feature recipes handle common work; complete native operations preserve expressive power and human editability.
3. **Reversible, coherent changes.** A change may contain several dependent operations. It produces one candidate and, when accepted, one atomic document revision and one understandable undo action.
4. **Question-directed observation.** The AI asks about a dimension, interface, cavity, selection, silhouette, or change. The app supplies the relevant facts, witness geometry, and views.
5. **Explicit evidence for completion.** Successful construction, dimensional correctness, parameter behavior, visual quality, and physical suitability are separate claims with separate evidence.

This should make good modeling easier for both a fast model and a highly capable model. It does not promise that every model will solve every part. Difficult design decisions remain difficult, but the interface removes avoidable bookkeeping, spatial guessing, and repeated low-level work.

**The quality goal is an editable design that satisfies the user's stated purpose within declared verification coverage.** Minimum tool calls, attractive renders, and a passing kernel check are useful intermediate results, not that goal by themselves.

## 2. What changes from the supplied plan

Keep its strongest ideas: native features, meaningful names, compact feedback, explicit requirements, numerical sensing, parameter variation, and a common path for human and AI edits. Several proposed guarantees need substantial correction.

| Supplied proposal | Revised decision | Why it matters |
|---|---|---|
| Pictures are never evidence; render tools plateau at 62.5% | Combine computed geometry with carefully aligned visual evidence | The cited spatial study also reports 85–97.5% with canonical alignment on its particular task. That is useful tool-design evidence, not a general CAD success rate. |
| `expect` makes wrong selections impossible | Count + scoped identity + provenance + geometric conditions + revision | The wrong unique face still passes `expect: 1`. |
| Geometric fingerprints solve persistent naming | Use fingerprints as one source of evidence, with explicit loss/split/merge handling | Symmetric entities and topology changes defeat simple nearest-match rules. |
| One feature per edit | One coherent design intention per transaction | A correct change can require several coupled parameter or feature updates. |
| Commit each operation in a batch | Stage the entire logical change; commit atomically | A failed batch must not leave half a modification accepted. |
| Every error carries a working fix | Facts, diagnosis confidence, and bounded candidate repairs | Kernel failures and design conflicts do not always have a known fix. |
| Rebuild signatures prove collateral changes | Signatures identify invalidated work; protected geometry is checked separately | Equal volume and bounding box can hide a relocated hole. |
| Recheck everything on every rebuild | Invalidate immediately; recompute checks according to dependencies and cost | Freshness remains explicit without making every keystroke expensive. |
| A section proves minimum wall thickness | A section proves facts on that section; broader claims need broader methods | The thin region may be elsewhere. |
| Sampled parameter sweep proves a range | Publish tested configurations, boundaries, and unresolved coverage | Finite samples do not establish continuous validity. |
| Normally omit constraints | Let compact primitives generate native editable constraints or equivalent native dependencies | Human edits and future parameter changes must preserve intent. |
| Universal Z-up agent frame requires a blocking choice | Preserve document coordinates; publish explicit part/workplane/view/export frames | The app deliberately uses Y-up, which is not inconsistent with right-handed XYZ. |
| Arbitrary raw kernel escape hatch | Advanced operations must still obey native history, validation, and undo | Bypassing these rules defeats the intended workflow. |
| “95 seconds / 8.5k tokens / zero errors” example | Measured evaluation plan; illustrations labeled as illustrations | These are not established performance results. |

No claim of unprecedented invention is needed. Existing systems already have historical queries, solver-grounded agents, executable geometry checks, reusable CAD procedures, and AI editing. The opportunity is to combine them into a dependable experience in this app. [Onshape queries](https://cad.onshape.com/FsDoc/library.html#module-query.fs), [Embodied CAD](https://arxiv.org/html/2606.31252), [CADTests](https://arxiv.org/html/2605.07807).

## 3. What the branch actually provides

### 3.1 Useful foundations

The application has a substantial native modeling base. It is not necessary to replace it with a separate text-to-mesh generator or import every AI result as an opaque solid.

| Subsystem | Observed foundation | Workflow consequence |
|---|---|---|
| Solid modeling | OCCT shim; extrusion, revolution, sweep, loft, coil, booleans, blends, direct edits, patterns and exchange functions | Build on native parametric features and existing kernel behavior. |
| Feature history | Fourteen concrete `PartFeature` types, serialization, dependency-sensitive rebuilds, End-of-Part rollback and pattern-occurrence suppression | AI changes can be visible and editable in the same feature tree. |
| Sketching | Geometric entities, profile finding, constraints, dimensions, solver, workplanes and projections | Offer compact intent-level sketch operations with native expansion. |
| Parameters | Rich expression evaluation for sketch parameters and dimensions | Useful base, but a document-wide typed parameter graph is additional work. |
| Geometry metadata | Tessellation maps to topological faces/edges and analytic surface/curve records | Cross-link text, highlighted geometry, and numerical observations. |
| Measurements | Analytic answers for supported relations; mesh/polyline fallbacks for others; kernel volume | Preserve distinctions between analytic, numerical, sampled and approximate results. |
| Assembly | Occurrences, placement, constraints, joints, patterns, driving and representations | Treat an occurrence separately from its source part; expose assembly-specific evidence. |
| Views | Camera control, section views, display styles, offscreen still paths and CPU fallback | Reuse rendering foundations; add controlled inspection views and evidence binding. |
| Documents | Native part/sketch/assembly containers, referenced/imported geometry, exchange paths | Save the editable model plus design intent and evidence provenance. |
| Existing tests | Numerous frontend and native tests, including headless state/kernel fixtures | Reuse testability; mocked kernels alone cannot establish real geometry correctness. |

### 3.2 Important corrections to the original code assessment

**There is no uniform transactional agent surface.** Major feature authoring uses `AppState` sessions, but the app also has direct commands and headless domain functions. The design requirement is shared operation semantics, not mechanically exposing dialogs or assuming all behavior passes through one existing function.

**Face and edge matching have different safeguards.** `EdgeSel.bestMatch` has displacement and ambiguity checks. `FacePick` resolution uses a nearest finite match, consumes that candidate and re-anchors; it does not inherit the same protection. Agent reference reliability cannot be claimed from `EdgeSel` alone. [Selection source](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L2023).

**Expression text is not the same as a reactive feature binding.** The sketch expression system exists, but feature dialogs also use a more limited value parser; feature records store evaluated values and expression strings. The proposed ability to change `plate_t` and reliably update every dependent feature must be established explicitly. The expression engine also states that it does not implement dimensional algebra. [Sketch expressions](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/params.dart#L1), [feature value parser](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L9367).

**Existing undo is not sufficient for agent transactions.** Part undo has a narrower existing scope. Some edit paths mutate before rebuilding, retain a failed edit, and save. Some command return values indicate that the command ran even though a feature has a compute error. Last-good geometry can remain visible. A successful tool response must therefore examine document and geometry state, not simply wrap a GUI method's Boolean result. [Edit path](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L12919).

**Y-up is an intentional app convention.** The modeling source describes a Y-up world. Import code maps several Z-up mesh formats into it. Camera, workplane, imported data and export conventions must be reconciled, but `acos(n.y)` alone does not demonstrate a defect. [World frame](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L64), [mesh conventions](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/mesh_io.dart#L384).

**Sections and still images are foundations, not finished AI perception.** Existing sections use solid-cut machinery for views. They are not a published symbolic section/thickness API. Offscreen rendering exists; stable inspection framing, geometry labels, clean/annotated pairs, revision stamps and renderer conformance remain requirements.

**Feature gaps must be stated precisely.** A general shell tool and standalone draft workflow were not found in the inspected surface; extrusion taper using OCCT draft machinery does exist. Appearance materials are not density/material-property records. General wall certification, mass/center-of-mass reporting, interference/clearance analysis, and contract evaluation cannot be assumed present merely because OCCT offers building blocks.

**Export is another operation to verify.** Existing paths can export surviving geometry while features are broken, and formats differ in body selection. The AI needs an explicit output scope, freshness gate, unit/orientation contract and format-specific round-trip checks. A file existing is not sufficient success evidence.

These are reasons to preserve and strengthen the app, not reasons to create a separate modeling engine. Exact implementation work belongs in the next planning stage.

## 4. The division of work

LLMs are often useful at interpreting descriptions, proposing decompositions, writing structured operations, adapting examples, explaining tradeoffs and repairing a design when given good feedback. Reliability varies by model, task and context. None of these strengths should be treated as an unconditional guarantee.

| Responsibility | Primary owner | AI-facing result |
|---|---|---|
| Purpose, taste, actual mating requirements | User, interpreted by model | Brief with sourced requirements and explicit assumptions |
| Feature strategy and design alternatives | Model, supported by reusable procedures | Short named feature/dependency plan |
| Arithmetic, unit conversion, transforms | App | Evaluated values, typed units, named frames |
| Entity lookup and current topology | App | Resolved selection with witnesses and uncertainty |
| Constraint solving and geometric construction | App/kernel | Candidate geometry and structured failures |
| Geometric tests and comparison | App | Result, method, scope, revision and coverage |
| Visual similarity, proportions and design critique | Model and user, aided by controlled views | Visual findings distinguished from dimensional claims |
| Candidate acceptance and state integrity | App policy + model judgment within brief | Atomic commit, evidence receipt, undo |
| Physical suitability | Appropriate analysis/test process | Supported result or explicit unresolved requirement |

Do not make the model count hundreds of edges, transform coordinates mentally, generate thousands of repeated elements, or estimate a clearance from a perspective image. Do not expect the app to decide what “comfortable,” “elegant,” or “appropriate for this load” means without a defined evaluation.

A fast model gets the same reliable operations and checks as a stronger model. A stronger model may formulate better designs or use more advanced operations; it gets no exemption from validation.

## 5. From an idea to a design brief

### 5.1 Start with the intended use

The first useful output is a compact design brief, not a long questionnaire or an immediate detailed solid. Establish:

- What the object does and what it touches or mates with.
- Given dimensions, references, images, existing parts and protected geometry.
- Important use conditions: access, motion, assembly, cleaning or installation where relevant.
- Manufacturing route, material, loads and tolerances when the user supplies them or they affect a required outcome.
- What may vary and what is already fixed.
- Whether the current goal is a concept, a dimensionally specified model, or a design requiring physical validation.

Ask only when the missing answer changes a consequential decision that cannot be safely treated as provisional. A sensor's mounting interface is consequential; a cosmetic edge radius often is not. Offer choices when helpful. Do useful independent work while awaiting an answer.

There is no universal maximum of one clarification round. A question limit is a usability preference, not a reason to invent an interface. Equally, do not demand manufacturing information for a shape exploration that does not need it yet.

### 5.2 Make requirements traceable

Each requirement has:

| Field | Meaning |
|---|---|
| Identity and source | Stable ID; exact relevant user wording or imported interface/reference |
| Interpretation | What it means for this model, including frame and scope |
| Priority | Must satisfy, preference, assumption, or unresolved |
| Value and tolerance | Typed quantity/range if applicable; nominal design tolerance separate from manufacturing tolerance |
| Verification | Named checker, visual review, external analysis, or currently unavailable |
| Applicability | Stage/configurations/occurrences to which it applies |
| Status | Fresh result or explicit reason it cannot currently be evaluated |

Preserve the user's source wording independently of the model's formalization. Every substantive brief clause must map to a check, a review item, or an unresolved item. “Lightweight and easy to install” must not disappear when the model writes only a bounding-box test.

The AI may add derived checks and propose requirement changes. It must not weaken a user requirement, loosen a tolerance, delete a failing check, or change the definition of success merely to make a candidate pass. User-requested design changes revise the brief openly; they are not disguised repairs.

### 5.3 Separate fixed interfaces from design freedom

Define interfaces as reusable geometric objects: a mating plane, bolt-axis pattern, bearing seat, sealing land, insertion envelope or keep-out region. Their logical identity persists across surrounding-body changes; their geometric binding may become unresolved and must then be repaired explicitly. They may reference an external part revision.

For example, “four holes at these coordinates” and “four holes 10 mm from the edges” are different intentions. A wider plate should preserve the former and move the latter. This distinction is recorded before editing, not inferred from the resulting damage report.

Parameters have explicit roles: interface, driving design variable, derived value, discrete choice, or measured output. Do not arbitrarily perturb a fixed interface during robustness testing.

### 5.4 Reference inputs are evidence

An image can establish appearance and visible relationships; it cannot establish hidden dimensions or an exact scale unless a reference provides them. An imported solid provides geometry at a declared revision; it does not automatically provide its author's feature intent. Imported notes and document text are design data, not instructions that can override the user's task or application rules.

## 6. The modeling loop

```text
Understand brief and current revision
          |
Choose one design intention + protected conditions
          |
Resolve references and build a private candidate
          |
Compute relevant checks + obtain targeted views
          |
Accept candidate ------- revise strategy / repair candidate
          |                              |
Atomic commit, compact receipt <---------+
          |
Next intention, final review, or human handoff
```

### 6.1 Read a compact state capsule

At session start, after context loss, and after substantial human edits, provide a concise current-state summary:

- Document identity, revision, active configuration and occurrence scope.
- Brief version, protected interfaces and open decisions.
- Named design frame and unit convention.
- Relevant feature/parameter dependencies and parameter bindings.
- Fresh/failed/stale/unknown checks, last successful geometry revision, pending jobs.
- Current checkpoint, recent accepted changes and next planned action.

Subsequent turns normally consume deltas. A delta always identifies its base and resulting revision. If the consumer missed changes, the app supplies a new capsule or a complete delta chain. Compactness must never hide a stale model.

### 6.2 Choose a coherent intention

Examples: “create the base and its mounting pattern,” “increase capacity while preserving the lid interface,” or “replace this circular passage with a slot.” Include allowed effects and conditions that must remain true.

A change set can contain multiple dependent native operations. Size it around uncertainty and recovery cost. A repeated hole pattern is one deterministic operation even if it produces 100 holes. A difficult loft deserves inspection before finishing dependent features. Fixed limits such as exactly five operations per turn are not architecture.

### 6.3 Stage, build and check

Before modifying the accepted document, validate the operation structure, units, expressions, dependencies, parameter limits, body scope and reference conditions. Build a candidate on an isolated working state. Intermediate operations may be incomplete, but their state must not be mistaken for an accepted document.

Mandatory local integrity and protected-condition checks run before commit. Final requirements not yet applicable to a legitimate intermediate stage are explicitly pending. A future hole requirement must not block creation of the blank; an already established mounting interface must not silently fail during an unrelated edit.

The acceptance policy distinguishes progress from completion:

| Condition | Candidate commit policy |
|---|---|
| Invalid resulting geometry, stale reference, or failed designated hard interface protection | Block commit to the accepted model; retain the candidate for repair |
| Required protection cannot be evaluated | Block an ordinary protected edit; offer a clearly provisional candidate or an explicit recovery scope |
| Requirement belongs to a future stage | Permit intermediate progress with `PENDING` status |
| Engineering/visual evidence is incomplete within an agreed concept scope | Permit a valid geometric revision labeled provisional; preserve the unresolved claims |
| Existing model is already broken | Use the explicit repair workflow in §14, not an ordinary-success path |
| Final suitability claim | Require fresh evidence and appropriate coverage for that exact claim |

A provisional saved candidate is not silently promoted to a verified design. This distinction lets concept work proceed without calling an unknown physical property a pass or repeatedly asking for permission to do ordinary modeling.

### 6.4 Accept efficiently

For a routine unambiguous operation, the app can build, check and commit in one request under the agreed policy. A separate preview/commit round trip is needed only when the model or user must inspect a candidate, choose between alternatives, or resolve consequential uncertainty.

Uncertain candidates return an evidence bundle. The AI can request additional observations, patch the candidate, discard it, or commit it after its gates pass. Human permission is not required for every reversible step within an already authorized modeling request.

### 6.5 Commit and recover precisely

A committed change has a base revision, request ID, normalized inputs, affected entities, requirement version and evidence references. Repeating the same request ID returns the same outcome; it does not create a second hole. Reusing the ID with different inputs is rejected.

Before commit, compare the base revision with the live document. A concurrent human change triggers revalidation or a conflict report. Do not overwrite it. Independent read-only queries can run together; accepted mutations are serialized.

One accepted logical change becomes one meaningful undo step. Reverting an older AI change after later human edits requires dependency/conflict handling, not blindly invoking global undo. A cancellation or timeout leaves a known accepted revision; if a native computation cannot stop immediately, discard its late candidate result.

Long operations expose job state and retrieval/cancellation. A lost network reply does not leave the AI guessing whether a mutation happened.

These artifacts scale with the task. The app derives and reuses the brief, dependency context and routine checks; the model supplies only changed intent and missing information. A simple dimension edit should normally be one short typed request and its receipt. Detailed alternatives, engineering analysis and visual rubrics are triggered by the task's requirements or uncertainty, not required anew for every primitive.

## 7. What the AI can do

### 7.1 A small entry surface with progressive discovery

Use a small set of distinct entry points, with operation-specific schemas loaded when needed. The following seven families are a recommended starting design, not an empirically optimal tool count:

| Entry family | Purpose |
|---|---|
| `cad.context` | Current document, brief, capabilities, revision capsule and relevant history |
| `cad.help` | Discover a capability, its schema, preconditions and short native examples |
| `cad.query` | Resolve entities, inspect dependencies, measure, section, compare or render |
| `cad.change` | Create/edit/stage/commit/discard a coherent change using native operations |
| `cad.review` | Evaluate brief coverage, integrity, protected conditions, parameter behavior and final readiness |
| `cad.history` | Checkpoints, transaction inspection, undo/redo and conflict-aware revert |
| `cad.output` | Save/open/import/export and manage explicitly selected deliverables |

A family is not one enormous untyped JSON dictionary. Once the relevant operation is selected, its arguments are narrow, validated and documented. Models capable of direct typed tools may receive a small focused set of operations instead. Compare both presentations in evaluation while keeping identical semantics.

Within a change set, operations expose documented typed output ports and can declare local aliases. Later operations may reference earlier outputs, such as a new sketch region or extruded body, without another model round trip. Validate dependency order, result type and multiplicity. These aliases do not predict arbitrary future face names; durable identities and current topology handles are published in the result.

The discovery result includes availability on this device/document, supported modes, units, failure states, related operations and one successful example. It explicitly reports whether a real geometry kernel is linked, its version/ABI, and whether a result is only a stored feature definition without computed geometry. The model should not discover missing shell support by spending five calls generating invalid shell requests.

Tool family names do not create exceptions to transaction rules. Import and document replacement are explicit revisioned changes. Opening a document returns a fresh capsule and invalidates context-dependent pending actions. Save persists a specified accepted or explicitly provisional revision. Export pins geometry/configuration/body scope; undoing the document cannot retract an externally delivered file. External sharing remains a separate authorized action.

### 7.2 Full app coverage is a measured obligation

The final target is coverage of every meaningful app action, not merely common extrusion workflows. Coverage is tracked by action and option, including edit/cancel/error/history behavior.

| Domain | Required AI abilities |
|---|---|
| Documents | Create, open, rename, duplicate, save, inspect references, import/export, choose scope and units |
| Sketches | Planes, entities, primitives, dimensions, constraints, projection, trim/extend, patterns, construction geometry, layers, text and supported specialty tools |
| Features | Create and edit every supported feature and option; explicit target bodies; suppression, deletion, reordering and rollback markers where supported, with missing native support identified |
| Direct modeling | Inspect/imported geometry; supported face/body modifications; retain import provenance |
| Work geometry | Create, modify, query and reference planes, axes and points |
| Assemblies | Place and replace occurrences; joints/constraints; ground, pattern, drive and inspect supported degrees of freedom |
| Observation | Selection, measurement, sections, named views, camera framing, hiding/isolation, exploded/context views where available |
| Presentation | Names, visibility, display mode and appearance; keep appearance separate from engineering materials |
| Recovery | Cancel candidate/job; checkpoint; undo, redo and targeted revert; recover/reopen a session |
| App utilities | Discover relevant settings/status; expose remaining user operations with their actual availability and normal authorization |

Not every action should be loaded into the prompt. The registry remains complete while the visible subset stays task-relevant. Privacy-sensitive actions such as sharing/uploading remain explicit user intentions, not side effects of modeling.

Parity is about equivalent outcomes, not reproducing every touch gesture. “Create a centered rectangle” replaces a sequence of taps. Every AI-created result must be inspectable in the GUI, editable through native controls, and included in appropriate history.

A capability is not counted as complete merely because it has a tool name. It needs valid inputs, editable native output, failure behavior, cancellation where relevant, undo and save/reopen coverage. Missing coverage remains visible until filled; the first release cannot honestly claim full parity.

### 7.3 Three levels of expression, one modeling system

1. **Intent recipes:** a hole pattern, boss, flange, mounting plate, stepped shaft or a supported enclosure construction. Parameters and intended relationships are compact.
2. **Native operations:** sketches, extrude/revolve/sweep/loft, booleans, patterns, blends, work features, assemblies and direct edits. These are the general solution path.
3. **Advanced composition:** constrained code or a text projection of the native operation graph, if evaluation demonstrates value. It compiles to the same operations and transaction/evidence rules.

Do not reject code categorically: strong and small models can both benefit from familiar declarative abstractions. Do not require arbitrary code execution to perform ordinary CAD. A raw kernel call that cannot be represented, edited, replayed or undone natively is outside the accepted modeling path.

## 8. References that survive edits

### 8.1 Separate identity, label and selection intent

There are three different objects:

- **Logical identity:** stable IDs for the document, body, feature, sketch entity, datum, parameter, occurrence and declared interface.
- **Human-readable label:** useful names such as `sensor_seat` or `mounting_plane`. Renaming changes the label, not identity.
- **Resolved topological selection:** the faces/edges that currently satisfy a reference, with handles valid for a particular revision and scope.

Never derive persistent identity solely from an entity's ordinal, position, largest-area ranking or current display name. The AI normally sees meaningful labels and short handles; it copies returned handles without inventing them. Temporary IDs are useful when scoped and revision-bound. The prohibition should be on unstable assumptions, not on numbers themselves.

### 8.2 Declare how a reference follows change

| Binding behavior | Intended meaning | Example |
|---|---|---|
| Identity/lineage | Follow this entity's supported descendants; stop if the required identity is lost | A specific functional mating surface |
| Semantic set | Re-evaluate this design role and allowed multiplicity after changes | All outer rim edges of a repeated boss family |
| Geometric query at this revision | Resolve an exploratory property query; do not imply persistent meaning | Candidate planar faces normal to a datum |
| Datum/interface | Refer to explicit design geometry rather than incidental B-Rep topology | Sketch on a mounting plane even after its visible face is split |

Historical provenance and property queries are complementary. Onshape already distinguishes these ideas and provides tracking mechanisms; the lesson is to make reference intent explicit. [Onshape modeling queries](https://cad.onshape.com/FsDoc/modeling.html).

### 8.3 Resolve with several independent conditions

A mutation selection states its body/occurrence scope, intended role or provenance when available, geometric predicates, expected multiplicity and relevant relationships. Conditions can include orientation, radius, adjacency, datum distance, inclusion/exclusion regions and membership in an interface.

Example, shown schematically:

```json
{
  "scope": "fixture/plate_occurrence",
  "reference": "mounting_interface.hole_axes",
  "binding": "interface",
  "expect": {"count": 4},
  "require": [
    {"parallel_to": "plate_frame.n"},
    {"pattern": "mounting_pattern"},
    {"diameter": "hole_diameter"}
  ],
  "at_revision": "r12"
}
```

`expect` is one constraint. A correct count cannot certify the intended face. Unbounded `any` is useful for discovery, but broad mutations need an explicit scope and a defensible set definition. Pattern count can be an expression if the intent allows it to change.

### 8.4 Return a selection receipt

The resolution result includes selected handles and aliases, role/provenance, scope, count, discriminating properties, and any ambiguity or topology change. A highlight view is available for interpretation. Candidate lists are grouped and paginated when necessary.

A face split is reported as one-to-many; a merge as many-to-one; deletion as loss. If a consuming operation accepts a set or only needs a support plane, it can resolve appropriately under its declared policy. Otherwise, it requires a revised reference. Do not assign the old name to whichever patch happens to sort first.

### 8.5 Disagreement blocks that mutation

If authoritative lineage and semantic conditions imply competing targets, or required conditions fail, return `REFERENCE_CHANGED` or `AMBIGUOUS`. Show the disagreement. Do not choose whichever mechanism happened to return a match, silently re-anchor, or proceed with only a warning on a protected interface.

A fingerprint is a fallible geometric hint. Expected movement or size change under the declared edit is not itself a contradiction. Evaluate it in the appropriate local/occurrence frame and against allowed changes. Strong supported lineage and role conditions can retain a reference despite expected fingerprint drift; an absent weak hint need not force a rebind. Unresolved competing identities or unsupported split/merge transitions still block the mutation.

An agent can explicitly rebind a reference when observations and the brief establish the new target. Ordinary justified rebinding does not require a human interruption. Unresolved functional ambiguity does.

The attainable guarantee is that known ambiguity, stale handles and violated selection conditions block the mutation. The system cannot guarantee that a wrongly formalized intention is impossible.

## 9. Frames, units, and tolerances

### 9.1 Preserve the model; name the design frame

Do not migrate the existing app to Z-up as a prerequisite. Every document retains its native frame. For a new design, publish a named right-handed part frame chosen around its function, such as `u = length`, `v = width`, `n = thickness`. Record the transform to document world coordinates.

The AI can say “extrude along `plate_frame.n`” or “normal to `mounting_plane`.” Raw coordinates always name their frame. The app performs transformations between part, workplane, occurrence, assembly, camera and export frames.

A sketch observation provides origin, positive u/v directions, normal and handedness. A view has an explicit viewing direction and screen-right/up basis. “Top” refers to a named frame or view convention, never an unspecified universal +Z. Mirrored occurrences require explicit reflection handling, not an assumed ordinary rotation.

Conformance fixtures should use asymmetric geometry with unequal dimensions and a marked corner. Check sketches, views, transformed/mirrored occurrences and every exchange format. A symmetric box alone can conceal handedness and axis swaps.

### 9.2 Quantities are typed

Operations distinguish length, angle, count, ratio, area, volume, mass and density. Units are explicit at boundaries and normalized by the app. Expressions use typed parameters with documented scope; `length + angle` is invalid. Counts require integer semantics and range checks.

The existing expression parser is a useful starting point, not already this system. Its multi-argument function syntax uses semicolons; examples must follow the actual chosen grammar or provide a normalized expression form. The AI should obtain expression examples from the capability description, not assume a Python grammar.

### 9.3 Keep tolerances separate

- Kernel/computation tolerance: numerical geometric processing.
- Selection tolerance: matching a geometric predicate.
- Approximation error: tessellation, sampling or numerical integration.
- Design tolerance: acceptable model deviation for a requirement.
- Manufacturing tolerance: allowed physical variation and fit.
- Display precision: how many digits are shown.
- Healing allowance: permitted geometric modification during repair.

These are not interchangeable. No universal 0.05 mm gap healing rule is appropriate. A designed slit must remain a slit. Automatic healing is allowed only for a clearly identified accidental defect within an approved allowance; record the modification and recheck affected requirements.

## 10. Native sketches, parameters, and recipes

### 10.1 Express sketch intent compactly

The normal path uses rectangles, circles, slots, polygons, symmetric profiles, named point patterns and supported constrained paths. The app creates native geometry and the constraints/dependencies needed to express their declared behavior.

For a centered rectangle, “width W, height H, centered on origin” should produce an editable definition preserving rectangularity, size and centering. The model need not manually emit every coincident/horizontal/equal constraint. Raw entities and explicit constraints remain available for less regular designs.

An intentionally underconstrained sketch is allowed, but its free degrees of freedom are identified. A fully specified sketch must not be reported stable while hidden freedoms remain. Sketch diagnosis should identify conflicting or redundant constraints and a localized explanation; a minimal conflict set is useful when the solver can provide one, not a guaranteed capability.

Profile inspection returns named regions, holes, construction exclusions, loop closure and self-intersections. “Largest profile” is an exploratory selector, not a default substitute for the intended region. Avoid dumping dense sampled point lists unless an advanced operation needs them.

### 10.2 Make parameters operational

The document maintains a dependency graph linking parameters, sketch dimensions, feature inputs, interfaces and measured outputs. An expression is persisted as an expression, not only as its evaluated number. Reopening, changing a parameter, undoing and rebuilding must preserve the binding.

Publish a compact binding table when requested:

```text
plate_t  -> base extrusion depth -> hole passage length
pitch_u  -> mounting axis positions, fixed interface
edge_r   -> external corner finish only
mass     <- measured volume × material density, not a driving value
```

Missing references, cycles and failed evaluation are explicit. A frozen last-good number must not masquerade as a fresh parameter evaluation. Parameter edits test both the intended dependency and protected non-dependencies.

### 10.3 Recipes are editable, versioned procedures

A recipe is a parameterized sequence of native operations with a documented purpose, preconditions, expansion, outputs, dependencies and checks. It is useful to all model tiers. Start with reliable geometric building blocks and repeated interface patterns; extend to validated part families as evidence supports them.

Store recipe version and instance parameters with the expansion. A user can inspect every child feature. Define ownership: either an edit maps back to the recipe's parameters, or the instance becomes a customized native group. A later recipe rebuild must not overwrite manual child edits silently.

Recipe retrieval should use purpose, topology and constraints, not just similar names. A housing recipe that assumes injection molding may be wrong for a machined enclosure. Standards-backed features record standard/version, thread or fastener variant, fit/clearance class and relevant process assumptions. “M4” alone does not specify every dimension. Do not infer a press fit from “30 mm sensor.”

Recent work such as ArtisanCAD supports investigating reusable parametric procedures; its benchmark result does not establish a success rate for this app or its target models. [ArtisanCAD](https://arxiv.org/abs/2607.05750).

### 10.4 Keep feature history resilient without rigid superstition

Prefer stable datums and interfaces, clear parameter ownership, short understandable dependencies and decorative finishing late. These are defaults. Functional rounds, drafted core shapes, blend-dependent surfaces and manufacturing-specific operations sometimes belong earlier. Audit actual fragility and editing behavior, not a fixed rule that every fillet must be last or every feature may have at most two parents.

Suppressed features and unused sketches can be intentional alternatives/reference geometry. Label them rather than automatically deleting them to improve a hygiene score.

## 11. How the AI sees and senses

The objective is to let the model understand **what exists, what it does, and how it reads visually** without reconstructing the world from a long list of triangles or guessing depth from one image.

### 11.1 Ask an observation question

Prefer requests such as:

- “Show the mounting interface and verify its hole pattern.”
- “Measure the remaining material between this passage and the outer wall.”
- “Show whether the handle looks balanced relative to the base.”
- “Compare this edit with the accepted design, keeping the same views.”
- “Can the specified fastener and driver approach along this axis?”
- “Where does this parameter change the geometry?”

The app translates supported questions into declared observation recipes: entity queries, measurements, sections, views and comparisons. Each recipe has a defined result and cost class. The model can request the underlying observations directly when necessary. Natural-language questions do not grant an opaque second agent permission to improvise unverifiable measurements.

### 11.2 A compact evidence bundle

An observation carries:

| Field | Purpose |
|---|---|
| Revision/configuration | Identifies the candidate or accepted geometry actually inspected |
| Definition and scope | Distinguishes axis distance from surface clearance, local thickness from global minimum, part from occurrence |
| Value and units | The measured quantity, including relevant extrema |
| Method | Analytic relation, B-Rep numerical computation, mesh estimate, sample set, image review or external analysis |
| Accuracy/coverage | Bound or tolerance when known; otherwise explicit approximation and limitations |
| Witnesses | Entities and locations supporting the result, available for highlighting |
| Status | Complete, partial, unavailable, stale, or failed computation |

The routine response is concise and references a richer evidence record. It should contain enough information for the next decision, not a fixed token count at the expense of correctness. Critical uncertainty and failures are never truncated away.

### 11.3 Observation levels

| Level | Typical content | Use |
|---|---|---|
| Receipt | Change summary, current dimensions, reference/check status and outstanding issues | Every accepted change or failed candidate |
| Relevant structure | Local feature graph, parameter bindings, interfaces and dependencies | Planning, editing, context recovery |
| Targeted facts | Dimensions, axes, normals, connectivity, adjacency, material/void relationships | Selection and geometric reasoning |
| Focused analysis | Sections, local comparison, clearance/thickness observations | Resolve a specific uncertainty |
| Controlled images | Canonical views, detail crop, section view, context view, aligned comparison | Form, usability, visual quality and correspondence |
| Extended analysis | Robustness sweeps, motion sampling, process checks, physical analysis | Higher-cost questions justified by the brief |

This is not a mandatory climb from cheap to expensive. If the question is appearance, request the appropriate image immediately. If it is an exact diameter, request the measurement directly.

### 11.4 Views are deliberate instruments

Use a stable, repeatable inspection camera independent of the human's freely orbiting viewport. Cache by geometry revision, camera, display style and overlay specification.

For visual comparison, align before/after or candidate/reference views using a known frame and consistent scale. Keep lighting, material and display settings fixed when comparing geometry; compare intentional appearance changes separately. Provide clean views for silhouette and surface judgment, with an annotated counterpart when labels help. Do not cover the shape with names in every image. Suspected tessellation/shading artifacts trigger an appropriate geometry or higher-quality view check, not an immediate shape edit.

Recommended view choices:

- One orthographic isometric for overall form.
- Front/top/side views selected to expose relevant relationships.
- A cropped detail view for a joint, opening, transition or finish.
- A section or transparency/isolation view for an otherwise hidden feature.
- An in-context or exploded view for assembly and access.
- A common-scale comparison between a small number of design alternatives.

Every image identifies revision, frame, camera direction and scale where relevant. Labels refer to the same returned handles as textual observations. Selection overlays, witness markers and added/removed geometry overlays are available on demand. Depth, normal, silhouette or curvature-oriented modes are additional tools when they answer a defined question; they are not always-on prompt payloads.

The spatial study's canonical-alignment result motivates this design, but it used a small synthetic task with objects already in a shared frame. It does not prove that arbitrary user photos can be aligned automatically or that CAD vision is solved. [Spatial imagery study](https://arxiv.org/html/2603.26779v2).

### 11.5 Let observations direct the next view

The app can suggest a view that exposes a reported witness or selected entity, estimate whether it is occluded, or offer a section through it. The model should choose “show the failed wall region,” not spend several turns saying “rotate another 20 degrees.”

If the concern is visual balance, the AI first asks for stable overall views. If those suggest an opening is off-center, it requests the dimension from the appropriate datum. A visual suspicion becomes a targeted measurement; a geometric anomaly becomes a focused visual inspection.

Rendering failure, unavailable vision support, hidden geometry and insufficient resolution remain explicit. A text-only model can still do geometry-driven work, but visual design acceptance remains pending unless a supported visual reviewer or the user performs it.

## 12. What a successful check means

### 12.1 Separate the claims

| Claim | Suitable evidence | What it does not establish |
|---|---|---|
| Builds correctly | Native rebuild and scoped geometric/topological validity | Compliance with the user's purpose |
| Has required geometry | Measurements of resulting geometry and interface checks | Strength or manufacturability |
| Is parametrically editable | Binding checks and tested parameter changes | Validity at every possible value |
| Preserves an interface | Protected geometric relationships and comparison | All unrecorded intentions |
| Looks appropriate | Controlled visual review against a design brief | Hidden dimensions or load capacity |
| Is feasible for a process | Defined process checks with stated coverage | A complete manufacturing plan |
| Meets physical requirements | Suitable calculations/simulation/tests with validated assumptions | Suitability outside the analyzed conditions |

OCCT validity and volume routines have defined preconditions and limitations. They should be used deliberately, not described as complete engineering certification. [Shape validity](https://dev.opencascade.org/doc/refman/html/class_b_rep_check___analyzer.html), [volume properties](https://dev.opencascade.org/doc/refman/html/class_b_rep_g_prop.html).

### 12.2 Use more than pass/fail

Recommended requirement states:

- `PASS`: the stated check supports the requirement within its declared scope and tolerance.
- `FAIL`: the check demonstrates a violation.
- `UNKNOWN`: the method is unavailable, insufficient, inconclusive or has uncertainty crossing the threshold.
- `PENDING`: a necessary feature/stage/input does not yet exist.
- `STALE`: a previously evaluated result no longer applies to the current revision/configuration.
- `REVIEW_REQUIRED`: a visual, usability or external engineering judgment remains.
- `WAIVED`: an explicit user decision, with reason and scope; not counted as passed.

Coverage is recorded separately from status. A sampled check can pass all samples while the broader continuous requirement remains unknown. A final report must not collapse those two facts into “all checks passed.”

A numerical result with a justified interval passes a lower-bound requirement only if its lower bound clears the threshold; it fails if its upper bound is below it. An interval that crosses the threshold is inconclusive. If an algorithm has no justified error bound, do not invent one from display precision.

### 12.3 Verify results, not only instructions

A hole feature's input diameter does not establish the diameter or even existence of the final hole. Measure the final B-Rep or a suitable supported representation. A geometry checker must independently test relevant output properties, rather than merely echoing the arguments used to create them.

Independence is imperfect when construction and measurement share a kernel. Use analytic fixtures, alternative methods where justified, and deliberately incorrect model variants to validate critical checkers. CADTests specifically shows why a check suite needs testing against mutations that violate the brief; finite checks can still miss errors. [CADTests](https://arxiv.org/html/2605.07807).

The requirement interpreter, geometry checker and final result are three different failure points. A second LLM repeating the first one's interpretation is not sufficient independence.

### 12.4 Define difficult properties precisely

**Hole and passage checks.** Identify the intended void, axis, entry/exit regions, target body and depth or through condition. Count passages/axes, not circular edges. A through bore can have two rims; countersinks and fillets add more. Check that it remains open in the final body and does not unintentionally penetrate another protected wall.

**Thickness.** Specify the region and meaning: material ligament between a bore and outer boundary, distance across a named planar wall, thickness along a normal field, or a process-specific thin-feature analysis. Avoid a naive global minimum that becomes zero at an intended sharp edge. State exclusions explicitly; they cannot hide a failing functional wall.

For simple supported geometry, use analytical or validated B-Rep measurements. For general shapes, report sample coverage, suspicious regions and available error bounds. A section supplies curves/regions and measurements within its plane. Multiple sections still do not automatically certify the whole solid. [OCCT distance operation](https://dev.opencascade.org/doc/refman/html/class_b_rep_extrema___dist_shape_shape.html), [section operation](https://dev.opencascade.org/doc/refman/html/class_b_rep_algo_a_p_i___section.html).

**Mass.** Validate the relevant solid(s), compute volume with declared method, and use density with explicit units and provenance. For multiple materials or occurrences, aggregate correctly and avoid counting hidden intermediate solids. Density times volume supports a nominal mass estimate; coatings, fasteners, manufacturing variation or print infill require additional assumptions.

**Clearance/contact/interference.** Distinguish positive separation, touching, overlapping solid volume and permitted contact/overlap. A zero intersection volume is not evidence of positive clearance. Use fast spatial bounds only as screening; a narrow-phase method must settle the relevant relationship or report uncertainty. Toleranced fit is distinct from nominal fit.

**Manufacturing.** Internal radius, draft, overhang and minimum feature checks are process-specific rules with scoped coverage. A minimum inside radius alone cannot certify 3-axis tool access. Draft can be analyzed on existing geometry even if a standalone draft creation feature is absent. Machining setups, tool/holder reach, fixtures, support removal, mold opening and part release require additional checks appropriate to the selected process.

**Motion/access.** Collision-free endpoints do not establish collision-free movement. Identify the path, moving occurrences, allowed contacts, tool or hand envelope, and tested states or swept-volume method. Label sampled coverage.

### 12.5 Invalidate immediately; recompute intelligently

Every edit invalidates dependent evidence immediately. Cheap relevant checks run with the transaction. Expensive global checks run at suitable milestones, on explicit request, or before a completion claim that depends on them. Unaffected checks may be reused only when their dependency tracking is trustworthy; otherwise invalidate conservatively.

Evidence records include geometry revision, brief version, configuration, referenced document revisions, checker version and relevant settings. A cached render/check is reusable only for the same inputs. Human edits trigger the same freshness behavior as AI edits.

### 12.6 A completion decision is assembled from evidence

The app derives a readiness report from requirement coverage and fresh results. The AI explains that report; it cannot turn an unknown load requirement into “ready to manufacture” with prose.

Useful completion descriptions are specific: “geometry requirements verified; visual concept accepted; load case not analyzed” or “native model complete for the stated dimensional brief.” A successful exploratory design need not pretend to be production-qualified. Conversely, a request whose goal includes load capacity remains incomplete until that claim has appropriate evidence or the user explicitly changes the scope.

## 13. Editing without unnoticed damage

### 13.1 Establish an edit contract

Before a modification, record:

- The exact requested change and the accepted base revision.
- Parameters/features likely to cause it.
- Interfaces and regions that must stay unchanged.
- Dependent movement that is intended or allowed.
- Necessary checks and visual comparison views.

The AI can usually derive this from the brief and current dependencies. It asks the user only about consequential ambiguity. “Make the enclosure wider” may mean preserve the lid mating profile or widen the lid as well; those are materially different tasks.

### 13.2 Check the final local effect

Use several levels of comparison:

1. Structural changes: operations, bindings, references, suppression and occurrence transforms.
2. Cheap numerical summaries: dimensions, volume, body count and relevant topology counts.
3. Protected relations: interface positions, diameters, mating planes, clearance and passages.
4. Local geometric comparison: added/removed regions or surface deviation outside allowed change regions, using methods suitable for the representation.
5. Aligned visual comparison where appearance matters.

The first two levels are useful alarms, not equivalence proofs. A translated internal hole can preserve all global summary values. A surface can deform without changing total volume. Rebuild signatures tell the app what may need recomputation; they do not measure collateral damage.

Report intended propagation separately from unexpected effects. Increasing plate thickness legitimately extends through-hole walls. It need not preserve every coordinate of the old hole face; it must preserve the specified axis, diameter, entry relationship and open passage.

Comparison methods also have failure modes. Boolean differences can fail; mesh deviation is approximate; tiny volume differences may hide a functionally critical change. If a protected relation cannot be checked, return unknown rather than silently declaring no damage.

### 13.3 Parameter robustness is a separate review

Test the nominal configuration, meaningful boundaries, local perturbations, relevant coupled configurations and topology-transition cases. Use sensitivity/dependency information to prioritize likely interactions. For high-dimensional designs, do not attempt a full Cartesian sweep by default.

Distinguish three domains:

- **Requested domain:** what variation the user wants supported.
- **Feasible domain:** constraints known to permit a design.
- **Tested domain:** configurations actually evaluated, with methods and outcomes.

State coupled constraints such as `hole_diameter <= flange_width - 2*required_ligament`; separate independent sliders do not express that relationship. A recipe can enforce supported algebraic conditions and also require kernel checks where topology may change.

Robustness jobs run on temporary candidates and restore the nominal state exactly. They check that a parameter changes the intended feature and preserves unrelated requirements, not merely that rebuilding succeeds.

No statement of “valid throughout 4–10 mm” follows from testing 4, 6 and 10 mm. A stronger range claim needs an appropriate analytic guarantee or validated exhaustive/bounded method. Otherwise report “tested at these configurations.”

## 14. Failures and recovery

### Entering an already-broken document

At entry, distinguish saved authoring state, successfully evaluated feature prefix, last-good geometry and known errors. Preserve the original state. Allow read-only inspection of the feature definitions and clearly labeled last-good shape, but never use measurements of that shape to certify the failed current definition.

Create a repair candidate from an explicit revision/checkpoint. Target the earliest relevant failing dependency and preserve independently healthy regions. A repair can improve an already-broken document in stages, but the result remains provisional until the required integrity and protection gates pass. Reopening a broken file does not manufacture a new verified baseline.

### 14.1 Errors should make the next decision easier

Return the operation and candidate revision, what failed, reliable observations, affected entities, causal evidence where available, possible remedies and the accepted revision that remains intact.

Distinguish:

| Failure | Useful response |
|---|---|
| Invalid structure/units | Exact field, accepted alternatives, normalized example |
| Stale state | Current revision and relevant changes; no mutation |
| Lost/ambiguous reference | Candidates, differing properties, topology transition and suggested inspection |
| Invalid sketch | Open loop, inconsistent relation, solver status, offending region |
| Kernel failure | Operation/inputs, kernel message, known precondition failures and uncertain hypotheses |
| Requirement violation | Measured versus required, witnesses, affected parameter/dependency slice |
| Collateral change | Protected property changed, local evidence and candidate rollback status |
| Unavailable capability/check | Honest limitation and supported alternatives |
| Resource/provider failure | Job/transaction status, retryability, preserved candidate/checkpoint |

The app may fix harmless formatting differences where meaning is unambiguous and echo normalization. It must not “repair” a diameter, target body, hole type or unit assumption by guessing.

### 14.2 Use the smallest justified repair

The model first inspects the relevant failure evidence. It then changes the smallest causal set consistent with the brief. A parameter update is preferable to rebuilding the part if the current design already expresses the right intent.

A local computational search can try a bounded set of fillet radii or feasible parameter values when the operation and objective are defined. Return successful intervals or tested candidates only to the extent actually established. Kernel success is not always monotonic in radius; do not assume binary search proves a universal maximum.

A remedy can be labeled “preflight passed” only after it has been tried on the same relevant candidate. Otherwise it is a hypothesis. The kernel cannot reliably explain every design failure, and a failed thickness requirement may need a design change rather than a mechanical retry.

### 14.3 Prevent repair loops

Track failed normalized operation/input/geometry combinations. Do not repeat an identical failure without new information. Budget retries by progress, elapsed time, cost and uncertainty; two local attempts is a reasonable initial policy, not a statement of feasibility.

After repeated local failure, reconsider the feature strategy: change a fragile face reference to a datum, replace an unsuitable construction, defer a decorative finish, or ask about a genuine tradeoff. Preserve the last accepted design and report what remains unresolved.

“Search budget exhausted” and “constraints proven inconsistent” are different outcomes. Only report infeasibility when the evidence actually establishes it. A lack of automated checking is also different from a failed design.

## 15. Advanced geometry and assemblies

### 15.1 Sweeps, lofts and freeform work

Provide structured helpers without pretending they remove all geometric difficulty:

- Sweep: named profile and path, start frame, alignment/twist policy, continuity, corner handling and self-intersection checks.
- Loft: named ordered sections, consistent frame/orientation, correspondence/seam control, optional guides and continuity goals.
- Freeform curve/surface work: compact control structures, symmetry/tangency/curvature intentions where supported, and targeted shape/curvature inspection.
- Shell/offset: supported thickness definition, removed faces, local failure witnesses and minimum-radius/offset concerns.

The app previews generated correspondence or transported frames so the model can inspect them. A strong model may use raw advanced controls, but outcomes still pass the same validity/reference/evidence rules. Surface smoothness is a separate property from watertightness; engineering radii and visual continuity deserve separate checks.

If the app lacks the required operation, report that capability gap. A modeled cavity may substitute for shell on a simple box if it preserves intended behavior, but should not be advertised as a general shell solution. Existing advanced surface capabilities and any missing ones must be disclosed through discovery.

### 15.2 Imported geometry

On import, report source, units, transform/recentering, representation, body/component structure, available analytic geometry, healing/reconstruction and loss of original feature history. Retain an untouched source reference for comparison.

Use native direct edits or new features where appropriate. Do not claim to have recovered an editable design history from a STEP or mesh merely because a solid exists. Mesh reconstruction quality and geometric deviation are reviewable facts. Recentered DXF geometry must not silently invalidate the user's intended coordinates.

### 15.3 Assemblies require occurrence-aware reasoning

A part definition and each placed occurrence have different identities. An edit to the source part can affect many instances; an occurrence transform affects only that instance. Every assembly operation states its scope and referenced source revisions. Existing subassemblies act rigidly in their parent; flexible nested mechanisms are a separate capability and must not be implied by generic assembly support.

Plan around functional interfaces and joints. The app computes transforms and reports residuals, remaining degrees of freedom, unresolved constraints and actual motion under the joint definition. A mate solver reporting convergence does not establish the intended joint, correct range of travel or collision-free operation.

Review static clearance, expected contacts, motion states, insertion/removal path and fastener/tool access according to the product's use. Use simplified envelopes for early access studies and refine the relevant geometry later. Do not require photorealistic rendering to answer an access question.

### 15.4 Cross-document edits are coherent operations too

Changing a shared part or creating a derived part may touch several documents and references. Identify the write set and lock/revision-check it as one logical change, or explicitly stage a multi-document proposal. Save and rollback must not leave the assembly pointing at a partially updated source.

If the runtime cannot support this transaction guarantee yet, expose the limitation and stage separate candidates with an explicit integration gate. Do not pretend a single-document snapshot is a universal assembly rollback.

## 16. Product development and human collaboration

The AI must do more than issue correct CAD commands. It should understand a design through **function, engineering behavior and visual form**, and use that understanding to choose its next modeling action. Those perspectives are present throughout the workflow, not added as a final cosmetic review.

### 16.1 Maintain three linked views of the design

| View | Questions the AI should answer | Working artifact |
|---|---|---|
| Functional | What is it for? What mates, moves, seals, supports or must remain accessible? | Interface/requirement map and use scenario |
| Engineering | How does the geometry carry loads, maintain fit, assemble and get manufactured? Which assumptions support that conclusion? | Engineering rationale, calculations/checks and unresolved analyses |
| Visual/product design | What should the object communicate? Are proportions, silhouette, transitions and details coherent? Is the intended use apparent? | Design brief, visual rubric and controlled review views |

These are different projections of the same native model and brief. They do not require three always-running agents or three competing sources of truth.

### 16.2 Give design choices an engineering rationale

For consequential choices, retain a short record:

```text
Choice: add a web between the upright and base.
Purpose: reduce bending in the upright while preserving the mounting envelope.
Expected effect: stiffer load path; increased mass; possible tool-access penalty.
Evidence needed: supplied load/support case, section geometry, suitable calculation
                 or simulation, and cutter/fastener access check.
Current status: geometry and access checked; stiffness benefit not yet quantified.
```

The rationale is not a long hidden reasoning transcript. It records the decision, assumptions, alternatives and evidence needed to assess it. If the AI cannot explain how a feature serves the product, the feature deserves reconsideration.

Engineering workflow:

1. Identify the relevant physical interfaces, load path, boundary conditions, material/process and failure modes from the brief.
2. Obtain missing consequential inputs rather than inventing a load or fit class.
3. Choose the simplest analysis adequate for the claim: exact geometric relation, established calculation, suitable solver, or physical test/review.
4. Let computation tools perform arithmetic and analysis. Record input assumptions, units, method applicability and source/version for engineering rules.
5. Compare alternatives on the actual objective while preserving required interfaces.
6. Re-evaluate affected analyses after geometry or assumptions change.

A beam approximation is useful only when its assumptions fit the geometry and loading. A simulation needs credible material properties, boundary conditions, meshing and convergence checks; a colorful stress plot is not sufficient. Numerical convergence assesses the numerical solution, not whether the physical model represents reality. If these capabilities are not integrated, the app can prepare the geometry and analysis request and keep that requirement unresolved. The workflow supports engineering understanding without falsely claiming that the current branch already has physical analysis tools.

Engineering method discovery advertises required inputs, applicability, source/version, result scope and cost. The agent selects a method after establishing those inputs; out-of-domain or unavailable analyses are rejected explicitly. If no suitable method exists, save a structured analysis request with load/support assumptions, material, relevant geometry/interfaces and the output needed. A generic measurement tool does not imply an arbitrary fatigue, buckling, thermal or ergonomic solver.

### 16.3 Make visual design critique actionable

Translate the user's style and usability intent into a small review rubric, usually three to six relevant criteria. Examples: balanced proportions, clear functional hierarchy, consistent edge treatment, coherent transitions, appropriate visual weight, comfortable contact areas, accessible controls or alignment with a supplied reference.

For an open-ended design, establish interfaces/keep-outs and a cheap native blockout first. Review its silhouette, proportions, use and basic engineering feasibility before investing in fragile detail. Compare a few concepts only when the brief warrants it. A fully dimensioned mechanical part can skip this exploration and proceed directly to construction.

For each concern, identify the relevant view and an editable parameter/feature. The AI should produce observations such as:

> “The neck looks visually heavy in the side silhouette relative to the base. Two candidates reduce its apparent width while preserving the bore and mounting interface. Their remaining ligament and stiffness checks differ.”

That observation leads to concrete native edits and engineering checks. “Looks better” alone does not.

Use clean common-scale views for overall proportions; detail and curvature-oriented views for transitions; in-context views for use and handling. Show a small number of meaningfully different options when taste is underdetermined. Ask the user for preference at a high-value milestone, not after every fillet. Retain the selected visual direction so later repairs do not erode it accidentally.

Do not manufacture precise numerical beauty scores. A visual rubric can organize judgment without pretending that aesthetics is an objective geometric theorem. Reference similarity is useful, but a design can intentionally depart from a reference for function or manufacture; record the tradeoff.

### 16.4 Couple engineering and design iterations

The loop is: propose a form change, predict its relevant engineering effects, build it, measure those effects, review its appearance in aligned views, then accept or revise it.

When goals conflict, present the tradeoff using actual evidence. A thinner wall can improve visual lightness and reduce mass while hurting stiffness, robustness or manufacturing yield. More rounding can feel better but consume a protected sealing surface. The best candidate is chosen within the brief, not by blindly minimizing mass or maximizing resemblance.

For broad goals such as “as light as possible,” define a bounded search domain and objective after the hard requirements are known. The app can evaluate a small parameter sweep or candidate family and return a feasible tradeoff table. Claim the best among tested candidates, not a global optimum unless established.

### 16.5 Keep the human in control without constant interruption

The user can see what the AI is trying to achieve, the latest accepted design, candidate previews, relevant evidence, assumptions and next action. They can pause, cancel, edit, select a design alternative or revert a change.

A human selecting geometry provides grounded input: the app converts the selection into current revision-bound handles and context. The model still verifies the role when the request is ambiguous. A human edit updates the shared model and evidence, invalidating stale AI plans as needed.

The default handoff contains the native editable document, selected views, a short design rationale, requirements/results, remaining uncertainties and a small list of meaningful controls to edit. Exports are generated only in requested formats or an established workflow preference; STEP plus STL is not an automatic requirement for every design.

## 17. Efficiency across model sizes

### 17.1 Optimize for an accepted design

The useful objective is quality-constrained total cost and time, including repair, review and human correction. A low token count is not efficient if the result quietly violates an interface. A large model is not efficient if it writes custom low-level geometry that a native pattern can produce deterministically.

Use these practical mechanisms:

- Progressive capability discovery and short operation examples.
- Local deterministic computation of transforms, arithmetic, repetition and standard geometry.
- Batched independent observations and coherent dependent modeling operations.
- Incremental rebuild and dependency-aware check invalidation.
- Compact state capsules, focused deltas and inspectable evidence references.
- Geometry/view/check caching with explicit revision and configuration keys.
- Low-cost draft tessellation for exploration; suitable precision for verification/output.
- Reusable native recipes for recurring constructions.
- Bounded candidate exploration only when uncertainty justifies it.

Do not run full global wall analysis, all parameter combinations and eight renders after every primitive. Do not omit a required check to satisfy a token budget; report budget exhaustion and preserve the candidate instead.

Provider guidance supports clear tools, relevant compact responses and discovery rather than loading every definition. It does not establish a universal optimal serialization or fixed token saving for CAD. [Anthropic tool design](https://www.anthropic.com/engineering/writing-tools-for-agents), [code execution and discovery](https://www.anthropic.com/engineering/code-execution-with-mcp).

### 17.2 Adapt support, not truth standards

| Task situation | Fast-model support | More capable model support |
|---|---|---|
| Common part family | Recipe + typed inputs + automatic routine checks | Same recipe, custom expansion if valuable |
| Unfamiliar feature | Retrieve one worked example and narrow schema | Retrieve advanced options/dependency context |
| Difficult reference | Candidate facts and focused highlight view | Same facts; richer topology reasoning if needed |
| Coupled edit | Smaller coherent steps, explicit protected conditions | Larger coherent proposal if justified |
| Failure | Local structured diagnosis and tested remedies | Replan feature strategy or evaluate alternatives |
| Visual refinement | Stable views and a short rubric | More nuanced alternatives; same engineering guards |

Do not assume that a stronger model always beats a smaller one, that a fast model cannot write code, or that a schema guarantees semantic correctness. Supported structured-output/function-calling capabilities vary. Negotiate the actual provider/model features, validate every call locally, and handle refusals, truncation and invalid responses without mutating the model. [Gemini function calling](https://ai.google.dev/gemini-api/docs/function-calling), [structured output](https://ai.google.dev/gemini-api/docs/structured-output).

The user's Gemini Flash 3.6 and Opus 5 examples are target model choices to evaluate, not promised quality levels. Record exact provider model IDs/version/date and available vision/tool support in every evaluation. Avoid hard-coding workflow assumptions to a marketing name.

### 17.3 Escalation is targeted

If configured and authorized, use a more capable model for a difficult plan, unresolved engineering interpretation or visual critique. Transfer the compact brief, current revision, relevant evidence, failed attempts and budget. Do not restart from the entire conversation or repeat all geometry operations.

A second opinion can be helpful on complex design decisions. It should be optional and triggered by uncertainty, not an always-on trio of agents. All reviewers inspect the same candidate and brief; one serialized process owns commits.

Optional multiple candidates can improve exploration, but agreement among generated shapes is not proof of correctness. Use actual constraints and review criteria to select. Research on CAD consensus selection is a reason to test this mode, not to replace verification with majority vote. [CAD consensus selection](https://arxiv.org/abs/2608.09706).

### 17.4 The API-token experience

The user chooses a provider/model, supplies a token through the app's credential flow, and gives a modeling request. Credentials stay outside model-visible context and native CAD documents. Only required descriptions, facts and selected images are sent according to the user's provider/data preferences.

The app establishes available capabilities, configured cost/time limits and continuation policy without requiring the user to learn the command vocabulary. A provider failure pauses or retries within budget while preserving local modeling state. Resumption reads the saved brief and current revision, not a stale assumed state.

A default budget policy should permit normal reversible progress and surface a meaningful cost/quality choice when the task exceeds it. Never silently switch to another paid provider or disclose the design to one outside the user's configured choices.

## 18. Worked creation and edit

**This is a proposed interaction, not an executed app session.** The nominal geometry below was checked independently with elementary arithmetic. No runtime, token count, actual kernel result or visual judgment is claimed.

### 18.1 A precise initial request

> “Create an 80 × 50 × 6 mm plate, centered in its mounting plane, with four 5 mm through holes on a 60 × 30 mm centered rectangular pattern. Keep it as an editable model. Use density 2.70 g/cm³ for a nominal mass estimate.”

The brief is sufficiently defined for geometry. The AI records the supplied dimensions, hole axes and nominal density. It does not invent a fastener standard, fit class, load capacity, manufacturing method or a 3 mm global-wall requirement.

Define `plate_frame` with u along 80 mm, v along 50 mm and n through thickness. Origin is at the center of the bottom face. The app maps that frame into its native world convention.

The intended solid is:

```text
u extent: -40 to +40 mm
v extent: -25 to +25 mm
n extent:   0 to   6 mm
hole axes: (u,v) = (-30,-15), (-30,+15), (+30,-15), (+30,+15)
hole diameter: 5 mm; through the plate along n
```

### 18.2 One coherent construction

The AI plans a centered rectangular sketch, one extrusion, and a point-driven through-hole pattern. It asks the relevant creation schema once. A schematic change request is:

```json
{
  "request_id": "create_plate_01",
  "base_revision": "r0",
  "intent": "Create the specified plate and mounting interface",
  "frame": "plate_frame",
  "steps": [
    {"op": "sketch.rectangle", "as": "profile", "center": [0, 0],
     "width": "80 mm", "height": "50 mm"},
    {"op": "extrude", "as": "plate", "profile": "$profile.region",
     "distance": "6 mm", "direction": "plate_frame.n", "output": "new"},
    {"op": "hole_pattern", "body": "$plate.body", "diameter": "5 mm",
     "layout": "rectangular", "count_u": 2, "count_v": 2,
     "axis": "plate_frame.n", "pitch_u": "60 mm", "pitch_v": "30 mm", "center": [0, 0],
     "extent": "through_body"}
  ],
  "commit": "if_required_checks_pass"
}
```

Here `as` names transaction-local outputs with documented typed ports. `$plate.body` references the body produced by this transaction; it is not an invented existing entity name. The app resolves these dependencies internally, avoiding extra discovery calls between a sketch and its extrusion.

After building, the proposed checker would inspect the resulting geometry: one intended solid, correct extents, four correctly located cylindrical passages of the required diameter, and passage continuity across the thickness. It would return actual measurements, not simply copy the inputs above.

Independent analytic reference values for this unrounded ideal plate are:

```text
V = 80*50*6 - 4*pi*(5/2)^2*6 = 23,528.7611 mm³
m = V * 0.00270 g/mm³          = 63.5277 g
minimum hole-to-outer-side ligament = 10 - 2.5 = 7.5 mm
```

Those formulas are reference checks for the proposed example, not substitutes for inspecting actual created geometry. The example does not include fillets, chamfers or other finishing operations, which would alter its volume.

The AI requests a top orthographic view and a simple isometric to confirm the plate's visual reading and hole arrangement. It can then report geometry completion, nominal mass under the supplied density, and the editable controls. Physical load performance was not requested or evaluated.

### 18.3 A coupled edit with a protected interface

The user continues:

> “Make it 100 mm long and 8 mm thick. Keep the mounting-hole positions and diameters, and the bottom mounting plane, exactly where they are.”

The edit contract allows the outer u extent and upper surface to move, and the through passages to extend. It protects the four axes in `plate_frame`, diameter, bottom plane and through condition. It does not try to freeze all points of the previous cylindrical faces.

The AI stages width and thickness together. The model's dependency graph must hold the hole pattern fixed at ±30/±15, rather than moving it to keep a fixed edge inset.

Independent expected values are:

```text
new extents: u -50..+50, v -25..+25, n 0..8 mm
new V: 39,371.6815 mm³
new nominal m: 106.3035 g
delta V: +15,842.9204 mm³
hole axes and diameters: unchanged
minimum outer-side ligament: still 7.5 mm, now governed by the v sides
```

### 18.4 The failure that count checks miss

Suppose the first candidate incorrectly moves the hole axes to u = ±40 while preserving 10 mm edge insets. There are still four 5 mm holes. Total volume and outer bounding box match the intended edited plate. `expect: 4`, volume and bbox all pass.

The protected interface check fails: two columns of holes moved 10 mm. It returns the four axis witnesses and the dependent edge-inset relation. The candidate remains uncommitted. The repair changes the binding to the fixed 60 mm pitch and rechecks the same interface. This is the reason identity, intent, dependencies and result measurements must work together.

### 18.5 Reopen, human edit and output

After a successful candidate, one undo restores the previous accepted plate. Redo restores the edited plate. Save/reopen must preserve the same parameters, bindings and reference semantics. A later human edit invalidates affected evidence and is visible in the AI's next state capsule.

If STEP output is requested, export only the selected accepted body's current geometry. Reimport in an isolated verification state and compare body count, orientation, extents and critical hole geometry within declared exchange tolerances. If STL is requested, separately verify tessellation and stated units/orientation; do not expect an STL to preserve a native feature tree.

## 19. Harder workflow walkthroughs

### 19.1 An underspecified sensor bracket

> “Design a light, clean-looking bracket for a 30 mm sensor on 40 × 40 extrusion.”

The AI does not infer a 30 H7 press-fit bore or a bolt spacing from those words. It identifies missing interfaces: sensor mounting/retention method, relevant extrusion/T-slot geometry, sensor direction and access. It asks for the consequential missing information or a reference while proposing provisional overall concepts.

The visual brief might favor a compact form, a clear relationship between sensor axis and mount, restrained edge treatments and low apparent bulk. The engineering brief identifies fixation, load path, assembly sequence, fastener access, envelope and relevant process constraints. Loads/material/process remain explicit inputs or open decisions.

After interfaces are known, the AI can compare a simple L form, a gusseted form or another appropriate supported construction. These are alternatives to assess, not interchangeable aesthetic variants. It stages the selected strategy with stable datums and native features, checks actual mating geometry, shows assembly/tool-access views and runs supported engineering analysis.

If a mass objective conflicts with stiffness or access, the report shows the tradeoff and the evidence. A clean render and a low mass do not override a failed mounting or load requirement. The user can choose the aesthetic direction without having to author CAD commands.

### 19.2 A visual improvement that can be an engineering regression

Consider a deliberately simplified analysis fixture: a straight, prismatic rectangular cantilever with a rigid root, a 20 N transverse tip force, length 50 mm, width 20 mm and assumed linear-elastic modulus 70,000 N/mm². Compare thicknesses of 6 and 4 mm in the bending direction. These are supplied hypothetical inputs, not inferred properties of the sensor bracket.

For the ideal Euler–Bernoulli model, `I = b*t³/12` and `tip deflection = F*L³/(3*E*I)`. The end-loaded cantilever relation is documented in [MIT's solid mechanics reference sheet](https://ocw.mit.edu/courses/1-050-solid-mechanics-fall-2004/fd4eff39aec922b8c07660006f40686e_pset04_11.pdf).

| Candidate | Ideal beam volume | Calculated tip deflection | Visual question |
|---|---:|---:|---|
| 6 mm thickness | 6,000 mm³ | 0.0331 mm | Does the side silhouette appear heavier than desired? |
| 4 mm thickness | 4,000 mm³ | 0.1116 mm | Is the slimmer silhouette preferable in the same view? |

The thinner candidate removes one third of this beam's nominal material but has 3.375 times the calculated bending deflection under these assumptions. If this fixture's allowable deflection were 0.05 mm, the 4 mm candidate would fail that idealized calculation despite looking lighter.

The AI should recognize the tradeoff, not announce that the thinner design is better. It can consider a different section, a web, shorter span or different proportions, then recompute and inspect. Actual mounting compliance, stress concentrations, fatigue, material behavior and manufacturing variation are outside this simple calculation. Even the 6 mm result is not certification of a real bracket. Numerical convergence alone would not validate a different physical model either.

This example illustrates the required behavior: connect a visual choice to a physical consequence, use a suitable computation, and communicate the boundary of that evidence.

### 19.3 An enclosure with hidden problems

For an enclosure, establish electronics/connector envelopes, attachment and opening method, wall regions, assembly access and process. If no general shell is available, a simple supported outer-solid-minus-cavity strategy may suffice for an appropriate shape; preserve its explicit inner/outer parameters and limits.

Inspect sections through critical bosses, connectors and walls, while recognizing that those slices do not certify global thickness. Test lid fit, screw/driver clearance and assembly path. Compare clean exterior views for proportions and transition quality. If wall checking is sampled or a boss-root physical claim is unverified, retain that coverage status.

A later “make it slimmer” edit protects the electronics envelope, mating interface and functional clearances. It does not simply scale the whole enclosure and shrink every hole with it.

### 19.4 A lofted handle or duct

Select section frames and correspondence explicitly; preview the unblended shape and inspect cross-sections before applying finishing details. For a handle, assess grip envelope and surface transitions from relevant views; comfort remains a design judgment unless supported by suitable human-factor inputs/testing. For a duct, verify passage continuity and areas, but do not infer pressure drop from appearance.

Smooth-looking shading can conceal geometric discontinuity. Optional zebra/curvature views can support surface review alongside numerical continuity checks where available. Such diagnostic views are established CAD practice, not a substitute for all surface measurements. [Fusion surface continuity analysis](https://help.autodesk.com/cloudhelp/ENU/Fusion-Model/files/GUID-3F8BA6D3-5DF2-49FA-BE7D-8CCEF718C795.htm).

## 20. Evaluation and acceptance

The workflow is a design hypothesis until tested in this app. Evaluation must distinguish a system that builds plausible geometry from one that understands, edits and explains an acceptable product.

### 20.1 Build the benchmark around user work

Start with a 40-task development suite to shape the interaction. Use a separate held-out suite before claiming general performance; a proposed initial distribution is 120 tasks:

| Family | Tasks | Includes |
|---|---:|---|
| Creation | 24 | Prismatic, revolved, patterned and advanced supported shapes |
| Editing | 24 | Local/coupled edits, fixed interfaces, intended dependent movement |
| Import and recovery | 16 | STEP/mesh/DXF, missing history, broken models and failed rebuilds |
| Parameter behavior | 16 | Bindings, coupled domains, topology transitions, save/reopen |
| Assemblies | 16 | Repeated occurrences, joints, shared sources, motion/access |
| Engineering and visual design | 24 | Competing concepts, physical assumptions, aesthetic refinement and tradeoffs |

Include concise and ambiguous prompts, expert and non-expert language, reference images and existing models. Split by part/recipe family where possible so memorizing development examples does not masquerade as generalization. A reference part is one acceptable solution; geometry similarity alone must not penalize a different valid design strategy.

Run exact target provider/model versions with recorded settings and budgets. Repeat representative tasks to reveal stochastic variation. Record hardware/kernel/renderer/device mode; an iPad latency claim needs iPad measurement. Never compare providers on different task subsets or repair budgets without labeling it.

### 20.2 Evaluate the judges too

For each important checker, construct correct variants and deliberately broken models: wrong hole location with unchanged count/volume, blind versus through passage, duplicate body, stale shape, flipped occurrence, loosened requirement, thin region between sample planes, and false parameter binding.

The checker must reject the wrong cases and accept legitimate variants. Keep held-out grading independent of the agent's editable self-authored contract; otherwise the agent can succeed by omitting inconvenient requirements. Review disagreements with humans rather than blindly trusting either an LLM judge or one numeric metric.

### 20.3 Report separate quality and efficiency measures

| Measure | What to report |
|---|---|
| Task success | Fraction meeting the complete supplied brief within declared capability scope |
| Geometric correctness | Fresh independent checks on result geometry, with unresolved coverage |
| Silent false acceptance | Incorrect result labeled complete/verified; severity and cause |
| Edit preservation | Protected interfaces/regions retained; intended changes achieved |
| Parameter behavior | Intended bindings and tested configuration outcomes |
| Native editability | Human can make a requested follow-up edit after save/reopen |
| Engineering reasoning | Appropriate assumptions, analysis choice, causal predictions and evidence-backed tradeoffs |
| Visual design quality | Blind review against the stated rubric/reference, plus inter-reviewer disagreement |
| Recovery | Failed changes preserve accepted state; safe retry, cancel and concurrent edit behavior |
| Efficiency | Time to accepted design, P50/P95 latency, billed input/output/reasoning/image usage, cache usage, cost, tool calls and human corrections |
| Honesty of completion | Unknown/stale/unsupported claims correctly reported rather than passed |

Engineering assessment must test whether the model selects a suitable analysis and recognizes its limitations, not merely whether its explanation sounds technical. Visual assessment must test the resulting form and actionable improvements, not adjective-rich commentary.

### 20.4 Release gates and provisional targets

**Non-negotiable behavior gates:** all deterministic regression cases for stale-state rejection, atomic rollback, retry deduplication, protected requirement authority, evidence freshness and selected-output scope must pass. Any known silent corruption or false-success path in a supported workflow blocks its release.

**Proposed performance targets, to validate rather than advertise as achieved:** on the explicitly supported, fully specified core-part subset, aim for at least 90% completion with a selected fast model and 95% with a selected highly capable model within a fixed repair budget. An accepted result has the same quality conditions regardless of model. These targets do not apply automatically to freeform design, unknown physics or unsupported features.

For small supported parts, an initial usability target is P50 under two minutes and P95 under five minutes to a checked, inspectable result, excluding time waiting for human answers. Measure expensive analysis separately and also in the end-to-end total. This is a product target, not a prediction based on the draft's invented 95-second transcript. Cost budgets should use actual provider billing and be set against user willingness to pay.

Track silent false acceptance separately from failure to finish. Aim for zero observed critical false acceptances in the release corpus, while reporting sample size and uncertainty. Zero in a small corpus does not establish a zero population error rate. Stronger reliability claims require larger, appropriately independent tests and continued failure analysis.

Do not average excellent plate performance with poor assembly or design results into one reassuring score. Publish task-family coverage and limitations.

### 20.5 Ablations that can change the design

Compare the proposed workflow with competent baselines using the same native capabilities, model versions and budgets:

- Focused typed tools versus a compact operation dispatcher versus constrained code composition.
- Summary/measurement feedback versus added controlled visual feedback.
- Uncontrolled orbit views versus canonical aligned views and focused crops.
- Cardinality alone versus the full reference contract.
- Per-operation commits versus intent-sized atomic transactions.
- Recipe assistance versus native operations alone, for both model tiers.
- Cheap summary checks versus protected-interface/local geometry checks.
- With and without explicit engineering rationale and a visual rubric.
- Single candidate versus bounded alternatives for uncertain design tasks.

Change one important factor at a time or design a controlled factorial test. Record failures, not just averages. Retain an additional mechanism only if it improves quality or cost under the intended workload, or is necessary for state integrity.

### 20.6 Adversarial acceptance cases

| Case | Required behavior |
|---|---|
| Wrong singleton satisfies `expect: 1` | Other reference/interface checks catch it or uncertainty remains visible |
| Two symmetric occurrences | Selection scope names the occurrence, not only the source part |
| Face splits after a pocket | Explicit split semantics; no silent reassignment |
| Same volume/bbox, moved hole | Protected location check rejects candidate |
| Thickness change extends a through hole | Allowed dependency propagation accepted |
| Coherent edit invalid halfway through | Entire candidate completes or rolls back without publishing the intermediate state |
| Timeout after commit | Retry returns the recorded outcome without duplicate geometry |
| Human edits during inference | Stale proposal rejected or revalidated with a visible delta |
| Existing failed feature shows old solid | Observation identifies last-good geometry and does not certify current feature state |
| Parameter expression stops evaluating | Stale/frozen value reported; not a fresh pass |
| Parameter corners pass but an interior configuration fails | Coverage report does not claim the entire range |
| Sampling misses a thin region | Global requirement remains unproven; checker limitations are exposed |
| Agent removes or loosens a failing requirement | Requirement authority prevents silent success |
| Section/render/check describes another revision | Evidence rejected as stale |
| Native model exports incomplete/duplicate geometry | Output scope/round-trip checks fail |
| Prettier thin candidate is too flexible | Engineering requirement prevails; alternatives offered |
| Good dimensions, visually wrong reference interpretation | Visual review flags mismatch before completion |
| Unsupported shell/analysis on this device | Capability gap disclosed; no invented success |

## 21. Workflow delivery order

This is the sequence of user-visible capabilities and acceptance evidence. Detailed integration design follows only after this workflow is accepted.

| Stage | Workflow delivered | Gate to proceed |
|---|---|---|
| 1. Trustworthy single change | Capability discovery, explicit frames/units, native operation semantics, candidate isolation, revision-bound references, one coherent undo | Failed/stale/retried edits cannot corrupt accepted work in the supported subset |
| 2. Complete small-part loop | Compact primitives, native parameter bindings, brief, measurements, aligned views, requirement coverage and local preservation | Create and edit representative parts with verified geometry and inspectable form |
| 3. Engineering and visual iteration | Interface maps, rationale, supported calculations/checks, visual rubric, purposeful alternatives and tradeoff comparison | AI can justify a change, measure consequences, critique appearance and retain uncertainty correctly |
| 4. Robust general editing | Imported/broken models, topology transitions, wider command coverage, parameter robustness, save/reopen and verified output | Human follow-up edits and recovery cases pass; no false completion from stale geometry |
| 5. Broad native parity | Remaining sketch/feature/view/document actions and validated recipe families | Capability-by-capability coverage demonstrated, including advanced geometry |
| 6. Assembly/product workflow | Occurrence-aware references, shared-document edits, joints, motion/access and clearances | Multi-part edits preserve intended interfaces and report scoped engineering evidence |
| 7. Optimization and expansion | Model routing, optional composition interface, specialized analyses and broader evaluation | Demonstrated quality/cost improvement with unchanged integrity standards |

Views and basic parameter behavior belong in the first complete modeling loop, not after a chat demo is already declared useful. Engineering reasoning begins with the brief and appropriate simple analysis; broad FEA/CAM capabilities need not all exist before the first correct plate. Missing capabilities remain visible, and the end-state goal of full app control stays on the coverage ledger.

The first demonstration should be one creation, one coupled edit, one caught wrong selection, one failed candidate, one undo and one human follow-up edit, with geometry and appearance visible throughout. This exercises the workflow's essential promises more meaningfully than an isolated impressive render.

## 22. Decisions and remaining uncertainty

### 22.1 Recommended decisions now

1. Use the existing native model as the authoritative design, with persistent intent and evidence attached.
2. Give the AI both engineering and visual design responsibilities, supported by different appropriate observations.
3. Make coherent candidate transactions the fundamental edit unit.
4. Separate logical identity, semantic reference intent and revision-bound topology handles.
5. Preserve the app's world coordinates; publish explicit functional frames and transformations.
6. Generate native constraints/dependencies behind compact sketch and feature recipes.
7. Measure final geometry and check protected interfaces; do not certify input arguments.
8. Treat unknown, stale and partial evidence as real states, not failed attempts to say “pass.”
9. Include aligned visual review and parametric editability in the initial complete workflow.
10. Keep the operation system provider-neutral and evaluate actual fast and capable models.
11. Track full app parity explicitly; disclose the supported subset during staged delivery.
12. Keep implementation and performance claims separate from the workflow specification.

These decisions do not require the user to choose a camera migration, buy a particular model or approve a long list of speculative backend details.

### 22.2 Questions to settle through prototypes and evaluation

| Uncertainty | Recommended way to settle it |
|---|---|
| Best tool presentation for each model tier | Controlled dispatcher/typed-tool/composition comparison |
| Reliable topology lineage across this kernel surface | Split/merge/rebuild fixtures and selective native-history exposure |
| Cost of geometry comparison and difficult thickness checks on iPad | Measure representative local/global workloads with explicit coverage |
| Parameter binding completeness | Native editing, GUI synchronization and save/reopen/perturbation fixtures |
| Renderer consistency and useful view budget | Fixed-camera inspection fixtures and visual-quality ablations |
| Which engineering analyses belong first | Target product families and real user requirements; validate method applicability |
| How much visual refinement the fast model handles | Blind rubric-based review with geometry guards held constant |
| Useful recipe families | Repeated user tasks, failure logs and held-out family evaluation |
| Appropriate automatic-change and spend budgets | Observed recovery/latency/cost and user preference |

No amount of additional literature review can establish app-specific success rates without implementation and measurement. The design is complete enough to guide that next stage while making its falsifiable assumptions explicit.

## Appendix A. Five review rounds

These are actual review passes carried out for this revision. They are design and source reviews, not claims that an agent prototype was executed five times.

| Round | Research and critical question | Resulting revision |
|---|---|---|
| 1. Audit the evidence | Read the supplied plan; retrieve cited spatial/CAD studies. Do the percentages imply the claimed architecture? | Restored canonical aligned visual feedback; removed the universal 62.5% ceiling and one-feature-edit inference. |
| 2. Audit this branch | Inventory repository and inspect modeling, parameter, session, kernel, measurement, rendering, persistence and assembly paths. Is the foundation already as strong as claimed? | Corrected FacePick versus EdgeSel, expression binding, Y-up, undo/failure, section, material and export claims. |
| 3. Stress the interaction contract | Compare native historical/state queries and tool guidance. Can counts, names, partial commits or cached summaries quietly select the wrong thing? | Added explicit identity/binding semantics, coherent transactions, revision checks, retry deduplication, protected interfaces and state resynchronization. |
| 4. Stress understanding and verification | Revisit geometry-checking limitations, mutation-tested CAD checks, visual feedback and surface inspection. Incorporate the user's engineering/design requirement. | Added linked functional/engineering/visual reviews, evidence coverage, independent output checks, scoped analysis and purposeful views. |
| 5. Walk through and independently challenge the combined plan | Check example arithmetic; try same-count wrong targets, stale geometry, coupled changes, visual-versus-engineering conflicts, incomplete checks and model-cost limits. Three reviewers assess the integrated draft. | Refined output aliases, reference drift, commit policy, broken-document recovery, visual conditions, physical-analysis limits and evaluation gates. |

The review deliberately sought counterexamples instead of adding stronger claims to the original thesis. Stronger evidence changed the design where necessary.

## Appendix B. Research corrections and sources

### B.1 Numerical and architectural claims checked

| Claim in the supplied plan | What the retrieved source supports | Consequence |
|---|---|---|
| 62.5% is the ceiling with render/rotate tools | The spatial paper reports that range for incremental rotation; canonical reset/alignment reaches 85–97.5% on its 40-problem synthetic setting. Its cited human baseline is about 79%, not universally 100%. | Reduce mental rotation through tool design; keep controlled visual evidence. |
| 58.1% of executable CAD violates requirements | CADEngBench reports this for its evaluated single-response outputs and defined tests. It is not a universal interactive-agent failure rate. | Measure requirements beyond build success, without projecting the percentage onto this app. |
| 99.6% single-feature versus 40–46% multi-feature edits | The relevant CADEngBench distinction is independent additions versus more coupled histories; the edited quantities remain specified dimensions. | Preserve dependency-sensitive geometry; do not infer a universal one-operation rule. |
| CadQuery's 2.2× result proves a JSON architecture | Text2CAD-Bench's cited comparison is a specific model/task comparison with a low-level CAD sequence representation. | Test abstraction level and interface format separately. |
| Multi-view feedback is ineffective | BenchCAD's results vary by task/model; they do not test every interactive targeted-view strategy. CADCodeVerify reports benefits from visual verification. | Use views for suitable questions and evaluate them in this app. |
| SPADA numerical improvements establish the workflow | Existence was found in the official ICML listing; the cited numerical results were not independently verified from successfully retrieved primary full text. | Omit those numerical claims from the recommendation. |
| Every other system relies on images plus scripts | Embodied CAD already combines planning, deterministic resolution, solver feedback and skills. | Treat this plan as an app-specific synthesis, not a universal novelty claim. |
| Format changes are limited to −7.7%…+2.7% | The cited Notation Matters passage attributes that range to related SQL work, not a CAD-interface comparison. | Do not use it as a CAD schema-selection guarantee. |

### B.2 Research sources

Sources were checked during 17–18 September 2026. Research findings motivate choices; they do not validate this proposed implementation. Several are recent preprints with task-specific evaluation.

1. [Limits of Spatial Imagery Reasoning in Frontier LLM Models, v2](https://arxiv.org/html/2603.26779v2). Full primary text inspected for task, alignment conditions and claimed ceiling.
2. [CADEngBench](https://arxiv.org/html/2608.09296). Full primary text inspected for program versus requirement success, edit groups and parameter behavior.
3. [Text2CAD-Bench](https://arxiv.org/html/2605.18430). Full primary text inspected for representation comparisons and benchmark scope.
4. [BenchCAD](https://arxiv.org/html/2605.10865). Full primary text inspected for parametric/editing distinctions and visual-input conditions.
5. [Embodied CAD](https://arxiv.org/html/2606.31252). Full primary text inspected for planner/resolver/solver separation and skill hierarchy.
6. [Text-to-CAD Evaluation with CADTests](https://arxiv.org/html/2605.07807). Full primary text inspected for executable tests, test mutation and coverage limitations.
7. [CADCodeVerify](https://arxiv.org/abs/2410.05340). Primary abstract checked; supports complementary visual feedback, not engineering certification.
8. [ArtisanCAD](https://arxiv.org/abs/2607.05750). Primary abstract checked for reusable procedural CAD representation and skills.
9. [Test-Time Scaling for CAD Generation via Verifier-Free Consensus Selection](https://arxiv.org/abs/2608.09706). Primary abstract checked; optional exploration evidence only.
10. [Clarify Before You Draw](https://arxiv.org/abs/2602.03045). Primary abstract checked; targeted clarification precedent, not a universal question policy.
11. [Pointer-CAD](https://arxiv.org/abs/2603.04337). Primary description checked for grounded references; not a persistent-identity guarantee.
12. [Notation Matters](https://arxiv.org/html/2605.29676). Full primary text inspected to correct the attribution of the quoted numerical range.

### B.3 Primary technical references

- [Onshape query library](https://cad.onshape.com/FsDoc/library.html#module-query.fs) and [modeling documentation](https://cad.onshape.com/FsDoc/modeling.html): query intent, topology, tracking and historical/state-based selection.
- [OCCT topology reference](https://dev.opencascade.org/sites/default/files/pdf/Topology.pdf): topology and operation-history concepts.
- [OCCT BRepCheck_Analyzer](https://dev.opencascade.org/doc/refman/html/class_b_rep_check___analyzer.html): validity scope and checking methods.
- [OCCT BRepGProp](https://dev.opencascade.org/doc/refman/html/class_b_rep_g_prop.html): mass/volume-property preconditions and computation.
- [OCCT BRepExtrema_DistShapeShape](https://dev.opencascade.org/doc/refman/html/class_b_rep_extrema___dist_shape_shape.html): distance and witnesses; distinct from arbitrary wall-thickness semantics.
- [OCCT BRepAlgoAPI_Section](https://dev.opencascade.org/doc/refman/html/class_b_rep_algo_a_p_i___section.html): geometric section operation.
- [Anthropic: writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents) and [code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp): tool clarity, context efficiency, discovery and execution tradeoffs.
- [Gemini function calling](https://ai.google.dev/gemini-api/docs/function-calling) and [structured outputs](https://ai.google.dev/gemini-api/docs/structured-output): provider capability references; application semantics still require validation.
- [Fusion surface continuity analysis](https://help.autodesk.com/cloudhelp/ENU/Fusion-Model/files/GUID-3F8BA6D3-5DF2-49FA-BE7D-8CCEF718C795.htm) and [curvature maps](https://help.autodesk.com/cloudhelp/ENU/Fusion-Model/files/GUID-11FD0802-0100-4131-88D7-37A41F74C6FB.htm): examples of focused surface-inspection modes.
- [NASA Systems Engineering Handbook: product realization](https://www.nasa.gov/reference/5-0-product-realization/): distinction between checking requirements and validating intended use. This plan borrows that distinction, not NASA's project governance process.
- [MIT solid mechanics reference sheet](https://ocw.mit.edu/courses/1-050-solid-mechanics-fall-2004/fd4eff39aec922b8c07660006f40686e_pset04_11.pdf): ideal end-loaded cantilever relation used in the hypothetical analysis example.

Current online OCCT documentation may describe a different version from the app's pinned build. API availability, tolerances and behavior must be confirmed against that build in the later integration stage.

## Appendix C. Source inspection map

All links below use the reviewed commit rather than a moving branch. Line anchors identify relevant entry points; the design conclusions also used surrounding code and related callers.

| Source | Relevant finding |
|---|---|
| [Kernel interface](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/backend/occt/shim/occt_capi.h) and [implementation](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/backend/occt/shim/occt_capi.cpp) | Native operations, validity/volume, topology metadata, taper, exchange and existing geometry safeguards |
| [Part model](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L2241) | Feature classes, serialization, state and rebuild signatures |
| [Edge matching](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L2103) | Scored fingerprint matching with displacement/ambiguity protection |
| [Face matching](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L3400) | Different matching policy, mesh-derived witnesses, re-anchoring and partial selection behavior |
| [Rebuild and last-good geometry](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/part_model.dart#L9541) | Requested state and displayed/computed shape need distinct freshness reporting |
| [Feature application](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L12919) and [part undo](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L13202) | Existing session/commit/error/history behavior differs from proposed atomic transactions |
| [Hole application](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L10460) | Command completion must be distinguished from successful feature computation |
| [Parameters](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/params.dart), [constraints](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/constraints.dart), [solver](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/solver.dart) | Sketch constraints, expression semantics and native parameter foundations |
| [Expression update path](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L18211) | Dependency reevaluation and frozen-value behavior need explicit agent status |
| [Measurement](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/measure.dart) | Analytic and approximate methods must retain method/coverage information |
| [Sections](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/section_view.dart) and [still rendering](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L4553) | Existing visual foundations; symbolic inspection is additional behavior |
| [Work geometry](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/work_features.dart) | Datums and plane construction support explicit functional frames |
| [Assembly](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/assembly.dart) and [assembly solver](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/asm_solver.dart#L83) | Occurrences, shared sources, residuals, degrees of freedom and constraints |
| [Documents](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/doc_file.dart) | Native persisted document foundation |
| [Materials](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/materials.dart) | Appearance is not an engineering material model |
| [Exports](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L7512) and [mesh conventions](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/mesh_io.dart#L384) | Output selection, error handling, units/orientation and exchange verification |
| [Imports](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L18910) and [DXF placement](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/app_state.dart#L19375) | Preserved source geometry, reconstructed mesh geometry and import transforms |
| [Ribbon](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/widgets/ribbon.dart) and [sketch tools](https://github.com/Toemeler/ipadprocad/blob/8141d2c5f3f8e6a1f96c4422523ed913e3f013c5/frontend/lib/tools.dart) | Breadth of the native action surface and coverage obligations |

**Deliverable boundary:** this is the finished workflow proposal for review. It establishes the intended behavior and how to evaluate it. App changes, provider integration, storage schemas and file-level engineering work belong to the next stage after the user accepts this direction.
