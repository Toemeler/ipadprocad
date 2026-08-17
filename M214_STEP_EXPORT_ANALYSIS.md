# M214 — "The STEP export tells the truth" — Analysis & Fix

Report: *"the step exporter has a lot of problems. some features are not correctly
exported like holes or fillets and stuff. also the share button only opens the part
currently somehow."*

Both are reproducible from the code alone. Neither needed a device log, because
neither is a kernel bug — the geometry OCCT built was always correct. The export
picked the **wrong solids** and then **unioned** them, and the share button reached
the export through the **navigation** entry point. Line references below are to the
tree before this commit.

---

## 1. Why holes and fillets vanished

### The fold stores history, not just the result

`recomputeAllFeatures` (`part_model.dart:5040-5179`) folds the feature list into
bodies. The crucial property is at `part_model.dart:5106` and `:5158`:

```dart
// Unchanged: f.solid already holds the folded result AT THIS POSITION
...
final combined = combineSolids(kernel, f.output, prev.solid!, f.solid!);
if (combined != null) {
  f.disposeSolid();
  f.solid = combined;
  prev.consumedByJoin = true;   // <-- prev is history now
}
```

Every feature keeps **its own running accumulation**, and the feature it grew out of
is flagged `consumedByJoin`. So a three-feature part holds three live `KernelSolid`s:

| feature | `f.solid` is | `consumedByJoin` |
|---|---|---|
| Extrusion1 (block) | the block | `true` |
| Extrusion2 (`cut`) | block − hole | `true` |
| Fillet1 | (block − hole), filleted | `false` |

Only the last one is the part. That is exactly what every other consumer of the model
already knew:

- `reality_scene.dart:56` — `f.visible && f.solid != null && !f.consumedByJoin && !f.rolledBack`
- `app_state.dart:3120` (gallery thumbnail) — same four clauses
- `part_model.dart:3093` (`bodyNames`) — `f.solid == null || f.consumedByJoin` → skip
- `part_model.dart:5449`, `:5888`, `:5930`, `viewport3d.dart:670` — same rule

### The exporter was the one place that did not

`app_state.dart:3237-3240`:

```dart
final solids = [
  for (final f in p.features)
    if (f.solid != null) f.solid!      // <-- no !consumedByJoin, no !rolledBack
];
```

Three solids went to the kernel instead of one.

### …and the kernel then put the material back

`part_model.dart:4214-4255` unioned whatever list it was handed:

```dart
if (shapes.length == 1) return shapes.first.exportStep(path);
...
final seed = ffi.fuse(s, s);      // "cheap copy via self-union"
...
final fused = ffi.fuse(acc, s);
```

Union is the exact inverse of what the later features did:

```
block ∪ (block − hole)      = block          → the hole is gone
block ∪ filleted(block)     = block          → the fillet is gone
```

**This is the whole bug.** It is a perfect explanation of the symptom — a hole is
plainly visible on screen (the viewport reads only the non-consumed solid) and
plainly absent from the file (the export read all of them and unioned). A `join`
feature survived, which is why the exporter looked like it "mostly worked": union
of a block and block∪boss is block∪boss, so additive parts came out right and only
subtractive and body-modifying features were destroyed. That matches "holes or
fillets **and stuff**" precisely.

Secondary damage from the same union:

- **Two separate bodies became one.** A part with two disjoint solids was fused into
  a single STEP product, losing body identity that the receiving CAD would otherwise
  show as two bodies.
- **`ffi.fuse(s, s)` as a copy.** A self-union is a full boolean against identical
  geometry — the most expensive possible way to obtain a handle, and one that can
  regularise the shape into something other than what was modelled.
- **A failed union meant no export at all.** `BRepAlgoAPI_Fuse` on a many-faced part
  is not failure-free; when it failed, an otherwise perfectly exportable part
  produced nothing.
- **Rolled-back features.** The filter also lacked `!rolledBack`. That one was
  latent rather than live (`part_model.dart:5071` disposes a rolled-back feature's
  solid, so it is `null` anyway), but the export was relying on a detail two
  functions away instead of stating its own rule.

### Fix

`partExportBodies(PartModel)` (`part_model.dart`) is now the single named
definition of "the model as a list of bodies", carrying the same three clauses the
viewport uses, plus a documented reason why `visible` is deliberately **not** one of
them (M182: visibility is a display property; hiding a body to see past it must not
drop it from the file you send to the shop — Inventor exports hidden bodies too).

`PartKernel.exportStepBodies` replaces the union with one named STEP product per
body. `OcctPartKernel` refuses a body whose B-Rep is gone rather than silently
skipping it: handing over a file that is quietly missing part of the model is the
one outcome an exporter must never have.

---

## 2. Why Share opened the part

`home_view.dart:325-340` → `AppState.partExportStep` → `app_state.dart:3229`:

```dart
final wasLoaded = parts.containsKey(name);
if (!wasLoaded) await openPart(name);      // <-- navigation
```

`openPart` (`app_state.dart:3041-3047`) ends with:

```dart
if (!openTabs.contains(name)) openTabs.add(name);
curTab = name;
activeChild = null;
editingLayer = null;
tool = Tool.none;
_reanalyze();
notifyListeners();
```

So sharing a part from the gallery added a tab, made the part the current document,
cleared the active tool and rebuilt the viewport. `wasLoaded` was computed and then
**never read again** — the intent to undo the open was written down and never
implemented.

The sketch side never had this problem: `sketchExportPath` (`app_state.dart:1740`)
loads a headless `SketchModel` via `_loadSketchIn` and exports from that. The part
side simply never got the equivalent.

### Fix

`openPart` is split. `_loadPartModel(name)` reads the document, attaches child
sketches, re-reads imported STEP bodies and folds the features — and touches no UI
state and does not register itself in `parts`. `openPart` is now that plus the tab
bookkeeping. `partExportStep` calls `_loadPartModel` directly and disposes the
result in a `finally` — `PartModel.dispose()`, not just the feature solids, because
the headless copy also owns a solver engine per child sketch (otherwise every share
of a closed part leaked all of them).

Two related side effects went with it:

- **`await savePart(name)` ran unconditionally.** Exporting a part rewrote the
  document, its thumbnail and its modified date — including for a part loaded purely
  to export it, where the save was a byte-for-byte copy of what was already on disk.
  It is now done only for a part the user actually has open, which is the only case
  that can have unsaved edits.
- **The kernel-availability check ran after the load.** It now runs first: without a
  kernel there is nothing to export whatever the document holds.

---

## 3. What else was not production-ready in the written file

The shim's `occt_export_step` (`occt_capi.cpp:1341-1359`) was five lines with every
translation parameter left at its default:

```cpp
STEPControl_Writer writer;
if (writer.Transfer(shape->s, STEPControl_AsIs) != IFSelect_RetDone) ...
if (writer.Write(path) != IFSelect_RetDone) ...
```

| Problem | Why it matters | Fix |
|---|---|---|
| **Units never pinned.** `Interface_Static` is process-global and persistent. The app *does* read STEP files in the same process (`occt_import_step`, on every reopen of a part with an imported body). | A file silently written in inches is a part machined 25.4× wrong. This is the only failure here that destroys physical material. | `write.step.unit = MM`, **read back and verified**; the export is refused rather than written if it did not take. |
| **Schema never pinned.** The header advertised AP214; nothing enforced it. | Advertised and actual schema agreed only by coincidence. | `write.step.schema = AP214IS`, explicitly. AP214IS and not AP242 on purpose: this file's job is to open everywhere, including older shop readers. AP242 only starts paying for itself with colour/PMI, which needs XCAF — see the limitation below. |
| **No product name.** OCCT's generic default was used for every body of every part ever exported. | The receiving CAD showed one anonymous body. | `write.step.product.name` is set **between transfers**, which is what gives each body its own name (`STEPControl_ActorWrite` reads it at transfer time). |
| **No file header.** | Every file claimed to be an unnamed model from a generic translator; the document's own name appeared nowhere in the file the user just shared. | `FILE_NAME` carries the document name and the originating system. The array-valued header fields (author, organisation, description) are deliberately left alone — they are addressed by index, and writing index 1 of a list the writer may not have sized would throw, trading a lost export for a cosmetic string. |
| **Curve mode / precision mode unset.** | Readers differ in whether they trust the 3D curve or the pcurve; a trimmed cylindrical face — i.e. every hole in this app — is exactly where that bites. | `write.surfacecurve.mode = 1` (write both), `write.precision.mode = 0` (per-shape tolerance, so a fine fillet is not flattened to a coarse global). |
| **Failure message named nothing.** "shape transfer failed" on a ten-body part. | Not actionable. | The failing body is named: `body "Solid7" (7 of 10) could not be transferred`. |
| **Stale files could be shared.** A failed export left the *previous* file at the same path. | Only the `return null` stood between yesterday's geometry and the share sheet. | The target is deleted before the write, and a zero-byte/missing result after a "successful" write is reported rather than shared. |
| **A silently dropped body.** A feature that failed to build is simply absent from the export set. | The user gets a file missing part of their part, with no indication. | The names of features that failed to build are logged and surfaced in a toast alongside the successful export. |

`occt_export_step` is kept and now delegates to `occt_export_step_named` with n = 1,
so the two entry points cannot drift apart on units or schema. Shim ABI → **v17**.

---

## 4. Why this survived 211 milestones

There was **no test of the export path at all**. `grep -rn "partExportStep\|exportStep" frontend/test/`
before this commit matched only the four `exportStep` stubs in kernel fakes, all of
which `return false`. The one code path whose output leaves the device and gets
manufactured from was the one path with no coverage.

`frontend/test/m214_step_export_test.dart` now pins, on host with a fake kernel:

- a hole survives the export (the cut result reaches the kernel, not the block)
- a fillet survives the export
- block → hole → fillet exports **one** body, with the arithmetically exact volume
- two separate bodies stay two bodies, with distinct names
- a body below End of Part is not in the file
- a **hidden** body **is** in the file
- exporting a closed part does not open it, does not touch `curTab`/`openTabs`,
  does not leave a model in `parts`, and does not rewrite the document
- exporting an open part leaves it open, current, and with its solids intact
- a failed write leaves no stale file to be shared
- a kernel that reports success without writing is caught, not shared
- no kernel is reported honestly rather than faked

Smoke test `[33]` in `backend/occt/tests/smoke_occt.c` covers the native half against
real OCCT: two disjoint boxes (1000 mm³ and 125 mm³) exported and re-imported must
come back as **two** solids totalling 1125 mm³ — a fused export fails this — with
both body names and the document name present in the file, millimetres declared, and
every refusal path (null array, n = 0, empty path, null body in the set) returning 0
without crashing.

---

## Known limitation (deliberate, documented)

Per-body **colours** and a real **assembly tree** need `STEPCAFControl_Writer` and an
XCAF document. The vendored OCCT is configured with
`-DBUILD_MODULE_ApplicationFramework=OFF` (`backend/occt/VENDOR.md:67`,
`.github/workflows/occt-build.yml:56`), so `TKXCAF`/`TKLCAF` are not built and those
classes are not linkable. Enabling them means rebuilding the OCCT install, adding
toolkits to `backend/occt/CMakeLists.txt`, and growing the iOS binary — a separate,
deliberate decision, not something to smuggle in here. Everything achievable with
`STEPControl_Writer` (units, schema, per-body product names, file header,
multi-body output) is done.
