---
id: laser/materials/solid-wood
title: Solid wood — grain, and what it does to a cut
type: material
process: laser
triggers: [solid wood, massivholz, hardwood, hartholz, walnut, nussbaum, oak, eiche, maple, ahorn, bamboo, bambus, veneer, furnier]
depends_on: [laser/materials/material-table]
confidence: medium
updated: 2026-09-22
---

# Solid wood — grain, and what it does to a cut

Solid wood is the only material in this folder whose properties change
*within one part*. The beam crosses early wood and late wood, soft and hard
bands, and cuts each at a different rate. That is a defect in a jig and the
entire point in a decorative piece.

## When this applies

Visible one-off pieces, signage, inlay, boxes where the material is the point.
Not for anything that needs dimensional repeatability across a batch.

## Good starting values

| What | Start with | Works between | Why |
|---|---|---|---|
| Kerf, 3 mm | 0.30 mm | 0.25–0.35 mm | varies *along* the cut as the grain changes |
| Minimum hole ⌀ | 1.5× thickness | 1×–2× | short grain around a small hole breaks out |
| Minimum web | 2× thickness | 1.5×–3× | a web running along the grain splits under almost no load |
| Press-fit interference | 0.06 mm | 0.04–0.10 mm | with the grain it splits; across it, it grips |
| Comfortable cut thickness | ≤ 5 mm | 8 mm on light species | |

### Species behaviour

| Species | Cuts | Engraves | Note |
|---|---|---|---|
| Maple, birch, poplar | cleanly, pale edge | high contrast | the best all-round choice |
| Cherry | cleanly | excellent | darkens attractively with age |
| Walnut | well | low contrast (already dark) | expensive; engraving barely shows |
| Oak, ash | unevenly — hard/soft bands | patchy | open pores trap soot |
| Bamboo (laminated) | very cleanly | excellent, high contrast | dense and uniform; behaves more like MDF than wood |
| Any resinous softwood (pine, fir) | flares, sticky edge | poor | resin pockets can flame |

## How to build it

1. **Orient the part on the grain deliberately.** Long thin features must run
   *with* the grain or they snap; slots must be cut *across* it or they split.
2. Expect the kerf to vary along a single cut. For joints, use the widest
   value from the comb test, not the average.
3. Mask, or expect soot in the open pores of oak and ash — it does not sand
   out easily.
4. Cut a test piece from the *same board*. Species is not enough information;
   one walnut board cuts differently from the next.

## When to do it differently

- **A batch of identical parts** → laminated bamboo or laser ply. Solid wood
  will not repeat.
- **Very thin filigree** → across-grain webs will break in handling. Increase
  minimum web to 3× thickness, or use acrylic.
- **Dark species with an engrave** → engrave-then-paint-fill, or choose a pale
  species. A walnut engrave is nearly invisible.

## Images

![the same slot cut across and along the grain](img/fig-grain-direction.svg)
*The same slot, cut across the grain and along it. Along the grain the short
fibres between the slot and the edge split out under hand pressure; across it
they hold.*

## Source & date

- Species behaviour: [Hobbyist Laser Calc — laser cutter settings for wood](https://hobbyistlasercalc.com/laser-settings-wood),
  [CoMakingSpace wiki — laser cutter material settings](https://wiki.comakingspace.de/Laser_Cutter_Material_Settings).
- `confidence: medium` — grain behaviour is certain, numbers are indicative.
