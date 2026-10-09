# Native modelling workflow (desktop/legacy)

The iPad now uses real on-device build123d Python; see
[AI_BUILD123D.md](AI_BUILD123D.md). This document describes the native program
path retained for desktop use and its regression coverage.

## Upstream analysis

Reviewed `earthtojake/text-to-cad` at `523ae2134` (cadgen 0.7.19), against
ipadprocad's `20e8b2da` baseline. Upstream is an MIT-licensed CAD toolkit and
agent playbook, not a hosted AI model or a special pretrained modelling engine.
Its agent writes parameterized Python/build123d programs; cadgen runs them using
OpenCascade and produces independently readable STEP/mesh artifacts. The agent
checks dimensions and topology, reviews rendered snapshots, repairs the source,
and regenerates the result. Its sample models are examples, not a training set
that the app can install to make its provider more capable.

The useful mechanisms are:

- Explicit dimensions, functional datums, named parameters and manufacturing
  assumptions, rather than inferred coordinates or a fixed example design.
- Durable source programs that can be edited and regenerated consistently.
- Checks on actual built geometry, including interfaces and topology; a
  successful CAD operation is not sufficient evidence of a correct design.
- A visual review after visible changes, with views chosen to expose features.
- Repairing the failing construction while retaining the user's requirements.

Relevant upstream sources: `skills/cad/SKILL.md`, and its references
`cad-brief.md`, `build123d-modeling.md`, `inspection-and-validation.md`,
`repair-loop.md`, `snapshot-review.md`, and `packages/cadgen/README.md`.
The upstream notice is preserved in [text-to-cad-LICENSE.txt](third-party/text-to-cad-LICENSE.txt).

## Integration into ipadprocad

ipadprocad already has an OpenCascade kernel, an editable sketch/feature
compiler, measurements, snapshots, and an iterative provider connection.
Its native whole-part `program` workflow existed but was disabled by default.
The legacy instructions told the model not to plan, and a program's `say`
could end a turn before the provider had read the resulting view/report.
Program identities and previous steps also lived only in executor memory.
An overlap heuristic could automatically delete another named program part.

The integration uses the native program compiler and transfers upstream's
source/validation/review workflow to it. It does not run arbitrary Python on
an iPad or add a remote modelling service. Sketches, solids, holes and lofts
remain ordinary timeline features; existing provider settings, UI, undo,
save and live viewport are retained.

### Build and review

Native programs are now the default instructions. They cover whole parts in
world millimetres with Y up, retain explicit named parameters, and ask for
missing interface dimensions only when needed. Assumptions can be recorded
through `brief_note` actions alongside the program.

A changed program always receives another provider round with the actual
report and, for image-capable providers, the attached post-build view. Its
own `say` cannot bypass that review. The agent can inspect hidden features
with `look` or `section`, repair the program, or finish with a title/say-only
block. Repairs get a new review. Geometry checks still gate completion; an
exhausted repair budget cannot approve a title/say with outstanding problems.
A missing image remains an explicit visual-verification limitation.

### Source and identity

Optional `aiPrograms` metadata is saved inside the existing part document.
It contains symbolic steps and variable definitions, resolved values/steps,
body identity, check failures and an authoring fingerprint. It participates
in the normal save/load and undo/redo snapshots. Current sources are included
in bounded document context without truncating individual formulas.

Executors rehydrate state for the document they operate on, including after
undo or reopen. A manual timeline/sketch geometry edit invalidates the source;
a stale replay is refused, and the assistant is directed to edit the current
features or append a new program to the existing body. A new part name creates
a new part. Geometric overlap never authorizes automatic deletion.

Streamed construction remains available for new parts. Replacements and
appended edits run after the complete program arrives. Cancelled or failed
streams restore the pre-stream snapshot before the next request proceeds.

### Geometry

`loft` is now available inside native programs:

```json
{"part":"transition", "steps":[
  {"loft":{"plane":"xz", "ruled":true, "sections":[
    {"at":0, "outline":{"rect":[-20,-20,20,20]}},
    {"at":30, "outline":{"rect":[-10,-10,10,10]}}
  ]}}
], "expect":{"size":[40,30,40], "volume":28000, "pieces":1}}
```

Each section becomes an editable sketch and the transition an editable
LoftFeature. It supports 2–20 parallel sections and add/cut/common modes.
Repeated lofts require explicitly translated sections. A hollow transition
can be made by cutting an inner loft from the outer one.

Programs report positive volume and native B-Rep validity, alongside existing
size/capacity/hole/section/piece/interference checks. Unknown expectation keys,
malformed sizes/sections and failed hole measurements are reported as failed
checks rather than silently ignored. Successful repairs clear prior failures.

## Validation and limits

The regression suite is `frontend/test/ai_native_workflow_test.dart` and runs
alongside program/operation tests in `.github/workflows/ai-bench.yml` with the
real OpenCascade kernel. It exercises review/image delivery, an incorrect
height followed by a measured repair, symbolic source persistence, edits by a
new executor, manual-edit preservation, rollback/undo/redo, aborted streams,
provider failure cleanup, a loft with analytically known volume, and failed
unsupported checks. Existing replay scenarios remain available.

Run locally from `frontend`:

```bash
PROTOTYPE_NATIVE_DIR=/path/to/native flutter test \
  test/ai_native_workflow_test.dart test/ai_program_test.dart \
  test/ai_real_kernel_test.dart test/kernel_fault_test.dart
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
```

Provider-generated design quality still depends on the selected model and
its vision capability. Deterministic tests establish construction and loop
behaviour; they do not establish a live-model success rate or certify strength,
printability, wall thickness or fit. Use the existing opt-in `AI_BENCH=live`
benchmark with a configured provider key to measure generated design quality
and latency. No live provider credentials were available for this integration.

Local validation on this branch: 327 assistant tests passed with the native
library from the matching `build-20e8b2d` Linux release, including all new
workflow tests and existing kernel fault tests. All 12 main replay benchmark
scenarios passed. Flutter analysis completed with zero errors; existing
repository warnings and informational diagnostics remain. The iOS package
has not been built or published from this environment.
