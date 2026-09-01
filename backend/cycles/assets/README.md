# The render assets

**Nothing in here is required.** A build made from a clean clone has none of
these files and renders exactly what M343 rendered: the four-light rig, flat
Principled surfaces, the app's own viewport colour behind the model. Every one
of them is looked for once at launch (`cycles_assets.dart`) and checked again
with `fopen` in the shim before a node is built, so a missing file is a
surface without a texture and never an error.

What they buy is the difference between a render that looks *rendered* and one
that looks *photographed*.

---

## 1. The environment map — the one that matters most

```
backend/cycles/assets/hdri/studio.hdr        (or studio.exr)
```

**Equirectangular** (a 2:1 latitude/longitude panorama), **32-bit float**,
Radiance `.hdr` preferred over `.exr` — it is about a third the size for a
difference nobody can see in a reflection, and the whole file is decoded into
memory and stays there for as long as rendered mode is on.

**Size: 2K (2048 × 1024) is the right answer.** 4K doubles the memory for
detail that only shows in a mirror, and this scene has no mirrors — the
smoothest surface in it is polished copper at roughness 0.20. A 2K map is
about 24 MB in memory as float RGB.

**What kind of map.** A **studio / softbox** environment: a dark room with two
or three large bright rectangular sources, the sort sold as "studio lighting"
or "photo studio HDRI". Not an outdoor one. The reasons are specific:

* a product photograph's whole look is a large soft source with a clean
  falloff across a curved surface, and that is what a softbox is;
* an outdoor map has a sky that fills half the sphere at one brightness, which
  lights a part from above at one tone and flattens it — the same failure a
  uniform world had (M332);
* a studio map's dark surround is what makes a metal edge read: the bright
  streak of the softbox against the dark room *is* the highlight, and there is
  nothing else in the picture that can draw it.

Poly Haven's `studio_small_*`, `brown_photostudio_*` and `photo_studio_*` sets
are all CC0 and all suitable. So is any HDRI you shoot yourself.

**Why one file and not a list.** A studio is a lighting decision, not a
preference. Two of them are two different products, and a picker for it would
be the first control in this app that changes what a render *means* rather
than how it is computed. If a second is ever wanted it arrives as a named
choice with a reason.

The environment is the **light** and not the **background**: what the camera
sees behind the model stays the app's own viewport colour, so a path-traced
image lands on exactly the ground the rest of the app is drawing. Cycles can
tell a camera ray from a light ray, so both are true at once
(`build_world` in `cycles_shim.cpp`).

---

## 2. Texture sets — per appearance

```
backend/cycles/assets/materials/<id>/basecolor.jpg
backend/cycles/assets/materials/<id>/roughness.jpg
backend/cycles/assets/materials/<id>/metallic.jpg
backend/cycles/assets/materials/<id>/height.jpg
backend/cycles/assets/materials/<id>/ao.jpg
```

`.png` works too and is tried second. **Every map is optional on its own** —
a directory with only `roughness.jpg` in it is a perfectly good set, and is
in fact most of the value.

`<id>` is one of the appearance ids the app already has, plus `steel`:

| directory    | what it is                            |
|--------------|---------------------------------------|
| `steel`      | unpainted — **the commonest body in any assembly** |
| `aluminium`  | |
| `graphite`   | |
| `brass`      | |
| `copper`     | |
| `red` `green` `blue` `violet` | painted / anodised |

**If you only supply one, supply `steel`.**

### What each map is

| file | colour space | what it does |
|---|---|---|
| `basecolor` | **sRGB** | multiplies the appearance's own colour. Author it **near white/neutral** — the app's palette decides what metal it is, this decides how the surface varies. |
| `roughness` | linear/greyscale | multiplies the appearance's roughness. **This is the one that does the most work.** |
| `metallic`  | linear/greyscale | multiplies the appearance's metallic. Rarely needed. |
| `height`    | linear/greyscale | relief. See below. |
| `ao`        | linear/greyscale | multiplied into the base colour at half strength. |

### `height`, not `normal` — this one matters

Supply a **height / displacement / bump** map, greyscale, where white is high.
**A tangent-space normal map cannot be used and must not be dropped in
instead.**

A tangent-space normal map needs a tangent frame, and a tangent frame needs
UVs. A CAD tessellation has no UVs and never will: it is regenerated from the
B-rep every time the model changes, and there is nowhere for a UV layout to
live between one tessellation and the next. So the textures are **box
projected** (triplanar) in object space — and there is no single correct
tangent for a triplanar projection, because each of the three projections has
its own.

A height field has no such problem. Cycles' `BumpNode` differentiates it
numerically, in world space, by evaluating the same shader at offset
positions, so it inherits whatever projection the height came through and is
correct for all three at once.

Most PBR sets ship a `height` or `disp` map alongside the normal map. That is
the file. If a set has only a normal map, either convert it to height or leave
the slot empty — leaving it empty is fine, and is much better than putting a
normal map in it, which would be interpreted as a height field and produce
nonsense.

### Scale, and why it is in millimetres

One tile covers **40 mm** of surface (`kCyclesTextureScale`). In world units,
not as a repeat count, because the bodies are real objects at real sizes: a
brushed grain is a fixed physical scale, and a bracket and the plate it bolts
to have to show the same one. A repeat count would make the small part's grain
coarse and the big part's fine, which is the single most common way a
triplanar setup announces itself as fake.

So author the textures as **tileable, seamless, at a scale that reads
correctly across 40 mm**. Brushed metal: the grain should be fine — dozens of
lines across the tile, not four. Cast/blasted: a fine even stipple.

### Size

**1K (1024 × 1024) is plenty**, 2K if the grain is very fine. These are
sampled across a 40 mm patch of a part that is a few hundred pixels on screen;
4K is memory spent on detail below the pixel. JPEG at quality 90 for the
colour map, PNG for the greyscale ones if you have banding.

---

## Where they end up

CI copies this directory into the Cycles distribution as `cycles-dist/assets`,
which is bundled at `Runner.app/cycles/assets` — beside the kernel source
tree, under the resource root the shim is already given. They are **not**
Flutter assets, because Cycles loads images through OpenImageIO from a *path*,
on a background thread, and a Flutter asset is a byte range inside a bundle
that only the Dart side can address.

The `cycles-ios` job's cache key includes this directory, so adding or
changing a file here rebuilds the distribution.

---

## Licensing

Anything committed here ships inside the app. Use **CC0 / public domain**
sources (Poly Haven, ambientCG) or your own work, and record what you used in
`SOURCES.md` beside this file.
