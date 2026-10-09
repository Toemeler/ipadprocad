# On-device build123d modelling

The iPad assistant now generates **real build123d 0.11.1 Python**. The app bundles
Python/Pyodide and the OCP.wasm port of OpenCascade's Python bindings. The code
runs entirely on the iPad in a WebKit Web Worker. There is no external modelling
worker, runtime package download, endpoint setting or separate modelling account.
The selected AI provider still receives the user's request and model context;
local geometry execution does not make cloud AI inference local.

## What was taken from text-to-cad

`earthtojake/text-to-cad` at `523ae2134` is a CAD toolkit and agent instruction
set, not a specially trained model. Its key modelling approach is unrestricted
parametric build123d source followed by actual geometry checks, visual inspection
and source-level repairs. The app's instructions adapt its brief, construction,
selection, placement, inspection, snapshot-review and repair guidance. They do
not translate Python into the app's old restricted primitive JSON program.

The app owns rendering and document persistence, so it does not embed cadgen's
CLI, filesystem decorators or separate viewer. It runs the actual build123d
geometry API and substitutes live native CAD feedback for exported viewer files.
MIT notices are in `docs/third-party/`. Additional binary dependency notices are
collected in the offline runtime bundle during packaging.

## How a model reaches the live viewport

1. The existing AI provider produces a `build123d` action containing one complete
   script and a stable model name. The iOS workspace offers this protocol by
   default. Native primitive programs are refused on this path.
2. The local worker imports build123d. The script calls
   `publish(current_shape, "Feature description")` after major completed
   operations. These are real geometry checkpoints during execution, after the
   AI has written its script; incomplete Python is not executed while typing.
3. Each checkpoint carries a STEP B-Rep in the app's coordinate frame. Flutter
   imports it through the existing native OCCT kernel and displays it in the
   RealityKit/GPU/CPU viewport. A changing feature label appears in the AI status.
4. Preview geometry is transient. It is excluded from document JSON, export and
   the feature timeline. Existing bodies remain intact beneath a replacement
   preview. Cancellation terminates the worker and clears only that preview.
5. Once Python finishes and the native kernel accepts the final valid solids,
   the app commits imported-result features as **one undoable change**. Python,
   parameters, checks and immutable STEP sources travel with the saved document.
6. The model receives Python errors/traceback, native volume/validity, actual
   shape measurements and a rendered view when the provider supports images.
   A build cannot close with its predicted `say`: the next AI round must inspect
   the result, repair it or finish after review.

Generated bodies are native CAD solids you can select, measure and add features
to. Their internal build123d operations are **not automatically converted to
individual editable Flutter sketches/features**. Parametric AI revisions edit
the saved Python. Manual downstream changes cause a fingerprint mismatch and
prevent stale source from overwriting them.

## Modelling protocol

```json
{"title":"Building bracket","actions":[{"op":"build123d","part":"bracket",
 "code":"import build123d as bd\nwidth,depth,height=40,30,20\nresult=bd.Box(width,depth,height,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN))\npublish(result,'Base block')\nresult -= bd.Cylinder(4,height+2).translate((0,0,height/2))\npublish(result,'Through bore')",
 "checks":{"size_mm":[40,30,20],"solids":1}}]}
```

Use a stable `part` name to regenerate a model. Code must assign its final Shape
or BuildPart to `result`; builders, algebra, curves, booleans, lofts, revolves,
sweeps and finishing are real build123d operations. Text can use the bundled
`Inter` font. The script has a maximum of 32 live checkpoints and 150 seconds.

`inputs: ["Solid1"]` makes the exact native body available as
`import_existing("Solid1")`. Optional `replace: ["Solid1"]` appends its changed
result to that body while preserving earlier native authoring. This requires one
input body and one result solid. Input B-Reps are snapshotted immutably so
subsequent source revisions rebuild from the original geometry instead of
repeatedly applying a transform to their previous output. Other bodies remain.
An edit made during execution invalidates that result and is retained.

Python uses conventional **Z up**, millimetres and degrees. The app uses **Y up**:
app `(x,y,z)` becomes Python `(x,-z,y)`, Python `(x,y,z)` becomes app `(x,z,-y)`.
Inputs and exports apply that rotation automatically; instructions distinguish
context coordinates from Python coordinates.

Checks support `size_mm: [dx,dy,dz]`, `volume_mm3: [min,max]` and `solids: integer`,
in the Python frame. Bad checks and invalid/non-solid results fail explicitly.
Measured requirement failures reach the model as open problems for repair.
Python assertions can check interfaces and detailed dimensions. Surface-only
output and separate motion/assembly constraints are not supported by this bridge.

## Offline packaging

The pinned bundle is approximately 73 MB before IPA compression. Large binaries
are generated assets rather than committed Git blobs. The lock file contains
exact versions, URLs and SHA256 hashes for Python, packages and WASM bindings.
The iOS build workflow runs the bundler **before** `flutter build`:

```sh
python3 -m pip install packaging
python3 tools/modelling/bundle_runtime.py
```

Normal builds do not resolve dependency versions. Maintainers can intentionally
regenerate the lock with `--resolve`, then rerun browser and native tests. The
core pins are Pyodide 0.29.5/Python 3.13, build123d 0.11.1 and OCP 7.9.3.1's
compatible `pyemscripten_2025_0_wasm32` wheel. Mismatched native wheels are refused.
No package resolution or downloading happens on the iPad.

The in-repo `native_menu` plugin registers a separate local CAD channel. Its
nonpersistent WebKit page is served by a loopback-only static asset listener
under a random route. It can serve only the signed runtime asset directory.
Navigation and CSP forbid other origins. Model Python lives in a Worker without
the main page's WebKit message handler, app files or credentials. The Python
filesystem is WASM memory, carrying only explicit input geometry. Stopping the
build destroys execution even if Python or OCCT does not return cooperatively.
The existing iOS scaffold already permits local networking for this loopback
origin. The listener does not bind to the LAN.

The original native program engine remains available on desktop; this change
adds the local WebKit runtime to iOS, not a desktop Python installation.

## Verification

`tools/modelling/test_wasm.py` executes actual build123d/OCP.wasm geometry under
CSP in Chromium and WebKit, verifies analytic volumes and dimensions, STEP/input
coordinate round trips, hollow bodies, lofts, Python failures, failed requirements,
blocked network access, cancellation and restart. No LLM/provider key is required.
The dedicated workflow runs both browser engines on runtime changes.

```sh
python -m pip install playwright
python -m playwright install --with-deps chromium webkit
python tools/modelling/test_wasm.py --browser all
cd frontend
PROTOTYPE_NATIVE_DIR=<kernel lib directory> flutter test test/ai_build123d_test.dart
```

Native integration tests use a STEP generated by the real WASM runtime, not a
fake box kernel. They verify preview exclusion from export/save, one-step
undo/redo, native geometry, replacement history, immutable original inputs,
source protection, cancellation and concurrent user edits. Controller coverage
also checks that build123d source receives image feedback before completion.

The `ios-bridge` CI job compiles Flutter and the actual Swift plugin against the
iOS SDK without signing, then verifies the runtime assets inside the app bundle.
The initial integration passed this check and both browser engines in
[GitHub Actions run 37940597572](https://github.com/Toemeler/ipadprocad/actions/runs/37940597572).
Browser WebKit and an unsigned iOS compile are not an installed iPad test. A
signed build still needs device verification for memory, WebKit process lifetime
and smooth viewport updates.
There is no live LLM quality benchmark yet: no provider credential is configured
in this development environment.
