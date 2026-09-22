---
id: design/start-here
title: Design — start here
type: basics
process: design
triggers: [design, designer, designen, gestaltung, schön, schoen, nice, beautiful, elegant, aesthetic, ästhetisch, aesthetik, styling, look, aussehen, form, formgebung, good looking, hübsch, modern, clean, minimal, professional, hochwertig, premium, gestalten]
depends_on: [design/form/proportion-and-stance, design/form/radii-and-edge-treatment]
confidence: high
updated: 2026-09-22
---

# Design — start here

A part that meets its specification is not yet a designed part. This is the
difference between the two, and what to do about it before saying a whole
object is finished.

## When this applies

- Any request for a whole object, and **always** when the user says designer,
  schön, elegant, modern, hochwertig, premium, or names a style.
- Not for a narrow change. "Add a 5 mm hole there" is a hole, not an
  opportunity to restyle somebody's part.

## Good starting values

The failure this document exists to prevent has a shape. It is a primitive —
a box, a plate, a cylinder — with the required features cut into it, handed
over as if the requirements were the design.

| Symptom | What it reads as | The fix |
|---|---|---|
| One extruded profile, nothing else | an unfinished blank | give the form a second move: a taper, a step, a sweep, a relieved underside |
| Every edge sharp | a CAD default nobody touched | break every edge a hand meets; see `design/form/radii-and-edge-treatment` |
| One radius used everywhere | cheap, injection-moulded toy | a radius hierarchy — large on the silhouette, small on details |
| Parts that look stuck together | two objects, not one | blend the junction; see `design/form/transitions-and-continuity` |
| Uniform thickness everywhere | heavy, inert | thin where it is not loaded, thick where it is |
| Functional features placed wherever they fit | accidental | align them to each other and to the form's own axes |

Three ratios worth knowing, because eyes read them and nobody can say why:

| Relationship | Start with | Works between | Why |
|---|---|---|---|
| Overall proportion of a visible face | 1 : 1.6 | 1:1.3 – 1:2.2 | squarer reads as inert, longer reads as a strip rather than an object |
| Silhouette radius vs part height | 0.25 × height | 0.1–0.4 | below this the corner reads as sharp at a glance; above it the form goes soft and loses its edges |
| Detail radius vs silhouette radius | 0.25 × | 0.15–0.4 | a visible step between radius sizes is what makes a form look deliberate rather than rounded-off |

## How to build it

Design happens in the profile, before the first extrude. Once a shape is a
solid, everything you add is correction.

1. **Say what the object IS in one sentence** — "a cable holder that screws to
   a desk edge and takes one 6 mm cable". That sentence decides the stance,
   the footprint and where the mass goes.
2. **Draw the silhouette properly.** Arcs where the object curves, a real
   radius on every corner that will be seen, one profile that already looks
   like the finished thing from its most-seen direction. A rectangle you plan
   to fix later is a rectangle you will hand over.
3. **Decide where the mass is.** Something that mounts to a surface wants a
   wide, thin, confident base and a lighter upper form. Equal thickness
   throughout is the look of a part nobody made a decision about.
4. **Place the functional features on the form's own geometry** — centred on
   it, aligned to its axes, at its centre of area. Read the part's `centreMm`
   rather than assuming the world origin is its middle.
5. **Treat the edges last, with a hierarchy.** Not one fillet command over
   everything.
6. **Look at it.** Every block returns a view. If the silhouette does not read
   as the thing you were asked for, the design is not done, whatever the
   feature tree says.

## When to do it differently

- **A purely internal part** (a bracket inside a housing) → stance and edge
  treatment still matter for the hand that assembles it, proportion does not.
- **The user named a style** → follow it over the defaults here. "Industrial",
  "Bauhaus", "organic" and "minimal" all contradict at least one row above.
- **The user asked for a quick test piece** → a primitive is the correct
  answer. Ask nothing and build the box.
- **The process constrains the form** → manufacturing wins, always, but it
  constrains far less than it first appears; see
  `design/process/designing-for-the-printed-look`.

## Images

No figures yet. The rules above are about proportion and edge treatment, and
a line drawing of either is easy to misread as the shape to copy — which is
the opposite of what they are for. See `PHOTOS.md` for what would help.

## Source & date

- Standard industrial-design practice: proportion, radius hierarchy, mass
  distribution and edge treatment as taught in product design, restated as
  things that can be checked on a CAD model.
- The failure table is taken from issue #82, where a request for "ein
  Designer Kabelhalter" was answered with a 46 × 22 × 4 mm rounded slab.
- `confidence: high` for the checklist and the failure table, which are
  descriptive. The three ratios are conventions, not physics: they are a
  good place to start an argument with, not numbers to defend.
