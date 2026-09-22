---
id: laser/materials/solid-wood
title: Solid wood — species, grain and what each one does
type: material
process: laser
triggers: [solid wood, massivholz, hardwood, hartholz, species, holzart, walnut, nussbaum, oak, eiche, maple, ahorn, cherry, kirsche, birch, birke, basswood, linde, alder, erle, beech, buche, ash, esche, pine, kiefer, balsa, grain, maserung]
depends_on: [laser/materials/wood-overview, laser/geometry/grain-and-ply-direction]
confidence: medium
updated: 2026-09-22
---

# Solid wood — species, grain and what each one does

Solid wood is the only material in this folder whose properties change
**within one part**. The beam crosses early wood and late wood, soft bands and
hard bands, and cuts each at a different rate. In a jig that is a defect; in a
visible piece it is the entire point.

Species choice decides three things at once: how cleanly it cuts, how much
contrast an engrave has, and whether the finished thing looks cheap.

## When this applies

Visible one-off pieces, signage, lids, faces, inlay, boxes where the material
is the point. Not for batches that must be identical, and not for anything
structural and thin — short grain snaps.

## Good starting values

### Cutting numbers

| What | Start with | Works between | Why |
|---|---|---|---|
| Kerf, 3 mm | 0.30 mm | 0.25–0.35 mm | and it varies *along* one cut as the grain changes |
| Minimum hole ⌀ | 1.5 × thickness | 1×–2× | short grain around a small hole breaks out |
| Minimum web | 2 × thickness | 1.5×–3× | a web running along the grain splits under almost no load |
| Press-fit interference | 0.06 mm | 0.04–0.10 mm | with the grain it splits; across it, it grips |
| Comfortable cut thickness | ≤ 5 mm | 8 mm on pale, low-resin species | |
| Moisture content | 8–12 % | | above ~14 % it cuts badly and warps afterwards |

### The species table

Contrast is for **engraving**: how dark the mark looks against the unburnt
surface.

| Species | Cuts | Engrave contrast | Resin | Notes |
|---|---|---|---|---|
| **Basswood / lime** (Linde) | very cleanly | **excellent** | none | soft, pale, even; the best beginner species |
| **Alder** (Erle) | cleanly | **excellent** | low | fine even grain, dark crisp marks |
| **Maple** (Ahorn) | cleanly | **excellent** | none | hard, pale, the usual choice for photo engraving |
| **Birch** (Birke) | cleanly | very good | low | cream to light brown, plain or wavy figure |
| **Cherry** (Kirsche) | well | **excellent** | low | warm, darkens with age; needs more power than basswood |
| **Walnut** (Nussbaum) | well | **low** — dark on dark | low | premium look, subtle tone-on-tone engrave |
| **Beech** (Buche) | well | good | none | hard, plain, cheap; burns a little dark |
| **Oak / ash** (Eiche / Esche) | **unevenly** | patchy | none | open pores trap soot and the hard/soft bands cut at different rates |
| **Pine, fir, spruce** | flares | poor | **high** | resin pockets can flame; sticky edge |
| **Balsa** | instantly | poor | none | too soft to hold detail, but excellent for mock-ups |
| **Padauk, iroko, exotic hardwoods** | variably | variable | variable | check the dust: several are respiratory sensitisers |

### The short version

- **Engraving matters most** → basswood, alder or maple.
- **Looks matter most** → cherry or walnut, and accept low engrave contrast.
- **Cheap and predictable** → beech or birch.
- **Never** → resinous softwoods, and open-pored oak if the engrave has to be
  clean.

### Grain direction is a structural decision

Solid wood is roughly **ten times weaker across the grain than along it**. In
a laser-cut part that shows up as:

| Feature | Rule |
|---|---|
| A long thin part | grain runs **along** its length, or it snaps |
| A slot | cut **across** the grain, or the material between slot and edge splits out |
| A tab | grain runs along the tab, never across its root |
| A thin web | 3 × thickness minimum if it runs across the grain |

→ [`grain-and-ply-direction`](../03-geometry/grain-and-ply-direction.md)

### Wood moves, and it moves unevenly

Solid wood expands and contracts with humidity, far more **across** the grain
than along it: roughly 8 % tangentially and 4 % radially between soaked and
oven-dry, which in a heated room over a year means a seasonal swing of about
6–8 % moisture content. Practically, allow around **1–2 mm per 100 mm across
the grain**, and essentially nothing along it.

For laser-cut parts this matters in exactly one place: a joint whose two
halves have their grain at 90° to each other will fit in January and bind in
July. Plywood does not have this problem, which is another reason the folder
defaults to it.

## How to build it

1. **Choose the species for the engrave**, if there is one; that is the
   property hardest to fix later.
2. Check the board is **dry and flat** — 8–12 % moisture content, no cup.
3. Lay every part out with its **grain direction decided deliberately**, not
   by nesting efficiency.
4. Cut a test piece **from the same board**. Species is not enough
   information: one walnut board cuts differently from the next.
5. Mask, or expect soot in the open pores of oak and ash — it does not sand
   out easily.
6. Expect the kerf to vary along a single cut. For joints, use the widest
   value from the comb test, not the average.
7. Sand the visible faces after cutting; 240 grit removes the smoke film.

## When to do it differently

- **A batch of identical parts** → laminated bamboo or birch ply. Solid wood
  will not repeat.
- **Very thin filigree** → across-grain webs break in handling. Go to 3 ×
  thickness, or use cast acrylic.
- **Dark species with an engrave** → engrave then paint-fill, or inlay a pale
  species. A walnut engrave is nearly invisible.
- **Thick stock (>8 mm)** → the edge chars heavily and the cut tapers. A
  bandsaw and a router will beat the laser here.
- **The look of hardwood, the behaviour of ply** → species-faced plywood.
  → [`plywood`](plywood.md)

## Images

![the same slot cut across and along the grain](img/fig-grain-direction.svg)
*The same slot, across the grain and along it. Along the grain the short
fibres between the slot and the edge split out under hand pressure; across it
they hold.*

![engrave contrast across six species](img/fig-species-contrast.svg)
*The same mark, same settings, six species. Contrast is a property of the
wood, not of the machine — no power setting rescues a walnut engrave.*

## Source & date

- Species behaviour and engrave contrast: [Thunder Laser — best types of wood for laser engraving](https://www.thunderlaser.com/laser-blogs/best-wood-for-laser-engraving.html),
  [xTool — best wood for laser cutting and engraving](https://www.xtool.com/blogs/xtool-academy/best-wood-for-laser-cutting-and-engraving),
  [Ocooch Hardwoods — thin wood for laser](https://ocoochhardwoods.com/laser/),
  [Creality Falcon — best woods for laser engraving and cutting](https://www.crealityfalcon.com/blogs/laser-academy/choosing-the-best-woods-for-laser-engraving-cutting-a-tutorial).
- Wood movement (≈8 % tangential, ≈4 % radial; 6–8 % seasonal EMC swing):
  [Workshop Companion — wood movement](https://workshopcompanion.com/know-how/design/nature-of-wood/wood-movement.html),
  [Thos. Moser — wood moves](https://www.thosmoser.com/blog/2020/09/16/wood-moves-crafting-receptive-designs/).
- `confidence: medium` — grain behaviour and the species ordering are
  reliable; the numbers are indicative.
