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

| Decision | Start with | Why |
|---|---|---|
| Outline | the contents' footprint, offset by the clearance — the `enclose` op when they are modelled | a housing is the envelope of what it holds, not a rectangle around it |
| Clearance to moving parts | 0.5–1.0 mm (wheels, spools, cords) | printed walls wander ±0.2; a rubbing wheel is a brake |
| Clearance to still parts | 0.2–0.3 mm, or a press fit where it locates them | a motor held by its own pocket needs no screws |
| Wall | 1.6–2.4 mm printed (four to six lines), 3 mm for a case that is handled | stiff enough to hold shafts true |
| Floor | the wall, or thinner where nothing bears on it | a floor as thick as the tallest part is material doing nothing |
| Height | the contents' top plus the rim they need — not a round number | a lid, if any, closes on the rim |
| Outer radii | the contents' own radii plus clearance plus wall | round contents give a round case; the case should read as that |

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
   joined, or a cut that lowers the wall where nothing stands.
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

- Written for issue #93, 2026-09-23, from the capstan-drive case in that
  report and the `enclose` op it led to.
