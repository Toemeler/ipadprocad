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
makes it work is the groove the cord runs in, the pitch diameter the ratio is
measured at, and the bore that grips the shaft. All three went wrong in #92
and #93: grooves with a vertical flange on one side and a 45° slope on the
other, a ratio taken at the drum instead of the cord, and a 0.6 mm "foot
chamfer" copied from the mug recipe onto a 4.4 mm spool.

## When this applies

Any round part a cord, string or thin rope runs on or winds onto: a capstan
drive, a winch drum, an idler pulley, a spool. Printed upright (axis
vertical), which keeps the bore round and puts the groove flanks at a
printable angle.

Not for toothed belts (GT2 and similar need their tooth profile) or gears.

## Good starting values

**An idler or guide pulley — one groove, the cord passes over it.**

| Quantity | Value | Source |
|---|---|---|
| Groove opening | 30–45° included (wire-rope sheaves); 34–40° for a V-groove cord pulley | Rockett; Firgelli |
| Groove depth | 1.5 × cord Ø | Rockett |
| Groove bottom | radius 5 % larger than the cord's | Rockett |
| Cord seated | 70–80 % of its Ø still above the flanks at rest (V-groove) | Firgelli |
| Groove shape | symmetric — both flanks at the same angle | a groove steep on one side and sloped on the other walks the cord to the steep side (#93) |

Printed upright, a flank that opens at 30–45° included stands 67–75° from
horizontal: well inside the 45° overhang limit (Hubs), so the groove needs no
support. Only the round bottom of a U-groove turns horizontal at its top;
below a 1 mm cord it is smaller than a line and prints anyway.

**A capstan drive — the cord wraps a small drum and drives a large one.**

| Quantity | Value | Source |
|---|---|---|
| Wraps on the small drum | 3–5 turns | Aaed Musa's printed capstan drive; Firgelli |
| Groove | helical on BOTH drums, pitch a little over the cord Ø, so the wraps lie side by side and unwind guided | Aaed Musa |
| Anchoring | cord wrapped round the small drum, fixed to the large drum at both ends | Aaed Musa |
| Tension | adjustable — a lead screw or a tensioner at one anchor | Aaed Musa |
| Ratio | pitch diameters, i.e. **through the centre of the cord**: (D_large + d) / (D_small + d) | Certex (drum pitch diameter) |
| Small drum Ø vs cord Ø (D/d) | ≥ 20 for steel cable in occasional use, ≥ 40 cyclic; synthetic rope tolerates much smaller | Firgelli; Sandia (Mazumdar et al. 2017) |
| Cord | Dyneema (low weight, high strength) or Vectran (lowest creep) | Aaed Musa; Sandia |

The ratio note is not academic. On the #93 drive (Ø2.6 small drum, Ø28
large, 0.2 mm cord) the surface ratio is 10.8:1 and the pitch ratio 10.1:1 —
7 % apart, and it is the pitch ratio the output follows. Real drives also
drift from the drawn ratio for reasons of their own (Aaed Musa's, drawn for
8:1, measured 8.55:1), so measure the built ratio before relying on it.

**Every drum and pulley.**

| Quantity | Value | Source |
|---|---|---|
| Bore | print it slightly undersized and drill or ream to size; vertical holes come out small | Hubs |
| Bore on a D-shaft | the flat modelled, so the flat — not friction — takes the torque | practice; see holes-shafts-and-teardrops for the fit |
| Bottom-edge chamfer | light: 0.2–0.5 mm; or none, and leave it to the slicer's elephant-foot compensation (≈0.2 mm, on by default in Prusa profiles) | QIDI; Prusa; see chamfers-fillets-elephant-foot |
| Edges the cord runs over | no chamfer | a chamfer there moves where the cord sits |

## How to build it

Draw the half-section on XY (x = radius, y = height) with `sketch_path`,
closed, and revolve it about Y. A guide pulley with a symmetric groove, depth
1.5 d and a 40° opening, from vars:

```cad
{"title": "Umlenkrolle", "vars": {"rb": 2.6, "d": 1.0, "depth": "1.5*d",
  "rf": 8, "lip": 1.2, "half": "tan(20)*depth", "w": "d*1.05"},
 "actions": [
  {"op": "create_sketch", "plane": "xy", "id": "half"},
  {"op": "sketch_path", "sketch": "half", "start": ["rb", 0], "segments": [
     {"to": ["rf", 0]},
     {"to": ["rf", "lip"]},
     {"to": ["rf-depth", "lip+half"]},
     {"to": ["rf-depth", "lip+half+w"]},
     {"to": ["rf", "lip+2*half+w"]},
     {"to": ["rf", "2*lip+2*half+w"]},
     {"to": ["rb", "2*lip+2*half+w"]}]},
  {"op": "revolve", "sketch": "half", "axis": "y", "angle": 360, "id": "rolle"}]}
```

A capstan drum is the same half-section with a wide flat drum between the
flanges (wraps × pitch + one pitch). The helical groove on it is a `coil`
of the cord's section cut into the drum, pitch as above.

## When to do it differently

- **Very thin cord (≤ 0.3 mm)** → a groove 1.5 d deep is under one nozzle
  line; make the drum plain between two flanges and let the helical wraps
  sit on it.
- **A wheel that must run true** → print undersize, then drill or ream the
  bore (Hubs); run-out at the groove should stay under 0.1 mm (Firgelli).
- **A large, light wheel** → spokes or a thin web save material; keep the hub
  at least twice the bore.

## Images

None yet.

## Source & date

Researched 2026-09-23 for issues #92 and #93:

- Rockett Inc., "Tips on Designing the Right Steel Cable Sheaves" — groove
  angle 30–45°, depth 1.5 × rope Ø, groove 5 % over rope Ø.
  https://www.rockettinc.com/steel-cable-sheaves/
- Firgelli Automations, "V-grooved Rope Pulley Mechanism" and "Capstan
  (gear) Mechanism" — 34–40° V-groove, 70–80 % exposure, run-out < 0.1 mm,
  D/d ≥ 20 / 40 for steel, 3–5 wraps.
  https://www.firgelliauto.com/blogs/mechanisms/v-grooved-rope-pulley
  https://www.firgelliauto.com/blogs/mechanisms/capstan-gear
- Aaed Musa, "Capstan Drive" (printed PLA, Dyneema DM20, 3–5 wraps, helical
  drums, lead-screw tension; 8:1 drawn, 8.55:1 measured, cause unknown).
  https://www.aaedmusa.com/projects/capstandrive
- Certex USA, "Calculating Drum Capacity" — pitch diameter through the
  centre of the rope. https://www.certex.com/wire-rope-general-information/calculating-drum-capacity/
- Mazumdar et al., "Synthetic Fiber Capstan Drives for Highly Efficient,
  Torque Controlled, Robotic Applications", IEEE RA-L 2017 (Sandia) —
  Dyneema/Vectran, lower D/d than steel, 95 % efficiency.
  https://www.osti.gov/pages/biblio/1340266
- Protolabs Network (Hubs), "How to design parts for FDM 3D printing" —
  45° overhang limit, vertical holes print undersized.
  https://www.hubs.com/knowledge-base/how-design-parts-fdm-3d-printing/
- Prusa Knowledge Base, "Elephant foot compensation" — ≈0.2 mm, on by
  default. https://help.prusa3d.com/article/elephant-foot-compensation_114487
- QIDI, "Fix elephant foot" — a 0.2–0.5 mm base chamfer.
  https://us.qidi3d.com/blogs/news/fix-3d-print-elephant-foot

Not from a source, and marked where it is used: the one-sided groove
walking the cord, and "no chamfer where the cord runs" — both from the #93
report.
