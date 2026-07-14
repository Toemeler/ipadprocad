# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status (Stand M25)

| Meilenstein | Stand |
|---|---|
| **M1** Headless-Core-Build + iOS-CI | ✅ erledigt (statische Libs, arm64/iphoneos) |
| **M2** C-ABI-Wrapper (`qcad_capi.h`) | ✅ erledigt & validiert; in M5 um Geometrie-Abfrage erweitert |
| **M3** Headless-Logiktest im iOS-Simulator | ✅ erledigt (`SMOKE: PASS`, inkl. Geometrie-Query-Checks) |
| **M4** UI-Design als interaktiver HTML-Mock | ✅ abgeschlossen (`create-panel.html` = verbindliche 1:1-Spec) |
| **M5** Flutter-App (1:1-Port) + echtes Zeichnen + IPA | ✅ Grundausbau erledigt, CI-validiert |
| **M6–M8** Grips/Modify/Snap, Constraints, Bemaßung | ✅ erledigt |
| **M9–M11** Echter Constraint-Solver (SolveSpace `libslvs` via FFI) | ✅ erledigt, in den iOS-Build gelinkt |
| **M12–M14** Auto-Coincident auf den Center Point, Lock, live-korrekter Drag | ✅ erledigt |
| **M15** Diagnose-Log auf dem Gerät (Files-App) | ✅ erledigt |
| **M16** Geometrie strikt an Layer gebunden + Sichtbarkeits-Auge | ✅ erledigt |
| **M17** Layer = Editier-Scope, Auge blendet wirklich alles aus | ✅ erledigt |
| **M18** Produktionsreifes Layer-System (Lock/Rename/Delete/Move) | ✅ erledigt |
| **M19** Fix "alles landet auf Layer 0" (Backend) + Z-Order | ✅ erledigt |
| **M20** Fix: Bögen/Kurven verschwanden beim Ziehen (slvs-Writeback) | ✅ erledigt |
| **M21** Inventor-komplette Bemaßung (alle Pick-Kombinationen) | ✅ erledigt, CI-Gates (Shim-Host-Test + Dart-Tests) |
| **M22** Splines produktionsreif (Tag-Erhalt, periodisch geschlossen, Klick-auf-Start) | ✅ erledigt |
| **M23** Ellipse = 3 Definitionspunkte statt 96-Vertex-Polygon | ✅ erledigt |
| **M24** Ellipsen-Feinschliff, Inventor-Platzierungsregionen, Inline-Werteingabe | ✅ erledigt |
| **M25** Projizierter CP bemaßbar, Mittellinien-Stil, Ellipsen-Achsen als Entities | ✅ erledigt |
| **M26** Inventor-DOF-Färbung: Träger-Analyse (freie Länge = weiß) + Kanten-Färbung + Status-Anzeige | ✅ erledigt (Geräte-Test offen) |
| **M27** Bemaßung antippen/doppeltippen öffnet den Wert-Editor (Label-Treffertest statt Anker) | ✅ erledigt (Geräte-Test offen) |
| **M28** Polylinien-Kanten in Bemaßungen: Punkt↔Kante, Linie↔Kante, Kante↔Kante (Abstand/Winkel `ang4`) | ✅ erledigt (Geräte-Test offen) |

### Constraint-Solver (M9–M14)

Der QCAD-Core hat **keinen** Constraint-Solver (vom Maintainer bestätigt), also
ist SolveSpace's `libslvs` als zweiter nativer Kern eingebettet
(`backend/slvs/`, stdlib-only, eigener flacher C-Shim + Host-Test-Gate). QCAD
bleibt für Geometrie und DXF zuständig, libslvs löst die Constraints.

Der Solver verifiziert jedes native Ergebnis gegen die Dart-Residuen und fällt
bei Zweifel auf einen Levenberg-Marquardt-Solver in Dart zurück — ein falsches
Ergebnis kann also nicht durchrutschen.

**Grip-Drag ist eine Bitte, kein Befehl:** der gezogene Punkt wird über
`Slvs_System.dragged[]` nur *bevorzugt*, nie hart gepinnt. Constraints halten
also live während des Ziehens: eine vertikale Kante bleibt vertikal, ein
gegroundeter Punkt bewegt sich nicht, und ein voll bestimmter Punkt lässt sich
gar nicht erst anfassen. (`SLVS_C_WHERE_DRAGGED` wäre ein *hartes* Constraint
und würde die echten überstimmen — der Fallstrick ist in `HANDOFF.md`
dokumentiert.)

### Layer (M16)

Jede Entity gehört zu **genau einem** Layer, und die Bindung sitzt im
QCAD-Dokument (`qcad_set_current_layer` / `qcad_entity_layer`, intern `RLayer` +
`REntity::setLayerId`) — dadurch überlebt sie den DXF-Roundtrip.

- **Zeichnen geht nur im Edit-Mode eines Layers.** Ohne Edit-Mode ist kein
  Werkzeug aktivierbar; neue Geometrie wird beim Commit zwingend auf den
  editierten Layer gestempelt.
- **Auge im Model Browser** blendet Layer ein/aus. Unsichtbare Layer werden nicht
  gemalt, nicht gepickt, nicht gesnappt und haben keine Grips. Sichtbarkeit
  filtert nie die Geometrieliste (Constraint-Referenzen sind index-basiert) —
  es wird nur übersprungen.

### Layer-Verwaltung (M18, CI/Geräte-Test ausstehend)

Das Layer-System ist zu einer vollständigen Verwaltung ausgebaut (Frontend-only,
auf dem vorhandenen Backend-Layer-Pfad — keine neue C++-API). Im Kontextmenü
einer Layer-Zeile: **Lock/Unlock** (gesperrter Layer bleibt sichtbar, ist aber
read-only), **Rename** und **Delete** (löscht Geometrie + remappt Constraints;
beides für die Pflichtebene „0" gesperrt) sowie **Move N here** — verschiebt die
aktuelle Selektion auf den Layer. Letzteres sortiert auch Altbestände: Geometrie,
die durch einen Prä-M16-Build auf „0" gelandet ist, lässt sich per Box-Select →
Rechtsklick-Ziel → „Move" umziehen. Die Pflichtebene „0" verhält sich wie in
AutoCAD (nicht umbenenn-/löschbar) und erscheint nur, solange sie Geometrie
trägt. Sichtbarkeit + Lock + Reihenfolge liegen versioniert im Sidecar
(`<name>.layers.json`). **Wichtig:** Der ursprüngliche „alles auf Layer 0"-Fehler
kam von einem IPA vor M16 — ein frischer Build ist nötig.

### Bemaßung (M21) — Inventors General Dimension, vollständig

Ein Werkzeug, das den Bemaßungstyp aus der Pick-Kombination ableitet — exakt
wie Inventors General Dimension. Jeder Klick erweitert entweder die Auswahl
(wenn die Kombination gültig ist) oder platziert die Bemaßung:

| Auswahl | Bemaßung |
|---|---|
| Linie | Länge (fluchtend / horizontal / vertikal, per Platzierung) |
| Kreis / Bogen | Durchmesser / Radius |
| Punkt + Punkt | Abstand (fluchtend / H / V per Platzierung) |
| Linie + Punkt | senkrechter Abstand Punkt↔Linie |
| Linie + Linie | Winkel; (nahezu) parallel → linearer Abstand |
| Kreis/Bogen + Punkt | Abstand Punkt↔Mittelpunkt |
| Kreis/Bogen + Kreis/Bogen | Abstand Mittelpunkt↔Mittelpunkt |
| Kreis/Bogen + Linie | senkrechter Abstand Mittelpunkt↔Linie |
| Punkt + Punkt + Punkt | Winkel (zweiter Pick = Scheitel) |
| Polylinien-Kante | ihre zwei Ecken (kombiniert weiter, z. B. + Punkt → Winkel) |

Technisch: zwei neue Bemaßungsarten. `pline` (Punkt-Linie-Abstand) läuft
nativ über den neuen Shim-Code `SH_PT_LINE_DIST` (Shim v2,
`SLVS_C_PT_LINE_DISTANCE`, vorzeichenrichtig — der Punkt bleibt auf seiner
Seite der Linie); ein älteres Binary wird per Versions-Gate erkannt und fällt
auf den verifizierten Dart-LM-Solver zurück statt die Bemaßung stumm zu
verlieren. `ang3` (3-Punkt-Winkel) läuft bewusst immer über den LM-Solver
(der Shim kennt keinen 3-Punkt-Winkel). Alle Mittelpunkt-Kombinationen
reduzieren sich auf die vorhandene Punkt-Punkt-Distanz (`getPt(circle, 0)` =
Zentrum), inklusive DXF-Sidecar-Roundtrip. Getestet: Shim-Host-Gate
(Szenarien 9/10, beide Seiten der Linie) + `frontend/test/` (18 Dart-Tests:
Messen, LM-Treiben, Überbestimmt-Erkennung, komplette Pick-Matrix); beide
laufen in der CI.

### Splines (M22)

Zwei Spline-Werkzeuge wie in Inventor: **Control-Vertex** (kubischer
B-Spline, Punkte liegen NEBEN der Kurve) und **Interpolation** (Kurve läuft
DURCH die Punkte). Gespeichert wird nur das Definitionspolygon als getaggte
Polyline — die Kurve entsteht Dart-seitig, deshalb sind ausschließlich die
Kontroll-/Fit-Punkte Grips und Snap-Ziele. Offene Splines sind geklemmt
(Kurve beginnt/endet auf dem ersten/letzten Punkt), geschlossene sind echte
PERIODISCHE B-Splines (schließen exakt, C2-glatt am Stoß). Klick auf den
Startpunkt (ab 3 Punkten) schließt und committet sofort. CV-Splines zeigen
bei Hover/Selektion ihr gestricheltes Kontrollpolygon mit Punktmarkern.

### Ellipse (M23–M25)

Eine Ellipse besteht aus genau **3 Definitionspunkten** — Zentrum,
Hauptscheitel, Nebenscheitel — mit Inventors Grip-Semantik: Zentrum
verschiebt die ganze Ellipse, Hauptscheitel rotiert/streckt sie
(Nebenscheitel folgt senkrecht), Nebenscheitel ändert nur die
Nebenausdehnung. Die Kurve ist scher-immun (der Nebenscheitel zählt nur mit
seiner Komponente senkrecht zur Hauptachse) und wird bei jedem Edit
kanonisiert. Snap: Zentrum + alle vier Quadranten.

Beim Commit entstehen die beiden **Achsen als echte Mittellinien-Entities**
(gestrichelt gerendert, aber vollwertig: verschiebbar, bemaßbar,
constraintbar), an die Ellipse gebunden über coincident(Achsende, Scheitel)
und midpoint(Zentrum auf Achse) — Achse ziehen treibt die Ellipse durch den
Solver und umgekehrt. In der Bemaßung zählt die Ellipse als Kurve
(Bezugspunkt = Zentrum): Ellipse+Linie → Abstand Zentrum↔Linie,
Ellipse+Punkt → Abstand zum Zentrum, Ellipse+Kreis/Ellipse →
Zentrum↔Zentrum.

### Mittellinien-Stil (M25)

Jede Linie kann per Ribbon (Format → Centerline) in den Mittellinien-Stil
geschaltet werden — Inventors Format-Toggle. Der Stil ist reine Darstellung
(gestrichelt); die Linie bleibt voll editierbar und überlebt Speichern/Laden
und jeden Edit (Sidecar `<name>.styles.json`, analog zu den Spline-Tags).

### Bemaßung — Bedienung (M24/M25)

- **Platzierungsregionen wie Inventor:** Bei zwei Punkten entscheidet die
  Position der Vorschau — über/unter der Box → horizontale Bemaßung,
  links/rechts → vertikale, entlang der Normalen → fluchtend. Beim Ziehen
  wechselt der Typ live durch.
- **Vertex vor Kante:** Ein Klick auf einen Punkt gewinnt immer gegen die
  darunterliegende Entity; Linienlänge = Klick auf den Linienkörper.
- **Inline-Werteingabe:** Der Wert wird in einem Textfeld direkt AUF der
  Bemaßung eingegeben — öffnet nach dem Platzieren und beim Tippen auf eine
  bestehende Bemaßung. Enter committet, Esc bricht ab, Klick daneben
  committet (die Bemaßung bleibt, wie in Inventor). Einheiten mm/cm/m bzw.
  Grad.
- **Projizierter Center Point:** Der Ursprung ist ein vollwertiges
  Bemaßungs- und Constraint-Ziel (Punkt↔Ursprung, Linie↔Ursprung usw.).

### DOF-Färbung wie Inventor (M26)

Jede Entity wird nach dem Zustand ihres **Trägers** gefärbt — Inventors
bestätigte Semantik (Autodesk-Forum, Antwort des Inventor-Teams): eine Linie
wird weiß, sobald ihre unendliche Trägergerade — Richtung UND senkrechte
Lage — fixiert ist, auch wenn noch keine Längenbemaßung existiert. Der noch
verschiebbare Endpunkt ist eine eigene Entity (Grips/DOF-Pfeile) und hält
die Linie nicht mehr violett. Kreise/Bögen: Träger = Zentrum + Radius (freie
Bogen-Endwinkel zählen nicht). Gewöhnliche Polylinien (Rechtecke, Polygone)
werden **pro Kante** gefärbt — ein Rechteck wird Kante für Kante weiß, wie
Inventors vier einzelne Linien, statt erst mit dem letzten Vertex.
Splines/Ellipsen bleiben eine Kurve: weiß, wenn alle Definitionspunkte fest
sind. Unten rechts im Viewport steht Inventors Status: „N dimensions
needed" bzw. „Fully Constrained".

### Diagnose-Log (M15)



Die App schreibt ein ausführliches Log ins Documents-Verzeichnis, sichtbar in der
**Dateien-App → Auf meinem iPad → ipadprocad → logs → `ipadprocad_log.txt`**
(`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`). Enthält
Drag-Lifecycle mit vollständigen Sketch-Dumps, Solver-Pfad (slvs vs. LM,
Verify-Residuum, Fallback-Gründe), jede Exception mit Stacktrace und den
Commit-SHA des Builds. WARN/ERROR werden sofort synchron geflusht, überleben also
auch einen harten Crash.

### M5 im Detail

**Frontend (`frontend/`, komplett neu):** 1:1-Flutter-Port des finalen
HTML-Mocks — Inventor-Sketch-Tab-Ribbon (Panels: Layer, Create, Project
Geometry, Pattern, Constrain, Insert, Format, Modify + Exit/Finish),
Flyout-Menüs mit exakten Einträgen, Model-Browser (Origin-Expander,
Layer-Zeilen mit Kontextmenü/Doppelklick-Edit, Inventor-Highlight),
Layer-Edit-Modus (graue Referenz-Achsen + gelber projizierter Center Point),
Home-View mit Recent-Karten und untere Tab-Leiste. Icons: die
handgezeichneten Mock-SVGs verbatim via `flutter_svg`.

**Echtes Zeichnen über das Backend:** Line, Circle (Center Point), Rectangle
(Two Point) und Arc (Three Point) laufen real über die QCAD-C-API (Dart-FFI);
gerendert wird aus dem QCAD-Dokument (`qcad_entity_ids` /
`qcad_entity_geometry`). Alle übrigen Ribbon-Funktionen sind wie im Mock
sichtbar, aber noch ohne Funktion. Ohne gelinkte Libs (z. B. Desktop-Dev)
greift ein ehrlicher Dart-Fallback; der Start-Marker meldet
`DART SMOKE: PASS (backend=qcad-ffi|dart-fallback)`.

**Persistenz:** DXF pro Skizze + generiertes Preview-PNG im
App-Documents-Verzeichnis (Autosave bei Finish, Tab-Schließen, Home); die
Recent-Karten zeigen echte gespeicherte Skizzen.

**Eingabe (erste Version):** Maus + Keyboard am iPad; Trackpad-2-Finger-Pan
und Pinch-Zoom sind integriert, Scrollrad zoomt, Esc bricht das aktive Tool
ab. Touch-Gesten auf dem Screen folgen später.

**Test-IPA:** Der CI-Job `m5-flutter-ipa` baut die App gegen den QCAD-Core
und lädt das unsignierte IPA als Artefakt **`ipadprocad-unsigned-ipa`** hoch
(Retention 3 Tage; bei Ablauf Workflow einfach neu laufen lassen).
Installation aufs iPad per Sideloadly oder AltStore (re-signiert mit eigener
Apple-ID). Verifiziert im CI: `M5 LINK CHECK: PASS` und alle 14
`_qcad_*`-Symbole exportiert im Runner-Binary.

Details, CI-Fallstricke (Qt-Static-Link via `ninja -t commands`,
`exported_symbols_list`, pipefail-Fallen) und offene Punkte für M6:
siehe `HANDOFF.md`.

## Architektur

```
backend/slvs/          Vendortes SolveSpace libslvs (Constraint-Solver) + C-Shim
  shim/                Flache C-API (ein slvs_solve()) für Dart-FFI
  tests/               Host-Test-Gate (shim_test.c) — läuft in der CI
backend/qcad-core/     Vendorter, headless-tauglicher QCAD-Core (C++, GPLv3)
  src/core/            Dokumentmodell, Geometrie/Mathematik, RSpatialIndexSimple
  src/entity/          Entity-Typen (Linie, Kreis, Bogen, Polylinie, Spline, …)
  src/operations/      Modifikations-/Transformationsoperationen
  src/io/dxf/          DXF-Import/-Export (auf dxflib)
  src/3rdparty/dxflib/ DXF-Low-Level-Bibliothek (statisch)
  src/capi/            C-ABI-Wrapper (extern "C") für FFI — Ziel libqcadcapi.a
  bindings/dart/       Kanonische Dart-FFI-Bindings + Beispiel
frontend/              Flutter-App (1:1-Port des UI-Mocks, FFI-Anbindung,
                       Zeichnen/Speichern/Laden/Previews) — siehe frontend/lib/
ci/                    CI-Hilfsskripte (parse_link_txt.py: Linkzeile -> Xcode)
.github/workflows/     CI: Core-Build (iOS), Sim-Logiktest, Flutter-IPA-Build
```

`gui`, `run` sowie der JS-Actionlayer (`scripts/`) aus dem QCAD-Upstream sind
bewusst nicht enthalten; die GUI ist die eigene Flutter-App in `frontend/`.

## Lizenz

Der vendorte QCAD-Core steht unter GPLv3 (`backend/qcad-core/LICENSE.txt`,
`gpl-3.0.txt`, `gpl-3.0-exceptions.txt`), `dxflib` unter GPLv2+. Die
Lizenzkompatibilität mit der finalen App-Distribution ist vor Produktiv-Release
zu klären.
