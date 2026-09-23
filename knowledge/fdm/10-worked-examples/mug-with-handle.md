---
id: fdm/examples/mug-with-handle
title: Worked example — a cup or mug with a handle, printed upright
type: example
process: fdm
triggers: [cup, mug, teacup, tea cup, coffee cup, tasse, teetasse, kaffeetasse, becher, trinkbecher, handle, henkel, griff, tumbler, beaker, drinking]
depends_on: [fdm/geometry/overhangs-and-bridging, design/people/ergonomics]
confidence: medium
updated: 2026-09-23
---

# Worked example — a cup or mug with a handle, printed upright

The part people ask for most, and the one that went wrong most often (#70,
#71, #84, #87): a body that was a solid cylinder with a hole cut in it, a
handle that was a flat extruded slab with a square window, a handle whose top
arm stuck straight out of the wall and printed in mid-air. Every one of those
is avoidable in the order of operations below, which is built and checked on
the app's own kernel.

## When this applies

Any cup, mug, beaker or tumbler printed on a filament printer, with or
without a handle. The same order works for any hollow vessel with an
attachment on its side: a pen pot with a hook, a planter with a lug.

Not for a cup that will be slip-cast or thrown — there the handle is pulled or
cast separately and none of the printing rules below apply.

## Good starting values

| Quantity | Value | Why |
|---|---|---|
| Wall `t` | 2.4 mm | six lines of 0.4 mm; stiff, and watertight with 3+ perimeters |
| Floor | the same `t` | the shell makes it so |
| Outside diameter `D` | 64–80 mm | the hand wraps around it; for 200 ml take 64 so the cup is tall enough for a round handle |
| Height `H` | from the capacity, below | |
| Capacity headroom | +12 % | so the stated volume is not filled to the brim |
| Handle tube | Ø10–11 mm | the grip; thinner feels flimsy and snaps between layers |
| Finger opening | ≥ 18 mm between wall and the inside of the grip | one finger through, knuckle clear |
| Handle attachment | 15 % and 85 % of the height | balance in the hand, and height for the legs to rise |
| Handle legs out `k` | 15 mm, rising 35° | then a round arc — about 24 mm reach, an 18 mm opening |
| Handle legs | rising at least **30° from horizontal** (35° drawn) | printable upright without support (see the overhang rules) |
| Rim | R1 on both rim edges | a lip, not a knife edge |
| Foot | 0.6 mm chamfer | against elephant's foot; do it LAST |

Height from capacity `V` (in mm³ — 200 ml is 200000):
`H = V / (pi * (D/2 - t)^2) * 1.12 + t` — write exactly that as an
expression; the app evaluates it.

## How to build it

Three blocks. The order is not a style choice: a chamfer before the shell
makes the shell fall back to rounded joins, and a handle added to that body
does not fuse; a handle added before the shell gets hollowed with the cup.

```cad
{"title": "Tassenkörper", "vars": {"D": 64, "t": 2.4, "R": "D/2",
  "H": "200000/(pi*(D/2-t)^2)*1.12+t"},
 "actions": [
  {"op": "create_sketch", "plane": "xz", "id": "body_sk"},
  {"op": "sketch_circle", "x": 0, "y": 0, "diameter": "D"},
  {"op": "extrude", "distance": "H", "id": "body"},
  {"op": "shell", "thickness": "t", "open": "top", "id": "wall"}]}
```

The handle is a ROUND tube swept along a smooth path in the XY plane, not an
extruded outline: a slab with a window is the look of a first draft. The path
is a D: a straight leg rising 35° out of the wall, a TANGENT arc round the far
side, and a leg back in — drawn with `sketch_path` (`closed: false`), which the
sweep joins into one smooth curve. The legs are defined by their angle, so
they stay printable whatever height the cup comes out; the arc takes the rest
of the height, so it is always round, never pointed. Its ends sit 1 mm inside the wall, so the tube
is fused solidly — and then the bore is cut again, which removes the ends
that poked through into the cup.

```cad
{"title": "Henkel", "vars": {"a": "H*0.15", "b": "H*0.85", "k": 15, "e": "k*tan(35)"},
 "actions": [
  {"op": "create_sketch", "plane": "xy", "id": "handle_path"},
  {"op": "sketch_path", "closed": false, "start": ["R-1", "a"], "segments": [
     {"to": ["R-1+k", "a+e"]},
     {"to": ["R-1+k", "b-e"], "tangent": true},
     {"to": ["R-1", "b"]}]},
  {"op": "sweep", "path_sketch": "handle_path", "profile_circle": 11,
   "operation": "join", "id": "handle"},
  {"op": "create_sketch", "plane": "xz", "offset": "t", "id": "bore"},
  {"op": "sketch_circle", "x": 0, "y": 0, "diameter": "D-2*t"},
  {"op": "extrude", "distance": "H", "operation": "cut", "id": "bore_cut"}]}
```

```cad
{"title": "Rand und Fuß", "say": "Fertig: Tasse Ø64, 200 ml, 2,4 mm Wand, runder Henkel, Rand R1, Fuß gefast.",
 "actions": [
  {"op": "fillet", "radius": 1, "near": [["R", "H", 0], ["R-t", "H", 0]], "id": "rim"},
  {"op": "chamfer", "distance": 0.6, "near": [["-R", 0, 0]], "id": "foot"}]}
```

Built on the app's kernel this is one valid solid, and the app's overhang
check finds nothing that needs support.

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
