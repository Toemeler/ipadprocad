---
id: shared/img-style
title: Diagram conventions
type: basics
process: shared
triggers: [diagram style, drawing convention, svg style, Diagrammstil]
depends_on: []
confidence: high
updated: 2026-09-22
---

# Diagram conventions

The diagrams in this knowledge base are read by two audiences with opposite
strengths: a human skims them, and a vision model looks for the one difference
between the good picture and the bad one. Both are served by the same rule —
**one picture, one point.**

## When this applies

Writing or editing any `.svg` under a `knowledge/**/img/` folder. Photographs
follow [`PHOTOS.md`](PHOTOS.md) instead.

## Good starting values

| What | Start with | Works between | Why |
|---|---|---|---|
| Canvas | 480 × 300 px viewBox | 320–720 wide | wide enough for a labelled section, small enough to read inline |
| Background | explicit `#fff` rounded rect | — | the file must survive a dark-themed markdown viewer |
| Stroke — geometry | `#1a1a1a`, 2 px | 1.5–2.5 px | reads at thumbnail size |
| Stroke — dimension lines | `#0b6bcb`, 1.2 px | — | blue always means "a measurement", never material |
| Fill — material | `#d9d9d9` | — | grey is always solid material |
| Fill — removed / gap | `#ffffff` | — | white is always absence of material |
| Accent — the thing that is wrong | `#c62828` | — | red appears **only** in `bad-*` diagrams |
| Accent — the thing that is right | `#2e7d32` | — | green appears **only** in `good-*` diagrams |
| Label text | 13 px system sans | 11–15 px | below 11 px it is unreadable when the doc is scaled down |

## How to build it

1. Name the file for its verdict: `good-<subject>.svg`, `bad-<subject>.svg`, or
   `fig-<subject>.svg` for a neutral explainer.
2. Open with the white rounded background rect so the drawing never sits
   directly on a dark page.
3. Draw the material in grey, the removed material in white.
4. Add **one** annotation. If a second annotation feels necessary, it is a
   second diagram.
5. Put the dimension that the rule is about in blue, with its value as text.
6. Keep every coordinate on whole or half pixels — SVG anti-aliasing turns a
   2 px line at x=10.3 into a soft 3 px smear.

## When to do it differently

- **A sequence of operations** → one diagram per step, numbered
  `fig-<subject>-1.svg`, `-2.svg`, rather than one crowded picture.
- **A comparison of three or more options** → a single `fig-` diagram with a
  row of variants is clearer than three files, as long as each variant carries
  its own label.
- **Something whose failure is about texture or colour** (charring, stringing,
  a sink mark) → a diagram cannot show it. Request a photograph in
  `PHOTOS.md` instead.

## Images

![the palette and line weights used by every diagram](laser/01-basics/img/fig-diagram-legend.svg)
*The legend every other diagram in this knowledge base is drawn against: grey
is material, white is what the process removed, blue measures, red is the
mistake, green is the fix.*

## Source & date

- Conventions set for this repository, 2026-09-22. No external source.
- `confidence: high` — these are house rules, not facts about the world; they
  are true because this folder follows them.
