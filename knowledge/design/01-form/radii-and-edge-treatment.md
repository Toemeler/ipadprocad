---
id: design/form/radii-and-edge-treatment
title: Radii and edge treatment
type: rules
process: design
triggers: [radius, radien, fillet, verrundung, verrunden, rounded, abgerundet, chamfer, fase, anfasen, edge, kante, sharp, scharf, corner, ecke, break the edge, kantenbruch, soft, weich, bevel, abschrägung, abschraegung]
depends_on: []
confidence: high
updated: 2026-09-22
---

# Radii and edge treatment

Edges are where a part is touched, where light catches it, and where the
difference between a designed object and a CAD default is most visible.

## When this applies

- Every object with an outside surface a person sees or holds.
- Not to internal faces nobody meets, and not to a mating surface, where a
  radius is a fit error.

## Good starting values

**A hierarchy, not a radius.** One radius applied everywhere is the single
most recognisable signature of a part nobody designed. Three sizes, clearly
different from each other, is what reads as deliberate.

| Tier | Start with | Works between | Where |
|---|---|---|---|
| Silhouette | 0.25 × part height | 0.1–0.4 × | the corners you see in outline from the most-viewed direction |
| Secondary | 0.25 × the silhouette radius | 0.15–0.4 × | where two forms meet, around raised features |
| Edge break | 0.4–0.6 mm | 0.3–1.0 mm | every remaining edge a hand can reach |

The ratios matter more than the absolute numbers. Two radii that differ by
less than about 1.5× read as the same radius done badly; make them differ by
3–4× and both look intentional.

**Fillet or chamfer.**

| Use | When | Why |
|---|---|---|
| Fillet | anything held, anything organic, any edge that carries load | it spreads stress and it feels right in a hand |
| Chamfer | a lead-in, a machined look, a face meeting a mating surface | it reads as precise, and it prints cleanly on a downward face where a fillet would droop |
| Nothing | mating faces, thin walls where the radius would eat the wall | a radius on a mating face is a gap |

**The limit.** A fillet cannot exceed the material beside it. On a wall of
thickness `t`, keep an external radius under `0.45 × t` and an internal one
under `0.8 × t`, or the blend will either fail in the kernel or leave a knife
edge that prints as nothing.

## How to build it

1. **Draw the silhouette radius in the sketch**, not as a 3D fillet.
   `sketch_rounded_rect` and `sketch_slot` make true arcs that cannot fail at
   rebuild time, and a 3D fillet on four sharp corners is four chances for the
   kernel to refuse.
2. Build the form.
3. Apply the secondary radius where forms meet.
4. Apply the edge break LAST, with `{"edges": "outer"}` so it does not catch
   the mouths of holes — a hole mouth is a circular edge and `"all"` will find
   it, which is how a countersink ends up with a rounded lip that no screw
   sits in.
5. Look at the view. Every radius you meant should be visible as a highlight;
   if the part looks uniformly soft, the hierarchy collapsed and the
   silhouette radius needs to grow.

## When to do it differently

- **A blend was refused** → the report names the largest size that builds on
  those edges. Use that number. Do not retry the same one and do not silently
  drop the blend.
- **Printed, and the edge is on the first layer** → a bottom fillet fights the
  elephant's foot and prints badly. Use a 0.5–1.0 mm chamfer there instead;
  see `fdm/geometry/chamfers-fillets-elephant-foot`.
- **A deliberately sharp style** → keep the silhouette sharp and still break
  the edges 0.3 mm, because an unbroken printed or machined edge is sharp
  enough to mark a hand.

## Images

No figures yet.

## Source & date

- Standard industrial-design and DFM practice. The wall-thickness limits are
  geometry: a radius larger than the material cannot exist.
- `confidence: high` for the limits and the fillet/chamfer split, which are
  mechanical. The tier ratios are convention.
