# Ribbon icon system — SPEC

The design system for every icon the ribbons, overflow menus and flyouts draw. Five designers draw
the remaining icons in parallel from this file, so everything here is a rule, not a suggestion.
Where a rule says **must**, the lint in `tools/icon_redesign/build.py` checks it and the build fails.

- Preview and lint: `python3 tools/icon_redesign/build.py ICONS_JSON` writes `docs/icon_redesign.html`.
  See [§10](#10-build-preview-and-lint).
- Reference icons, already drawn to final quality, set the bar: `IC/line34 IC/circle34 IC/rect34
  CN/coincident CN/dim CR/extrude CR/revolve MO/fillet MO/hole WF/plane WF/axis AS/place
  AS/constrain MS/measure`. **Open them next to your work.**
- Canonical motifs: `design/icons/_motifs/*.svg`. Copy geometry from them; do not redraw it.

---

## 1. References and principles

The system was built against the published guidelines and the real artwork of the reference sets,
not from memory alone. Everything was fetched on 2026-10-06. The network proxy of this session
**blocked** autodesk.com, help.autodesk.com, fluent2.microsoft.design, learn.microsoft.com,
shapr3d.com (including support.shapr3d.com), cad.onshape.com, help.solidworks.com, Siemens,
blender.org (including wiki.blender.org) and plasticity.xyz. For those vendors the notes below come
from search-engine extracts of their pages, plus how their shipping products look. They are marked
*(search extract)* or *(product convention)*. Apple's HIG, Microsoft's Fluent SVG repository,
Autodesk's open-source Weave/HIG icon package and FreeCAD's CAD icon set were read directly, and
their SVGs were measured. A side-by-side sheet of the studied artwork at 64 and 28 px is at
`…/scratchpad/shots-icons/00-reference-sheet.png`.

| Source | What we took | Link |
|---|---|---|
| **Apple SF Symbols / HIG Icons** (read directly) | One stroke weight across the whole family ("use the same stroke weight in every icon"; match level of detail, weight and *perspective*). **Optical centring**: a bottom-heavy glyph moves up, as the download-arrow example shows. *Hierarchical* rendering, where one colour sits on primary, secondary and tertiary layers; that is our INK / LINE / DIM and the three face stops. Restrained multicolour: colour only where it "enhances meaning". Enclosures and badges are *components*, not redrawn per icon, which becomes our badge motifs. "Draw whole shapes" and do the gaps with geometry. Text only when it *is* the meaning. | [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols), [Icons](https://developer.apple.com/design/human-interface-guidelines/icons) |
| **Microsoft Fluent UI System Icons** (SVGs measured) | Size-specific masters: 20 px uses a 1.0 stroke, while **24 and 28 px use a 1.5 stroke on a 2 px padding**. Outer corners are rounded at about 1.5 at 28. The `cube_28_regular` silhouette spans 2–26 with an inner Y-edge. Its receding slope is 0.4; we use 0.5, see §4. Metaphors are one object plus one modifier at the bottom-right. | [microsoft/fluentui-system-icons](https://github.com/microsoft/fluentui-system-icons) (`assets/Cube/SVG/ic_fluent_cube_28_regular.svg`, `Ruler`, `Arrow Rotate Clockwise`) |
| **Autodesk Weave / HIG** (package read directly) | A 24 grid plus a 16 "information-dense" set: separate small masters rather than scaled-down large ones, which is our `.sm.svg` rule. Monochrome glyphs, square terminals, and `file-part` / `file-assembly` metaphors. Fusion dropped its blue toolbar bar to "make the toolbar more neutral so users can focus on their designs" and moved icons to SVG for high DPI and dark mode *(search extract)*. Fusion command icons ship at 16/32/64 with `-dark` and disabled variants *(search extract)*. In the products, solids are grey and the feature being created or the face it acts on is the single blue element *(product convention)*. | [Autodesk/hig `packages/icons`](https://github.com/Autodesk/hig), [Fusion UI modernization](https://www.autodesk.com/products/fusion-360/blog/ui-modernization-update/), [Fusion API: icons](https://help.autodesk.com/cloudhelp/ENU/Fusion-360-API/files/UserInterface_UM.htm), [Inventor 2024 UI](https://help.autodesk.com/cloudhelp/2024/ENU/Inventor-WhatsNew/files/GUID-333B7827-5CD7-4E79-810A-5BD1274254E6.htm) |
| **Shapr3D** | UI refresh: "newly-improved icons … larger labels", with labels optionally hidden and shown on hover *(search extract)*. That is our default: **unlabelled** icons must stand on their own. The tool set is Extrude, Revolve, Chamfer/Fillet as one tool, and so on, drawn as a single solid with one highlighted feature *(product convention)*. | [Refreshing the Shapr3D UI](https://www.shapr3d.com/blog/refreshing-the-shapr3d-user-interface), [Extrude tool](https://support.shapr3d.com/hc/en-us/articles/26649987200796) |
| **Blender 4.x** | Icons are "14×14 within a 16×16 grid", "purposefully simple and chunky", and nothing is narrower than one grid unit. Colour: "restrained … subdued, professional … neutral with one or two highlight colours" *(search extract)*. That is our 1 accent + 1 secondary rule. | [Blender HIG: Icons](https://wiki.blender.org/wiki/Human_Interface_Guidelines/Icons) |
| **FreeCAD PartDesign / Sketcher** (SVGs studied, open source) | The canonical CAD metaphors in a real shipping set: **Pad** is a block over its profile. **Revolution** is a profile swept round an axis. **Fillet** and **Chamfer** are a block whose rounded or bevelled edge alone is in the highlight colour. **Hole** is a bore in a block. **Plane** is a parallelogram with corner points. **Line** is a segment with end points. **Circle** has a centre and a rim point. **Rectangle** has two corner points. **Coincident** is elements meeting at a dot. **Dimension** is extension lines plus arrows. **Parallel** is `//`, **Perpendicular** is `∟`, and **Tangent** is a curve touching a line. Patterns are repeated instances. What we do not take: Tango gradients, black outlines on every shape, three to four hues per icon. | [FreeCAD icons](https://github.com/FreeCAD/FreeCAD/tree/main/src/Mod/PartDesign/Gui/Resources/icons) |
| **Onshape** | Extrude and Revolve sit side by side as the first two feature tools. Feature dialogs use a colour paradigm for the selection roles *(search extract)*. | [Feature basics](https://cad.onshape.com/help/Content/PartStudio/feature_basics.htm) |
| **SolidWorks 2025** | "Hole Type icons are clearer to distinguish": one family, one metaphor, differing only in the profile detail *(search extract)*. The 2025 Simplified Interface cuts toolbar clutter *(search extract)*. | [SW 2025 UI](https://help.solidworks.com/2025/English/WhatsNew/c_wn_ui.htm) |
| **Siemens NX / Solid Edge** | Nothing concrete was retrievable. The product convention is that work features (datum planes and axes) carry their own colour, distinct from solids, as in Inventor's orange work planes. | — |
| **Plasticity** | Its 2025 UI is "modern, streamlined", with clutter reduced by context-sensitive widgets *(search extract)*. Lesson: the ribbon icon carries the command, not decoration. | [Plasticity 2025.1](https://www.cgchannel.com/2025/02/plastic-software-releases-plasticity-2025-1) |

**Principles distilled**, all of them enforced below:

1. **One family, one weight.** A 1.5 stroke at 28, 2.0 only for the hero element and 1.25 for fine annotation (Apple, Fluent).
2. **One projection** for every solid in the set (Apple: "perspective").
3. **Grey is the world; one colour is the verb.** Context solids are neutral; the thing the command creates or acts on carries the accent (Fusion, Shapr3D, FreeCAD, Blender).
4. **Work features have their own colour** (amber), as Inventor's orange work planes do and as our own viewport draws them (`T.previewFill`).
5. **Draw at the size it is used.** The 28 master is the design, and smaller sizes get their own simplified master when needed (Fluent, Weave, Blender).
6. **Gaps, not knock-outs.** Overlaps are separated by geometry (Apple's whole shapes plus offset gaps).
7. **No text** unless the glyph *is* a letter, and then as outlined paths (Apple).

**Metaphors CAD users already know.** We must stay recognisable on these, and a new drawing that
breaks one needs a reason:

| Command | Known metaphor | Ours |
|---|---|---|
| Extrude | prism rising from its profile, with an up arrow | accent prism plus an INK arrow from the top face |
| Revolve | solid of revolution, axis, arc arrow round it | accent cylinder, amber dash-dot axis, 3D arc arrow |
| Sweep / Loft / Coil | profile along a path / between two profiles / along a helix | same accent solid language, with the path in INK |
| Fillet / Chamfer | block with one rounded / bevelled edge highlighted | neutral block, accent fillet face |
| Hole | bore in a block | neutral slab, accent bore |
| Shell | hollowed block, thin walls | neutral block opened, accent inner walls |
| Plane / Axis / Point | parallelogram / dash-dot line / dot | amber, same motifs everywhere |
| Line / Circle / Rect / Arc | geometry plus grip points | ACC 2.0 geometry plus INK grips |
| Constraints | `∟ // = ⊙ —` and so on, on the geometry | INK geometry plus ACC marker |
| Dimension / Measure | extension lines and arrows / ruler | amber arrows; ruler for Measure |
| Pattern | repeated instances (grid, ring, mirror) | first instance accent, copies neutral |
| Place / Constrain / Joint | component cube, arrow; two parts mated | accent part, neutral base |

---

## 2. Grid, keylines and sizes

**Master:** every icon is one SVG with `viewBox="0 0 28 28"` and no `width`/`height`. 28 is the primary
size: the default rail draws 28 px glyphs in 36 px cells, unlabelled.

| Placement | Size | Scale of the master | Notes |
|---|---|---|---|
| Rail / compact band (default) | **28** | 1.000 | the design size |
| Big button, named mode | 34 | 1.214 | |
| Flyout row | 26 | 0.929 | |
| Small row, overflow menu | 18 | 0.643 | `.sm.svg` rule below |

**Live area** 2–26 (24 u, 2 u padding, as in Fluent 24/28). Strokes may reach 1 u into the padding,
and nothing crosses 0.75 or 27.25 (lint). **Keylines** (`_motifs/grid-keylines.svg`): circle r 11 at
(14,14); square 3.5–24.5 (rx 1.5); portrait 5–23 × 2–26; landscape 2–26 × 5–23; the canonical cube
outline.

**Optical size: fill the keyline.** This is the rule that makes the set look like Fluent or SF Symbols
rather than a sparse, timid set (round 4 fixed exactly this). The primary glyph spans its keyline:

- a solid spans the circle keyline: the canonical cube is 22 wide (3–25) and 23 tall (2.5–25.5),
  matching Fluent's `cube_28` (2–26);
- 2D primitives reach the square keyline (line 4.5→23.5, circle r 10.5, rectangle 3.5–24.5 × 6.5–21.5);
- a tall glyph uses the portrait keyline and a wide one the landscape keyline.

The lint fails any glyph whose major extent, strokes included, is under **19 u**. Aim for 21–23.

**Optical centring** (Apple): the visual mass sits on (14,14). A bottom-heavy drawing such as a
block with an arrow above it is shifted until it *looks* centred. The shift is at most 1.5 u, and it
goes into the drawing, never into a transform.

**Axis-aligned straight edges** sit on whole or half units, so they are crisp at 2× (iPad and
high-DPI Windows) and at worst half a pixel soft at 1×. Avoid quarter units except where the
projection forces them.

**18 px (`.sm.svg`).** No small master by default. Every master is checked at 18 px, which is 0.643×.
A `<key>.sm.svg` (same folder, same `viewBox 0 0 28 28`, same palette) is **required** when the
master has any of these:

- a feature narrower than 2 u, or a clear gap between strokes under 1.5 u;
- more than six separately readable parts;
- tick marks or dashes shorter than 2 u.

The small master uses a 2.0 stroke everywhere (1.5 for fine strokes), drops secondary detail such as
ticks, inner edges and the third face stop, and keeps the silhouette and the colour roles. None of
the 14 references needed one.

## 3. Stroke, fill, corners, detail

| Weight | Use |
|---|---|
| **1.5** (standard) | outlines and edges of solids, 3D arc arrows, axes, rulers, rings, source profiles (dashed) |
| **2.0** (hero) | **all 2D sketch geometry** (ACC created, INK existing/constrained), the main direction arrow, a selected edge, badge `+`/`−` |
| **1.25** (fine, minimum) | dimension and extension lines, inner edges of accent solids, ruler ticks, secondary radius lines |

- Nothing is thinner than 1.25. Root attributes are always
  `fill="none" stroke-linecap="round" stroke-linejoin="round"`.
- **Dashes** use `stroke-linecap="butt"`:
  - preview: `2 1.5`
  - source profile of a feature (the sketch an extrude/revolve consumes, `_motifs/source-profile.svg`): `2.5 1.5` at 1.5 in INK
  - construction: `3 2` at 1.5 in DIM
  - axis and centreline dash-dot: `4 1.5 1 1.5` at 2.0, or `3 1.5 1 1.5` at 1.5
- **Fill** only:
  - solids, with the face stops (§4);
  - grips and points (solid);
  - arrowheads (solid, with a 1.0 stroke of the same colour to round them);
  - planes, preview regions and selected 2D regions, as a *tint*: the role colour with
    `fill-opacity` from .25 to .35, the only opacity allowed. `opacity` and `stroke-opacity` are banned.
  - 2D sketch geometry is never filled.
- **Corners:** non-geometric objects (ruler, sheet, layer, document) use rx 1.5. Grips use rx 1.
  Sketch rectangles and solids keep sharp model corners; the round join softens them.
- **Minimum detail:**
  - a dot has r ≥ 1.25;
  - a grip is ≥ 3.5 square, standard 4.5;
  - an arrowhead is ≥ 3 u long;
  - the clear gap between parallel strokes is ≥ 1.5 u;
  - an enclosed counter is ≥ 2.5 u.
- **Overlaps:** there is no "background colour" knock-out, because any colour you pick is wrong on
  one of rail, panel or fly. Break the underlying stroke with a gap of at least 1.25 u (see
  `CN/coincident`), or let a filled element sit on top.
- **Nothing dark-on-accent** (lint-enforced): never draw an INK, LINE or DIM stroke or fill *over* an
  accent face. On light themes INK maps to about #201E1E and the accent faces to #1C-#3A blues
  (≈ 1.5:1), so the overlap vanishes, as the round-1 extrude arrow did. Arrows, cursors and markers sit
  on the ground, kept ≥ 1.25 u clear of accent solids: see `CR/extrude` (the arrow stands beside the
  prism) and `CR/revolve` (the arc runs through the missing quadrant). Edges that only *bound* an
  accent face (the fillet's INK edges) are fine, and so is INK over *neutral* faces. The lint flattens
  every shape and fails any dark sample point inside an accent face that is more than half a stroke
  plus 0.35 u from the face's edge.
- **Arrowhead** (direction): a filled triangle, length 4.5 and half-width 2.75 at 28, plus a 1.0 stroke
  of its own colour. Dimension arrowheads use length 3.4 and half-width 2.1. Generator: `ahead()` in
  the reference source; geometry in `_motifs/arrow-direction.svg`.

## 4. Projection (3D) and the sketch (2D) convention

**One axonometric for every solid: 2:1 dimetric** ("pixel isometric"). The receding axes run at
±26.565° (2 across, 1 down) and the vertical stays vertical, with equal scale on all three axes.
We chose it over Fluent's 0.4 slope and true isometric (30°) because 2:1 lands every vertex on
half-units, so edges stay crisp at 2×.

- In grid units the axes are x → (+2, +1)·k (right face), y → (−2, +1)·k (left face) and z → (0, −1).
- **Canonical cube** (`_motifs/cube-component.svg`): top T (14,2.5), right R (25,8), front F
  (14,13.5), left L (3,8); verticals 12. Bottoms: (3,20), (14,25.5), (25,20). Half-width 11, rhombus
  22 × 11; it spans the circle keyline. Scale it with the same 2:1 ratio and keep verticals ≈ 1.1 ×
  half-width for a cube; slabs are shorter. When two solids share the canvas (Place, Constrain), the
  pair together fills the keyline.
- **Circles:** horizontal circles project to ellipses with **ry = rx / 2** and a horizontal major axis.
  Circles on a vertical face use the face's matrix: right face `matrix(.894 .447 0 1 cx cy)`, left face
  `matrix(.894 -.447 0 1 cx cy)`. Cylinders are drawn as in `_motifs/cylinder.svg`.
- **Viewpoint** is always from front-above. Never show a bottom face, and never a back-left or
  back-right view. Hidden edges are not drawn, except when they *are* the message (a shell's inner
  wall), and then they use DIM, dashed.

**Face stops and lighting.** Three fills per solid, always in this order:

| Face | Neutral | Accent |
|---|---|---|
| left (lit) | `FA #666666` | `AFA #8BBBEE` |
| **top** | `FB #545454` (always the middle stop) | `AFB #559CE7` |
| right (shade) | `FC #424242` | `AFC #207CDF` |

Why the top is the middle stop: `_map` inverts neutral lightness on light themes. With the top as the
middle stop, inversion only swaps the side faces (lit from the left on dark, from the right on light),
and a solid never looks lit from below. Accent faces keep their order in both themes, because `_map`
preserves chromatic order.

- **Neutral solids:** silhouette and visible edges in **INK 1.5**.
- **Accent solids:** silhouette in **ACCHI 1.5** and inner edges in **ACCHI 1.25**. No INK outline on
  accent solids.
- **Curved faces** (cylinder side, fillet) are split into a lit half (FA/AFA) and a shade half
  (FC/AFC). Gradients are not used.

**Sketch / 2D convention** (`IC`, `CN`, `MD`, `IN`, sketch patterns):

- 2D icons are drawn flat in front view, with no projection, plane or grid.
- Geometry the command **creates**: `ACC`, 2.0, unfilled.
- **Existing / input / constrained** sketch geometry: `INK`, 2.0 (same weight as created geometry, so
  2D icons have one line weight; 1.5 is the 3D-edge weight).
- **Grip points:** INK squares 4.5 (rx 1) on the defining points (`_motifs/point-grip.svg`). A
  centre point is a grip; on a circle that has no centre grip, use a 3.5 INK `+`.
- **Construction:** DIM dashed `3 2`. **Projected / reference** geometry: AMB 1.5. **Dimensions:** AMB.
- A sketch **on a solid** (newSketch, projgeo, emboss, decal) is drawn in dimetric: the face is
  neutral, and the sketch curves are mapped with the face's matrix.

## 5. Colour roles

Every colour is a 6-digit `#RRGGBB` from this table. **Nothing else** may appear: no 3-digit hex,
no names, no `rgb()`, no `currentColor`. At runtime `frontend/lib/icon_theme.dart _map` recolours
them:

- neutrals (HSL S < .12) keep their lightness on dark and invert on light;
- chromatic colours move to the palette's hue by bucket: 175–265 → accent, 75–175 → ok,
  18–75 → amber, else → error;
- chromatic lightness is clamped to .32–.82 on dark and squeezed to .16 + .30·L on light.

The mapped values and WCAG contrast below are for **Carbon Pro Neutral**. The rail is `bg`
#1D1E1F / #E7E7E8, the panel #252627 / #F4F4F5 and the fly #2E2E2F / #FFFFFF.

| Token | Source | Role | Use | Dark → | rail / panel / fly | Light → | rail / panel / fly |
|---|---|---|---|---|---|---|---|
| `INK` | `#E0E0E0` | primary glyph: outlines, existing geometry, arrows, grips | stroke, fill | `#DFDFE1` | 12.5 / 11.4 / 10.2 | `#201E1E` | 13.4 / 15.1 / 16.6 |
| `LINE` | `#ADADAD` | secondary glyph: context geometry that must recede | stroke, fill | `#AAAAB0` | 7.2 / 6.6 / 5.9 | `#554F4F` | 6.5 / 7.3 / 8.0 |
| `DIM` | `#8F8F8F` | tertiary: construction, hidden, radius lines, disabled parts | stroke, fill | `#8B8B93` | 4.9 / 4.5 / 4.0 | `#746C6C` | 4.1 / 4.7 / 5.1 |
| `FA` `FB` `FC` | `#666666` `#545454` `#424242` | neutral face stops (left / top / right) | **fill only** | | 2.8–1.6 | | 2.4–1.5 |
| `ACC` | `#6CABEF` | **accent**: what the command creates or acts on | stroke, fill | `#6DABEE` | 6.9 / 6.3 / 5.6 | `#1C5A9E` | 5.7 / 6.4 / 7.0 |
| `ACCHI` | `#BFDAF8` | edges of accent solids, accent highlights | stroke, fill | `#ADD0F5` | 10.4 / 9.5 / 8.5 | `#2067B5` | 4.6 / 5.2 / 5.7 |
| `AFA` `AFB` `AFC` | `#8BBBEE` `#559CE7` `#207CDF` | accent face stops | **fill only** | | | | |
| `AMB` | `#ED8D26` | **work features**, reference / projected geometry, preview, dimension, measure | stroke, fill, tint | `#EF8E24` | 6.8 / 6.2 / 5.5 | `#A05504` | 4.5 / 5.0 / 5.5 |
| `OK` | `#29A35C` | add / new / confirm / finish (`+` badge, Finish) | stroke, fill | `#27A55B` | 5.3 / 4.8 / 4.3 | `#048A46` | 3.6 / 4.0 / 4.4 |
| `ERR` | `#E96C67` | remove / delete / trim-away / error (`−` badge, deleted part) | stroke, fill | `#EC6764` | 5.3 / 4.8 / 4.3 | `#8A2C2C` | 6.9 / 7.7 / 8.5 |

**Rules:**

- **At most 1 accent family plus 1 secondary per icon.** The families are ACC (`ACC ACCHI AFA AFB AFC`),
  AMB, OK and ERR. You may use ACC plus one of AMB/OK/ERR, or one secondary alone (a work feature).
  You may not use two secondaries.
- Every icon has at least one glyph-role colour (INK, LINE, DIM, ACC, ACCHI, AMB, OK or ERR). Glyph
  roles reach ≥ 3:1 on rail, panel and fly in both themes. Face stops are banned as strokes; they are
  volume, not outline.
- **What gets the accent:** the one element the command *produces* (the new solid, the new sketch
  curve, the hole) or, when nothing new is produced, the *selection it acts on* (the edge that gets
  filleted, the face that moves). Context is neutral. If two things want the accent, the result wins.
- **Amber** is the work-feature colour, because the viewport draws work planes in `T.previewFill`.
  It also covers reference geometry, previews, dimensions and measurement.
- **Known `_map` caveats**, fixed by the §12 integration: on light themes neutrals borrow `T.ink`'s hue,
  so they pick up a faint pink cast (FA → #9D9595), and accent solids go heavy navy. Design for the
  shipping `_map` (the lint checks both); the page's **_map** control shows the integration.

## 6. Shared motifs (`design/icons/_motifs/`)

Copy the geometry; scale only uniformly, and only when a motif must shrink to share the canvas.

| Motif | File | Geometry |
|---|---|---|
| Grid and keylines | `grid-keylines.svg` | §2, plus the canonical cube outline |
| Projection axes | `projection-axes.svg` | x (+2,+1), y (−2,+1), z up |
| Grip / sketch point | `point-grip.svg` | INK rect 4.5 × 4.5, rx 1, centred on the point (4 at line ends in constraint icons, 3.5 secondary); on 2.0 ACC geometry |
| Centre mark | `point-center.svg` | INK `+`, arms 2.5, 1.5 stroke |
| Cursor | `cursor-select.svg` | path `M8 4V21.5L12.1 17.9L15 24.2L17.9 22.9L15 16.8H20.5Z`, INK fill and 1.25 stroke; translate only |
| Direction arrow | `arrow-direction.svg` | shaft 2.0 ending 4.5 short of the tip; head length 4.5, half-width 2.75 (2.25 when space is tight) |
| Rotation arrow (2D) | `arrow-rotation.svg` | arc r 10.5 about (14,14), about 300°, head at the end tangent |
| Rotation arrow (3D) | `arrow-rotation-3d.svg` | ellipse arc rx 11.5 ry 5.25 (2:1), front half only, head length 4 |
| Dimension | `arrow-dimension.svg` | AMB extension lines 1.25, dim line 1.25, heads 3.6 / 2.2, 0.9 clear of the extension line |
| Source profile | `source-profile.svg` | INK 1.5 dashed `2.5 1.5` rhombus on the base plane: the sketch a feature consumes |
| Constraint markers | `constraint-markers.svg` | ACC 1.5: coincident ring r 3 + dot r 1.25; parallel `//`; perpendicular `∟`; equal `=`; horizontal `—`; vertical `|`; tangent arc on line; symmetric `|<<`; lock (rx 1 body + shackle) |
| Plus / minus badge | `badge-plus.svg`, `badge-minus.svg` | bare 2.0 `+` (OK) or `−` (ERR), arms 4, centred at (22,21), with no ring and no disc; the host drawing keeps clear of a 9 × 9 box there |
| Work plane | `plane-work.svg` | right-face parallelogram (3.5,3) (24.5,13.5) (24.5,25) (3.5,14.5); AMB tint .3 plus a 1.5 outline |
| Work axis | `axis-work.svg` | AMB 2.0 dash-dot `4 1.5 1 1.5`, butt |
| Work point | `point-work.svg` | AMB dot r 2.75 plus a ring r 6 at 1.25 |
| Component cube | `cube-component.svg`, `cube-component-accent.svg` | the canonical cube, neutral and accent |
| Cylinder | `cylinder.svg` | rx 8, ry 4; split lit/shade halves |
| Selection highlight | `selection-highlight.svg` | the selected face in accent stops with an ACCHI outline; a selected edge is ACC 2.0 |
| Preview | `dashed-preview.svg` | AMB 1.5 dashed `2 1.5` outline of the not-yet-created shape |
| Sketch profile | `sketch-profile.svg` | a closed ACC 2.0 profile with grips; the standard "a sketch" stand-in |

**The constraint glyph language** (family B). The constrained geometry is INK 2.0, with 4.0 grips at
the far ends of the segments; see `CN/coincident`, where two segment ends stop at one ringed point. The marker is ACC 1.5, drawn at the locus of the relation: on the corner for `∟`,
beside the pair for `//`, `=` across both equal segments. One marker per icon. No badge frame: the
viewport's framed badges are a viewport idiom.

## 7. No `<text>`, ever

Letters (`Text`, `Geometry Text`, Parameters `fx`, `G2`) are drawn as paths, either 1.5/2.0
monoline strokes or filled outlines. Use a geometric sans skeleton with cap height 10–12 u on the
glyph's own baseline. `<text>`, `<tspan>` and `font-*` attributes fail the lint.

## 8. File layout and naming

```
design/icons/
  SPEC.md                this file (the family table below is parsed by the build)
  _motifs/<name>.svg      canonical geometry
  <MAP>/<key>.svg         IC CN IN MD MS CR MO WF PT PL VW AX PN AS  — key exactly as in svg_icons.dart
  <MAP>/<key>.sm.svg      optional 18 px master (§2)
  single/<name>.svg       layerBigIcon finishIcon returnIcon newSketchIcon assemblyMenuIcon part3dMenuIcon
  DE/<id>.svg             deMove deSize deScale deRotate deDelete  (the Direct flyout ids)
  IN/params.svg           Parameters (fx)
```

SVG shape:

- One root `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none" stroke-linecap="round" stroke-linejoin="round">`.
- Children are `path`, `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon` and `g`.
- `transform` may only be a `matrix` or `translate`.
- No `id`, `style`, `class`, `<defs>`, gradients, masks, clip paths, filters, `<image>` or comments.

## 9. Handover checklist (tick all before you hand in)

1. [ ] The file sits at the path in §8, under the exact key from the family table, with `viewBox 0 0 28 28`.
2. [ ] Only §5 hexes. One accent family plus at most one secondary. No face stop used as a stroke.
3. [ ] Strokes are 1.5 / 2.0 / 1.25 only, with round caps and joins; dashes use butt caps.
4. [ ] Solids use the 2:1 dimetric projection, the face-stop order (top = middle) and the edge colours of §4.
5. [ ] Sketch geometry follows §4: ACC 2.0 created, INK 2.0 existing, INK grips.
6. [ ] No INK / LINE / DIM drawn over an accent face (§3; lint-enforced); check the light theme specifically.
7. [ ] Motifs are copied from `_motifs/`, not redrawn.
8. [ ] The glyph **fills** its keyline (major extent 21–23 u, lint minimum 19), stays inside 0.75–27.25,
   and is optically centred.
9. [ ] **Five-second test at 28 px, unlabelled, in the 1-column rail**, in both themes: someone who
   knows Inventor names the command. If not, simplify.
10. [ ] At 18 px nothing clogs; otherwise add a `.sm.svg`.
11. [ ] It does not duplicate another key's drawing, and it is distinct from its flyout siblings.
12. [ ] `python3 tools/icon_redesign/build.py …` passes: the lint is green and the atlas shows it as drawn.
13. [ ] It sits next to the reference icons in `docs/icon_redesign.html` at the same weight. Check the
    atlas and the rail in dark *and* light.

## 10. Build, preview and lint

```
dart run tools/ribbon_icon_mockup/dump.dart /tmp/icons.json     # current icons (plain Dart)
python3 tools/icon_redesign/build.py /tmp/icons.json            # -> docs/icon_redesign.html
```

The build parses this file's family table for the scope, loads `design/icons/**`, lints every new
SVG and the motifs, and **exits non-zero** on any of these:

- `<text>` or font attributes;
- a 3-digit or named colour, or any colour outside §5;
- a wrong `viewBox`;
- banned elements or attributes;
- more chromatic families than allowed;
- a face stop used as a stroke;
- a stroke under 1.25;
- a `fill-opacity` outside .25–.35;
- a mapped glyph colour under 3:1 on the Carbon Pro Neutral rail in either theme, under the shipping
  `_map` **and** the §12 integration;
- a dark-on-light glyph (INK, LINE or DIM) drawn over an accent face;
- a glyph whose major extent is under 19 u, or that crosses 0.75 / 27.25;
- a file that is not in the table;
- two keys with identical drawings.

## 11. Family table

Every in-scope key, with what it must depict. ★ marks a reference icon that is already drawn.
An **alias** row (`= KEY`) is the flyout's default entry for the same command: its file must be a
byte-identical copy of the target (the build checks it and exempts the pair from the duplicate lint).
Draw the target; copy it last. `fam` is the designer family:

- **A** sketch Create
- **B** sketch Constrain / Modify / Insert / 2D pattern / sketch singles
- **C** part Create / Modify / Direct
- **D** work features / 3D pattern / view / measure
- **E** assembly

Counts: A 35 · B 41 · C 24 · D 44 · E 13 = **157** keys, of which 14 are drawn. D is the largest but
most mechanical family: plane, axis and point variants built from three motifs. E is the smallest but
has the most complex drawings per icon.

| fam | key | concept (what it must depict) |
|---|---|---|
| A | `IC.line34` | ★ diagonal ACC segment (4.5→23.5) with INK grips at both ends |
| A | `IC.circle34` | ★ ACC circle, INK centre grip, rim grip, DIM radius |
| A | `IC.arc34` | ACC three-point arc (about 200°), grips at both ends and on the arc |
| A | `IC.rect34` | ★ ACC rectangle, INK grips on two opposite corners |
| A | `IC.fillet18` | two INK lines meeting at a corner, the corner replaced by an ACC arc; tangent grips |
| A | `IC.text18` | outlined sans "A" in ACC with a short INK baseline |
| A | `IC.point18` | single INK grip with a small ACC `+` crosshair, no other geometry |
| A | `IC.fline` | = `IC.line34` |
| A | `IC.fmidline` | ACC segment with an INK grip at its MIDPOINT and end grips smaller/DIM — line drawn from its middle |
| A | `IC.fsplinecv` | ACC smooth S-spline with its control polygon in DIM dashed and INK control-vertex grips off the curve |
| A | `IC.fsplinei` | ACC S-spline passing THROUGH three INK grips on the curve |
| A | `IC.fsplinefree` | ACC freehand wavy stroke with cursor motif at its end |
| A | `IC.feqcurve` | ACC sine curve over short INK x/y axes; small outlined `f` optional |
| A | `IC.fbridge` | two INK curves with a gap, bridged by an ACC smooth curve tangent to both |
| A | `IC.fcirclecp` | = `IC.circle34` |
| A | `IC.fcircletan` | ACC circle tangent to three INK lines (triangle), tangent points marked |
| A | `IC.fellipse` | ACC ellipse with DIM major/minor axis lines and centre grip |
| A | `IC.farc3` | = `IC.arc34` |
| A | `IC.farctan` | INK line ending in a grip, ACC arc continuing tangentially from it |
| A | `IC.farccp` | ACC arc with centre grip and DIM radius lines to both ends |
| A | `IC.frect2p` | = `IC.rect34` |
| A | `IC.frect3p` | rotated (≈20°) ACC rectangle with grips on three corners |
| A | `IC.frect2pc` | ACC rectangle with centre grip and one corner grip, DIM diagonal |
| A | `IC.frect3pc` | rotated ACC rectangle with centre grip + two edge-mid grips |
| A | `IC.fslotcc` | ACC straight slot (stadium), grips at the two arc centres, DIM centreline |
| A | `IC.fslotov` | ACC straight slot with grips at the two overall ends (tips) |
| A | `IC.fslotcp` | ACC straight slot with centre grip and one end-centre grip |
| A | `IC.fslot3a` | ACC curved (arc) slot, three grips along its arc centreline |
| A | `IC.fslotcpa` | ACC curved slot with the arc's centre grip and DIM radius |
| A | `IC.fpolygon` | ACC regular hexagon with centre grip and DIM circumscribed circle |
| A | `IC.ffillet` | = `IC.fillet18` |
| A | `IC.fchamfer` | two INK lines meeting at a corner, corner cut by a straight ACC bevel |
| A | `IC.ftext` | = `IC.text18` |
| A | `IC.fgtext` | outlined "A" in ACC sitting on an INK arc (text along geometry) |
| A | `IC.projgeo` | neutral dimetric block; one top-face edge projected down as an AMB line onto a flat sketch plane outline below, AMB dashed projectors |
| B | `IC.patrect` | 2D: one ACC square + three INK copies in a 2×2 grid, DIM direction arrows |
| B | `IC.patcirc` | 2D: one ACC dot/square + five INK copies on a DIM circle around an INK centre grip |
| B | `IC.patmir` | 2D: ACC half-shape and INK mirrored half about a DIM dash-dot mirror line |
| B | `CN.dim` | ★ AMB dimension with extension lines over an INK segment with grips |
| B | `CN.autodim` | INK L-profile with two AMB dimensions (one horizontal, one vertical) placed automatically: no grips, both dims identical weight |
| B | `CN.coincident` | ★ two INK segments (one horizontal, one vertical) whose ends stop at ONE ringed ACC point |
| B | `CN.collinear` | two INK segments on one straight line with a gap, ACC dashed line running through both |
| B | `CN.concentric` | two INK circles of different radius, ACC shared centre dot |
| B | `CN.lock` | INK point/segment with ACC padlock marker (fix) |
| B | `CN.parallel` | two INK lines at the same angle, ACC `//` marker between |
| B | `CN.perp` | two INK lines meeting at 90°, ACC `∟` square marker in the corner |
| B | `CN.horiz` | INK horizontal line with grips, ACC `—` marker (short bar) above, levelling feel |
| B | `CN.vert` | INK vertical line with grips, ACC `|` marker beside |
| B | `CN.tangent` | INK circle touched by an INK line, ACC dot at the tangency + short ACC tick |
| B | `CN.symmetric` | two INK grips mirrored about a DIM dash-dot line, ACC `‹ ›` markers |
| B | `CN.equal` | two INK segments of equal length, ACC `=` marker on each |
| B | `CN.smooth` | INK line flowing into an INK curve, ACC curvature comb (5 short spines) along the curve at the joint |
| B | `CN.conset` | constraint marker sheet (∟ //) with a small INK gear — settings |
| B | `CN.showcons` | INK geometry with two ACC framed constraint badges and an INK eye |
| B | `MD.trim` | INK line crossing a curve; the cut-off piece in ERR dashed, scissors-free (no clip-art) |
| B | `MD.split` | INK line with an ACC break point (two grips with a 2u gap) splitting it |
| B | `MD.moffset` | INK profile and its ACC parallel offset copy, short DIM offset arrow |
| B | `MD.extend` | INK line extended in ACC up to an INK boundary line, arrow at the end |
| B | `MD.move` | ACC shape with INK four-way move arrow |
| B | `MD.copy` | INK shape and ACC duplicate offset diagonally, small arrow |
| B | `MD.mrotate` | ACC shape rotated about an INK centre grip with a 2D rotation arrow |
| B | `MD.mscale` | small INK square and larger ACC square sharing a corner grip, diagonal arrow |
| B | `MD.stretch` | INK profile with the right half stretched in ACC, DIM dashed selection window, arrow |
| B | `IN.image` | sheet with mountain + sun (rx 1.5 frame, INK), ACC sky/mountain fill tint |
| B | `IN.points` | grid of INK points with a sheet/table corner (points from spreadsheet), ACC first point |
| B | `IN.acad` | AutoCAD import: INK sheet (rx 1.5, folded corner) with an ACC 2D drawing (rect + circle) inside and an INK import arrow entering it; no lettering |
| B | `IN.constr` | construction toggle: DIM dashed line between INK grips with ACC highlight |
| B | `IN.params` | NEW: outlined italic `fx` in ACC on INK rounded field (parameters) |
| B | `IN.gear` | spur gear outline (12 teeth) in ACC with INK hub circle |
| B | `IN.driven` | AMB dimension in parentheses style (driven/reference): AMB dim + DIM dashed extension |
| B | `IN.sphere` | Centerline: INK line drawn as dash-dot ACC centreline between grips |
| B | `IN.center` | Center Point toggle: INK `+` centre mark in ACC ring |
| B | `IN.showfmt` | INK lines in three formats (solid, dashed, dash-dot) with an eye |
| B | `single.layerBigIcon` | two stacked INK sheets (rx 1.5, dimetric-flat), top one ACC with OK `+` badge — new layer |
| B | `single.finishIcon` | OK check mark (2.0) over a faint INK sketch profile — finish sketch |
| B | `single.newSketchIcon` | neutral dimetric plane/face with an ACC 2D profile drawn on it, OK `+` badge |
| C | `CR.extrude` | ★ dashed INK source profile on the base plane, accent prism lifted off it, INK up arrow beside (off the solid) |
| C | `CR.revolve` | ★ three-quarter revolved accent body with its flat cut face, AMB axis, one INK arc arrow sweeping into the missing quadrant |
| C | `CR.sweep` | ACC solid tube following an INK curved path (S), profile circle at start |
| C | `CR.loft` | ACC solid blending a square profile (bottom) into a round profile (top) |
| C | `CR.coil` | ACC helix spring (3 turns) around a DIM axis |
| C | `CR.emboss` | neutral slab with raised ACC letter-like profile on its top face |
| C | `CR.derive` | neutral cube with an ACC copy linked by a curved arrow (derived part) |
| C | `CR.decal` | neutral block with an ACC image sheet (mountain glyph) applied to its face |
| C | `MO.fillet` | ★ large neutral block; the front-top edge is a big two-tone accent round, its radius visible in the silhouette |
| C | `MO.hole` | ★ neutral slab, accent bore |
| C | `MO.chamfer` | neutral block, one edge bevelled flat, bevel face accent |
| C | `MO.shell` | neutral block opened at top, accent thin inner walls visible |
| C | `MO.draft` | neutral block whose side faces taper (wider at bottom), tapered face accent, AMB pull direction |
| C | `MO.thread` | neutral cylinder with ACC helical thread lines on its side |
| C | `MO.combine` | two overlapping neutral solids, the union outline / shared region accent |
| C | `MO.thicken` | neutral thin sheet and an ACC thickened slab with offset arrow |
| C | `MO.split` | neutral block cut by an AMB plane, one half accent and slightly separated |
| C | `MO.direct` | neutral block with one ACC face and a 3D move arrow (direct edit) |
| C | `MO.deleteface` | neutral block with one face shown as ERR dashed outline (removed) |
| C | `DE.deMove` | NEW: ACC face pushed along an INK arrow (move face) |
| C | `DE.deSize` | NEW: ACC cylinder face with radial INK double arrow (resize) |
| C | `DE.deScale` | NEW: small neutral cube inside larger ACC cube outline, diagonal arrow |
| C | `DE.deRotate` | NEW: ACC face tilted about an AMB axis with rotation arrow |
| C | `DE.deDelete` | NEW: neutral block, ERR dashed face, ERR `−` badge |
| D | `WF.plane` | ★ amber work plane (right-face parallelogram, tint + outline) |
| D | `WF.axis` | ★ amber dash-dot axis through a neutral cylinder |
| D | `WF.point` | amber work point (dot + ring) on a neutral block vertex |
| D | `WF.ucs` | three-axis triad: amber origin + INK arrows with small amber plane corners |
| D | `PL.plane` | = `WF.plane` |
| D | `PL.offset` | neutral slab, amber plane floating parallel above its top face, DIM offset arrow |
| D | `PL.parallelpt` | amber plane parallel to a neutral face passing through an ACC point |
| D | `PL.midplane2` | two neutral parallel faces, amber plane centred between |
| D | `PL.midtorus` | neutral torus (ring) cut through its middle by an amber plane |
| D | `PL.angleedge` | neutral block edge (ACC) as hinge, amber plane rotated about it, angle arc |
| D | `PL.threepts` | three ACC points with an amber plane through them |
| D | `PL.twoedges` | two ACC coplanar edges of a neutral block, amber plane through both |
| D | `PL.tansurfedge` | neutral cylinder, amber plane tangent along its side, ACC edge |
| D | `PL.tansurfpt` | neutral sphere/cylinder, amber plane touching at an ACC point |
| D | `PL.tanparallel` | neutral cylinder, amber plane tangent and parallel to a DIM reference plane |
| D | `PL.normalaxis` | ACC axis line piercing an amber plane at 90°, point marked |
| D | `PL.normalcurve` | ACC curve with an amber plane normal to it at an INK point |
| D | `AX.axis` | = `WF.axis` |
| D | `AX.onedge` | amber axis lying along an ACC edge of a neutral block |
| D | `AX.axparallel` | amber axis parallel to an INK line through an ACC point |
| D | `AX.twopts` | amber axis through two ACC points |
| D | `AX.intersect` | two neutral/AMB-tint planes crossing, amber axis along their intersection |
| D | `AX.normalplane` | neutral face with an amber axis standing normal through an ACC point |
| D | `AX.centeredge` | neutral cylinder top edge ACC, amber axis through its centre |
| D | `AX.revolved` | neutral revolved solid (vase) with amber axis |
| D | `PN.point` | = `WF.point` |
| D | `PN.grounded` | amber point with an INK ground symbol (three bars) beneath |
| D | `PN.vertex` | neutral block with the amber point on a vertex |
| D | `PN.int3planes` | three amber-tint planes meeting, amber point at the corner |
| D | `PN.int2lines` | two INK lines crossing, amber point at the crossing |
| D | `PN.intplaneline` | amber-tint plane pierced by an INK line, amber point at the pierce |
| D | `PN.centerloop` | ACC closed edge loop (ellipse on a face), amber point at its centre |
| D | `PN.centertorus` | neutral torus, amber point at its centre |
| D | `PN.centersphere` | neutral sphere (two-tone), amber point at its centre |
| D | `PT.rect` | 3D: one ACC cube + neutral copies in a 2×2 grid on the ground, INK direction arrows |
| D | `PT.circ` | 3D: one ACC cube + neutral copies around an amber axis |
| D | `PT.sketch` | 3D: ACC cube + neutral copies placed on INK sketch points |
| D | `PT.mirror` | 3D: ACC solid and neutral mirrored copy about an amber plane |
| D | `VW.shaded` | neutral shaded sphere/cube with INK edges (shaded + edges) |
| D | `VW.rendered` | glossy ACC-lit sphere with highlight and soft floor shadow (DIM) |
| D | `VW.section` | neutral block cut by an amber plane, cut face hatched (INK hatch) |
| D | `VW.engine` | render engine: ray (INK arrow) bouncing off a neutral sphere, ACC light dot |
| D | `VW.floor` | neutral cube standing on an INK floor grid (dimetric) with DIM shadow |
| D | `MS.measure` | ★ ruler with amber dimension above |
| E | `AS.place` | ★ accent component cube with INK down arrow |
| E | `AS.create` | dashed ACC outline cube (new, in-place) with OK `+` badge |
| E | `AS.freemove` | neutral component cube with INK four-way move arrows (3D) |
| E | `AS.freerotate` | neutral component cube with 3D rotation arrow around it |
| E | `AS.joint` | two parts (ACC + neutral) with a joint origin marker (circle + axes) between |
| E | `AS.constrain` | ★ mate: accent part above a neutral base, two ACC arrows pressing it onto the mating plane |
| E | `AS.show` | two parts with an ACC constraint glyph and INK eye |
| E | `AS.showsick` | two parts with an ERR constraint glyph (broken) and INK eye |
| E | `AS.hideall` | two parts with a DIM constraint glyph and INK eye-slash |
| E | `AS.copy` | ACC component cube with neutral duplicate offset, copy arrow |
| E | `single.assemblyMenuIcon` | three stacked component cubes (one ACC) — assembly document |
| E | `single.part3dMenuIcon` | single neutral part (L-block) with ACC top face — part document |
| E | `single.returnIcon` | INK return arrow (U-turn up-left) out of an ACC component cube — leave in-place edit |

## 12. Integration (ships with the icon set; `frontend/lib/icon_theme.dart`)

Two changes to `_map`. Both are previewed on `docs/icon_redesign.html` (the **_map** control:
Shipping / (a) / (a)+(b)). Both are mirrored in `build.py map_icon_proposed`, so the lint checks the
3:1 rule under them too. The Python and JS ports were verified equal on every palette token.

**(a) Hue-less greys.** A pure-grey `T.ink` (Carbon Pro Neutral Light: #1E1E1E) has a meaningless HSL
hue of 0°, so every neutral stop picks up red at saturation .04 (FA → #9D9595, a visible pink).

```dart
  if (hsl.saturation < 0.12) {
    final l = light ? 1.0 - hsl.lightness : hsl.lightness;
    final ink = HSLColor.fromColor(T.ink);
    // SPEC §12 (a): a grey ink has no hue to lend; tinting with it turns the ramp pink.
    final s = ink.saturation < 0.05 ? 0.0 : 0.04;
    return _hexOf(ink.withSaturation(s).withLightness(l.clamp(0.12, 0.92)).toColor());
  }
```

**(b) A luminance-capped light band.** On light themes chromatic lightness is squeezed into .16–.46, so
accent solids read as heavy navy (#174980–#1C589A).

- A plain gentler band cannot work. The build swept .20–.32 low ends against .46–.60 high ends, and
  every band lighter than today drops a glyph colour (bright greens and light blues first) under 3:1,
  because `_map` constrains HSL lightness, not luminance.
- What works is to treat the two roles differently:
  - **glyph colours** are mapped into [.22, cap], where *cap* is the lightest L that still gives
    3.2:1 against `T.bg` for that colour's own hue and saturation, so contrast is guaranteed;
  - **the three accent face stops**, which are volume (always outlined, exempt from 3:1), get their
    own lighter band.

```dart
// SPEC §5 accent face stops: fill-only volume, always outlined by a glyph stroke.
const Set<int> _faceStops = {0x8BBBEE, 0x559CE7, 0x207CDF};
final Map<int, double> _capCache = {};   // clear it where _cache is cleared (palette / accent change)

double _lightCap(double hue, double sat) =>
    _capCache.putIfAbsent((hue * 1000).round() * 1000 + (sat * 1000).round(), () {
      final bg = T.bg.computeLuminance();
      double lo = 0, hi = 1;
      for (var i = 0; i < 24; i++) {
        final m = (lo + hi) / 2;
        final y = HSLColor.fromAHSL(1, hue, sat, m).toColor().computeLuminance();
        if ((bg + 0.05) / (y + 0.05) >= 3.2) { lo = m; } else { hi = m; }
      }
      return lo;
    });

  // in _map, chromatic branch:
  final sat = (t.saturation * 0.85 + hsl.saturation * 0.15).clamp(0.25, 0.95);
  final double l;
  if (!light) {
    l = hsl.lightness.clamp(0.32, 0.82);
  } else if (_faceStops.contains(v)) {
    l = 0.36 + hsl.lightness * 0.34;                        // SPEC §12 (b): faces, airy
  } else {
    final cap = _lightCap(t.hue, sat);
    l = 0.22 + hsl.lightness * (cap - 0.22);                  // SPEC §12 (b): glyphs, >= 3.2:1 on T.bg
  }
  return _hexOf(t.withLightness(l).withSaturation(sat).toColor());
```

Effect on Carbon Pro Neutral Light. The colours below are `_map` outputs from `build.py`. Glyph
contrast is on the rail.

| Token | Today | With (a)+(b) |
|---|---|---|
| FA / FB / FC (neutral faces) | #9D9595 / #AEA8A8 / #C0BABA (pink) | #999999 / #ABABAB / #BDBDBD |
| AFA / AFB / AFC (accent faces) | #1E5EA5 / #1B5595 / #184C86 (navy) | #5798E0 / #468EDD / #3483DA |
| ACC | #1C5A9E, 5.7:1 | #2169B9, 4.5:1 |
| ACCHI | #2067B5, 4.6:1 | #2577D1, 3.7:1 |
| AMB | #A05504, 4.5:1 | #9C5204, 4.7:1 |
| OK | #048A46, 3.6:1 | #047C3F, 4.3:1 |
| ERR | #8A2C2C, 6.9:1 | #B23838, 4.8:1 |

Dark themes are unchanged. Hard-coded face hexes in `_faceStops` tie `_map` to this SPEC's palette.
That is intentional: the palette is closed, and the lint forbids any other face colour.
