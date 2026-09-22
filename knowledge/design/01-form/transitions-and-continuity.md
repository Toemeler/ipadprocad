---
id: design/form/transitions-and-continuity
title: How two forms meet
type: rules
process: design
triggers: [transition, übergang, uebergang, junction, verbindung, blend, überblendung, stuck on, aufgesetzt, angeklebt, two parts, zwei teile, boss, dom, rib, rippe, gusset, verstrebung, tangent, tangential, continuous, stetig, one piece, aus einem stück, integrated, integriert]
depends_on: [design/form/radii-and-edge-treatment]
confidence: medium
updated: 2026-09-22
---

# How two forms meet

Most objects are two or three forms joined. Whether they read as one object or
as parts glued together is decided entirely at the junction.

## When this applies

- Any part where something rises from something else: a boss on a plate, a
  clip on a base, a handle on a body, a rib on a wall.
- Not where the two forms are meant to read as separate — a button in a
  housing, a lid on a box.

## Good starting values

**The junction radius is the whole thing.** A vertical form meeting a flat one
at a sharp corner reads as stuck on, and it is also where the part breaks.

| What | Start with | Works between | Why |
|---|---|---|---|
| Fillet where a form rises from a base | 0.5 × the rising form's thickness | 0.3–1.0 × | below 0.3 it reads as a butt joint and concentrates stress exactly where the bending moment is highest; above 1.0 the two forms merge into a blob |
| Rib thickness vs the wall it stiffens | 0.6 × wall | 0.5–0.8 × | thicker than the wall sinks and shows on the other face; thinner than 0.5 does not stiffen |
| Rib height | 3 × wall | 2–5 × | beyond 5× it buckles instead of stiffening |
| Gusset under a cantilevered form | 45°, height = 1.5 × the form's thickness | 30–60° | 45° prints without support and is where the load actually goes |

**Footprint.** A form rising from a base needs a base wider than itself, or
there is nothing for the blend to live in.

| What | Start with | Why |
|---|---|---|
| Base past the rising form, each side | ≥ 2 × the junction fillet | a fillet larger than the material beside it cannot be built, and the kernel will say so |

**Overlap is not a junction.** A solid that merely intersects another is a
boolean, not a transition: it will be watertight and it will still look
wrong, because nothing was designed at the seam.

## How to build it

1. Build the base form.
2. Build the rising form so its footprint sits **fully inside** the base, set
   in by at least twice the junction radius. Read the base's `extentMm` and
   `centreMm` from the block report and place it against those numbers — not
   against sketch (0,0), which is the world origin and usually not on the
   part at all.
3. Join them.
4. Fillet the junction, selecting near the seam.
5. Look at the returned view from the side. If you can see a step, a
   floating edge, or the two forms reading as two objects, fix it before
   adding anything else.

## When to do it differently

- **The rising form must reach the base's edge** (a flange, a lip) → then it
  is not a junction, it is one continuous profile. Draw it as one profile and
  extrude once, rather than joining two solids and blending the seam.
- **Printed vertically** → a fillet on an upward-facing junction prints
  cleanly; the same fillet on a downward-facing one is an overhang. See
  `fdm/geometry/overhangs-and-bridging`.
- **Two forms genuinely are separate parts** → then give them a visible,
  even gap (0.5–1.0 mm) and let the separation read as deliberate. An
  accidental 0.1 mm gap reads as a mistake; a deliberate 0.8 mm one reads as
  a design.

## Images

No figures yet.

## Source & date

- Standard practice for moulded and printed parts; the rib and gusset ratios
  are the usual DFM figures and are there to prevent sink marks and buckling
  as much as for appearance.
- The "fully inside the base" rule and the pointer to `extentMm`/`centreMm`
  come from issue #82, where a cable clamp was placed by assuming the world
  origin was the plate's centre and landed with most of its volume in open
  air, touching the part along a 2.5 mm sliver at the edge.
- `confidence: medium` — the ratios are conventions; the geometry constraint
  (a fillet cannot exceed the material beside it) is not.
