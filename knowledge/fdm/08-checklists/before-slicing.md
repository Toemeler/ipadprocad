---
id: fdm/checklists/before-slicing
title: Before you slice — the FDM checklist
type: checklist
process: fdm
triggers: [checklist, checkliste, before printing, vor dem drucken, ready to print, druckbereit, review, prüfen, final check, is this printable, druckbar]
depends_on: [fdm/basics/orientation-and-strength, fdm/geometry/overhangs-and-bridging, fdm/fits/clearance-table]
confidence: high
updated: 2026-09-22
---

# Before you slice — the FDM checklist

Twenty checks, grouped. Two minutes, and it catches nearly everything that
turns twelve hours of printing into a bin item.

## When this applies

Immediately before export. Also a good structure for the assistant to walk
through when asked "is this printable?"

## Good starting values

### Orientation — decide this first

- [ ] The main load runs **across** layers, not pulling them apart.
- [ ] The intended orientation is recorded in the model (an arrow, a note, the filename).
- [ ] Holes that must be round have **vertical** axes.
- [ ] The part fits the build volume in that orientation.

### Geometry

- [ ] Every wall is a whole multiple of the line width (0.84 / 1.26 / 1.68 mm).
- [ ] No feature is thinner than one line width.
- [ ] Every overhang is 45° or less, or has a deliberate fix.
- [ ] Every bridge is within the material's limit, with both ends anchored.
- [ ] Every horizontal hole is a teardrop, a hex, or has a sacrificial bridge.
- [ ] Every bottom outside edge has a 0.5 mm chamfer.
- [ ] No fillet on a bottom outside edge.
- [ ] Internal load-bearing corners are filleted.

### Fits and hardware

- [ ] Every clearance is **diametral**, not per side.
- [ ] Holes carry the print allowance (0.2 mm on an M3 clearance hole).
- [ ] The material adjustment is applied (+0.05–0.1 mm for PETG, +0.2 for TPU).
- [ ] Every bought component was **measured**, not taken from a datasheet.
- [ ] Insert bosses have ≥ 1.6 mm of plastic around them and a base fillet.
- [ ] Nut traps are +0.2 mm across flats and +0.3 mm on depth.
- [ ] Snap-fit arms flex **in the layer plane** and have a root fillet.

### Export

- [ ] Units are millimetres; the bounding box checks out in the slicer.
- [ ] 3MF where possible; STL at 0.01 mm chord height otherwise.
- [ ] The slicer reports no mesh errors.
- [ ] The **sliced preview** — not the model preview — looks right.
- [ ] The material is stated with the part.

## How to build it

Top to bottom. Orientation first, because everything below it depends on the
orientation being settled — an overhang check against the wrong orientation is
wasted work.

When a check fails, fix it and restart from the top of that group.

## When to do it differently

- **A cosmetic one-off** → orientation and export groups only.
- **A reprint of something that already worked** → check only what changed.
- **Someone else's model** → run everything, and assume nothing about the
  intended orientation.

## Images

None — this document is a checklist.

## Source & date

- Assembled from the documents it links to, 2026-09-22.
- `confidence: high`.
