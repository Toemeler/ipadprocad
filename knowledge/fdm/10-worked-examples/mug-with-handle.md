---
id: fdm/examples/mug-with-handle
title: Worked example — a cup or mug with a handle, printed upright
type: example
process: fdm
triggers: [cup, mug, teacup, tea cup, coffee cup, tasse, teetasse, kaffeetasse, becher, trinkbecher, handle, henkel, griff, tumbler, beaker, drinking]
depends_on: [fdm/geometry/overhangs-and-bridging, design/people/ergonomics]
confidence: medium
updated: 2026-09-24
---

# Worked example — a cup or mug with a handle, printed upright

The part people ask for most, and the one that went wrong most often (#70,
#71, #84, #87): a body that was a solid cylinder with a hole cut in it, a
handle that was a flat extruded slab with a square window, a handle whose top
arm stuck straight out of the wall and printed in mid-air. Every one of those
is avoidable in the order of operations below, which is built and checked on
the app's own kernel.

**This is a technique, not a design.** It holds the ORDER that builds and the
RULES that make it print — no example part: a drawn example gave every user
the same cup, to the tenth of a millimetre (#91: "the design is always the
same and not creative"). The design is yours to make: see **Make it this
user's cup** below.

## When this applies

Any cup, mug, beaker or tumbler printed on a filament printer, with or
without a handle. The same order works for any hollow vessel with an
attachment on its side: a pen pot with a hook, a planter with a lug.

Not for a cup that will be slip-cast or thrown — there the handle is pulled or
cast separately and none of the printing rules below apply.

## Good starting values

The first table holds LIMITS — what a printed cup has to satisfy whatever it
looks like. The second holds RANGES to design within; pick values for this
cup, and do not reach for the middle of every range by habit.

| Must hold | Value | Why |
|---|---|---|
| Wall `t` | 1.6–3.2 mm, a multiple of the line width (2.4 = six lines of 0.4) | stiff, and watertight with 3+ perimeters |
| Floor | at least `t` | the shell makes it so; a heavier floor is a design choice |
| Capacity headroom | +10–15 % | so the stated volume is not filled to the brim |
| Handle section | at least Ø9 mm round, or 8 × 12 mm flat | thinner feels flimsy and snaps between layers |
| Finger opening | ≥ 18 mm between wall and the inside of the grip | one finger through, knuckle clear |
| Overhangs | every underside **30° from horizontal** or steeper | printable upright without support (see the overhang rules) |
| Rim | rounded (R0.8–1.5), never a knife edge | a lip you drink from |
| Foot | 0.4–0.8 mm chamfer, LAST | against elephant's foot |

| Design within | Range | Notes |
|---|---|---|
| Outside diameter at the widest | 55–95 mm | the hand wraps round 60–80; an espresso cup sits low and small, a soup mug wide |
| Height to width | 0.6 (bowl, espresso) to 1.6 (tall mug, tumbler) | the capacity then fixes the size |
| Wall lean | vertical to 25° out | a flared or tapered body is a revolve, not an extrusion |
| Handle reach | 20–35 mm out from the wall | a one-finger ear is small, a full-hand grip reaches far |
| Handle attachment | anywhere from 10 % to 90 % of the height | a low ear, a centred loop, a full-height D |

Height from capacity `V` (in mm³ — 200 ml is 200000), for a straight wall:
`H = V / (pi * (D/2 - t)^2) * 1.12 + t` — write exactly that as an
expression; the app evaluates it. For any other profile, read `holdsMl`
in the report after the shell instead.

## How to build it

The order of moves is not a style choice: a chamfer before the shell makes the shell fall back to rounded
joins, and a handle added to that body does not fuse; a handle added before
the shell gets hollowed with the cup. (The ops are this app's own; see the
operation list.)

1. **The body in one `lathe`**: the half-section as [r, y] points about the
   vertical axis — any form the design wants (straight, tapered, bellied,
   waisted), every outward lean under 30°.
2. **`shell`** open at the top, wall `t`. Read `holdsMl` in the report: it is
   the measured capacity; change the height or the profile until it matches
   the capacity asked for (plus the headroom above).
3. **`handle`** — never a hand-drawn sweep. It measures the wall at the two
   heights you give and ends the handle inside the wall at both, whatever the
   taper, with legs rising at 35° so it prints upright. Choose the heights,
   the reach, round or angular, and the section.
4. **Rim and foot**: `fillet` with `edges: "top"`, then `chamfer` with
   `edges: "bottom"`, LAST.

## Make it this user's cup

Before the first block, decide what THIS cup is — from the request (who drinks
what from it, where it stands, a word like "elegant", "rustic", "for a
child"), and where the request says nothing, by your own choice. Then say in
one line what you chose and offer one other direction ("a tapered body with a
low ear handle — or would you rather have something taller and straight?").
Choose along these, and vary them from cup to cup:

- **Body form.** Straight cylinder, tapered cone (narrow foot, wide mouth),
  bulbous belly, waisted hourglass, faceted (a polygon instead of a circle —
  six to twelve sides), or a stepped foot ring. Every round form is one
  `lathe` of its half-section (straight, curved with arcs through points),
  then `shell` open at the top — keep every outward lean under 30°.
- **Proportion.** Low and wide, square (height ≈ width), or tall and narrow.
  Take it from the capacity and the drink, not from this page.
- **Handle.** Through the `handle` op, shaped by its arguments: a small
  ear (one finger, attached high, short span), a full-height D (from low to
  high, round), an angular handle (`style: "angular"`), a thick or slim
  section; or none, with a grip band of rings cut round the body. Whatever
  the shape, the section obeys its minimum.
- **Rim and foot.** A plain rounded rim, a lip that flares out 2–3 mm, a
  thickened rim band; a flat base, a recessed foot ring, a chamfered plinth.
- **Details, only where they serve.** A thumb rest on the handle, a gentle
  concave fillet (2–3 mm) at the handle joints, rings or flutes on the body.
  One or two, done properly — not all of them.

Never reuse a previous cup's numbers because they were in this document or in
an earlier conversation. The user asking again is asking for another cup.

## When to do it differently

- **A tapered or "designer" body** → revolve a profile instead of extruding a
  circle: draw the half-section on XY with `sketch_path` (a wall that leans
  out up to 30° still prints), revolve about Y, then shell open at the top as
  above.
- **A wider handle** (two or three fingers) → raise `k` and spread `a` and
  `b`. Keep the leg angle at 30° or more (the app says where it is not), and
  leave the arc at least twice the tube's radius — a turn tighter than the
  tube fails as "path too tight for the section".
- **No handle** (a tumbler, a pot) → the first block and the third.
- **A handle that must be very strong** → it prints along the layers either
  way; make the tube Ø12 and give the two joints a concave fillet of 2–3 mm
  (`fillet` with `edges: "concave"`), which also looks finished.
- **Dishwasher or hot drinks** → PETG or better, and a food-safe coating:
  printed layers hold bacteria. Say so to the user.

## Images

None yet.

## Source & date

- Built and checked on the app's own OpenCascade kernel for issue #87,
  2026-09-23: the three blocks above give one valid solid with no unsupported
  overhang at the owner's 30°-from-horizontal limit.
- Ergonomic numbers (finger opening, tube diameter) from
  [`design/people/ergonomics`](../../design/02-people/ergonomics-and-anthropometrics.md).
