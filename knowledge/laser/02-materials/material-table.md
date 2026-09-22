---
id: laser/materials/material-table
title: Material numbers — every sheet in one table
type: rules
process: laser
triggers: [material table, materialtabelle, compare, vergleich, kerf table, numbers, zahlen, thickness, dicke, minimum hole, stock sizes, standard thickness, lieferbar]
depends_on: [laser/materials/wood-overview, laser/basics/kerf-and-tolerance]
confidence: medium
updated: 2026-09-22
---

# Material numbers — every sheet in one table

The lookup table behind [`wood-overview`](wood-overview.md). Wood first,
because that is what this folder is for; everything else is below the rule.

Check [`never-cut-these`](never-cut-these.md) before any material that is not
on this list.

## When this applies

Looking up a number for a material already chosen. For *choosing* a material,
start at [`wood-overview`](wood-overview.md) instead — a table of numbers is a
poor way to make that decision.

## Good starting values

### Wood

| Material | Kerf @3 mm | Min hole ⌀ | Min web | Press fit | Edge | Engraves | Best for |
|---|---|---|---|---|---|---|---|
| **Birch plywood** | 0.28 mm | = t | 1.5 × t | **0.05–0.10 mm** | brown char, glue lines | good contrast | structure, boxes, everything |
| **Laser ply** (low glue) | 0.26 mm | = t | 1.5 × t | 0.05–0.10 mm | lighter char | good | when the edge shows |
| **Poplar ply** | 0.28 mm | = t | 2 × t | 0.05–0.08 mm | pale char | fair | cheap bulk, low load |
| **Solid basswood / maple** | 0.30 mm | 1.5 × t | 2 × t | 0.04–0.10 mm | pale, clean | **excellent** | visible pieces, engraving |
| **Solid walnut / cherry** | 0.30 mm | 1.5 × t | 2 × t | 0.04–0.10 mm | dark, clean | low (walnut) | premium faces |
| **Solid oak / ash** | 0.32 mm | 1.5 × t | 2 × t | 0.04–0.08 mm | uneven, sooty pores | patchy | avoid for engraving |
| **MDF** | 0.25 mm | = t | 2 × t | 0.05–0.10 mm | near black, furry | even, fuzzy | jigs, painted parts |
| **Laminated bamboo** | 0.25 mm | = t | 1.5 × t | 0.04–0.08 mm | pale, clean | **excellent** | repeatable visible parts |
| **Veneer 0.6 mm** | 0.15 mm | 1 mm | 1 mm | n/a | sealed | good | inlay, marquetry |

### Everything else

Covered because it turns up, not because it is the default.
→ [`non-wood-materials`](non-wood-materials.md)

| Material | Kerf @3 mm | Min hole ⌀ | Min web | Press fit | Edge |
|---|---|---|---|---|---|
| Cast acrylic | 0.17–0.20 mm | 1.5 mm | 1.5 mm | 0.025–0.05 mm | flame-polished |
| Extruded acrylic | 0.18–0.22 mm | 1.5 mm | 1.5 mm | 0.025–0.05 mm | glossy, crazes |
| Greyboard 1–2 mm | 0.08 mm | 1 mm | 1 mm | n/a | pale tan |
| Corrugated card | 0.12 mm | 3 mm | 2 mm | n/a | fluffy |
| Veg-tan leather | 0.20 mm | 2 mm | 3 mm | n/a | sealed, dark |
| Wool felt | 0.20 mm | 3 mm | 3 mm | n/a | sealed |
| POM (Delrin) | 0.20 mm | 2 mm | 2 mm | 0.05 mm | clean white |

### Stock thicknesses actually available

Designing to a thickness nobody sells is the cheapest mistake to avoid.

| Material | Common sheet thicknesses | Real tolerance |
|---|---|---|
| Birch ply | 3, 4, 6, 9, 12 mm | **2.6–3.3 mm on "3 mm"** — see [`plywood`](plywood.md) |
| MDF | 3, 4, 6, 9, 12 mm | ±0.2 mm |
| Solid hardwood (laser stock) | 3, 4, 5, 6 mm | ±0.2 mm, plus cupping |
| Bamboo | 3, 5, 6 mm | ±0.2 mm |
| Veneer | 0.5–0.6 mm | ±0.1 mm |
| Acrylic | 2, 3, 4, 5, 6, 8, 10 mm | ±0.15 mm (cast is worse) |
| Greyboard | 1.0, 1.5, 2.0 mm | ±0.1 mm |

### Practical cutting limits, 60–80 W CO₂

| Material | Comfortable | Possible, slowly | Do not |
|---|---|---|---|
| Birch ply | ≤ 6 mm | 9 mm | 12 mm — burns before it cuts |
| MDF | ≤ 6 mm | 9 mm | 12 mm |
| Solid hardwood | ≤ 5 mm | 8 mm (pale species) | 10 mm |
| Bamboo | ≤ 5 mm | 8 mm | 10 mm |
| Cast acrylic | ≤ 8 mm | 10–12 mm | >15 mm |

## How to build it

1. Choose the material at [`wood-overview`](wood-overview.md).
2. Take its kerf and minimum-feature numbers from the tables above as a
   **starting point**.
3. Replace the kerf with a measured one before anything has to fit.
   → [`kerf-test-comb`](../01-basics/kerf-test-comb.md)
4. Replace the thickness with a measured one, always.

## When to do it differently

- **A material not listed** → identify it first
  ([`never-cut-these`](never-cut-these.md)), then run the new-material
  procedure. → [`new-material-first-time`](../07-checklists/new-material-first-time.md)
- **A cutting service rather than your own machine** → ask for their kerf
  figures; most publish them.

## Images

![cut edge appearance across the wood family](img/fig-material-edges.svg)
*Birch ply, MDF, greyboard and cast acrylic. The cut edge is the property the
process gives you for free and the hardest to change afterwards.*

## Source & date

- Kerf and feature values: [CutLaserCut — laser kerf](https://cutlasercut.com/drawing-resources/expert-tips/laser-kerf/),
  [Box Studio — kerf reference table by machine](https://box-studio.cc/blog/2026-05-en-kerf-reference-table-by-machine),
  [SendCutSend — understanding small geometry](https://sendcutsend.com/blog/understanding-small-geometry-in-laser-cutting/).
- Plywood thickness tolerance: see [`plywood`](plywood.md) for the EN 315
  figures and their sources.
- `confidence: medium` — every kerf here is machine-dependent.
