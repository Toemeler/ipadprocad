---
id: design/form/openings-and-retention
title: Openings and retention — holders, clips and anything that holds something
type: recipe
process: design
triggers: [holder, halter, halterung, clip, klemme, klammer, cable, kabel, cable holder, kabelhalter, kabelklemme, bracket, halteklammer, hook, haken, cradle, saddle, sattel, retain, halten, festhalten, snap, einrasten, einclipsen, grip, greifen, mount, befestigung, organizer, ständer, staender, stand]
depends_on: [design/form/surfaces]
confidence: high
updated: 2026-09-22
---

# Openings and retention

The object has to let the thing IN, hold it, and let it out again. Every one
of those is geometry, and the first one is the one that gets forgotten.

## When this applies

- Anything described as a holder, clip, cradle, bracket, hook, saddle, mount
  or organiser — in any language.
- Not to a bearing or a bore that a shaft is assembled through axially; there
  a closed circle is correct.

## Good starting values

**A closed circle holds nothing.** A ring in a plate can only be threaded onto
a cable from its free end. If the cable is already connected at both ends — a
charger, a desk cable, a headphone lead, which is nearly always the case — the
part is unusable. It will look finished, measure correctly and be watertight.

For a cable of diameter **D**:

| What | Start with | Works between | Why |
|---|---|---|---|
| Bore diameter | D + 0.6 mm | D + 0.4 … D + 1.2 | the cable must sit without being pinched; printed holes also come out undersize |
| Mouth (opening) width | 0.8 × D | 0.7–0.9 × D | narrower than the cable is what retains it; wider and it falls out |
| Arm wall thickness | 2.0–2.4 mm | 1.6–3.0 | thinner will not spring back after a few cycles, thicker will not flex at all |
| Arm length from root to tip | ≥ 2 × D | 2–4 × D | a short arm cannot deflect the 0.2 × D the mouth needs; it just breaks at the root |
| Mouth lead-in chamfer | 0.5–1.0 mm | 0.5–1.5 | without it the cable has to be forced past a sharp corner |

**Which way the mouth points** decides whether the part is printable and
whether it works:

| Mouth direction | Verdict |
|---|---|
| Up (away from the base) | best — prints with no overhang at the crown, and the cable presses in from above, which is how a hand approaches a desk |
| Sideways | works; check the upper arm is not an unsupported overhang |
| Down | almost always wrong — gravity and the insertion force act in the same direction, so it releases on its own |

**A quick test before calling it done.** Name the thing it holds, the
direction a hand comes from, and the gap that thing passes through. If you
cannot state all three from the geometry, it is not a holder yet.

## How to build it

1. Draw the retaining profile as **one closed sketch profile**: outer arc,
   inner arc, and the two short faces of the mouth between them. Use
   `sketch_arc` with three points it passes THROUGH, or `sketch_slot` — an arc
   built from a centre and two angles makes you compute the endpoints, and a
   rounded endpoint will not close the profile.
2. Check `closedProfiles` in the result is 1 before extruding. If the extrude
   reports the sketch is open, the error names the gap and the two points —
   close those, do not redraw the shape.
3. Extrude it across the width of the holder.
4. Join it to the base, set fully inside the base's footprint, and fillet the
   junction — see [`surfaces-and-transitions`](surfaces-and-transitions.md).
5. **Look at the returned view.** The mouth must be visible as an opening. In
   the text silhouette, `o` is a hole you can see straight through; a retained
   opening seen end-on should show as a gap in the outline, not as a closed
   ring.
6. Run `section` across the bore and confirm the mouth measures what you
   intended.

## When to do it differently

- **The cable is free at one end and stays put** → a closed ring is simpler
  and stronger. Say in one line that you assumed it.
- **It must hold several sizes** → a V or a tapered slot retains a range where
  a circular bore retains one diameter.
- **Flexible filament (TPU)** → the mouth can be much tighter, down to 0.5 × D,
  because the whole part gives.
- **It will be screwed shut around the cable** (a two-piece clamp) → then
  there is no mouth and no spring; it is two halves and a fastener.

## Images

No figures yet.

## Source & date

- Standard practice for printed cable management and snap-fit retention;
  the arm-thickness and mouth figures are the usual cantilever-clip numbers
  for PLA and PETG at a 0.4 mm nozzle.
- The opening rule is from issue #82, where "ein Designer Kabelhalter" was
  answered with a Ø10.4 boss bored Ø6.4 straight through — a closed ring no
  connected cable can enter — and the bore was horizontal, so it also needed
  support to print. See `fdm/geometry/holes-shafts-and-teardrops`.
- `confidence: high`. The opening requirement is not a preference; the
  dimensional rows are starting points.
