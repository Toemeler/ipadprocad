# Photographs wanted

Every document in this knowledge base already has diagrams. Diagrams are good
at geometry and useless at **texture, colour and damage** — and those are
exactly the things a vision model cannot infer from prose. A photograph of a
charred plywood edge, a sink-marked boss or a delaminated fracture teaches
more in one frame than a page of description.

This file lists every photograph the documents would like, with its target
filename and what has to be visible in it. Nothing breaks while a photo is
missing; the entry simply is not referenced yet.

## How to add one

1. Shoot it (see the shooting notes at the bottom).
2. Save it at the **exact path** in the table, as `.jpg`, long edge 1600 px.
3. Paste the given snippet into that document's `## Images` section.
4. `python3 tools/kb/build_index.py && python3 tools/kb/validate_kb.py`

Priority column: **A** — the document is materially weaker without it.
**B** — clearly worth having. **C** — nice to have.

---

## Laser cutting

### A — highest value

| # | Save as | What must be visible | Goes in |
|---|---|---|---|
| L1 | `laser/02-materials/img/photo-edge-acrylic.jpg` | The cut edge of 3 mm **cast acrylic**, raking light, close enough to see it is glossy and flame-polished | `material-table` |
| L2 | `laser/02-materials/img/photo-edge-plywood.jpg` | The cut edge of 3 mm **birch ply**: brown char, the two darker glue lines, slight waviness through the thickness | `plywood` |
| L3 | `laser/02-materials/img/photo-edge-mdf.jpg` | Raw **MDF** cut edge, near-black and slightly furry, next to a painted one if possible | `mdf` |
| L4 | `laser/02-materials/img/photo-cast-vs-extruded.jpg` | The **same engraving** in cast and extruded acrylic, side by side, same lighting. Cast frosts white; extruded goes grey | `acrylic` |
| L5 | `laser/01-basics/img/photo-kerf-comb.jpg` | The ten-strip comb **reassembled and squeezed**, with callipers reading the total. The number should be legible | `kerf-test-comb` |
| L6 | `laser/01-basics/img/photo-fit-coupon.jpg` | The fit coupon with the test tab pushed into the middle slot, engraved numbers legible | `kerf-test-comb` |
| L7 | `laser/08-failures/img/photo-scorch-halo.jpg` | Brown smoke halo around a cut on **unmasked** plywood, ideally next to a masked one | `failure-catalogue` |
| L8 | `laser/08-failures/img/photo-double-cut.jpg` | A contour cut twice from duplicate lines: wide, black, tapered kerf next to a normal one | `failure-catalogue` |

### B

| # | Save as | What must be visible | Goes in |
|---|---|---|---|
| L9 | `laser/04-joints/img/photo-finger-joint-box.jpg` | An assembled finger-jointed box, corner filling the frame | `finger-joint` |
| L10 | `laser/04-joints/img/photo-joint-loose-vs-tight.jpg` | Two joints side by side: one rattling loose (uncompensated), one seated | `kerf-and-tolerance` |
| L11 | `laser/04-joints/img/photo-living-hinge-bent.jpg` | A living hinge **bent around a former**, links visibly twisted | `living-hinge` |
| L12 | `laser/04-joints/img/photo-living-hinge-cracked.jpg` | A failed living hinge, crack starting at a square slit end | `living-hinge` |
| L13 | `laser/04-joints/img/photo-t-slot-assembled.jpg` | A T-slot joint with the nut in its pocket and the screw started, on the bench | `t-slot-captive-nut` |
| L14 | `laser/04-joints/img/photo-stacked-layers.jpg` | A glued stack seen from the **side**, so the individual layers read as layers | `stacked-layer-construction` |
| L15 | `laser/04-joints/img/photo-stacked-contour.jpg` | A contour-stacked curved form, terracing clearly visible, ideally half sanded | `stacked-layer-construction` |
| L16 | `laser/05-engraving/img/photo-engrave-acrylic.jpg` | A frosted engraving on cast acrylic, lit from the edge so it glows | `raster-engraving` |
| L17 | `laser/05-engraving/img/photo-text-sizes.jpg` | The same word engraved at 3, 5 and 10 mm cap height on plywood | `text-and-fonts` |
| L18 | `laser/03-geometry/img/photo-corner-overburn.jpg` | A dark burn notch at a sharp corner on acrylic, next to a radiused corner | `corners-and-overburn` |

### C

| # | Save as | What must be visible | Goes in |
|---|---|---|---|
| L19 | `laser/02-materials/img/photo-edge-greyboard.jpg` | Greyboard cut edge, pale tan | `material-table` |
| L20 | `laser/02-materials/img/photo-sealed-felt.jpg` | Laser-cut felt edge next to a scissor-cut one, the fraying obvious | `leather-felt-textile` |
| L21 | `laser/03-geometry/img/photo-burnt-web.jpg` | A lattice where a too-narrow web has charred through | `minimum-features` |
| L22 | `laser/02-materials/img/photo-ply-void.jpg` | A plywood slot that landed on a core void | `plywood` |
| L23 | `laser/08-failures/img/photo-honeycomb-marks.jpg` | Back-reflection marks on the underside of a sheet from the honeycomb bed | `failure-catalogue` |
| L24 | `laser/07-checklists/img/photo-power-speed-grid.jpg` | A real power/speed test grid with engraved labels | `new-material-first-time` |
| L25 | `laser/09-worked-examples/img/photo-front-panel.jpg` | A finished acrylic front panel with its components fitted | `front-panel-with-cutouts` |

---

## FDM printing

### A — highest value

| # | Save as | What must be visible | Goes in |
|---|---|---|---|
| F1 | `fdm/09-failures/img/photo-fracture-layer.jpg` | A part broken **cleanly along a layer line** — the flat, striated fracture face filling the frame | `failure-catalogue`, `orientation-and-strength` |
| F2 | `fdm/09-failures/img/photo-fracture-ragged.jpg` | The contrast: a part broken *through* the material, ragged and stringy | `failure-catalogue` |
| F3 | `fdm/03-geometry/img/photo-elephant-foot.jpg` | The bottom 2 mm of a printed cube, raking light, the bulge at the base obvious against a straight edge | `chamfers-fillets-elephant-foot` |
| F4 | `fdm/02-materials/img/photo-warped-abs.jpg` | An ABS or ASA part with a corner lifted off the bed, or the finished part rocking on a flat surface | `abs-asa` |
| F5 | `fdm/03-geometry/img/photo-overhang-fan.jpg` | A printed overhang test fan, so the angle where the underside turns rough is visible | `overhangs-and-bridging` |
| F6 | `fdm/05-features/img/photo-insert-cracked-boss.jpg` | A heat-set insert that has split its boss, next to one seated correctly | `screw-boss-heat-set-insert` |
| F7 | `fdm/05-features/img/photo-snap-broken-root.jpg` | A snap-fit arm snapped off at the root, ideally one printed in the wrong orientation | `snap-fit-cantilever` |
| F8 | `fdm/01-basics/img/photo-tolerance-test-part.jpg` | The printed tolerance test part, with callipers on the 20 mm cube | `tolerance-test-part` |

### B

| # | Save as | What must be visible | Goes in |
|---|---|---|---|
| F9 | `fdm/02-materials/img/photo-stringing.jpg` | PETG stringing — fine webs between two towers | `petg` |
| F10 | `fdm/03-geometry/img/photo-bridge-sag.jpg` | A bridge test showing the span where sagging starts | `overhangs-and-bridging` |
| F11 | `fdm/03-geometry/img/photo-teardrop-vs-circle.jpg` | Two printed horizontal holes, one circular with a drooping top, one a clean teardrop | `holes-shafts-and-teardrops` |
| F12 | `fdm/05-features/img/photo-nut-trap.jpg` | A side-entry nut trap with the nut inserted | `nut-trap` |
| F13 | `fdm/06-support-strategy/img/photo-support-scar.jpg` | The rough, pitted face a support leaves, next to an unsupported face on the same part | `when-supports-are-fine` |
| F14 | `fdm/06-support-strategy/img/photo-tree-vs-block.jpg` | Tree and block supports on the same geometry, before removal | `when-supports-are-fine` |
| F15 | `fdm/03-geometry/img/photo-text-bottom-face.jpg` | Recessed text printed against the bed — the sharpest text FDM makes — next to the same text on a side wall | `text-and-embossing` |
| F16 | `fdm/04-fits/img/photo-pip-hinge.jpg` | A print-in-place hinge being broken in for the first time | `print-in-place` |

### C

| # | Save as | What must be visible | Goes in |
|---|---|---|---|
| F17 | `fdm/01-basics/img/photo-layer-lines.jpg` | A vertical wall and a top surface on the same part, so the two finishes contrast | `nozzle-line-width-layers` |
| F18 | `fdm/02-materials/img/photo-pla-heat-sag.jpg` | A PLA part that has sagged in heat — a car dashboard part is the classic | `pla` |
| F19 | `fdm/05-features/img/photo-split-dovetail.jpg` | A split part with a dovetail joint, dry-fitted | `splitting-large-parts` |
| F20 | `fdm/03-geometry/img/photo-thin-wall-gap.jpg` | A cross-section or top view showing the void left by a wall that is not a multiple of the line width | `walls-and-thin-features` |
| F21 | `fdm/02-materials/img/photo-tpu-part.jpg` | A TPU part being compressed, so the flexibility reads | `tpu` |
| F22 | `fdm/10-worked-examples/img/photo-enclosure.jpg` | A finished printed enclosure, open, with the board inside | `electronics-enclosure` |

---

## The snippet to paste

Add to the document's `## Images` section, in the order the document reads:

```markdown
![short alt text](img/photo-edge-plywood.jpg)
*What to look at, and why it is the good or the bad one. Name the visible
symptom, not the abstract rule.*
```

The caption is not optional. An uncaptioned photograph tells a model that
something is in the picture but not what — and the caption is what turns the
image into a rule it can apply.

## Shooting notes

| What | Do this |
|---|---|
| Lighting | Diffuse and **raking** — light from the side at a shallow angle. Flat frontal light hides char, layer lines and elephant foot, which are the whole point |
| Background | Plain, mid-grey or white. No workbench clutter |
| Scale | Include callipers, a steel rule or a coin wherever a dimension is the subject |
| Framing | Fill the frame with the feature. A part photographed whole shows nothing |
| Pairs | Wherever the table says "next to", shoot **both in one frame**, same light, same distance. A pair in one frame is worth far more than two separate photos |
| Focus | The defect, not the part |
| Format | JPEG, long edge 1600 px, under ~400 KB. These are reference photos, not prints |
| Honesty | Do not clean up the bad example. The charring, the strings and the crack are the content |

## If you would rather not shoot them

Every entry above is optional — the diagrams carry the documents on their own.
The eight marked **A** in each process are where a photograph earns the most,
and between them they are about an hour of bench work with parts most
workshops already have in a scrap bin.
