# tools/ipt — Autodesk Inventor part (.ipt) ⇄ Prototype part (.ptp)

Standalone (Python 3, `pip install -r requirements.txt`) and needs the app's
native kernel (`tools/desktop/build_native_windows.ps1` →
`frontend/build/native/prototype_native.dll`) for the replay.

```
py ipt2ptp.py Part.ipt                  # -> Part.ptp, full feature tree
py ipt2ptp.py Part.ipt --bodies-only    # -> exact bodies as imported solids only
py ptp2ipt.py Part.ptp -o back.ipt      # -> the Inventor part again
py check_geometry.py Part.ipt           # B-rep mapping self-check
py validate_step.py some.step           # load through the app's OCCT shim
```

## What converts

**.ipt → .ptp, 1:1 feature tree.**

* **Sketches**, every entity and constraint: points, lines, arcs, construction
  geometry; coincident / point-on-curve, horizontal, vertical, parallel,
  perpendicular, collinear, midpoint; every dimension as a named parameter
  (`d0`, `d1`, … with Inventor's values). Inventor's *offset* becomes
  concentric + equal + tangent + one gap dimension. Each sketch sits in
  Inventor's own frame. Every converted constraint is checked against the
  Inventor geometry (`check_sketch.py`), and the app's own solver accepts the
  result without moving anything (`frontend/test/m466…`).
* **Extrusions**: sketch, profile, distance, taper, direction (default /
  flipped / symmetric, read from the distance dimension's leader) and extent
  (through all), operation (new / join / cut, read from the faces the feature
  left in Inventor's result), body.
* **Fillets**: radius parameter and edges. The edges are found by replaying
  the tree in the app's kernel and picking, at each fillet, the edges whose
  blend at that radius is one of the faces Inventor tagged for that fillet.
* **Exact results**: Inventor's final bodies (exact B-rep, STEP) ride along
  as the stored result of each body's last feature. The app shows exactly
  what Inventor built until something in the tree is edited — Inventor's own
  model (`ResultCache` in `frontend/lib/part_model.dart`).
* Thumbnail, properties, and the Inventor original, byte for byte.

**.ptp → .ipt**: while the tree is the imported one (same features, every
stored result still valid — the app drops one exactly when an edit changes
its body) the original is written back byte for byte, with everything
Inventor had. After an edit the tool refuses: a new .ipt would need
Inventor's database written from scratch. Export STEP instead.

## Known limits

* **The app's kernel cannot rebuild every Inventor fillet.** OCCT has no
  rolling-ball-over-an-edge blend (a fillet running off one face onto the
  edge of a round Inventor made before). On the sample (`Handyhalterung`),
  Rundung4 onward fail to rebuild in the app. Until an edit, the stored
  result shows Inventor's exact body regardless; after an edit that forces a
  rebuild, those features fail honestly. The fillets' edge selections after
  the first unbuildable one are taken on the kernel's best-effort body and
  may differ from Inventor's.
* Projected geometry comes across as fixed reference geometry (construction +
  fix), not linked to the model edges.
* Face sketches carry their frame but no face reference, so they do not
  follow their face if it moves after an edit.
* Feature types met so far: extrusion, fillet. Others (revolve, hole,
  chamfer, pattern, …) raise `ConversionError`, and `ipt2ptp` falls back to
  exact bodies.

## The format, as far as it is known

| Layer | What it is |
|---|---|
| Container | OLE2 compound file |
| `\x05…` streams | OLE property sets, UTF-16 with name dictionaries (`ipt_container`) |
| `RSeStorage/B*`, `M*` | segment data / meta, each **zstd**-compressed after a small header |
| segment objects | 18-byte header, then objects back to back; object *i* spans `size_i + 9` bytes (sizes in the meta stream); references are `0x80000000 \| (index + 1)`; no class tags (`rse_segment`) |
| `PmBRepSegment` | an **ASM SAB** (`ASM BinaryFile4`): ACIS binary, cm (`asm_sab`) |
| `PmDCSegment` | parameters, sketches, features; also an ASM SAB with every extrusion's profile as a planar sheet body (`ipt_dc`, `ipt_model`, `ipt_features`, `ipt_profiles`) |
| `PmBrowserSegment` | model-tree node names |
| `PmGraphicsSegment` | display tessellation |

DC-segment details (all in the modules named above):

* parameter: name at +24 (length at +20), value and nominal at +36 +2·len;
* sketch entity: owner sketch reference at +24, flags at +20
  (`0x40` projected, `0x80000` construction, `0x40000` offset-made); a point
  has x,y at +28; a line/arc has a reference array at +28 (ends first, then
  points lying on it); an arc then a centre reference and its radius;
* sketch placement: origin, one in-plane axis and the normal; bytes 28/29 of
  the placement say whether that axis is x or y and whether it is reversed;
* constraints reference their system at +16; the class follows from size and
  participants (see `ipt_model._constraint`);
* a body's feature list holds one reference per feature in timeline order;
  reference value + 1 is the id in the B-rep face tags
  (`INV_NMX_BLEND_TAG`, `…SWEEPGENERATED_TAG`, `…FEATURE_DEPENDENCY_ATTRIB`).

SAB details: tag `0x0A` TRUE / `0x0B` FALSE; `{ ref n }` points at the n-th
`{ type` block, outer first; bs3 surface control points: u index fastest;
ACIS end multiplicity is `degree` (STEP needs `degree + 1`); edge parameters
negate once per reversal; cone `cos < 0`, torus `minor < 0`, sphere `r < 0`
and a spline's reversed flag mean an inward normal.
