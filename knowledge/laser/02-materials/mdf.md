---
id: laser/materials/mdf
title: MDF — cheap, flat, and always dark at the edge
type: material
process: laser
triggers: [mdf, mitteldichte faserplatte, fibreboard, faserplatte, hdf, cheap sheet, günstig, jig material, schablone, template, painted part, lackiert, formaldehyde, formaldehyd]
depends_on: [laser/materials/wood-overview, laser/basics/kerf-and-tolerance]
confidence: medium
updated: 2026-09-22
---

# MDF — cheap, flat, and always dark at the edge

MDF is wood fibre in a resin binder. It has no grain, no voids and no glue
lines, which makes it the most **predictable** sheet in the wood family — and
genuinely flatter than plywood, which is why jigs and templates are made of
it.

It is also the dirtiest thing in this folder to cut: dense, slow, near-black
at the edge, and the binder is the reason extraction matters.

## When this applies

Jigs, templates, drilling guides, painted parts, internal structure,
prototypes where cost beats appearance. Not for visible edges, not for damp
anything, not for fine filigree.

## Good starting values

| What | Start with | Works between | Why |
|---|---|---|---|
| Kerf, 3 mm | 0.25 mm | 0.20–0.30 mm | dense, slow cut, wide heat-affected zone |
| Kerf, 4 mm veneered | 0.16 mm | 0.14–0.20 mm | the veneer cuts cleanly and narrows the effective kerf |
| Measured thickness | measure it | ±0.2 mm of nominal | better than plywood, still not exact |
| Minimum hole ⌀ | = thickness | 1×–1.5× | below this the bore chars shut |
| Minimum web between cuts | 2 × thickness | 1.5×–3× | MDF holds heat longest of any sheet here |
| Part spacing when nesting | 3 mm | 2–4 mm | it carries heat sideways further than ply |
| Press-fit interference | 0.08 mm | 0.05–0.10 mm | compresses well, crumbles above ~0.15 mm |
| Comfortable cut thickness | ≤ 6 mm | 9 mm slowly | |

### The binder is a safety question

MDF is held together with a **urea-formaldehyde resin**, and cutting it
releases formaldehyde along with fine resin-laden particulate. This is not a
reason to avoid MDF; it is a reason to insist on extraction.

| | Do this |
|---|---|
| Extraction | mandatory, running, and checked — not a fan at a window |
| Filtration | HEPA for particulate **plus** activated carbon for the VOCs |
| Grade | look for **E1** or better; E0/CARB-2 MDF exists and is worth buying |
| Room | do not cut MDF in an occupied room without ducted extraction |
| Dust | the sanding dust is a respiratory irritant; mask up when cleaning edges |

### What MDF does that the others do not

- **It is genuinely flat.** For jigs and templates this beats plywood outright.
- **It has no grain**, so there is no direction to design around and no
  splitting.
- **It drinks finish.** Sealed cut edges need two or three coats of primer.
- **It swells irreversibly when wet.** A splash raises the surface by a
  millimetre and it never goes back down.

## How to build it

1. Use it for the part nobody looks at, and pair it with plywood or solid wood
   for the visible half of an assembly.
2. Confirm extraction is running **before** the job, not after the smell
   arrives.
3. Space parts 3 mm apart when nesting — more than plywood needs.
4. Cut slots slightly oversize and **glue**. MDF press fits work once; taking
   the joint apart crumbles the slot edge and it never grips again.
5. Seal the edges before painting, or accept a fuzzy, uneven finish.
   → [`sealing-and-finishing`](../10-wood-finishing/sealing-and-finishing.md)

## When to do it differently

- **The edge will be seen** → plywood, bamboo or solid wood. No amount of
  sanding makes an MDF cut edge attractive.
- **A thin web or fine tracery** → MDF crumbles. Use plywood, or cast acrylic.
- **The part will be screwed into repeatedly** → MDF strips its own screw
  holes after a few cycles. Use a captive nut or an insert.
  → [`fasteners-in-wood`](../10-wood-finishing/fasteners-in-wood.md)
- **Humidity or outdoors** → never.
- **Extraction is marginal** → cut plywood instead and accept the voids. This
  is a real trade, and it is the right one in a shared room.

## Images

![MDF cut edge, dark and slightly furry, next to a painted one](img/fig-mdf-edge.svg)
*Raw MDF edge versus the same edge sealed and painted. The raw edge is what
the laser always produces; the painted one is why the material is still worth
using.*

## Source & date

- Cutting behaviour and kerf: [Sculpteo — MDF material for laser cutting](https://www.sculpteo.com/en/lasercutting/laser-cutting-materials/mdf-material/),
  [Box Studio — best materials for laser-cut boxes](https://box-studio.cc/blog/2026-04-en-best-materials-laser-cut-boxes).
- Binder emissions and extraction: [Laser Engraving Tips — is it safe to laser cut MDF](https://laserengravingtips.com/is-it-safe-to-laser-cut-mdf/),
  [Snapmaker — laser fume safety](https://www.snapmaker.com/blog/ensure-laser-fume-safety-with-exhaust-system/),
  [Sumec — formaldehyde emission standards](https://www.sumecbuildingmaterial.com/blog/plywood-formaldehyde-emission-standards/).
- `confidence: medium`; the extraction requirement is `high`.
