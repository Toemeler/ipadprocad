---
id: laser/checklists/before-you-export
title: Before you export — the laser checklist
type: checklist
process: laser
triggers: [checklist, checkliste, before cutting, vor dem schneiden, ready to cut, fertig, review, prüfen, final check, abschlusskontrolle, export check]
depends_on: [laser/fileprep/common-errors, laser/basics/kerf-and-tolerance, laser/materials/wood-overview]
confidence: high
updated: 2026-09-22
---

# Before you export — the laser checklist

Twenty-four checks, grouped by what they protect. Running them takes about two
minutes and catches nearly everything that turns a sheet of material into
firewood.

## When this applies

Immediately before any file leaves for the machine. Also a good structure for
the assistant to walk through out loud when a user asks "is this ready?"

## Good starting values

### Safety — check first, always

- [ ] The material is **not** on the [`never-cut-these`](../02-materials/never-cut-these.md) list.
- [ ] The material composition is actually known, not assumed from appearance.
- [ ] No part of the geometry lies outside the machine bed.

### Wood

- [ ] The sheet is **flat** — no bow that would take part of the cut out of focus.
- [ ] The adhesive class is known (E0 / CARB-2 preferred, E1 acceptable) and extraction is running.
- [ ] Grain direction is decided for every part: long parts along it, slots across it.
- [ ] Every part that will be **glued** has a slip fit, not a press fit.
- [ ] The visible faces will be **masked** before cutting.
- [ ] Internal corners that will need sanding are reachable.

### Dimensions

- [ ] Sheet thickness has been **measured**, not taken from the label — "3 mm" ply is 2.6–3.3 mm.
- [ ] Kerf value is from [`machine-assumptions`](../01-basics/machine-assumptions.md), or the baseline is being used knowingly.
- [ ] Kerf compensation is applied **exactly once** — in the geometry *or* in the machine, not both.
- [ ] Every mating pair has a declared fit: press, slip, clearance or running.
- [ ] Slot widths derive from the mating part's measured thickness.
- [ ] A calibration rectangle (100 × 100 mm) is present on the `Guide` layer.

### Geometry

- [ ] No hole smaller than the material thickness.
- [ ] No web narrower than 1.5 × material thickness.
- [ ] No two cuts closer than 0.5 mm.
- [ ] Cut-through text has bridges, or uses a stencil typeface.
- [ ] Part spacing is ≥ 2 mm (≥ 3 mm for MDF).

### File hygiene

- [ ] Duplicate lines deleted.
- [ ] All cut contours closed.
- [ ] Text converted to outlines.
- [ ] Cut and score layers set to hairline; engrave layers filled with no stroke.
- [ ] Construction and guide geometry removed or excluded.
- [ ] Layers named and coloured per [`layers-colours-linewidth`](../06-file-prep/layers-colours-linewidth.md).
- [ ] Cut order is engrave → score → internal cuts → outline.

### After export

- [ ] The exported file has been **re-opened in a different application** and looks right.
- [ ] The calibration rectangle measures 100 mm.

## How to build it

Work top to bottom. The order is deliberate: safety cannot be fixed later,
dimensions are expensive to fix, and file hygiene is cheap.

When something fails a check, fix it and **restart from the top of that
group** — fixes introduce their own errors, especially in the file-hygiene
group where a union or a path repair can reopen a contour.

## When to do it differently

- **A one-off decorative part** → the dimensions group can be skipped
  entirely. Safety and file hygiene cannot.
- **A repeat of a job that already cut correctly** → check only what changed,
  plus the safety group.
- **Someone else's file** → run everything, and assume nothing about the
  layers.

## Images

None — this document is a checklist.

## Source & date

- Assembled from the documents it links to, 2026-09-22.
- `confidence: high`.
