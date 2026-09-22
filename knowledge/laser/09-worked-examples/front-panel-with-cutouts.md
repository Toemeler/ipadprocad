---
id: laser/examples/front-panel
title: Worked example — a plywood front panel with cutouts
type: example
process: laser
triggers: [front panel, frontplatte, panel, blende, cutout, ausschnitt, connector, stecker, usb, switch, schalter, display, potentiometer, label, beschriftung, control panel, bedienfeld, instrument]
depends_on: [laser/basics/fits, laser/geometry/minimum-features, laser/engraving/engraving-wood]
confidence: medium
updated: 2026-09-22
---

# Worked example — a plywood front panel with cutouts

The second common laser job: a flat panel carrying bought components. Nothing
here is structural — the difficulty is that **every hole has to fit something
that already exists**, which makes it an exercise in measuring other people's
parts, and in wood, in living with a sheet that is not the thickness it claims.

Target: a **4 mm birch plywood** panel, 160 × 80 mm, carrying a USB-C socket,
a 16 mm panel switch, a potentiometer, a 0.96″ OLED display, four M3 screws
and engraved labels.

## When this applies

Instrument panels, enclosure faces, mounting plates, control surfaces — any
sheet whose job is to hold bought hardware.

## Good starting values

### Step 0 — the two measurements everything rests on

| Quantity | Value | Where it came from |
|---|---|---|
| Nominal material | 4 mm birch ply, B/BB | chosen |
| **Measured thickness** | **3.85 mm** | callipers, three places, smallest reading |
| **Measured kerf** | **0.27 mm** | [`kerf-test-comb`](../01-basics/kerf-test-comb.md) |
| Compensation | geometry (Method B), 0.135 mm inward on every hole | the controller has no offset feature |
| Grain | face grain along the 160 mm dimension | the panel is long and thin; it wants stiffness that way |

### Every hole, and where its number comes from

| Component | Hole | Drawn | Fit | Why |
|---|---|---|---|---|
| M3 mounting screws ×4 | ⌀ 3.4 mm | 3.4 | clearance | ISO 273 medium; never a close fit on a four-screw pattern |
| Panel switch, 16 mm | ⌀ 16.2 mm | 16.2 | clearance +0.2 | the threaded bush must pass; the nut covers the gap |
| Potentiometer, 7 mm bush | ⌀ 7.2 mm | 7.2 | clearance | plus an anti-rotation notch if the pot has a lug |
| USB-C socket | 9.2 × 3.4 mm, 0.5 mm corner radius | rectangle | clearance +0.2 | **measure the actual socket** — "USB-C" is not a dimension |
| OLED 0.96″ | 26.0 × 14.5 mm window | rectangle | clearance +0.3 | the glass, not the PCB; leave the PCB behind the panel |
| OLED mounting | 4 × ⌀ 2.4 mm | 2.4 | clearance | M2 |

### The wood checks this panel needs and an acrylic one would not

| Check | Value here | Limit | Verdict |
|---|---|---|---|
| Smallest hole | 2.4 mm | ≥ 0.8 × t = 3.1 mm | **fails** — see below |
| Smallest web (OLED window to switch) | 6 mm | ≥ 1.5 × t = 5.8 mm | ok, barely |
| Edge distance, M3 holes | 8 mm from edge | ≥ 2 t = 7.7 mm | ok, barely |
| Grain under the long cutout | runs along it | — | ok |
| Corner radius on rectangular cutouts | 0.5 mm | — | added, against overburn |

The 2.4 mm M2 holes are **below the minimum hole diameter for 4 mm plywood**.
In acrylic they would be fine. Three options, and the document's job is to say
so rather than let them be cut and char shut:

1. Drill them after cutting (best — a drilled hole in ply is round and clean).
2. Open them to 3.5 mm and use washers.
3. Move the display mounting to standoffs behind the panel and cut no holes at
   all.

## How to build it

1. **Measure every component with callipers.** Datasheet dimensions are
   nominal and connectors vary between manufacturers. This is the whole job.
2. Measure the sheet, and check it is flat.
3. Decide the grain direction, then lay out the component positions, then
   check the webs between them.
4. Add 0.5 mm radii to rectangular cutouts.
   → [`corners-and-overburn`](../03-geometry/corners-and-overburn.md)
5. Put the labels on the `Engrave` layer, 5 mm cap height, medium-weight sans,
   stroke ≥ 0.5 mm. On birch the contrast is good; on a walnut-faced ply it
   would not be. → [`engraving-wood`](../05-engraving/engraving-wood.md)
6. **Mask both faces** before cutting — a panel is all visible surface.
7. Engrave first, cut the internal holes, cut the outline last.
8. Peel, sand the faces to 320, seal.
   → [`sealing-and-finishing`](../10-wood-finishing/sealing-and-finishing.md)
9. Cut a **cardboard proof first**. Twenty minutes, and it catches the
   connector that is 0.4 mm wider than its datasheet.

## When to do it differently

- **The panel must be stiff and thin** → 4 mm ply flexes over 160 mm. Go to
  6 mm, add a stiffening rib behind it, or support the long edges.
- **A backlit or edge-lit panel** → this is the case for cast acrylic; wood
  does not transmit light. Engrave the back face of 3 mm cast acrylic and
  light it from the edge. → [`acrylic`](../02-materials/acrylic.md)
- **Very small holes throughout** → acrylic, or drill them.
- **A premium look** → walnut- or cherry-faced ply for the panel and engrave
  nothing; label with a printed overlay or paint-filled engraving instead.
- **A panel handled daily** → seal it. Bare plywood around a switch picks up
  finger marks within a week.

## Images

![the panel layout with every cutout dimensioned](img/fig-front-panel-layout.svg)
*Every hole traced back to a measured component. "USB-C" is not a dimension —
the socket in your hand is.*

![why a cardboard proof is worth twenty minutes](img/fig-cardboard-proof.svg)
*The same file in 1.5 mm greyboard. It catches the connector that is wider
than its datasheet, before the plywood is cut.*

## Source & date

- Clearance hole sizes: ISO 273 medium series, as tabulated in
  [`fits-press-slip-clearance`](../01-basics/fits-press-slip-clearance.md).
- Minimum hole ⌀ in wood: [`minimum-features`](../03-geometry/minimum-features.md).
- Component dimensions are examples; every one of them should be measured.
- `confidence: medium`.
