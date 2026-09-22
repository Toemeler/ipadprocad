---
id: laser/basics/machine-assumptions
title: Machine assumptions — what these numbers were written for
type: basics
process: laser
triggers: [machine, maschine, my laser, laser settings, einstellungen, measured kerf, gemessene schnittfuge, calibration record]
depends_on: [laser/basics/kerf-and-tolerance]
confidence: high
updated: 2026-09-22
---

# Machine assumptions — what these numbers were written for

Every number in the laser folder assumes a generic mid-power CO₂ machine. This
file is where a real machine's measurements go, and **a measured value here
overrides the baseline everywhere else.** When the assistant has a value from
this file, it should use it and say so.

## When this applies

Read this before trusting any kerf, power or speed number in this folder.
Write to it after running [`kerf-test-comb`](kerf-test-comb.md).

## Good starting values

### What the rest of the folder assumes

| Assumption | Value | If your machine differs |
|---|---|---|
| Source | sealed CO₂ tube, 40–80 W | a diode laser cuts far less, chars more, and has a wider kerf on wood; a fibre laser will not cut most of these materials at all |
| Lens | 2″ focal length | a 1.5″ lens gives a narrower kerf and less depth of cut; a 2.5″ lens the reverse |
| Assist | compressed air | without air assist expect more charring and a wider effective kerf |
| Bed | honeycomb | a slat bed leaves less back-reflection marking on the underside |
| Focus | on the top surface | focusing at mid-thickness reduces taper on 6 mm+ material |
| Units | millimetres | every number in this folder is metric |

### Measured values for this shop

Fill this in. `—` means nobody has measured it yet, and the baseline from
[`kerf-and-tolerance`](kerf-and-tolerance.md) is being used instead.

| Material | Thickness (measured) | Kerf (measured) | Slip slot | Press slot | Date | By |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

### Machine record

| Field | Value |
|---|---|
| Machine | — |
| Tube power | — |
| Lens | — |
| Bed size | — |
| Controller / software | — |
| Last lens clean | — |

## How to build it

1. Run the comb test on the material you are about to use.
2. Add one row to the measured-values table. Never overwrite an old row —
   add a new one with today's date. A kerf that has drifted is a maintenance
   signal: a dirty lens or a tired tube widens the kerf before it stops
   cutting through.
3. If the machine itself changes, fill in the machine record and clear the
   measured values. They belong to the old configuration.

## When to do it differently

- **Shared machine / makerspace** → keep one row per machine and name it in
  the *By* column. Two machines in the same room routinely differ by 0.05 mm.
- **Cut service, not your own machine** → ask them for their kerf, or cut a
  comb as part of your first order. Services usually publish one.

## Images

None — this document is a record, not an explanation.

## Source & date

- Template written for this repository, 2026-09-22.
- `confidence: high` — this file contains no claims, only measurements.
