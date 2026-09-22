---
id: fdm/start-here
title: FDM printing — start here
type: basics
process: fdm
triggers: [3d print, 3d druck, fdm, fff, print, drucken, filament, additive, gedruckt, printed part, druckteil, make it printable, druckbar]
depends_on: [fdm/basics/orientation-and-strength, design/start-here]
confidence: high
updated: 2026-09-22
---

# FDM printing — start here

An FDM printer squeezes a 0.4 mm thread of molten plastic and draws with it,
layer on layer, from the bed upwards. Everything the process can and cannot do
follows from that: the part is built from **stacked lines**, it can only build
on what is already there, and it is **weaker between layers than along them**.

## When this applies

Any part that will be printed on a filament printer: enclosures, brackets,
jigs, housings, mechanism parts, prototypes. Read this first, then follow the
pointers.

Not for resin printing (different rules — resin is isotropic and has no
overhang limit worth speaking of), and not for flat sheet parts, which belong
in [`laser/start-here`](../laser/00-start-here.md).

## Good starting values

Five numbers carry most of the process. An assistant that knows only these
will already avoid most unprintable output.

| What | Start with | Works between | Why |
|---|---|---|---|
| **Nozzle / line width** | 0.4 / 0.42 mm | 0.25–0.8 | every wall is a whole number of these — [`nozzle-line-width-layers`](01-basics/nozzle-line-width-layers.md) |
| **Layer height** | 0.2 mm | 0.1–0.3 | the vertical resolution, and the step size of every horizontal feature |
| **Self-supporting overhang** | 45° from vertical | 40–60 | shallower needs support — [`overhangs-and-bridging`](03-geometry/overhangs-and-bridging.md) |
| **Minimum wall** | 0.8 mm (2 lines) | 0.4–1.6 | one line is fragile, two is a wall, three carries load |
| **Z-strength** | 40–75 % of XY | — | the single most important design fact — [`orientation-and-strength`](01-basics/orientation-and-strength.md) |

## How to build it

The order below is the order that avoids reprints. It is also a good plan for
the assistant to state out loud, because each step names the documents to load.

0. **Choose the object's design systems** — radius set, spacing scale,
   proportion family — before anything below.
   → [`design/start-here`](../design/00-start-here.md)
1. **Decide the print orientation first.** Not last. Orientation decides
   strength, which surfaces are smooth, where supports go and how long it
   takes. Everything else is downstream.
   → [`orientation-and-strength`](01-basics/orientation-and-strength.md)
2. **Pick the material** for the job, not the shelf.
   → [`choosing-a-material`](02-materials/choosing-a-material.md)
3. **Draw the walls** as whole multiples of the line width.
   → [`walls-and-thin-features`](03-geometry/walls-and-thin-features.md)
4. **Check every overhang and bridge** against the chosen orientation.
   → [`overhangs-and-bridging`](03-geometry/overhangs-and-bridging.md)
5. **Size the holes and fits** — printed holes come out undersize.
   → [`holes-shafts-and-teardrops`](03-geometry/holes-shafts-and-teardrops.md),
   [`clearance-table`](04-fits/clearance-table.md)
6. **Add the features** — bosses, nut traps, ribs, snap fits.
   → [`05-features/`](05-features/)
7. **Chamfer the bottom edges** against elephant foot.
   → [`chamfers-fillets-elephant-foot`](03-geometry/chamfers-fillets-elephant-foot.md)
8. **Run the checklist.**
   → [`before-slicing`](08-checklists/before-slicing.md)
9. **Run the design critique.** Printable and good are two different
   questions about the same part.
   → [`design/design-critique`](../design/05-process/design-critique.md)

## When to do it differently

- **A cosmetic part, no load** → skip the orientation analysis; orient for
  surface finish and print time instead.
- **A part that must be strong in one direction** → orientation is the whole
  design. Nothing else you do compensates for a load pulling layers apart.
- **A part bigger than the bed** → split it deliberately rather than scaling
  down. → [`splitting-large-parts`](05-features/splitting-large-parts.md)
- **A part that needs threads** → do not print them. Use a heat-set insert or
  a nut trap. → [`screw-boss-heat-set-insert`](05-features/screw-boss-heat-set-insert.md)
- **Flat plate-like parts in quantity** → a laser cutter will be faster and
  cheaper. → [`laser/start-here`](../laser/00-start-here.md)

## Images

![how to read every diagram in this knowledge base](../laser/01-basics/img/fig-diagram-legend.svg)
*Grey is material, white is empty air, blue is the measurement the rule is
about, red marks the mistake and green the fix.*

## Source & date

- Structure and pointers written for this repository, 2026-09-22.
- Headline numbers: [UltiMaker — design for FFF printing](https://ultimaker.com/learn/design-for-fff-3d-printing-maximize-your-success/),
  [Hydra Research — design rules](https://www.hydraresearch3d.com/design-rules).
- `confidence: high` for the process description; individual numbers carry
  their own confidence in their own documents.
