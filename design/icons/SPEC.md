# Ribbon icon system — SPEC v2 "Modern Crisp"

The binding design system for every icon that the ribbons, overflow menus and flyouts draw. It is
direction **2M·B, "Rendered Steel — Modern · B crisp"**, chosen by the user in the style study
(`docs/icon_style_study.html`, `tools/icon_redesign/study/steel-modern/`). Five designers redraw **all**
ribbon icons from this file, in parallel, as code. Everything here is a rule, not a suggestion. Where a rule
says **must**, the lint in `tools/icon_redesign/build.py` checks it and the build fails.

v2 **supersedes v1** (flat INK/ACC/AMB face stops, outlines, amber work features). The v1 scope, grid,
projection and file layout carry over, as amended below. Every v1 colour and material rule is void, and so
are the v1 motif files.

- **Draw through the library.** Every icon comes from a generator script,
  `tools/icon_redesign/families/<LETTER>.py`, which imports `tools/icon_redesign/lib/crisp.py` (§13).
  Icons are reproducible code. Never hand-edit an SVG.
- **Preview and lint:** `python3 tools/icon_redesign/build.py ICONS_JSON` writes `docs/icon_redesign.html`
  (§10).
- **References, drawn to final quality, set the bar:** `IC/line34 IC/circle34 IC/rect34 CN/coincident
  CN/dim CR/extrude CR/revolve MO/fillet MO/hole WF/plane WF/axis AS/place AS/constrain MS/measure`.
  Their generator is `tools/icon_redesign/families/ref.py`. **Read it before you draw anything.**

---

## 1. Direction and principles

The user liked direction 2, Rendered Steel (real volume, a lit steel material, one engineering-blue
feature: a premium CAD product), but found it "a bit old". v2 keeps the volume and drops every 2008 tell:

| v1 / old steel did | Why it dates | v2 does |
|---|---|---|
| multi-stop chrome bands (3–4 stops, a hot highlight) | the Aqua / Vista look | **exactly 2 stops per face**, 2–4 % apart: matte |
| contact shadows under solids | skeuomorphic "object on a desk" | **no shadow at all**: the shade face is the shadow |
| a dark contour plus a gradient | the face values already make the edge, so it looks stamped | **no outline**: faces separated by value alone |
| specular strokes on front edges | the Windows-7 bevel, a white seam at 28 | **one 0.6 u hairline**, on the lit top edge only |
| small, sharp, fussy solids (16–18 u) | busy and timid at once | **solids fill the cell** (up to 23 × 20 u), 0.6 u corners |
| rendered "pearl" sketch points | a glossy 3D detail on 2D line art | **flat dots**; sketch tools are line art |
| saturated blue material, amber, green, red | a rail of clip art | **one calm accent material**; no amber, green or red |

Benchmarks: Autodesk Fusion 2025 (UI refresh), Blender 4.x, Onshape, Shapr3D. Feature icons are a
small product render: steel bodies, one blue feature, slim flat ink tools.

**Principles** (each is enforced below):

1. **Grey is the world; one material is the verb.** Context is steel. The accent material sits only on
   the feature the tool creates or acts on.
2. **Two registers, on purpose.** 3D tools are rendered (steel and accent material). 2D sketch tools are
   line art (ink and flat dots). The sketch rail sits a step lighter than the part rail by design.
3. **Material is material, ink is ink.** Gradients are material: they keep their light direction in both
   themes. Flat paint is ink: it inverts with the theme. **Ink never crosses material** (§6.1).
4. **One projection, one light, one corner, one arrowhead** for the whole set.
5. **Fill the cell.** 28 is the design size, and a glyph spans its keyline.
6. **No text**: letters are paths.

**Metaphors CAD users already know** (keep them; a new drawing that breaks one needs a reason):

| Command | Known metaphor | v2 |
|---|---|---|
| Extrude | prism risen from a profile, up arrow | accent box, INK up arrow beside it on the ground |
| Revolve | ¾ solid of revolution, arc arrow round the axis | accent ¾ cylinder, INK rotation arrow concentric with the rim (§6.4) |
| Fillet / Chamfer | block with one rounded / bevelled edge | steel block, accent band / bevel face |
| Hole | bore in a block | steel slab, accent bore |
| Plane / Axis / Point | parallelogram / line / dot | **accent material**: pane, rod, disc (§5.3) |
| Line / Circle / Rect | geometry plus points | INK 1.5 line art, INK start dot, **ACC dot on the point being placed** |
| Constraints | `∟ // = ⊙ —` on the geometry | INK geometry plus one ACC marker |
| Dimension / Measure | extension lines and arrows / a rule | **ACC** dimension (flat accent ink), SEC extension lines; a steel rule |
| Pattern | repeated instances | first instance accent, copies steel |
| Place / Constrain | component cube, arrow; two parts mated | accent part, steel base, INK arrows |

## 2. Grid, keylines and sizes

**Master:** one SVG per key, `viewBox="0 0 28 28"`, with no `width` or `height`. The rail draws 28 pt glyphs
in 36 pt cells, unlabelled, in one column: that is the design size.

| Placement | Size | Scale |
|---|---|---|
| Rail / compact band (default) | **28** | 1.000 |
| Big button, named mode | 34 | 1.214 |
| Flyout row | 26 | 0.929 |
| Small row, overflow menu | 18 | 0.643 (`.sm.svg` rule, §2.4) |

### 2.1 Live area and bounds

The live area is 2–26 (24 u). Strokes and rounding may reach 1.25 u into the padding. **Nothing may cross
0.75 or 27.25** (lint, strokes included).

### 2.2 Fill the cell

The **major extent** of a glyph, strokes included, must be at least **19 u** (lint). Aim for 21–24 u.

- **Solids:** 18.5–23 u wide and 19–21 u tall. For example, the extrude box is 18.5 × 20.3 and the hole slab
  is 23 × 16.75.
- **2D primitives:** they reach the square keyline. The line runs 6→22 plus its dots, the circle has r 10.5,
  and the rectangle is 5–23 × 7–21 plus its dots.
- **Two solids together** (Place, Constrain, patterns): the group fills the keyline, not each solid.

### 2.3 Centring and pixel grid

- **Optical centring:** the visual mass sits on (14, 14). A glyph with an arrow beside or above it puts
  the arrow inside the cell, not the solid off-centre. Shift the drawing itself, never with a transform.
- **Axis-aligned edges** sit on whole or half units. Lattice vertices are wherever 2:1 puts them
  (quarter units are fine).

### 2.4 18 px masters (`<key>.sm.svg`)

There is no small master by default. Every master is checked at 18 px. A `.sm.svg` (same folder, same
`viewBox`, same palette, gradient ids with `-sm`) is **required** when the 28 master has any of these:

- a meaningful part narrower than **1.5 u**, or a clear gap under **1.25 u**;
- graduations, ticks or dashes shorter than **2 u**;
- more than **two solids plus ink**, or more than six separately readable parts.

The small master:

- **drops the hairline** (lint). The library does it: on an `Icon(ref, sm=True)` every `ic.hairline()` is a
  no-op, so a family draws its `.sm` with the same function and needs no `hair=` flag;
- drops secondary detail (SEC lines, ticks, inner marks), or makes it fewer and bolder;
- may step ink up one width (1.25 → 1.5, 1.5 → 2.0);
- keeps the silhouette, the material and the accent.

Draw it with the same function and a flag: `run(DRAW, small={'MS.measure': lambda ic: measure(ic,
marks=4, sm=True)})`. Of the references, only `MS.measure` needs one.

**Stale small masters.** A `.sm.svg` whose 28 master is v2 must itself be v2 (written by the same
generator) or removed. A v1 `.sm.svg` listed in `SUPERSEDED.txt` is overwritten by its family generator
(`IC/fillet18`, `ffillet`, `fchamfer`, `fsplinecv`, `fcircletan`, `projgeo` were); the entry then stays as a
harmless superseded record.

## 3. Projection

**One axonometric for every solid: 2:1 dimetric.** The receding axes run 2 across, 1 down. The vertical
stays vertical. All three axes have the same scale.

- **The `Iso(ox, oy, k=1)` projection** (lib): world x → screen (+1, +½)·k (right face), world y → (−1, +½)·k
  (left face), world z → (0, −1)·k. `(ox, oy)` is the screen point of the world origin.
- **Viewer and visible faces:** the viewer looks along −(1, 1, 1). Visible faces are +z (top), +y (left,
  **lit**) and +x (right, **shade**).
- **Viewpoint:** always front-above. Never show a bottom face or a back view. Hidden edges are never drawn.
- **Circles:** a horizontal circle projects to an ellipse with **ry = rx / 2**, with its major axis
  horizontal. Cylinders are vertical (`cylinder()`).
- **Planes** may use the stylised sheet (`WF.plane`: horizontal top and bottom edges, slanted sides).
  Use it when the plane is the hero. Use `iso_plane()` on the lattice when the plane sits in a scene with
  solids.
- **Sketch tools** (`IC`, `CN`, `MD`, `IN`, 2D patterns) are drawn flat, in front view, with no projection.
  A sketch *on a solid* (`newSketch`, `projgeo`, `emboss`, `decal`) puts material marks on the face (§6.1),
  not ink.

## 4. Material

Matte, with **exactly two stops per face** (lint) and **one key light, upper left**. Faces are told apart by
value alone. No outlines, no shadows, no radial gradients, no third stop.

| Material | Hue / S | Use |
|---|---|---|
| **steel** | 212° / .06: a cool grey, under the .12 neutral line | every body that is context: the part, the base, the reference |
| **acc** | 211° / .54: a calm engineering blue (it moves to the user's accent) | **only** the feature the tool creates or acts on (§5.2) |

**Stops.** Each entry is (lightness start → end) and the two source hexes. The light-theme column is
the v2 `_map` result (§12). The shipping `_map` inverts every stop, which is why `data-lit="2"` is
required.

| Material | Kind | L | Source stops | Light theme (v2) |
|---|---|---|---|---|
| steel | top | .93 → .89 | `#ECEDEE` → `#E1E3E5` | #BCBFC3 → #B3B8BD |
| steel | lit | .63 → .60 | `#9BA0A6` → `#93999F` | #838991 → #7D858C |
| steel | shade | .37 → .35 | `#595E64` → `#54595F` | #565B61 → #53585E |
| steel | curve | .67 → .39 | `#A6ABB0` → `#5D6369` | #8B9198 → #595F65 |
| steel | band | .93 → .39 | `#ECEDEE` → `#5D6369` | #BCBFC3 → #595F65 |
| steel | deep | .29 → .63 | `#464A4E` → `#9BA0A6` | #494D51 → #838991 |
| steel | pane | .85 → .53 | `#D6D9DB` → `#80878E` | #ACB2B6 → #71787F |
| acc | top | .88 → .84 | `#D0E0F1` → `#C0D5EC` | #90B5DE → #85ADDA |
| acc | lit | .65 → .62 | `#76A4D6` → `#6A9CD2` | #518BCB → #4885C8 |
| acc | shade | .45 → .42 | `#3571B1` → `#3169A5` | #3167A3 → #2E629B |
| acc | curve | .69 → .47 | `#85AFDB` → `#3776B9` | #5B92CF → #326BA9 |
| acc | band | .88 → .47 | `#D0E0F1` → `#3776B9` | #90B5DE → #326BA9 |
| acc | deep | .36 → .65 | `#2A5A8D` → `#76A4D6` | #29578A → #518BCB |
| acc | pane | .80 → .55 | `#B0CBE8` → `#4E8ACA` | #79A6D8 → #3978BE |

**Kinds and directions:**

- **top, lit, shade:** the three planar faces. Directions are in each face's own bounding box: top (0,0)→(1,1),
  lit and shade (0,0)→(.4,1).
- **curve:** a cylinder or cone side, lit at the left, (lit₀ + .04 → shade₀ + .02), horizontal in user space
  across the visible side.
- **band:** a fillet or round, (top₀ → curve₁), from its upper (lit) edge toward the shade face.
- **deep:** the far wall of a bore or pocket, (shade₁ − .06 → lit₀), vertical, dark under the back rim.
- **pane:** a plane or sheet, (top₀ − .08 → lit₁ − .07), diagonal across its box. **Glass** (a plane in front
  of or through a solid) adds `stop-opacity` .85 → .70. That is the only `stop-opacity` besides the
  hairline's.

**Hairline.** One **0.6 u** stroke on the lit edges of the top face (the edges it shares with the visible
sides), white `#FFFFFF` at stop-opacity .80 → .15, left to right. A cylinder carries it on the front-left
rim, a plane on its far edge. It is a gradient, so it is material. It is the only gradient stroke (lint).
Small masters drop it.

**Silhouette rounding.** Every silhouette corner of a solid gets a **0.6 u** quadratic fillet (planes:
1.0 u). **Per-corner plane rounding:** a pane drawn in pieces (the quadrants of `PN.int3planes`, a pane
split where a solid passes through it) rounds only its **outer** corners, 1.0 u; the corners where the
pieces meet stay sharp, so the assembled pane reads as one sheet. An internal face edge that runs into a rounded corner ends at the fillet's midpoint (de
Casteljau, t = .5), so faces meet on the curve, with no notch and no overlap. Internal edges stay sharp.
`Solid` does this. Never round by hand.

**Paint order** (lib does it): the silhouette in the shade stop (it closes antialiasing seams), then the side
faces, then the top faces, then the features (bore, band), then the hairline, then ink.

## 5. Colour roles

### 5.1 Ink (flat paint)

Flat `fill` and `stroke` colours are **ink**: they go through `_map` and invert on a light theme. Only these
three exist for general use (plus `ERR`, the status exception of §5.4, and `CON`, the constraint red of §5.5):

| Token | Source | Use | Dark rail | Light rail (v2 `_map`) |
|---|---|---|---|---|
| `INK` | `#D6D6D6` | arrows, sketch geometry, existing points, badges | #D6D6D6, 11.5:1 | #292929, 11.8:1 |
| `SEC` | `#8C8C8C` | extension lines, radius, construction, preview, reference, context curves | #8C8C8C, 5.0:1 | #737373, 3.8:1 |
| `ACC` | `#6AA9ED` | flat accent: the point being placed, the dimension, the target ring (the constraint marker is `CON`, §5.5) | #6AA9ED, 6.8:1 | #2169B8, 4.5:1 |
| `CON` | `#D96A6E` | constraint red: the relation marker of the geometric-constraint icons only (§5.5) | #E95D5A, 4.9:1 | #AB3A3A, 5.0:1 |

The rail is `bg` #1D1E1F (dark) / #E7E7E8 (light). Material never appears as flat paint (lint).

### 5.2 The one-accent rule

Each icon has **one accent**, on one thing:

- **3D:** the accent *material* sits on what the command **produces**: the new body, the fillet band, the
  bore, the new plane. When nothing new is produced, it sits on the **selection it acts on**: the face that
  moves, the part that is placed. Everything else is steel. If two things want it, the result wins.
- **2D:** the accent is *flat ACC* on **one** element, and the geometry is INK 1.5. The element is one of:
  - the point being placed (Create tools: ACC dot r 2.4);
  - the constraint marker (Constrain), which is drawn in the constraint red `CON`, not ACC (§5.5);
  - the dimension (Dimension);
  - the piece the tool adds to existing geometry (fillet arc, chamfer bevel, extension, bridge,
    tangent arc). That piece is ACC 1.5, and no accent dot is added.
- An icon never mixes the accent material with a second accent element, with one exception: an ACC
  dimension or ACC point on the ground next to steel solids (`MS.measure`), where steel is the context.
- **Result is accent (PL / AX / PN, every work-feature method).** The new plane, axis or point is the accent
  material (pane, rod, `mat_dot`). Every reference it is built from is **steel when it is an object** (a
  body, a pane, an axis rod, a point on material) and **ink when it lies on the ground** (an INK line or
  curve, an INK dot). A selected edge that is only a reference does not get an accent band: the pane or rod
  leaving the body along that edge shows it (`PL.twoedges`, `PL.angleedge`).
- **Steel bead.** A reference point that sits on material (a pane, a rod, a face) is a flush **steel**
  disc, r 2.1 (`bead()`). The accent `mat_dot` (r 2.4) is kept for the point a tool creates; a point on the
  ground is a flat dot.
- **Assembly copies** (`AS.copy`): the duplicate (the result) is the accent component, the original steel.

### 5.3 What replaced amber

In v1, amber marked work features, dimensions, measurement, reference geometry and previews. **v2 has no
amber.** Every amber role moves to an existing role:

| v1 amber role | v2 | Library call |
|---|---|---|
| **Work plane** (the result) | an **accent-material pane**, rounded 1.0, hairline on the far edge; **glass** where it passes in front of or through a solid | `plane()`, `iso_plane()` |
| **Work axis** (the result) | an **accent-material rod**, 1.9–2.2 u thick, lit on its left, round end. Being material, it may stand out of or pass through a solid: a flat end and a dark socket where it leaves a face (`WF.axis`) | `rod()` |
| **Work point** (the result) | on the ground: the ACC dot r 2.4 in the ACC ring r 4.6. On a solid: a flush accent-material disc r 2.4 | `work_point()`, `mat_dot()` |
| Work feature that is **context**, not the result (the mirror plane of `PT.mirror`, the cutting plane of `MO.split`, the reference plane of `PL.offset`) | the same object in **steel** (`mat='steel'`, glass where it crosses a solid) | same calls, `mat='steel'` |
| **Dimension** (sketch or 3D) | **ACC** dimension line and heads (flat accent), SEC 1.0 extension lines | `dim()` |
| **Measure** | a steel object or rule; the measured value is the ACC dimension | `dim()` |
| **Reference / projected geometry** | SEC 1.5, solid | `line(col=SEC)` |
| **Preview / construction / hidden** | SEC 1.25, dashed `2.5 2`, butt caps | `construct()` |
| 2D centre line, mirror line | SEC 1.25 dash-dot `5 1.75 1.25 1.75`, butt (it is drafting, not a work feature) | `ic.stroke(..., SEC, 1.25, DASH_AXIS)` |

The work-feature rule in one line: **a work feature is an object, so it is material: accent when it is the
result, steel when it is context.** That is also how the viewport now draws them (a blue pane, not an
orange one).

### 5.4 Status: when red or green is allowed

- **Green: never.** "New / add / create / finish" is not a status. Use an **INK `+` badge** (§6.6) or the
  accent on the new thing. `single.finishIcon` is just an **ACC check mark**, 2.0, centred.
- **Amber: never** (§5.3).
- **Red: exactly one case.** An icon whose subject is a **fault state** (a sick or failed relation that the
  user must look at) may draw **one** flat `ERR #E96C67` mark: the broken constraint glyph, at most 8 × 8 u,
  as flat ink, never as material. Today that is **`AS.showsick` only**. The build's `STATUS_RED` set holds
  the allowed keys, and anything else fails. Adding a key needs a SPEC change. On the rail ERR maps to
  #EC6764 (5.3:1) dark and #B23838 (4.8:1) light.
- **Delete, remove, trim, delete face and split are not faults.** Removal is drawn by absence: the removed
  piece is an SEC dashed ghost (`construct()`), plus an INK `−` badge when the ghost alone is ambiguous.
  Never red. A removed **face** may instead be drawn as the opening it leaves (`MO.deleteface`: the inside
  of the box shows through it) plus the `−` badge.
- **Ghosts on material edges.** A ghost is ink, so it lives on the ground (§6.1): it runs where nothing of
  the solid lies behind it (`DE.deDelete`: the removed slab at the back), or exactly **along** a solid's
  silhouette edge, never across a face. The lint's ink-over-material margin (half the stroke + 0.35 u from
  a face edge) is what lets a dashed line sit on a silhouette.

### 5.5 Constraint red

Inventor draws its constraint glyphs red, and so does the v2 set: a constraint reads as a constraint before
it reads as its shape.

- **`CON #D96A6E`** (hue 358, S .59, L .63): a quieter, slightly rose red, a step away from the error red
  `ERR #E96C67` (hue 2, S .75), so a constraint never reads as a fault. Flat ink, 1.5 like every marker (the
  coincident ring stays 1.0, the curvature comb 1.0 / 1.25), never material.
- **Scope (lint: the build's `CONSTRAINT_RED` set):** the geometric-constraint icons `CN.coincident`,
  `collinear`, `concentric`, `lock`, `parallel`, `perp`, `horiz`, `vert`, `tangent`, `symmetric`, `equal`,
  `smooth`, plus the constraint marks of `CN.showcons` and `CN.conset` (their eye and gear stay INK). Each of
  these must use `CON`, and may use no other red (no `ERR`). `CON` anywhere else fails.
- **What turns red:** the relation marker only. The geometry it acts on stays INK (and SEC). Where the icon
  **is** the marker, the whole glyph is `CON`: `CN.equal` (the `=` sign) and `CN.lock` (the padlock).
- **Not constraints:** `CN.dim` and `CN.autodim` are dimensions; they stay ACC (§5.3).
- **On the rail** `CON` falls in `_map`'s red bucket, so it maps onto `T.err`'s hue: #E95D5A (4.9:1) dark and
  #AB3A3A (5.0:1, v2 `_map`; #852D2D, 7.1:1, shipping `_map`) light. Because that is the error colour too,
  §12 proposes a separate `T.conMark` bucket for hues 345–360 so the two can be told apart and tuned apart.

### 5.6 Contrast

After the v2 `_map`, the **silhouette** of every icon must reach **3:1 on the rail in both Carbon Pro
Neutral themes** (lint). The silhouette is the strongest opaque paint: a flat ink, or a material stop at
opacity ≥ .9. Every flat ink in §5.1 reaches 3:1 on its own.

Light top faces (steel top .75 L on paper) do not need 3:1: they are bounded by their darker side faces.
A glass pane alone fails, so it needs an opaque partner.

## 6. Ink: strokes, arrows, sketch, marks

### 6.1 Ink lives on the ground

Flat ink **never crosses a material face** (lint: any ink sample point inside a gradient face, more than
half a stroke plus 0.35 u from its edge). The reason: ink inverts with the theme and material does not.
On one of the two themes an INK arrow on a light face (or a dark one) disappears. The consequences:

- Arrows, dimensions, dots and rings sit beside, above or below solids, ≥ 1 u clear (see `CR/extrude`,
  `AS/place`, `AS/constrain`).
- A mark **on** a solid is **material**:
  - a selected edge or face is an accent band or face;
  - a point is `mat_dot()`;
  - an axis is `rod()`;
  - graduations are shade-material marks (`MS/measure`).
- Material over material is fine (a rod through a cylinder, a glass plane through a block).

### 6.2 Stroke widths

Allowed widths (lint): **1.0, 1.25, 1.5, 2.0**, plus 0.5 (arrowhead softening only) and 0.6 (hairline
only). All caps and joins are round. Dashes use butt caps.

| Width | Use |
|---|---|
| **1.5** | sketch geometry (INK), reference geometry (SEC), the added sketch piece (ACC) and constraint markers (CON) |
| **1.25** | arrows (straight and arc), dimension line, construction, preview, 2D centre lines, radius (SEC) |
| **1.0** | extension lines (SEC), the coincident / target ring (ACC), curvature-comb spines (ACC; 1.0–1.25, the comb's envelope 1.25: `CN.smooth`) |
| **2.0** | symbols only: the `+` / `−` badge, the finish check mark, the `CN.equal` sign |

### 6.3 The arrow (one arrowhead for the whole set)

- **Shaft:** 1.25 u ink, round cap. It stops 3.0 u before the tip.
- **Head:** a slim filled triangle, **3.4 u long, 4.0 u wide** (half-width 2.0), plus a **0.5 u stroke of the
  same ink** with round joins, which softens the corners. `head()` / `arrow()` draw it. No other head exists.
- **Colour:** INK for motion and direction. ACC only when the arrow *is* the measured value (a dimension,
  an angle).
- **Double-headed** (dimensions): `arrow(..., both=True)`. The tips sit 0.7 u inside the extension lines.

### 6.4 Rotation and arc arrows

- **2D rotation** (sketch rotate, circular pattern): `arc_arrow()`, a circular or elliptical arc.
- **3D rotation** (Revolve, Rotate, Free Rotate, Direct Rotate, angle planes, revolve-style constraints):
  `arc_arrow_dimetric()`. Its rule:
  - The arc is an **ellipse concentric with the rim of the body it turns**: the same centre and the same
    2:1 ratio (ry = rx / 2), with a radius **2.5–3 u larger** than the rim. It follows the perspective; a
    flat circle on a dimetric body is wrong.
  - **Height and side:** the visible arc never crosses material (§6.1).
    - **At rim height** (centre = the top face's centre), it runs **round the back**, above the top face,
      and comes forward at a side. This is the standard.
    - **At base height** it runs round the front, under the body. Pass `body=(cx, half_width)` and the
      part of the arc that goes behind the body is hidden, ≥ 1 u clear of its silhouette. It reads as going
      round the body, not pasted on top of it.
  - **The sweep ends in the feature.** For Revolve the head ends in the mouth of the missing quarter.
    For Rotate it ends beside the turned part.
  - **Head on the path:** the head's axis is the chord of the last 3.4 u of the arc. It is tangent to the
    ellipse and its base sits on the path. The arc uses the same 1.25 u weight and the same head as every
    arrow.
  - **No axis tick** on Revolve (at 28 it reads as a burr). Draw an axis only when the tool is about the
    axis, as a `rod()`.
- **Rotation about a horizontal edge** (an angle plane hinged on an edge): `arc_arrow_iso()`, the same arc
  in the plane of rotation (e.g. y-z about an x edge), projected, placed beyond the end of the body so it
  stays on the ground.
- **2D rotation about a point** (`MD.mrotate`): the shape where it was (SEC dashed), the shape turned (INK),
  the ACC centre dot and `arc_arrow()` round the centre outside both.

### 6.5 Sketch tools: line art

- **Geometry:** INK **1.5**.
- **Construction and radius:** SEC **1.25**. Construction is dashed `2.5 2`.
- **Dots** are flat discs with no gradient:
  - an existing / start point: **INK r 1.9**;
  - the point being placed: **ACC r 2.4** (one per icon).
- **Coincident / target ring:** ACC 1.0 at **r 4.6** round the ACC dot (`ring()`); CON in `CN.coincident`.
- **Lines stop short of a ring:** a segment that meets a ringed point ends 6 u from its centre
  (`CN/coincident`).
- **Constraint markers** are CON (constraint red, §5.5) 1.5 at the locus of the relation: `∟` in the corner,
  `//` beside the pair, `› ‹` towards the symmetry axis. One marker per icon, and no badge frame. Equal and
  Lock are the marker alone: a bold CON `=` (2.0) and a CON padlock.
- No gradients and no `data-lit` in a pure sketch icon.

### 6.6 Badges, symbols, text

- **`+` / `−` badge:** INK 2.0, arms 3.5, centred at (22.5, 22.5) (`badge()`). The host drawing keeps
  1 u clear of a 9 × 9 corner there. There is no ring and no disc, and it is never green or red.
- **Eye (show / hide):** `eye(ic, c, w)`, one geometry everywhere. The lens is two quadratic arcs meeting in
  points, **w** wide and **0.42 w** tall, INK 1.5. The pupil is a filled INK disc, r **0.13 w** (minimum 1.5;
  ×0.8 on an `.sm`, so a ring of clear ground stays round it). Hide adds an INK 1.5 slash from
  (−0.4 w, +0.3 w) to (+0.4 w, −0.3 w) about the centre. Two sizes: `EYE_BADGE` (w 12 at (20.25, 21.5)), the
  eye as a modifier of a sketch tool (`CN.showcons`, `IN.showfmt`); `EYE_HERO` (w 16 at (14, 21.25)), the eye
  as the subject (`AS.show`, `AS.showsick`, `AS.hideall`; w 21 alone on their `.sm`).
- **Check mark:** ACC 2.0, alone and centred on (14, 14) (`single.finishIcon`): no frame or profile behind it,
  so it never reads as a check box, and never green.
- **Gear (settings):** `gear()`, trapezoid teeth, INK or ACC 1.5.

## 7. No `<text>`, ever

Letters (`Text`, `Geometry Text`, Parameters `fx`, `G2`) are paths: INK 1.5 monoline strokes, a geometric
sans skeleton, cap height 10–14 u. When the letter is the subject (`IC.text18`, `IC.fgtext`) it is drawn at
13.5–14 u and about as wide, so it reads at 18 pt. `<text>`, `<tspan>` and `font-*` fail the lint.

## 8. Files, generators and naming

```
design/icons/
  SPEC.md                 this file (the §11 table is parsed by the build)
  SUPERSEDED.txt          v1 files by sha256: ignored by the build while unchanged (never edit)
  <MAP>/<key>.svg         IC CN IN MD MS CR MO WF PT PL VW AX PN AS DE  (key exactly as in svg_icons.dart)
  <MAP>/<key>.sm.svg      optional 18 px master (§2.4)
  single/<name>.svg       layerBigIcon finishIcon returnIcon newSketchIcon assemblyMenuIcon part3dMenuIcon
tools/icon_redesign/
  lib/crisp.py            the drawing library (§13): palette, material, solids, ink, writer
  families/ref.py         the 14 references
  families/<A-E>.py       one generator per family (§11)
```

**Superseded files.** The v1 SVGs (family A, the partial B–E, the old references, `_motifs/`) stay on
disk. They are not deleted, and they are listed in `SUPERSEDED.txt` with their hash. The build ignores
them, so the atlas counts only v2 drawings. When your generator writes a key, the hash no longer matches,
and the file is linted and counted as drawn. **Overwrite, never delete.** `_motifs/` is v1 only: in v2,
motifs are library calls.

**SVG shape** (the writer emits exactly this; lint checks it):

- **Root:** `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none"
  stroke-linecap="round" stroke-linejoin="round">`, plus ` data-lit="2"` **if and only if** the SVG has a
  gradient.
- **Elements:** `defs`, `linearGradient`, `stop`, `path`, `circle`, `ellipse`, `rect`, `line`,
  `polyline`, `polygon`, `g`.
- **Banned:** `<text>`, filters, masks, clip paths, radial gradients, `<use>`, `style`, `class`, `opacity`,
  `fill-opacity`, `stroke-opacity`, comments, and an `id` on anything other than a gradient.
- **Gradient ids:** `g-<MAP>-<key>[-sm]-<part>`, for example `g-CR-extrude-at`. They are unique across
  every file (lint), and every gradient is used.

**Aliases** (§11 `= KEY`) are the same drawing under their own ids: the generator calls the target's
function with the alias's `Icon`. The lint compares the two with the ids stripped.

## 9. Handover checklist (tick all before you hand in)

1. [ ] Every key of your family is drawn by `tools/icon_redesign/families/<LETTER>.py` through
   `lib/crisp.py`. You have no hand-edited SVG, no copied path data from v1 and no private primitives
   that duplicate a library call. Extend the library (with the lead) instead.
2. [ ] Files sit at `design/icons/<MAP>/<key>.svg` under the exact §11 key. Aliases are generated, not
   copied.
3. [ ] **One accent** (§5.2), on the result, or else on what the tool acts on. Context is steel.
4. [ ] **No amber, green or red** (§5.3, §5.4). Work features are accent material when they are the result
   and steel when they are context. Dimensions are ACC. Previews and references are SEC.
5. [ ] Solids: 2:1 dimetric, two stops per face, 0.6 rounding, hairline on the lit top edges, no outline,
   no shadow. Use only `box / prism / wedge / cylinder / plane / rod / bore`, or `Solid` plus `face` for
   custom shapes.
6. [ ] Sketch tools are line art: INK 1.5 geometry, INK dot r 1.9 for existing points, ACC dot r 2.4 for
   the point placed, SEC 1.25 construction. No gradient.
7. [ ] Arrows use the one head; 3D rotation uses `arc_arrow_dimetric()` (§6.4).
8. [ ] **No ink over material** (lint). Marks on solids are material.
9. [ ] The glyph fills the cell (major extent 21–24 u, lint minimum 19), stays inside 0.75–27.25, and is
   optically centred.
10. [ ] **Five-second test** at 28 pt, unlabelled, in the one-column rail, dark **and** light: someone who
    knows Inventor or Fusion names the command. Then 18 pt in the overflow menu. If anything clogs, write
    a `.sm` (§2.4).
11. [ ] It is distinct from its flyout siblings and from every other key (lint: no identical drawings).
12. [ ] `python3 tools/icon_redesign/families/<LETTER>.py && python3 tools/icon_redesign/build.py …`
    passes. The atlas shows your keys as **drawn** with silhouette ≥ 3:1 in both themes.
13. [ ] It sits next to the references in `docs/icon_redesign.html` at the same weight, size and value
    range. Check the references strip, the rail mock and the atlas, in dark *and* light.

## 10. Build, preview and lint

```
dart run tools/ribbon_icon_mockup/dump.dart /tmp/icons.json    # the current icons (plain Dart)
python3 tools/icon_redesign/families/ref.py                     # the references (and your <LETTER>.py)
python3 tools/icon_redesign/build.py /tmp/icons.json            # lint + docs/icon_redesign.html
python3 tools/icon_redesign/build.py /tmp/icons.json --lint-only
```

The page shows the references strip (rail size, 18 pt, ×4, both themes), the app mock (rail at real
size), every ribbon, menu and flyout, the atlas (old | v2 per key with silhouette contrast) and the lint.
Its **`_map`** control defaults to **v2** (§12). *Shipping* shows why v2 needs `data-lit="2"`.

The build **exits non-zero** on any of these:

- **Elements and attributes:** `<text>` or `font-*`; filters, masks, clip paths, radial gradients, `<use>`,
  `style` or `class`; opacity attributes; comments; banned elements or attributes; an id on a
  non-gradient.
- **Shape:** a wrong `viewBox` or root attributes; width or height on the root.
- **Colour:**
  - a 3-digit, named or `rgb()` colour;
  - a flat colour other than INK, SEC or ACC;
  - a stop that is not a §4 material stop;
  - material used as flat paint;
  - **amber or green anywhere, or red outside `STATUS_RED`**.
- **Gradients:**
  - a gradient with other than 2 stops;
  - `stop-opacity` other than on the hairline or a glass pane (.85 / .70);
  - a gradient stroke other than the 0.6 hairline;
  - a hairline in a `.sm.svg`.
- **`data-lit`:** missing `data-lit="2"` on an SVG with gradients, or `data-lit` on one without.
- **Gradient ids:** an id without the `g-<MAP>-<key>[-sm]-` prefix, an id **colliding with any other file**,
  a dangling `url()`, an unused gradient.
- **Strokes:** an ink stroke width other than 1 / 1.25 / 1.5 / 2 (0.5 only on an arrowhead); a dash
  without butt caps.
- **Ink over material.**
- **Extent:** a major extent under 19 u, or anything past 0.75 / 27.25.
- **Contrast:** a silhouette under 3:1 on the rail, in either Carbon Pro Neutral theme, after the v2 `_map`.
- **Scope:**
  - a file not in the §11 table;
  - a `.sm.svg` without a v2 master;
  - two keys with identical drawings;
  - an alias that differs from its target;
  - this SPEC not listing a palette hex or a material stop.

## 11. Family table

Every in-scope key and what it must depict, in v2 terms. ★ marks a reference, already drawn. An **alias**
row (`= KEY`) is the flyout's default entry for the same command: generate it with the target's function.
`fam` is the designer family, and each family owns one generator:

| fam | scope | generator |
|---|---|---|
| **A** | sketch Create | `tools/icon_redesign/families/A.py` |
| **B** | sketch Constrain / Modify / Insert / 2D pattern / sketch singles | `tools/icon_redesign/families/B.py` |
| **C** | part Create / Modify / Direct | `tools/icon_redesign/families/C.py` |
| **D** | work features, PL / AX / PN, 3D pattern, view, measure | `tools/icon_redesign/families/D.py` |
| **E** | assembly | `tools/icon_redesign/families/E.py` |

The references are generated by `ref.py`, and no family regenerates them. A family may import its
reference functions (`from ref import revolve`) to build siblings.

Counts: A 35 · B 41 · C 24 · D 44 · E 13 = **157** keys, 14 of them references.

| fam | key | concept (what it must depict) |
|---|---|---|
| A | `IC.line34` | ★ INK 1.5 diagonal segment 6→22, INK start dot, ACC dot on the end being placed |
| A | `IC.circle34` | ★ INK circle r 10.5, SEC radius, ACC centre dot |
| A | `IC.arc34` | INK three-point arc (about 200°), INK dots at both ends, ACC dot on the third (placed) point on the arc |
| A | `IC.rect34` | ★ INK rectangle, INK dot on the first corner, ACC dot on the opposite corner being placed |
| A | `IC.fillet18` | two INK lines meeting at a corner, the corner replaced by an ACC 1.5 arc (the added piece), INK dots at the tangent points |
| A | `IC.text18` | outlined sans "A" (INK 1.5 monoline, cap height 14, about as wide) with an ACC dot at its insertion point on a short SEC baseline |
| A | `IC.point18` | a single ACC dot r 2.4 in the ACC ring, short SEC crosshair arms outside the ring |
| A | `IC.fline` | = `IC.line34` |
| A | `IC.fmidline` | INK segment, ACC dot at its MIDPOINT (placed first), INK dots at both ends |
| A | `IC.fsplinecv` | INK smooth S-spline; its control polygon SEC dashed with INK dots on the control vertices off the curve; ACC dot on the last vertex |
| A | `IC.fsplinei` | INK S-spline passing THROUGH three INK dots on the curve, ACC dot on the last |
| A | `IC.fsplinefree` | INK freehand stroke: one clean cursive loop (a single smooth path), ending in an ACC dot (the pen) |
| A | `IC.feqcurve` | INK sine curve (one period) plotted in the corner of SEC x / y axes (an L, clear of the curve); ACC dot on its last crest |
| A | `IC.fbridge` | two INK curves with a gap, bridged by an ACC 1.5 smooth curve tangent to both |
| A | `IC.fcirclecp` | = `IC.circle34` |
| A | `IC.fcircletan` | INK circle inscribed in a closed INK triangle (apex up, no overshoot at the corners), ACC dot at the last tangent point (on the base) |
| A | `IC.fellipse` | INK ellipse with SEC major/minor axis lines, ACC centre dot |
| A | `IC.farc3` | = `IC.arc34` |
| A | `IC.farctan` | INK line ending in an INK dot, ACC 1.5 arc continuing tangentially from it |
| A | `IC.farccp` | INK arc with its ACC centre dot and SEC radius lines to both ends |
| A | `IC.frect2p` | = `IC.rect34` |
| A | `IC.frect3p` | rotated (≈20°) INK rectangle, INK dots on two corners, ACC dot on the third |
| A | `IC.frect2pc` | INK rectangle, ACC centre dot, INK corner dot, SEC diagonal |
| A | `IC.frect3pc` | rotated INK rectangle, ACC centre dot, INK dots on two edge midpoints |
| A | `IC.fslotcc` | INK straight slot (stadium), INK dot at one arc centre, ACC dot at the other, SEC centreline |
| A | `IC.fslotov` | INK straight slot, INK dot at one tip, ACC dot at the other tip |
| A | `IC.fslotcp` | INK straight slot, ACC centre dot, INK end-centre dot |
| A | `IC.fslot3a` | INK curved (arc) slot, three dots along its SEC arc centreline (last ACC) |
| A | `IC.fslotcpa` | INK curved slot, ACC dot at the arc centre, SEC radius |
| A | `IC.fpolygon` | INK regular hexagon, ACC centre dot, SEC circumscribed circle (dashed) |
| A | `IC.ffillet` | = `IC.fillet18` |
| A | `IC.fchamfer` | two INK lines meeting at a corner, the corner cut by a straight ACC 1.5 bevel |
| A | `IC.ftext` | = `IC.text18` |
| A | `IC.fgtext` | INK monoline "A" (cap 13.5) standing on the crown of an INK arc (text along geometry), ACC dot at the start of the arc |
| A | `IC.projgeo` | steel block; its front-left top edge the shared accent `edge_band`; below it, on the ground, its projection as an ACC 1.5 line, long SEC dashed projectors continuing the block's vertical edges (ink kept off the block) |
| B | `IC.patrect` | 2D: one square with ACC corner dot + three INK copies in a 2×2 grid, SEC direction arrows |
| B | `IC.patcirc` | 2D: one ACC-dotted instance + five INK copies on an SEC circle round an INK centre dot |
| B | `IC.patmir` | 2D: INK half-shape and its INK mirror about an SEC dash-dot mirror line, ACC dot on the mirrored point |
| B | `CN.dim` | ★ ACC double-arrow dimension, SEC extension lines, over an INK segment with INK end dots |
| B | `CN.autodim` | INK L-profile with two ACC dimensions (one horizontal, one vertical) placed automatically; no dots |
| B | `CN.coincident` | ★ two INK segments whose ends stop 6 u short of ONE CON dot in the CON ring |
| B | `CN.collinear` | two INK segments with INK end dots on one straight line, a gap between them bridged by a CON 1.5 dashed line |
| B | `CN.concentric` | two INK circles of different radius, one CON centre dot |
| B | `CN.lock` | just a CON padlock (1.5): rx 1.5 body 7–21 × 12.25–23.75, round shackle, keyhole dot r 1.6; centred, no segment |
| B | `CN.parallel` | two INK lines at the same angle, CON `//` marker between them |
| B | `CN.perp` | two INK lines meeting at 90°, CON `∟` marker in the corner |
| B | `CN.horiz` | make horizontal: the line as it was (SEC dashed, slanted up from the left INK point), the line as constrained (INK horizontal, INK end dots), and the CON `arc_arrow` swinging one onto the other (the marker) |
| B | `CN.vert` | make vertical: the line as it was (SEC dashed, leaning right from the bottom INK point), the line as constrained (INK vertical, INK end dots), and the CON `arc_arrow` swinging one onto the other (the marker) |
| B | `CN.tangent` | INK circle touched by an INK line, CON dot at the tangency |
| B | `CN.symmetric` | two INK points (r 1.9) mirrored about an SEC dash-dot symmetry axis, CON `› ‹` chevrons between them pointing in towards the axis |
| B | `CN.equal` | just a bold CON equals sign: two parallel horizontal bars (2.0), 5→23 at y 10.5 and 17.5, centred; no segments |
| B | `CN.smooth` | INK line flowing into an INK curve (INK joint dot), CON curvature comb along the curve that grows from zero at the joint: 4 spines (1.0) and its envelope (1.25) |
| B | `CN.conset` | marker sheet (INK rx 1.5 frame, INK corner) carrying CON `∟` and `//` marks, with an INK gear (settings) |
| B | `CN.showcons` | one INK corner carrying its CON `∟` marker, and the INK eye (`EYE_BADGE`) |
| B | `MD.trim` | INK line crossing an INK curve; the cut-off piece an SEC dashed ghost, an ACC dot at the cut |
| B | `MD.split` | INK arc split where a short SEC 1.5 reference line crosses it: both pieces stay INK, parted by a gap either side of the ACC split dot (no ghost: that is Trim) |
| B | `MD.moffset` | SEC original profile and its INK parallel offset copy, ACC dot on the copy, short SEC offset arrow |
| B | `MD.extend` | INK line extended in ACC 1.5 up to an INK boundary line |
| B | `MD.move` | INK shape with an ACC dot at its base point and an INK four-way move arrow |
| B | `MD.copy` | SEC original shape and INK duplicate offset diagonally, ACC dot on the copy's base point, small INK arrow |
| B | `MD.mrotate` | rotate about a point: an INK rectangle turned about the ACC centre dot from where it was (SEC dashed), the INK `arc_arrow` round the centre outside both |
| B | `MD.mscale` | small SEC square and larger INK square sharing an ACC corner dot, INK diagonal arrow |
| B | `MD.stretch` | INK profile with the right half stretched, SEC dashed selection window, INK arrow, ACC dot on the moved corner |
| B | `IN.image` | INK sheet (rx 1.5 frame) with mountain + sun, the mountain an ACC 1.5 line |
| B | `IN.points` | points imported from a table: the sheet's INK corner (an L) and a 2 × 2 grid of INK dots, the first ACC |
| B | `IN.acad` | AutoCAD import: INK sheet (rx 1.5, folded corner) with an INK 2D drawing (rect + circle) inside, an ACC dot on it, INK import arrow entering; no lettering |
| B | `IN.constr` | construction toggle: SEC dashed line between INK dots with an ACC dot |
| B | `IN.params` | NEW: INK monoline italic `fx` on an SEC rounded field (parameters), ACC dot |
| B | `IN.gear` | spur gear outline (12 teeth) INK 1.5 with an ACC hub circle |
| B | `IN.driven` | driven / reference dimension: ACC dimension in parentheses (INK 1.25 arcs), SEC dashed extension |
| B | `IN.sphere` | Centerline format: the sketch line itself in INK 1.5 centre-line dash-dot (the sibling of `IN.constr`'s SEC dashed line), INK start dot, ACC end dot |
| B | `IN.center` | Center Point toggle: INK `+` centre mark in the ACC ring |
| B | `IN.showfmt` | INK lines in three formats (solid, dashed, dash-dot) with the INK eye (`EYE_BADGE`) |
| B | `single.layerBigIcon` | two stacked steel sheets (dimetric panes), the top one accent pane, INK `+` badge — new layer |
| B | `single.finishIcon` | just the ACC check mark (2.0), centred: short arm (4.5, 14.5)→(10.75, 20.75), long arm →(23.5, 6.75) — finish sketch (never green, no frame) |
| B | `single.newSketchIcon` | steel pane (a face) with an accent-material profile ring on it, INK `+` badge — new sketch |
| C | `CR.extrude` | ★ accent box, INK up arrow beside it on the ground |
| C | `CR.revolve` | ★ accent ¾ cylinder with its two cut faces, INK `arc_arrow_dimetric` concentric with the rim, round the back into the missing quarter |
| C | `CR.sweep` | accent round bar swept along a long S path (two bends: an S pipe, not a hook), its profile cap at the front end; the rest of the path an SEC 1.5 line on the ground ahead of it |
| C | `CR.loft` | accent solid blending a square base (bottom) into a round top (cylinder top) |
| C | `CR.coil` | accent helical spring (3 turns, a band of curve material) around an SEC axis line above and below |
| C | `CR.emboss` | steel slab with a raised accent letter-like profile (prism) on its top face |
| C | `CR.derive` | steel cube with an accent copy beside it, linked by an INK curved arrow on the ground |
| C | `CR.decal` | steel block with an accent pane (mountain cut-out) applied to its lit face |
| C | `MO.fillet` | ★ large steel block; the front-top edge is a big accent band round, its radius visible in the silhouette |
| C | `MO.hole` | ★ steel slab, accent bore |
| C | `MO.chamfer` | steel block, one edge bevelled flat, the bevel face accent |
| C | `MO.shell` | steel block opened at the top, accent thin inner walls (deep) visible |
| C | `MO.draft` | steel block whose side faces taper (wider at the bottom), the tapered face accent, INK pull arrow beside it |
| C | `MO.thread` | a hex-head bolt: steel hexagon head on a slim steel shank whose lower part carries accent thread crests, slanted (a helix) with saw-tooth teeth out of both silhouettes |
| C | `MO.combine` | two overlapping solids: the target body an accent box in front, the tool body an opaque steel cylinder behind it (the overlap read from the silhouettes on both themes) |
| C | `MO.thicken` | steel thin sheet and an accent thickened slab above it, INK offset arrow beside |
| C | `MO.split` | steel block cut by a steel glass plane, one half accent and slightly separated |
| C | `MO.direct` | steel block with one accent face and an INK 3D move arrow beside it |
| C | `MO.deleteface` | steel block with its right face deleted: through the opening the inside shows (dark back wall over a lit floor, an open box), INK `−` badge (never red) |
| C | `DE.deMove` | NEW: accent face pushed out of a steel block along an INK arrow beside it |
| C | `DE.deSize` | NEW: steel block with an accent cylindrical face (bore), INK radial double arrow on the ground |
| C | `DE.deScale` | NEW: small steel cube inside a larger accent glass cube (`glass_box`), INK diagonal arrow |
| C | `DE.deRotate` | NEW: the accent top slab of a steel block turned about the vertical axis, INK `arc_arrow_dimetric` concentric with it round the back |
| C | `DE.deDelete` | NEW: steel block, an SEC dashed ghost where the face was, INK `−` badge (never red) |
| D | `WF.plane` | ★ accent pane (the stylised sheet), hairline on the far edge |
| D | `WF.axis` | ★ steel cylinder, accent rod through its centre: out of the top face (socket) and out under the bottom rim |
| D | `WF.point` | steel block with an accent `mat_dot` on its top front vertex |
| D | `WF.ucs` | three INK axis arrows (dimetric x, y, z) from an accent `mat_dot` origin, small accent panes at the axis corners |
| D | `PL.plane` | = `WF.plane` |
| D | `PL.offset` | steel slab, accent pane floating parallel above its top face, INK offset arrow beside |
| D | `PL.parallelpt` | steel slab, accent pane floating parallel to its top face through a steel bead (the point) |
| D | `PL.midplane2` | two steel slabs face to face, an accent glass pane centred between them |
| D | `PL.midtorus` | steel torus (ring) cut through its middle by an accent glass pane |
| D | `PL.angleedge` | steel block, accent pane hinged on its top back edge and swung up out of the top face's plane, INK `arc_arrow_iso` in the plane of rotation beyond the block's end |
| D | `PL.threepts` | three steel beads (the points) on an accent pane through them |
| D | `PL.twoedges` | steel block; the accent plane through its top back-left and bottom front-right edges runs inside the solid, so only its two flaps show, each leaving the block exactly along its edge |
| D | `PL.tansurfedge` | steel cylinder, accent pane tangent along its side, accent band edge at the contact |
| D | `PL.tansurfpt` | steel sphere, accent glass pane touching it at a steel bead |
| D | `PL.tanparallel` | steel cylinder, accent pane tangent to it and parallel to a steel glass reference pane |
| D | `PL.normalaxis` | accent pane pierced at 90° by a steel rod (the reference axis), socket where it leaves the pane |
| D | `PL.normalcurve` | INK curve on the ground running through an accent pane that stands normal to it, a steel bead where it pierces the pane |
| D | `AX.axis` | = `WF.axis` |
| D | `AX.onedge` | accent rod lying along an edge of a steel block |
| D | `AX.axparallel` | accent rod through a steel bead (the point), parallel to an INK line on the ground below it |
| D | `AX.twopts` | accent rod through two steel beads (the points) |
| D | `AX.intersect` | two standing steel panes crossing (opaque, back wings then front wings), the accent rod along their common line |
| D | `AX.normalplane` | steel slab with an accent rod standing normal on it (socket at the foot) |
| D | `AX.centeredge` | steel slab with a circular edge (a steel bore in its top face), the accent rod through the circle's centre, out of the bore and out under the slab |
| D | `AX.revolved` | steel revolved solid (vase) with an accent rod as its axis |
| D | `PN.point` | = `WF.point` |
| D | `PN.grounded` | a grounded (fixed) point: an accent push pin (ball head, rod) stuck into a steel ground pane, socket at its point |
| D | `PN.vertex` | steel block with an accent `mat_dot` on a top vertex |
| D | `PN.int3planes` | three opaque steel panes (two standing, crossing; one lying) meeting in one point, drawn as quadrants back to front (outer corners rounded), accent `mat_dot` at the corner |
| D | `PN.int2lines` | two INK lines crossing, ACC work point at the crossing |
| D | `PN.intplaneline` | steel pane pierced by an INK line (kept 1.25 u off the pane), accent `mat_dot` at the pierce |
| D | `PN.centerloop` | steel slab with a circular loop (a steel bore in its top face), accent `mat_dot` at its centre |
| D | `PN.centertorus` | steel torus (larger, filling the cell), accent `mat_dot` at its centre |
| D | `PN.centersphere` | steel sphere (curve material, two stops), accent `mat_dot` at its centre |
| D | `PT.rect` | 3D: one accent cube + steel copies in a 2×2 grid, INK direction arrows on the ground |
| D | `PT.circ` | 3D: a circular pattern of bosses on a steel flange round its centre bore (the axis), the front boss accent, the copies steel |
| D | `PT.sketch` | 3D: cubes standing at irregular places (not a grid) on a steel sketch pane, the first accent, the copies steel |
| D | `PT.mirror` | 3D: accent solid and its steel mirrored copy about a steel glass pane |
| D | `VW.shaded` | Shaded (with edges): a steel cube in flat three-value shading with its edges drawn as material (a dark rim round the silhouette and dark strips on the three inner edges); no accent |
| D | `VW.rendered` | Realistic: an accent sphere lit from the upper left with a specular spot (steel top material, never white paint), on a glossy steel floor pane |
| D | `VW.section` | a cutaway: the front-right quarter of a steel block removed, the two cut faces accent |
| D | `VW.engine` | render engine: the camera aperture — an INK circle and six INK blades closing round a flat ACC hexagonal opening |
| D | `VW.floor` | steel cube standing on an SEC dimetric floor grid (on the ground beside, never under, the cube) |
| D | `MS.measure` | ★ steel rule on the lattice with shade-material graduations, ACC dimension above it, SEC vertical extension lines |
| E | `AS.place` | ★ accent component cube, INK down arrow above it |
| E | `AS.create` | accent glass component cube (`glass_box`: new, in place) against a steel component, INK `+` badge |
| E | `AS.freemove` | steel component cube with four INK arrows on the ground along the dimetric x and y axes, each starting 1.25 u clear of the silhouette, all four the same visible length |
| E | `AS.freerotate` | steel component cube with an INK `arc_arrow_dimetric` round it |
| E | `AS.joint` | a hinge: a steel leaf and an accent leaf (the component being jointed) open at 90° behind a knuckle stack (steel / accent / steel) on one pin, the accent pin rod standing out of the top knuckle |
| E | `AS.constrain` | ★ mate: accent part held above a steel base with a gap, two INK arrows beside it pressing down onto the base |
| E | `AS.show` | two steel parts with an ACC constraint marker (ring and dot) between their feet and the INK eye (`EYE_HERO`); 18 pt: the marker above a larger eye, no parts |
| E | `AS.showsick` | two steel parts with the ERR broken-constraint mark (the one status exception, §5.4) and the INK eye; 18 pt: the mark above a larger eye, no parts |
| E | `AS.hideall` | two steel parts with an SEC constraint marker and the INK eye-slash; 18 pt: the marker above a larger eye, no parts |
| E | `AS.copy` | steel original component behind, its accent duplicate (the result) offset in front, INK copy arrow |
| E | `single.assemblyMenuIcon` | three stacked component cubes (the component proportion, height 1.1 × side; the top one accent) — assembly document |
| E | `single.part3dMenuIcon` | a single steel part (L-block) with an accent top face — part document |
| E | `single.returnIcon` | INK return arrow (U-turn up-left) out of an accent component cube — leave in-place edit |

## 12. Integration (ships with the icon set; `frontend/lib/icon_theme.dart`)

v2 icons need three `_map` changes. All of them are in the preview's `_map` (default **v2**) and in
`build.py` (`map_flat`, `map_stop`, `map_svg`), so the lint checks contrast under them. The Python and JS
ports agree. Glyphs without `data-lit` (every v1 icon and every sketch tool) get (a) and (b) only.

**(a) Hue-less greys.** A pure-grey `T.ink` has a meaningless hue of 0°, so neutral ink picked up red at
saturation .04 (a pink cast on light themes).

**(b) A luminance-capped light band for chromatic ink.** Flat chromatic ink on a light theme maps into
[.22, cap], where *cap* is the lightest L of that hue and saturation that still gives 3.2:1 on `T.bg`.
(v1's face-stop branch is gone: v2 faces are gradients.)

**(c) `data-lit="2"`: gradient stops are material.**
- In an SVG whose root carries `data-lit="2"`, a `stop-color` is material, not ink.
- **Neutral stop** (S < .12): it keeps its own hue and saturation (the cool steel), and is **never
  inverted**. Lightness is `L′ = dark ? L : 0.10 + 0.70·L`, clamped .12–.92.
- **Chromatic stop:** the bucket's hue (the user's accent), saturation `min(own, target)`, lightness
  `L′ = dark ? L : 0.10 + 0.70·L`, clamped .22–.86.
- So the key light stays upper left on paper, and the material ramp is compressed just enough for the lit
  top face to separate from the paper without an outline.
- **Flat** `fill` and `stroke` colours in the same SVG are ink and go through `_map` unchanged.

```dart
final RegExp _hex = RegExp(r'(stop-color=")?#([0-9a-fA-F]{6})\b');

String themedIcon(String svg) {
  if (svg.contains('data-fixed')) return svg;
  if (!identical(_cachedFor, T.palette) || _cachedAccent != T.accentChoice.value) {
    _cachedFor = T.palette;
    _cachedAccent = T.accentChoice.value;
    _cache.clear();
    _capCache.clear();
  }
  return _cache.putIfAbsent(svg, () {
    // SPEC v2 §12 (c): in a data-lit="2" glyph a gradient stop is material, not ink.
    final lit = svg.contains('data-lit="2"');
    return svg.replaceAllMapped(_hex, (m) {
      final stop = m.group(1);
      final hex = m.group(2)!;
      return stop != null && lit ? '$stop${_mapStop(hex)}' : '${stop ?? ''}${_map(hex)}';
    });
  });
}

Color _bucket(double h) => h >= 175 && h < 265
    ? T.accent
    : h >= 75 && h < 175
        ? T.ok
        : h >= 18 && h < 75
            ? T.projRef
            : T.err;

// (c) material: never inverted; light themes compress the ramp to L' = .10 + .70 L
String _mapStop(String rrggbb) {
  final hsl = HSLColor.fromColor(Color(0xFF000000 | int.parse(rrggbb, radix: 16)));
  final l = T.isDark ? hsl.lightness : 0.10 + 0.70 * hsl.lightness;
  if (hsl.saturation < 0.12) {
    return _hexOf(hsl.withLightness(l.clamp(0.12, 0.92)).toColor());   // own hue + saturation
  }
  final t = HSLColor.fromColor(_bucket(hsl.hue));
  return _hexOf(t
      .withSaturation(math.min(hsl.saturation, t.saturation))
      .withLightness(l.clamp(0.22, 0.86))
      .toColor());
}

final Map<int, double> _capCache = {};
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

// ink (flat paint)
String _map(String rrggbb) {
  final hsl = HSLColor.fromColor(Color(0xFF000000 | int.parse(rrggbb, radix: 16)));
  final light = !T.isDark;
  if (hsl.saturation < 0.12) {
    final l = light ? 1.0 - hsl.lightness : hsl.lightness;
    final ink = HSLColor.fromColor(T.ink);
    final s = ink.saturation < 0.05 ? 0.0 : 0.04;                        // (a)
    return _hexOf(ink.withSaturation(s).withLightness(l.clamp(0.12, 0.92)).toColor());
  }
  final t = HSLColor.fromColor(_bucket(hsl.hue));
  final sat = (t.saturation * 0.85 + hsl.saturation * 0.15).clamp(0.25, 0.95);
  final l = light
      ? 0.22 + hsl.lightness * (_lightCap(t.hue, sat) - 0.22)              // (b)
      : hsl.lightness.clamp(0.32, 0.82);
  return _hexOf(t.withLightness(l).withSaturation(sat).toColor());
}
```

(`import 'dart:math' as math;`.) The first regex group is what makes (c) about 15 lines: it reads the
stop's context in the same single pass, and every other colour keeps today's path.

**Gradient-id rules** (why the lint is strict):

1. **Prefix `g-`.** `_hex` would rewrite a `url(#…)` whose id starts with six hex digits followed by a
   non-word character (`url(#decade-1)`). `g` is not a hex digit, so a `g-` id is never touched.
2. **`g-<MAP>-<key>[-sm]-<part>`, unique app-wide.** Each map and key owns its namespace. flutter_svg
   resolves ids per document, but the same SVG strings are inlined together in the HTML preview, in
   golden tests and in any future sprite. A collision there silently paints one icon with another's
   material. The build fails on any id seen in two files.
3. **No other ids.** Only gradients carry an id.

Effect on Carbon Pro Neutral, in the rail:

| | Dark | Light, shipping `_map` | Light, v2 |
|---|---|---|---|
| steel top / lit / shade | #ECEDEE / #9BA0A6 / #595E64 | #201D1D / #625B5B / #A49D9D (inverted: lit from below, black top) | #BCBFC3 / #838991 / #565B61 |
| accent top / lit / shade | #D0E0F1 / #76A4D6 / #3571B1 | #2569B4 / #1F5896 / #1A497D (navy) | #90B5DE / #518BCB / #3167A3 |
| INK / SEC / ACC | 11.5 / 5.0 / 6.8 : 1 | 11.9 / 4.0 / 5.7 : 1 | 11.8 / 3.8 / 4.5 : 1 |
| CON (constraint red) | #E95D5A, 4.9 : 1 | #852D2D, 7.1 : 1 | #AB3A3A, 5.0 : 1 |

**Proposed: a constraint bucket (`T.conMark`).** Today `CON #D96A6E` (hue 358) and `ERR #E96C67` (hue 2)
both land in the `else` bucket and take `T.err`'s hue and most of its saturation, so in the app a constraint
glyph is the error red (dark #E95D5A vs ERR #EC6764). Proposed, not yet made: a Palette field
`conMark` (Carbon Pro Neutral dark `0xFFDB6E73`, light `0xFFA8464A`; for other palettes, their `err` until
tuned) and, in `_map`, a band for hues 345–360 checked before the `else`:
`} else if (h >= 345) { target = T.conMark; // constraint glyphs (SPEC §5.5) }`. No shipping icon uses a hue in
265–360 today, so nothing else moves. Rail result: dark #DA696E (5.0 : 1), light #803235 shipping / #A44044 v2
(7.0 / 5.0 : 1). The build's `_bucket` (Python and JS) gets the same band when the token lands.

## 13. The drawing library: `tools/icon_redesign/lib/crisp.py`

Stdlib only. `from crisp import *` gives you everything below. The constants **are** the spec: the build
imports them (`PALETTE`, `STATUS`, `MATERIAL`, `STOPS`, `ALLOWED_WIDTHS`, `HAIR`, `GLASS`).

**Family generator skeleton:**

```python
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from crisp import *

def chamfer(ic):
    s = box(ic, Iso(14, 14.5), (0, 0, 0), (11, 11, 9), 'steel')
    ...

DRAW = {'MO.chamfer': chamfer, ...}
SMALL = {}                      # 'MAP.key': fn for an 18 px master
if __name__ == '__main__':
    run(DRAW, SMALL)            # --out DIR to write elsewhere, --only KEY,KEY to limit
```

**Constants:**

- **Ink:** `INK SEC ACC` (and `ERR`, status only; `CON`, the constraint set only). `dot(..., col=CON)` and
  `ring(..., col=CON)` paint a constraint marker.
- **Geometry:** `R` 0.6, `HAIR` 0.6, `HEAD_L` 3.4, `HEAD_W` 2.0, `SHAFT_BACK` 3.0, `DOT_INK` 1.9, `DOT_ACC` 2.4,
  `RING_R` 4.6, `RING_W` 1.0.
- **Dashes:** `DASH` `2.5 2`, `DASH_AXIS` `5 1.75 1.25 1.75`.
- **Material:** `MATERIAL`, `KINDS`, `mat_stops(mat, kind)`.

**The icon and writer:**

| Call | Does |
|---|---|
| `Icon(ref, sm=False)` | one SVG; ids `g-MAP-key[-sm]-<part>`; identical gradients are shared, others numbered |
| `ic.mat(mat, kind, x1.., user=False, opacity=None)` | a two-stop material paint (§4 directions by default) |
| `ic.fill(d, paint)`, `ic.stroke(d, col, w, dash=None)`, `ic.circle(c, r, fill, stroke, w)`, `ic.ellipse(c, rx, ry, paint)`, `ic.shape(d, col)` | raw drawing (widths are checked) |
| `ic.hairline(d, x1, x2)` | the 0.6 u lit-edge highlight (a no-op on an `.sm` icon, §2.4) |
| `ic.svg()`, `ic.write(root)` | the lint-clean SVG (`data-lit="2"` automatically when it has gradients) |
| `run(drawers, small=None)` | draw and write a family; `--out`, `--only` |

**Projection and solids:**

| Call | Does |
|---|---|
| `Iso(ox, oy, k=1)`, `iso.p(x, y, z)` | the 2:1 dimetric projection (§3) |
| `box(ic, iso, o, (a, b, h), mat, r=R, hair=True)` | a box; returns its `Solid` (screen points `B R F L Bb Rb Fb Lb` in `.P`) |
| `prism(ic, iso, base, z0, heights, mat)` | a vertical prism on a convex base polygon; per-vertex heights make sloped tops |
| `wedge(ic, iso, o, (a, b, h), mat, low='x')` | a box sloping to zero on one side (chamfer, draft) |
| `solid(ic, iso, W, faces, mat, kinds=None, sil_r=None)` | any convex polyhedron: hidden faces dropped, faces shaded by their normal (z top, y lit, x shade, override with `kinds`), hull rounded, hairline |
| `component(ic, top, half=9.25, mat='acc')` | the assembly component cube, top vertex at `top` |
| `cylinder(ic, c, rx, h, mat, ry=rx/2, cut=None)` | a vertical cylinder (c = top centre); `cut=(t1, t2)` removes a wedge (the Revolve body); returns `C Cb E(th, dy)` |
| `plane(ic, pts, mat='acc', glass=False)` | a pane (any 4 points), rounded 1.0, pane ramp, hairline on the far edge |
| `iso_plane(ic, iso, o, u, v, mat, glass)` | a pane on the lattice |
| `rod(ic, a, b, r=1.1, mat='acc', caps=(True, True), socket=False)` | the work axis rod (§5.3) |
| `bore(ic, c, rx, ry, mat='acc')` | a hole's cut-away face (deep ramp) |
| `pocket(ic, d, y0, y1, mat)` | any recessed face (deep ramp) |
| `face(ic, d, mat, kind, ...)` | fill a custom face; with `Solid(P, sil, radii)` (`.path(face)`, `.outline()`, `.end(v)`) for non-convex shapes such as `MO.fillet` |
| `mat_dot(ic, p, r=2.4, mat='acc')` | a point on a solid (the result); a reference point on material is `bead()` |

**Ink:**

| Call | Does |
|---|---|
| `arrow(ic, a, b, col=INK, both=False)` | straight arrow with the shared head |
| `head(tip, dir)`, `put_head(ic, tip, dir, col)` | the shared head alone |
| `arc_arrow(ic, c, rx, ry, a0, a1)` | a 2D rotation arrow, head tangent |
| `arc_arrow_dimetric(ic, c, rx, a0, a1, body=None, clear=1.0)` | **the 3D rotation arrow** (§6.4): concentric 2:1 ellipse, round the back at rim height, occluded where it passes behind `body` |
| `dim(ic, p, q, off, gap=4, over=2, dirn=None)` | an ACC dimension with SEC extension lines; `dirn` for extension along a world axis on a solid |
| `dot(ic, p, 'ink' or 'acc')`, `ring(ic, p)`, `work_point(ic, p)` | flat points and the target ring |
| `line(ic, pts, col=INK, w=1.5, close=False)` | sketch geometry |
| `construct(ic, d)` | SEC 1.25 dashed construction, preview, ghost |
| `work_axis(ic, a, b, col=SEC)` | a dash-dot centre line, ground only (2D drafting); the 3D work axis is `rod()` |
| `badge(ic, '+' or '-')` | the INK modifier badge |

**Shared motifs** (one drawing per idea, promoted from the family generators so every family draws the
idea the same way; a family must not keep a private copy):

| Call | Does |
|---|---|
| `eye(ic, c, w=12, slash=False, sm=False)`, `EYE_BADGE`, `EYE_HERO` | the show / hide eye (§6.6) |
| `gear(ic, c, r_tip, r_root, n, col)` | the settings / spur gear outline |
| `bead(ic, p, r=2.1)` | a reference point on material: a steel disc (§5.2) |
| `sphere(ic, c, r, mat)`, `torus(ic, c, rc, rt, mat, parts)` | curved bodies (curve / top / deep), hairline on the upper-left rim |
| `glass_box(ic, iso, o, size, mat='acc')`, `glass_cyl(ic, c, rx, h, mat='steel')` | see-through solids: every face in the glass pane ramp |
| `edge_band(ic, S, a, b, into_top, into_side, mat='acc', k=1.75)` | a selected edge of a box: an accent band straddling the edge a–b of Solid S |
| `tube(ic, iso, path, r, mat)` | a round bar swept along a horizontal 3D path, exact silhouette, profile cap |
| `helix_band(ic, c, rx, th0, th1, pitch, t, mat)` | a helical ribbon on a vertical cylinder (coil, thread) |
| `arc_arrow_iso(ic, iso, c, u, v, r, a0, a1)` | the rotation arrow in any world plane (an angle about a horizontal edge) |
| `clip_ink(pts, polys, margin=1.25)`, `ink_clear(p, polys)` | ground ink kept clear of the solids it runs behind (§6.1) |
| `clip_poly(subject, clipper)`, `round_pts(pts, r, which)` | faces seen through an opening (shell, delete face), clipped to a rounded silhouette |

To extend the library (a torus, a sphere, a helix band), add the primitive to `crisp.py`, keep it
stdlib-only, draw it through `Solid` / `ic.mat`, and tell the lead: every family must get it the same
way.
