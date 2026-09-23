---
id: design/form/housings
title: Housings and cases — a form that follows what is inside
type: rules
process: design
triggers: [case für, gehäuse für, case for, housing for, enclosure for, druckbares case, druckbares gehäuse, printable case, gehäuse um, case around, enclosure, gehäuse, gehaeuse, case, housing, hülle, huelle, cover, abdeckung, verkleidung, schutzgehäuse, box für, kasten, kapsel, einhausung, frame, rahmen, chassis, halter für, mechanism, mechanismus, getriebe gehäuse, gearbox, antrieb, drive, motor case, motorgehäuse, electronics case, shell for]
depends_on: [design/principles/proportion, design/form/edges-and-radii, design/form/seams-and-alignment, design/people/affordances]
confidence: medium
updated: 2026-09-23
---

# Housings and cases — a form that follows what is inside

A housing is designed from the INSIDE OUT. Its size, its outline and every
opening in it come from the parts it holds and what they have to do. A box
sized by eye and drawn first is always wrong in the same way: too big, a
different shape from its contents, and blind to what has to pass through its
walls. That is issue #93 exactly — a 33 × 37 mm rectangle round a Ø4.4 spool
and a Ø28 wheel, with a solid floor where the motor should have been.

## When this applies

- Any case, housing, cover or frame for parts that exist — in the model or
  as named components: a gearbox round its wheels, a motor mount, a case for
  a board, a cover over a mechanism.
- Printed, cut or moulded alike; the process sets the wall, not the form.
- Not to a container whose contents are free (a pot, a tray, a box of
  screws) — there the form is the design brief itself.

## Good starting values

| Decision | Start with | Source |
|---|---|---|
| Order | model (or import) every component first, then design the case round them — it is what makes clearance checks possible | Hubs; 3D On Demand; FacFox |
| Clearance round internal components | 0.5 mm; 1.0 mm on FDM, and at least that for anything that moves | Hubs; 3D On Demand |
| Wall | 2 mm recommended; 1.5 mm the FDM minimum | Hubs; 3D On Demand |
| Walls | uniform thickness throughout | FacFox |
| Ports and plugs | 2 mm larger than the plug (1 mm each side); 0.5 mm per side is the FDM minimum | Hubs; 3D On Demand |
| Screw clearance holes | + 0.25 mm on the diameter; − 0.25 mm where a screw must bite | Hubs |
| Bosses | at least one hole diameter of wall round the hole (M5 → 5 mm) | Hubs |
| Alignment lugs | at least 5 mm wide | Hubs |
| Ribs and gussets | 75–80 % of the wall thickness | FacFox |
| Corners | radii or fillets — lower stress, easier to print | Hubs |
| FDM accuracy | ± 0.3–0.5 mm; the clearances above exist because of it | 3D On Demand |
| Outline | the contents' footprint offset by the clearance — the `enclose` op when they are modelled | this app, #93 |
| Floor and height | from the contents: the floor carries only what bears on it, the height is the contents' top plus the rim they need | this app, #93 |

**Read the contents before drawing anything.** Every body that goes in: where
it is, how big it is, what moves and what is fixed. Then what crosses the
wall: shafts (a bearing seat, not a hole with slack), cords and belts (an
outlet where the cord LEAVES the drum, tangent to it, with a lead-in), cables
(a strain relief), buttons and ports (affordances), fasteners (bosses). Then
where the parting line or the open side goes: on the side you assemble from.

**The shape follows the contents.** Two wheels side by side want a case that
is two circles joined by tangents (the convex hull of the two, offset) — not
a rectangle, which puts empty corners exactly where the wheels are not. A
stepped contents (a motor under a wheel) wants a stepped housing: the tall
part over the tall part only. Where the case is visible, those steps and
curves ARE the design; the form tells you what is inside.

## How to build it

1. The contents first, each its own body, positioned as assembled.
2. `enclose` round them (`bodies`: the ones the case holds; `clearance` from
   the table; `wall`) — the outline follows their footprint, open at the top.
3. The crossings: shaft seats, cord outlets, cable exits, mounting holes,
   each as its own feature, each placed from the part it serves (read its
   centre from `describe_shape`, never guess).
4. Steps where the contents step: a second `enclose` over only the tall part,
   then `combine` the two cases with "join", or a cut that lowers the wall
   where nothing stands.
5. Edges last, scaled to the case (see edges-and-radii) — not the mug's 0.6
   mm foot on a 5 mm part.

## When to do it differently

- **The contents are not modelled** (a PCB by its datasheet, a motor by its
  drawing) → model them as simple stand-in bodies first — a box, a cylinder,
  the shaft — and enclose those. A case round nothing is a guess.
- **A case that must look designed more than it must be small** → start from
  the fitted outline and then decide what to smooth: one generous radius over
  two contents reads calmer than following every bump. Deviate on purpose,
  never by drawing a box first. See the enclosure worked example.
- **Concave contents** (an L-shaped arrangement) → the convex outline wastes
  the inside corner; enclose the two legs separately and join them.

## Images

None yet.

## Source & date

Researched 2026-09-23 for issue #93:

- Protolabs Network (Hubs), "How do you design enclosures for 3D printing?"
  — 2 mm walls, 0.5 mm round components, ports + 2 mm, holes ± 0.25 mm,
  bosses, 5 mm lugs, fillets, components first.
  https://www.hubs.com/knowledge-base/enclosure-design-3d-printing-step-step-guide/
- 3D On Demand, "How to Design 3D Printed Enclosures for Electronics" —
  1.0 mm clearance for FDM, 1.5 / 2.0 mm walls, 0.5 mm per side on
  connectors, ± 0.3–0.5 mm FDM accuracy, start from the component layout.
  https://www.3d-demand.com/blog/3d-printed-enclosures-electronics-guide
- FacFox, "Enclosure Design Guide for 3D Printing" — uniform walls, ribs at
  75–80 % of the wall, component measurement before the structure.
  https://facfox.com/docs/kb/enclosure-design-guide-for-3d-printing

The app's own, from the #93 report and marked "this app" in the table: the
outline following the contents' footprint (and the `enclose` op), round
contents giving a round case, stepped contents a stepped one, and the floor
and height taken from the contents.
