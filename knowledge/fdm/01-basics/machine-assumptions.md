---
id: fdm/basics/machine-assumptions
title: Machine assumptions — what these numbers were written for
type: basics
process: fdm
triggers: [machine, drucker, printer, my printer, bed size, bauraum, build volume, enclosure, settings, einstellungen, calibration record, measured tolerance]
depends_on: [fdm/basics/nozzle-line-width-layers]
confidence: high
updated: 2026-09-22
---

# Machine assumptions — what these numbers were written for

Every number in the FDM folder assumes a generic, well-tuned desktop printer.
This file is where a real machine's measurements go, and **a measured value
here overrides the baseline everywhere else.**

## When this applies

Read before trusting any clearance or tolerance number in this folder. Write
to it after running [`tolerance-test-part`](tolerance-test-part.md).

## Good starting values

### What the rest of the folder assumes

| Assumption | Value | If your machine differs |
|---|---|---|
| Nozzle | 0.4 mm, brass | a hardened nozzle for composites is the same size; a worn nozzle over-extrudes |
| Line width | 0.42 mm | scale every wall thickness with it |
| Layer height | 0.2 mm | affects the Z grid, not the XY clearances |
| Bed | heated, 220 × 220 mm | bigger beds warp more at the corners |
| Enclosure | none | required for ABS, ASA, PC and nylon |
| Extruder | direct drive | Bowden setups struggle with TPU |
| Cooling | full part fan | PLA needs it; ABS must not have it |
| Calibration | e-steps and flow calibrated | an uncalibrated flow rate makes every clearance wrong in the same direction |

### Measured values for this machine

`—` means nobody has measured it and the baseline is being used.

| What | Baseline | Measured | Date | By |
|---|---|---|---|---|
| Hole undersize | 0.1–0.3 mm | — | — | — |
| Shaft oversize | ~0.1 mm | — | — | — |
| Press-fit clearance | 0.1 mm | — | — | — |
| Sliding-fit clearance | 0.2–0.3 mm | — | — | — |
| Elephant foot | 0.1–0.2 mm | — | — | — |
| Max unsupported bridge | 50 mm (PLA) | — | — | — |
| Min self-supporting angle | 45° | — | — | — |

### Machine record

| Field | Value |
|---|---|
| Printer | — |
| Nozzle ⌀ / material | — |
| Build volume | — |
| Enclosed | — |
| Slicer + profile | — |
| Last flow calibration | — |

## How to build it

1. Print the tolerance test part on the material you actually use.
2. Fill in one row per measurement, with the date. Do not overwrite old rows —
   drift is a maintenance signal.
3. If the machine, nozzle or slicer profile changes, clear the measured values.
   They belonged to the old configuration.
4. Keep one table per **material** if the shop uses more than one seriously.
   PLA and PETG do not shrink the same way.

## When to do it differently

- **A print farm or a service** → ask for their tolerance figures, or print
  the test part as part of the first order.
- **Several printers** → one row set per machine. Two identical printers
  routinely differ by 0.1 mm on a press fit.

## Images

None — this document is a record.

## Source & date

- Template written for this repository, 2026-09-22.
- `confidence: high` — no claims, only measurements.
