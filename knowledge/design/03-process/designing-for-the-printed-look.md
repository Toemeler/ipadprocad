---
id: design/process/designing-for-the-printed-look
title: Designing for how a printed part looks
type: rules
process: design
triggers: [printed look, druckbild, surface, oberfläche, oberflaeche, finish, layer lines, schichtlinien, grain, maserung, orientation, ausrichtung, seam, naht, texture, textur, ugly, hässlich, haesslich, quality, qualität, qualitaet, visible, sichtbar, top surface, deckfläche]
depends_on: [fdm/basics/orientation-and-strength]
confidence: medium
updated: 2026-09-22
---

# Designing for how a printed part looks

An FDM part has a grain. Designing with it is the difference between a printed
object and an object that merely came out of a printer.

## When this applies

- Any part that will be printed and then looked at.
- Not to a part that will be sanded, filled and painted, where the surface is
  a substrate and none of this shows.

## Good starting values

**Orientation decides appearance before any feature does.** The same model
printed two ways does not look like the same object.

| Surface | How it comes out | Design response |
|---|---|---|
| Top, flat | best surface the machine makes | put the face that will be seen here |
| Bottom, on the bed | flat and slightly shiny, with an elephant's foot at the edge | chamfer 0.5–1 mm rather than fillet; see `fdm/geometry/chamfers-fillets-elephant-foot` |
| Vertical wall | even layer lines — a deliberate-looking horizontal grain | keep it truly vertical; a 5° draft makes the lines step visibly |
| Shallow slope (< 30° from horizontal) | stair-stepping, the worst surface on the part | avoid, or steepen past 45°, or make it a chamfer instead of a curve |
| Steep slope (> 45°) | acceptable, prints without support | where a curve has to go |

**Layer lines are a texture, so use them.** They run horizontally around the
part in whatever orientation it is printed. A form whose main lines run the
same way looks coherent; one that fights them looks accidental.

| What | Start with | Why |
|---|---|---|
| Visible feature alignment | parallel or perpendicular to the layers | a feature at 20° to the grain shows every layer as a separate step along its edge |
| Deliberate ribs or grooves as texture | 0.8–1.2 mm pitch, 0.4–0.6 mm deep | coarse enough to read as intentional rather than as a print artefact |
| Text and logos | raised, not recessed, ≥ 1.5 mm stroke, on a top or vertical face | recessed text fills with strings; see `fdm/geometry/text-and-embossing` |

**Hide what cannot be made pretty.** Supports scar whatever they touch. A
design that needs none is not just cheaper to print — it has no scarred
faces at all.

## How to build it

1. Decide the print orientation **while drawing the first profile**, not
   after. In this app that means choosing which plane the footprint goes on:
   XZ is the ground plane and +Y is up, so the face that ends up at minimum Y
   is the one on the bed.
2. Put the most-seen face at maximum Y where you can.
3. Replace any surface that would land between 0° and 30° from horizontal with
   either a flat face or a chamfer steeper than 45°.
4. Keep the part support-free: mouths open upward, holes vertical or
   teardropped, overhangs under 45°.
5. Look at the returned view and ask which face is at the bottom. That is the
   one with the elephant's foot and the support scars.

## When to do it differently

- **Strength decides the orientation** → layer adhesion is the weak axis and
  it wins over appearance every time; see `fdm/basics/orientation-and-strength`.
- **The part will be vapour-smoothed (ABS/ASA)** → layer lines disappear, and
  only the silhouette matters.
- **The user will print it themselves and has said how** → their orientation
  wins; design to it rather than to this table.

## Images

No figures yet.

## Source & date

- Common FDM practice; the surface-quality ordering is a property of how the
  process lays material down rather than of any one machine.
- `confidence: medium` — the ordering is reliable, the specific pitches and
  stroke widths are starting points for a 0.4 mm nozzle at 0.2 mm layers.
