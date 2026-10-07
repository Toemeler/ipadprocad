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

- **drops the hairline** (lint);
- drops secondary detail (SEC lines, ticks, inner marks), or makes it fewer and bolder;
- may step ink up one width (1.25 → 1.5, 1.5 → 2.0);
- keeps the silhouette, the material and the accent.

Draw it with the same function and a flag: `run(DRAW, small={'MS.measure': lambda ic: measure(ic,
marks=4, sm=True)})`. Of the references, only `MS.measure` needs one.

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
1.0 u). An internal face edge that runs into a rounded corner ends at the fillet's midpoint (de
Casteljau, t = .5), so faces meet on the curve, with no notch and no overlap. Internal edges stay sharp.
`Solid` does this. Never round by hand.

**Paint order** (lib does it): the silhouette in the shade stop (it closes antialiasing seams), then the side
faces, then the top faces, then the features (bore, band), then the hairline, then ink.

## 5. Colour roles

### 5.1 Ink (flat paint)

Flat `fill` and `stroke` colours are **ink**: they go through `_map` and invert on a light theme. Only these
three exist:

| Token | Source | Use | Dark rail | Light rail (v2 `_map`) |
|---|---|---|---|---|
| `INK` | `#D6D6D6` | arrows, sketch geometry, existing points, badges | #D6D6D6, 11.5:1 | #292929, 11.8:1 |
| `SEC` | `#8C8C8C` | extension lines, radius, construction, preview, reference, context curves | #8C8C8C, 5.0:1 | #737373, 3.8:1 |
| `ACC` | `#6AA9ED` | flat accent: the point being placed, the dimension, the constraint marker, the target ring | #6AA9ED, 6.8:1 | #2169B8, 4.5:1 |

The rail is `bg` #1D1E1F (dark) / #E7E7E8 (light). Material never appears as flat paint (lint).

### 5.2 The one-accent rule

Each icon has **one accent**, on one thing:

- **3D:** the accent *material* sits on what the command **produces**: the new body, the fillet band, the
  bore, the new plane. When nothing new is produced, it sits on the **selection it acts on**: the face that
  moves, the part that is placed. Everything else is steel. If two things want it, the result wins.
- **2D:** the accent is *flat ACC* on **one** element, and the geometry is INK 1.5. The element is one of:
  - the point being placed (Create tools: ACC dot r 2.4);
  - the constraint marker (Constrain);
  - the dimension (Dimension);
  - the piece the tool adds to existing geometry (fillet arc, chamfer bevel, extension, bridge,
    tangent arc). That piece is ACC 1.5, and no accent dot is added.
- An icon never mixes the accent material with a second accent element, with one exception: an ACC
  dimension or ACC point on the ground next to steel solids (`MS.measure`), where steel is the context.

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
  accent on the new thing. `single.finishIcon` is an **ACC check mark**, 2.0, over an SEC profile.
- **Amber: never** (§5.3).
- **Red: exactly one case.** An icon whose subject is a **fault state** (a sick or failed relation that the
  user must look at) may draw **one** flat `ERR #E96C67` mark: the broken constraint glyph, at most 8 × 8 u,
  as flat ink, never as material. Today that is **`AS.showsick` only**. The build's `STATUS_RED` set holds
  the allowed keys, and anything else fails. Adding a key needs a SPEC change. On the rail ERR maps to
  #EC6764 (5.3:1) dark and #B23838 (4.8:1) light.
- **Delete, remove, trim, delete face and split are not faults.** Removal is drawn by absence: the removed
  piece is an SEC dashed ghost (`construct()`), plus an INK `−` badge when the ghost alone is ambiguous.
  Never red.

### 5.5 Contrast

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
| **1.5** | sketch geometry (INK), reference geometry (SEC), the added sketch piece and constraint markers (ACC) |
| **1.25** | arrows (straight and arc), dimension line, construction, preview, 2D centre lines, radius (SEC) |
| **1.0** | extension lines (SEC), the coincident / target ring (ACC) |
| **2.0** | symbols only: the `+` / `−` badge, the finish check mark |

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

### 6.5 Sketch tools: line art

- **Geometry:** INK **1.5**.
- **Construction and radius:** SEC **1.25**. Construction is dashed `2.5 2`.
- **Dots** are flat discs with no gradient:
  - an existing / start point: **INK r 1.9**;
  - the point being placed: **ACC r 2.4** (one per icon).
- **Coincident / target ring:** ACC 1.0 at **r 4.6** round the ACC dot (`ring()`).
- **Lines stop short of a ring:** a segment that meets a ringed point ends 6 u from its centre
  (`CN/coincident`).
- **Constraint markers** are ACC 1.5 at the locus of the relation: `∟` in the corner, `//` beside the pair,
  `=` across both segments, a lock beside the point. One marker per icon, and no badge frame.
- No gradients and no `data-lit` in a pure sketch icon.

### 6.6 Badges, symbols, text

- **`+` / `−` badge:** INK 2.0, arms 3.5, centred at (22.5, 22.5) (`badge()`). The host drawing keeps
  1 u clear of a 9 × 9 corner there. There is no ring and no disc, and it is never green or red.
- **Eye (show / hide):** INK 1.5 lens and pupil. Hide adds an INK 1.5 slash.
- **Check mark:** ACC 2.0.

## 7. No `<text>`, ever

Letters (`Text`, `Geometry Text`, Parameters `fx`, `G2`) are paths: INK 1.5 monoline strokes, a geometric
sans skeleton, cap height 10–12 u. `<text>`, `<tspan>` and `font-*` fail the lint.

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
| A | `IC.text18` | outlined sans "A" (INK 1.5 monoline) with an ACC dot at its insertion point on a short SEC baseline |
| A | `IC.point18` | a single ACC dot r 2.4 in the ACC ring, short SEC crosshair arms outside the ring |
| A | `IC.fline` | = `IC.line34` |
| A | `IC.fmidline` | INK segment, ACC dot at its MIDPOINT (placed first), INK dots at both ends |
| A | `IC.fsplinecv` | INK smooth S-spline; its control polygon SEC dashed with INK dots on the control vertices off the curve; ACC dot on the last vertex |
| A | `IC.fsplinei` | INK S-spline passing THROUGH three INK dots on the curve, ACC dot on the last |
| A | `IC.fsplinefree` | INK freehand wavy stroke ending in an ACC dot (the pen) |
| A | `IC.feqcurve` | INK sine curve over short SEC x/y axes; ACC dot on the curve |
| A | `IC.fbridge` | two INK curves with a gap, bridged by an ACC 1.5 smooth curve tangent to both |
| A | `IC.fcirclecp` | = `IC.circle34` |
| A | `IC.fcircletan` | INK circle tangent to three INK lines (a triangle), ACC dots at the tangent points |
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
| A | `IC.fgtext` | INK monoline "A" sitting on an INK arc (text along geometry), ACC dot at the start of the arc |
| A | `IC.projgeo` | steel block; one top-face edge as an accent band; below it, on the ground, its projection as an ACC 1.5 line, SEC dashed projectors (ink kept off the block) |
| B | `IC.patrect` | 2D: one square with ACC corner dot + three INK copies in a 2×2 grid, SEC direction arrows |
| B | `IC.patcirc` | 2D: one ACC-dotted instance + five INK copies on an SEC circle round an INK centre dot |
| B | `IC.patmir` | 2D: INK half-shape and its INK mirror about an SEC dash-dot mirror line, ACC dot on the mirrored point |
| B | `CN.dim` | ★ ACC double-arrow dimension, SEC extension lines, over an INK segment with INK end dots |
| B | `CN.autodim` | INK L-profile with two ACC dimensions (one horizontal, one vertical) placed automatically; no dots |
| B | `CN.coincident` | ★ two INK segments whose ends stop 6 u short of ONE ACC dot in the ACC ring |
| B | `CN.collinear` | two INK segments on one straight line with a gap, an ACC 1.25 dashed line running through both |
| B | `CN.concentric` | two INK circles of different radius, one ACC centre dot in the ring |
| B | `CN.lock` | INK segment with INK dots, ACC padlock marker (1.5, rx 1 body + shackle) at one end |
| B | `CN.parallel` | two INK lines at the same angle, ACC `//` marker between them |
| B | `CN.perp` | two INK lines meeting at 90°, ACC `∟` marker in the corner |
| B | `CN.horiz` | INK horizontal line with INK dots, ACC `—` marker above |
| B | `CN.vert` | INK vertical line with INK dots, ACC `|` marker beside |
| B | `CN.tangent` | INK circle touched by an INK line, ACC dot at the tangency |
| B | `CN.symmetric` | two INK dots mirrored about an SEC dash-dot line, ACC `‹ ›` markers |
| B | `CN.equal` | two INK segments of equal length, ACC `=` marker on each |
| B | `CN.smooth` | INK line flowing into an INK curve, ACC curvature comb (5 short spines) along the curve at the joint |
| B | `CN.conset` | INK `∟` and `//` marker sheet (rx 1.5 frame) with an ACC gear (settings) |
| B | `CN.showcons` | INK geometry with two ACC constraint markers and an INK eye |
| B | `MD.trim` | INK line crossing an INK curve; the cut-off piece an SEC dashed ghost, an ACC dot at the cut |
| B | `MD.split` | INK line broken at an ACC split point (two INK end dots with a 2 u gap either side of the ACC dot) |
| B | `MD.moffset` | SEC original profile and its INK parallel offset copy, ACC dot on the copy, short SEC offset arrow |
| B | `MD.extend` | INK line extended in ACC 1.5 up to an INK boundary line |
| B | `MD.move` | INK shape with an ACC dot at its base point and an INK four-way move arrow |
| B | `MD.copy` | SEC original shape and INK duplicate offset diagonally, ACC dot on the copy's base point, small INK arrow |
| B | `MD.mrotate` | INK shape rotated about an ACC centre dot, INK 2D rotation arrow (`arc_arrow`) |
| B | `MD.mscale` | small SEC square and larger INK square sharing an ACC corner dot, INK diagonal arrow |
| B | `MD.stretch` | INK profile with the right half stretched, SEC dashed selection window, INK arrow, ACC dot on the moved corner |
| B | `IN.image` | INK sheet (rx 1.5 frame) with mountain + sun, the mountain an ACC 1.5 line |
| B | `IN.points` | grid of INK dots with a sheet/table corner (points from a spreadsheet), the first dot ACC |
| B | `IN.acad` | AutoCAD import: INK sheet (rx 1.5, folded corner) with an INK 2D drawing (rect + circle) inside, an ACC dot on it, INK import arrow entering; no lettering |
| B | `IN.constr` | construction toggle: SEC dashed line between INK dots with an ACC dot |
| B | `IN.params` | NEW: INK monoline italic `fx` on an SEC rounded field (parameters), ACC dot |
| B | `IN.gear` | spur gear outline (12 teeth) INK 1.5 with an ACC hub circle |
| B | `IN.driven` | driven / reference dimension: ACC dimension in parentheses (INK 1.25 arcs), SEC dashed extension |
| B | `IN.sphere` | Centerline: an SEC 1.25 dash-dot centre line between INK dots, ACC dot on one end |
| B | `IN.center` | Center Point toggle: INK `+` centre mark in the ACC ring |
| B | `IN.showfmt` | INK lines in three formats (solid, dashed, dash-dot) with an INK eye |
| B | `single.layerBigIcon` | two stacked steel sheets (dimetric panes), the top one accent pane, INK `+` badge — new layer |
| B | `single.finishIcon` | ACC check mark (2.0) over an SEC sketch profile — finish sketch (never green) |
| B | `single.newSketchIcon` | steel pane (a face) with an accent-material profile ring on it, INK `+` badge — new sketch |
| C | `CR.extrude` | ★ accent box, INK up arrow beside it on the ground |
| C | `CR.revolve` | ★ accent ¾ cylinder with its two cut faces, INK `arc_arrow_dimetric` concentric with the rim, round the back into the missing quarter |
| C | `CR.sweep` | accent tube following a curved (S) path; the path an SEC 1.5 line on the ground ahead of it |
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
| C | `MO.thread` | steel cylinder with accent helical thread bands on its side |
| C | `MO.combine` | two overlapping solids: the union body accent, the tool body steel glass |
| C | `MO.thicken` | steel thin sheet and an accent thickened slab above it, INK offset arrow beside |
| C | `MO.split` | steel block cut by a steel glass plane, one half accent and slightly separated |
| C | `MO.direct` | steel block with one accent face and an INK 3D move arrow beside it |
| C | `MO.deleteface` | steel block with one face missing: its outline as an SEC dashed ghost on the ground side, INK `−` badge (never red) |
| C | `DE.deMove` | NEW: accent face pushed out of a steel block along an INK arrow beside it |
| C | `DE.deSize` | NEW: steel block with an accent cylindrical face (bore), INK radial double arrow on the ground |
| C | `DE.deScale` | NEW: small steel cube inside a larger accent glass cube, INK diagonal arrow |
| C | `DE.deRotate` | NEW: accent face tilted about a steel rod (hinge), INK `arc_arrow_dimetric` |
| C | `DE.deDelete` | NEW: steel block, an SEC dashed ghost where the face was, INK `−` badge (never red) |
| D | `WF.plane` | ★ accent pane (the stylised sheet), hairline on the far edge |
| D | `WF.axis` | ★ steel cylinder, accent rod through its centre: out of the top face (socket) and out under the bottom rim |
| D | `WF.point` | steel block with an accent `mat_dot` on its top front vertex |
| D | `WF.ucs` | three INK axis arrows (dimetric x, y, z) from an accent `mat_dot` origin, small accent panes at the axis corners |
| D | `PL.plane` | = `WF.plane` |
| D | `PL.offset` | steel slab, accent pane floating parallel above its top face, INK offset arrow beside |
| D | `PL.parallelpt` | accent pane parallel to a steel face, passing through an ACC dot / `mat_dot` |
| D | `PL.midplane2` | two steel slabs face to face, an accent glass pane centred between them |
| D | `PL.midtorus` | steel torus (ring) cut through its middle by an accent glass pane |
| D | `PL.angleedge` | steel block whose top edge is an accent band (hinge), accent pane rotated about it, INK angle arc |
| D | `PL.threepts` | three ACC dots on the ground, accent pane through them |
| D | `PL.twoedges` | two accent-band edges of a steel block, accent glass pane through both |
| D | `PL.tansurfedge` | steel cylinder, accent pane tangent along its side, accent band edge at the contact |
| D | `PL.tansurfpt` | steel cylinder, accent pane touching at an accent `mat_dot` |
| D | `PL.tanparallel` | steel cylinder, accent pane tangent to it and parallel to a steel glass reference pane |
| D | `PL.normalaxis` | accent rod piercing a steel glass pane at 90°, `mat_dot` at the pierce |
| D | `PL.normalcurve` | INK curve on the ground with an accent pane normal to it at an ACC dot |
| D | `AX.axis` | = `WF.axis` |
| D | `AX.onedge` | accent rod lying along an edge of a steel block |
| D | `AX.axparallel` | accent rod parallel to an INK line on the ground, through an ACC dot |
| D | `AX.twopts` | accent rod through two ACC dots (the dots on the ground beyond the rod's ends) |
| D | `AX.intersect` | two steel glass panes crossing, accent rod along their intersection |
| D | `AX.normalplane` | steel slab with an accent rod standing normal on it (socket at the foot) |
| D | `AX.centeredge` | steel cylinder, its top rim an accent band, accent rod through its centre |
| D | `AX.revolved` | steel revolved solid (vase) with an accent rod as its axis |
| D | `PN.point` | = `WF.point` |
| D | `PN.grounded` | ACC work point (dot in ring) with an INK ground symbol (three bars) beneath |
| D | `PN.vertex` | steel block with an accent `mat_dot` on a top vertex |
| D | `PN.int3planes` | three steel glass panes meeting, an accent `mat_dot` at the corner |
| D | `PN.int2lines` | two INK lines crossing, ACC work point at the crossing |
| D | `PN.intplaneline` | steel glass pane pierced by an INK line, ACC work point at the pierce (line kept off the pane) |
| D | `PN.centerloop` | steel block with an accent elliptical band loop on its top face, `mat_dot` at its centre |
| D | `PN.centertorus` | steel torus, accent `mat_dot` at its centre |
| D | `PN.centersphere` | steel sphere (curve material, two stops), accent `mat_dot` at its centre |
| D | `PT.rect` | 3D: one accent cube + steel copies in a 2×2 grid, INK direction arrows on the ground |
| D | `PT.circ` | 3D: one accent cube + steel copies around a steel rod (the axis is context) |
| D | `PT.sketch` | 3D: accent cube + steel copies placed on INK sketch dots on the ground |
| D | `PT.mirror` | 3D: accent solid and its steel mirrored copy about a steel glass pane |
| D | `VW.shaded` | steel cube, plain three-face shading (the default view style) |
| D | `VW.rendered` | accent sphere in curve material with the hairline highlight (rendered look); no shadow |
| D | `VW.section` | steel block cut by an accent glass pane, the cut face shown in deep material |
| D | `VW.engine` | render engine: an INK ray arrow bouncing off a steel sphere, ACC dot for the light |
| D | `VW.floor` | steel cube standing on an SEC dimetric floor grid (on the ground beside, never under, the cube) |
| D | `MS.measure` | ★ steel rule on the lattice with shade-material graduations, ACC dimension above it, SEC vertical extension lines |
| E | `AS.place` | ★ accent component cube, INK down arrow above it |
| E | `AS.create` | accent glass component cube (new, in place) with an INK `+` badge |
| E | `AS.freemove` | steel component cube with INK four-way move arrows (dimetric x and y) on the ground |
| E | `AS.freerotate` | steel component cube with an INK `arc_arrow_dimetric` round it |
| E | `AS.joint` | two parts (accent + steel) with a joint origin (accent `mat_dot` + short rod stubs) between them |
| E | `AS.constrain` | ★ mate: accent part held above a steel base with a gap, two INK arrows beside it pressing down onto the base |
| E | `AS.show` | two steel parts with an ACC constraint marker on the ground and an INK eye |
| E | `AS.showsick` | two steel parts with the ERR broken-constraint mark (the one status exception, §5.4) and an INK eye |
| E | `AS.hideall` | two steel parts with an SEC constraint marker and an INK eye-slash |
| E | `AS.copy` | accent component cube with a steel duplicate offset, INK copy arrow |
| E | `single.assemblyMenuIcon` | three stacked component cubes (one accent) — assembly document |
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

- **Ink:** `INK SEC ACC` (and `ERR`, status only).
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
| `ic.hairline(d, x1, x2)` | the 0.6 u lit-edge highlight |
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
| `mat_dot(ic, p, r=2.4, mat='acc')` | a point on a solid |

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

To extend the library (a torus, a sphere, a helix band), add the primitive to `crisp.py`, keep it
stdlib-only, draw it through `Solid` / `ic.mat`, and tell the lead: every family must get it the same
way.
