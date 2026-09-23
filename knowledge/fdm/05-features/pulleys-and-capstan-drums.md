---
id: fdm/features/pulleys-and-capstan-drums
title: Cord pulleys, spools and capstan drums
type: recipe
process: fdm
triggers: [pulley, pulleys, capstan, capstan drive, spool, spule, rolle, seilrolle, schnurrolle, umlenkrolle, riemenscheibe, trommel, seiltrommel, winde, winch, drum, cord, string, schnur, faden, seil, groove, rille, wheel, laufrad]
depends_on: [fdm/geometry/overhangs-and-bridging, fdm/geometry/holes-shafts-and-teardrops, fdm/geometry/chamfers-fillets-elephant-foot]
confidence: medium
updated: 2026-09-23
---

# Cord pulleys, spools and capstan drums

A wheel a cord runs on is a turned part: one half-section, revolved. What
makes it work is the groove the cord runs in and the bore that grips the
shaft. Both went wrong in #92 and #93: grooves with a vertical flange on one
side and a 45° slope on the other (it looks like a stray chamfer, and the
cord walks to the steep side), and a 0.6 mm "foot chamfer" taken from the mug
recipe onto a 4.4 mm spool, where it ate a third of the flange.

## When this applies

Any round part a cord, string, thread or thin rope runs on or winds onto: a
capstan drive, a winch drum, an idler pulley, a spool, a reel. Printed
upright (axis vertical), which keeps the bore round and puts every flank of
the groove at a printable angle.

Not for toothed belts (GT2 and similar need their tooth profile) or gears.

## Good starting values

| Quantity | Value | Why |
|---|---|---|
| Groove | **symmetric**: a V with both flanks at 45°, or a round-bottomed U with 45° flanks | both flanks print upright without support, the cord centres itself |
| Groove depth | ≥ 3 × cord Ø, at least 0.8 mm | the cord cannot jump the flange |
| Flange lip | ≥ 0.8 mm thick at the rim (two lines of 0.4) | thinner lips break off |
| Capstan drum | a plain cylinder between two 45° flanges, width = turns × cord Ø + 1 mm | friction drive wants 3–5 wraps side by side, not a V that pinches |
| Ratio | ratio of diameters measured at the CORD CENTRE (drum Ø + cord Ø) | 1:10 is D_big + d = 10 × (D_small + d) |
| Bore on a D-shaft | nominal + 0.05–0.1 mm, with the D flat modelled | press fit that does not split; the flat takes the torque |
| Bore on a round shaft | see the hole table; a set screw or a D flat for torque | a press fit alone slips under load |
| Edge breaks | ≤ 0.2–0.3 mm on parts under 10 mm; none on an edge a cord runs over | a chamfer sized for a cup removes a small flange |
| Bottom chamfer | only on the bottom FACE'S outer edge, scaled as above | it is against elephant's foot, not decoration |

## How to build it

Draw the half-section on XY (x = radius, y = height) with `sketch_path`,
closed, and revolve it about Y. A V-groove spool, radii from the vars:

```cad
{"title": "Spule mit V-Rille", "vars": {"rb": 0.425, "rd": 1.3, "rf": 2.2,
  "y0": 0, "lip": 0.8, "g": "rf-rd"},
 "actions": [
  {"op": "create_sketch", "plane": "xy", "id": "half"},
  {"op": "sketch_path", "sketch": "half", "start": ["rb", "y0"], "segments": [
     {"to": ["rf", "y0"]},
     {"to": ["rf", "y0+lip"]},
     {"to": ["rd", "y0+lip+g"]},
     {"to": ["rf", "y0+lip+2*g"]},
     {"to": ["rf", "y0+2*lip+2*g"]},
     {"to": ["rb", "y0+2*lip+2*g"]}]},
  {"op": "revolve", "sketch": "half", "axis": "y", "angle": 360, "id": "spule"}]}
```

For a capstan drum, replace the two slope segments with a slope out of the
lower flange, a straight drum of the width the wraps need, and a slope back
up. Then the bore flat, if the shaft has one, as a small join inside the bore.

## When to do it differently

- **Very thin cord (≤ 0.3 mm)** → the groove is smaller than a nozzle line;
  make the drum plain and the flanges 45°, and let the wraps sit on the drum.
- **A wheel that must run true** → print it flat on its face and ream the
  bore; the upright print is round but can wobble layer to layer.
- **A large wheel (≥ 30 mm) in a small ratio** → spokes or a thin web save
  material and time; keep the hub at least 2 × the bore.

## Images

None yet.

## Source & date

- Written for issues #92 and #93, 2026-09-23, from the two spools and the
  28 mm wheel in those reports and the overhang rules this base already
  carries.
