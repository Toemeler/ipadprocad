---
id: shared/glossary
title: Glossary — German / English manufacturing terms
type: basics
process: shared
triggers: [glossary, terminology, Glossar, Begriffe, was heisst, translation]
depends_on: []
confidence: high
updated: 2026-09-22
---

# Glossary — German / English manufacturing terms

The app is natively German; this knowledge base is written in English, because
that is the language its numbers were published in and the language the terms
of art exist in. This file is the bridge. It matters for two reasons: the user
types German, and a mistranslated term sends the assistant to the wrong
document (*Steg* is a web, not a bridge; *Brücke* in FDM is a bridge but in
laser work it is a holding tab).

## When this applies

Reading a user request in German, or writing `triggers:` for a new document.
Every German term listed here should appear in the `triggers:` of the document
it belongs to.

## Good starting values

### Shared

| German | English | Note |
|---|---|---|
| Wandstärke | wall thickness | |
| Fase | chamfer | a cut corner, straight |
| Verrundung / Radius | fillet | a rounded corner |
| Passung | fit | press / sliding / clearance |
| Spiel | clearance | the gap, diametral unless said otherwise |
| Toleranz | tolerance | |
| Steg | web | the material *between* two cutouts |
| Aussparung | cutout / pocket | |
| Bohrung | hole | |
| Sackloch | blind hole | does not go through |
| Durchgangsloch | through hole | |
| Senkung | countersink | |
| Rippe | rib | |
| Verstärkung / Strebe | gusset | |
| Schnappverbindung | snap fit | |
| Gewinde | thread | |
| Gewindeeinsatz | threaded insert | heat-set insert = Einpressmutter, Gewindebuchse |
| Mutternfalle / Mutterntasche | nut trap | hex pocket for a nut |

### Laser cutting

| German | English | Note |
|---|---|---|
| Laserschneiden | laser cutting | |
| Schnittfuge / Schnittbreite | kerf | the width the beam removes |
| Kerf-Ausgleich | kerf compensation | |
| Gravur | engraving | raster, removes area |
| Ritzen / Kerben | scoring | vector, marks a line |
| Zinken / Fingerzinken | finger joint / box joint | |
| Zapfen | tab / tenon | the part that sticks out |
| Schlitz / Nut | slot | the part it goes into |
| Steckverbindung | tab-and-slot joint | |
| Überlappung / Halbüberblattung | cross-lap joint | |
| Schichtbauweise / Stapelbauweise | stacked-layer construction | |
| Biegescharnier / Lasergelenk | living hinge / lattice hinge | |
| Haltesteg | holding tab | keeps a cut part in the sheet |
| Verschachtelung | nesting | |
| Brandspur | scorch mark / charring | |
| Sperrholz | plywood | |
| Acrylglas / Plexiglas | acrylic / PMMA | cast = gegossen, extruded = extrudiert |
| Pappe / Karton | cardboard / boxboard | |

### FDM printing

| German | English | Note |
|---|---|---|
| Schichtdicke | layer height | |
| Schichthaftung | layer adhesion | |
| Extrusionsbreite / Linienbreite | line width / extrusion width | |
| Düse | nozzle | |
| Überhang | overhang | |
| Brücke | bridge | an unsupported horizontal span |
| Stützstruktur | support | |
| Warping / Verzug | warping | |
| Elefantenfuß | elephant foot | first layers squashed wider |
| Schichttrennung / Delamination | delamination | layers separating |
| Fadenziehen | stringing | |
| Füllung | infill | |
| Perimeter / Außenwand | perimeter / wall | |
| Druckbett | build plate / bed | |
| Bauraum | build volume | |
| Druckrichtung / Orientierung | print orientation | |

## How to build it

When writing a new document, take the German words a user would actually say
out loud — not the dictionary form — and put them in `triggers:`. *Kiste* and
*Schachtel* both mean box; both belong in the finger-joint document's
triggers, because the user will type one of them and not care which.

## When to do it differently

- **A term with no clean German equivalent** (bridging, elephant foot,
  stringing) → keep the English word in the triggers as well. German makers
  use it untranslated, and so does the slicer UI.
- **A term that means different things per process** (*Brücke*) → list it in
  both processes' documents and let the plan's other words decide.

## Images

None — this document is a lookup table.

## Source & date

- Compiled for this repository, 2026-09-22, from the terminology used across
  the sources cited in the individual documents.
- `confidence: high` — vocabulary, not measurement.
