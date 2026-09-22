---
id: design/form/proportion-and-stance
title: Proportion, stance and where the mass goes
type: rules
process: design
triggers: [proportion, proportionen, stance, haltung, mass, masse, visual weight, thickness, dicke, slab, platte, chunky, klobig, thin, dünn, duenn, heavy, schwer, light, leicht, bulky, plump, footprint, grundfläche, grundflaeche, base, sockel, looks wrong, sieht falsch aus]
depends_on: []
confidence: medium
updated: 2026-09-22
---

# Proportion, stance and where the mass goes

Why one part looks designed and another looks like the block it was cut from,
when both have the same features and the same dimensions.

## When this applies

- Any whole object with a visible outside.
- Not to a part whose proportions are fixed by what it mates with — there,
  the mating dimensions win and the only freedom left is edge treatment.

## Good starting values

**Thickness.** The commonest error is one thickness everywhere, and the second
commonest is a base too thin for the thing standing on it.

| What | Start with | Works between | Why |
|---|---|---|---|
| Base plate of a mounted object | 4–5 mm | 3–8 mm | under 3 mm it flexes when the screw is tightened and reads as flimsy; over 8 mm it reads as a spacer with a part on top |
| Upper form vs its base | 0.6 × base thickness | 0.4–0.8 | equal thickness makes two slabs; lighter above the base is what gives an object a stance |
| Footprint vs height | 1.5 : 1 or wider | 1:1 – 3:1 | taller than its footprint reads as unstable, and on a printed part it usually is |
| A wall nobody loads | 2 × the wall you must have | up to 3× | thicker than that is material doing nothing, and it is visible |

**Overhang of a base.** A base that stops exactly where the form above it
stops reads as a cut-off. Let it run past:

| What | Start with | Works between | Why |
|---|---|---|---|
| Base past the form above | 3–6 mm | 2–10 mm | gives the object a visible ground plane and somewhere for a screw to be that is not through the middle of the feature |

**Where a screw goes.** Centred in the plate is the default and often the
worst place: it puts the fixing in the middle of the visible face and forces
everything else around it.

| Situation | Put it | Why |
|---|---|---|
| One screw, a form to one side | centred on the BASE, clear of the form | the base is the part that touches the wall, so its centre is the honest place to fix it |
| One screw, symmetric object | on the axis of symmetry | anywhere else fights the symmetry the whole form announces |
| Two screws | on the long axis, each 0.2–0.25 of the length in from the ends | at the ends they look like an afterthought, in the middle they do not resist rotation |

Whatever you choose, place it against the part's measured `centreMm`, not
against sketch (0,0). They are not the same point unless the first profile was
drawn centred.

## How to build it

1. Draw the base profile centred on the sketch origin, so that every later
   feature can use (0,0) and mean the middle.
2. Give it a real silhouette radius — see
   `design/form/radii-and-edge-treatment`.
3. Build the upper form as its own profile, thinner, and set back from the
   base edge by the overhang above.
4. Place the fixing against the base's centre.
5. Look at the returned view from the side. If the two forms read as two
   stacked slabs of the same weight, thin the upper one and try again.

## When to do it differently

- **The object hangs rather than sits** → mass goes high, not low; the stance
  rules invert.
- **It must nest or stack** → the stacking interface fixes the footprint and
  the wall, and proportion is whatever is left.
- **It is a grip or a handle** → hand dimensions win over every ratio here.
- **A visible mounting is the point** (exposed hardware as a style) → then the
  screw belongs where it can be seen, and the rows above do not apply.

## Images

No figures yet. Proportion is comparative and a single drawing of "the right
proportion" teaches the drawing rather than the comparison.

## Source & date

- Standard product-design practice, restated as checkable CAD numbers.
- `confidence: medium`. These are conventions that hold for small mounted
  objects of the kind this app is used for, not laws. Where a user's own taste
  disagrees, the user is right and this document is not.
