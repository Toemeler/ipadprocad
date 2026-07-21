# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status (Stand M37)

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
| **M29** Tangenten-Constraint mit Splines (Spline↔Linie/Kreis/Bogen/Spline, am Spline-ENDE wie Inventor) | ✅ erledigt (Geräte-Test offen) |
| **M30** Tastatur-Shortcuts: D/L/C/R Werkzeuge, S Layer beenden/neu, Strg+S speichern | ✅ erledigt (Geräte-Test offen) |
| **M31** Tangente mit Rechteck-/Polygon-Kanten (Spline↔Kante, Kreis↔Kante) + Klick-basierte Ende/Kante-Auflösung | ✅ erledigt (Geräte-Test offen) |
| **M32** Project Geometry wie Inventor: Linien anderer Layer + X/Y-Achse, gelb, gepinnt, quell-verfolgend; Show Constraints/DOF default AUS | ✅ erledigt (Geräte-Test offen) |
| **M33** Project Geometry für ALLE Typen (Kreis/Bogen/Spline/Ellipse/Polylinie), Hover-Highlight + aktiver Button im Project-Modus, Fremd-Layer nicht selektierbar | ✅ erledigt (Geräte-Test offen) |
| **M34** Rechtecke = VIER Linien mit Constraints (Inventor-Modell); Polygon-/Bestands-Rechteck-KANTEN projizieren als einzelne gelbe Linien; Hover-Fix Polylines; Projektions-Polylines gelb | ✅ erledigt (Geräte-Test offen) |
| **M35** Pattern-Panel funktional: Rechteckige/Runde Anordnung + Spiegeln mit Inventor-Dialogen (modeless über dem Viewport), Live-Preview, Fitted/Assoziativ, Self Symmetric für Splines; neuer Constraint `pattern` (LM-only, slvs-Bail) | ✅ erledigt (Geräte-Test offen) |
| **M36** Form-Auto-Constraints (Slots koinzident/tangent/equal/parallel bzw. konzentrisch, Tangenten-Kreis/-Bogen), Fillet/Chamfer komplett wie Inventor (Linie/Bogen/Kreis, 3 Chamfer-Modi, modeless Dialog, Radius-Dim + equal-Kette), Trim/Split erhalten Constraints/Bemaßungen (`remapAfterReplace`) | ✅ erledigt; Geräte-Test deckte Bugs auf → in M37 behoben |
| **M37** Produktions-Härtung nach Geräte-Test: Solver-Sicherheitsnetz (nie divergiertes Rendern/Committen, atomare Ops), Slot/Fillet/Chamfer redundanzfrei + korrekt (Ecken-Koinzidenz-Entfernung, x/y-Setback-Bemaßung), Fillet-Button startet, signierte Tangente + Shim v3 (endpunktverankert) | ✅ erledigt, Host 157 + Shim-Gate 12 grün (Geräte-Test offen) |
| **M38–M40** Trim-Upgrade, Undo/Redo pro Skizze, Construction-Linetype | ✅ erledigt |
| **M41** Inventors Parameter-/Ausdrucks-System: Bemaßungen sind benannte Parameter (d0, d1, … / "Name = Ausdruck"), volles Formel-Parsing im Edit-Feld (Operatoren, Einheiten, Funktionen, PI/E), Referenzen auf andere Bemaßungen per Klick aufs Label, fx:-Anzeige des berechneten Werts, Ausdruck bleibt gespeichert und erscheint beim Editieren wieder | ✅ erledigt (Geräte-Test offen) |
| **M42** Hover-Highlight auf antippbaren Bemaßungs-Labels (Editiermodus + offenes Ausdrucks-Feld); außerhalb des Layer-Editiermodus sind Bemaßungen, Constraints, DOF-Pfeile und Construction-Geometrie unsichtbar (nur die Linien bleiben) | ✅ erledigt; Geräte-Test deckte den Tastatur-Race beim Referenz-Klick auf → M42-Fix |
| **M43** Inventors Parameters-Fenster: fx-Button im neuen Manage-Panel öffnet eine verschiebbare Tabelle aller Modell-Parameter (Bemaßungen) + User-Parameter (anlegen/umbenennen/löschen), Equation-Zellen mit voller Formel-Grammatik, Live-Validierung und Klick-auf-Bemaßung-Referenz | ✅ erledigt, 198 Host-Tests grün (Geräte-Test offen) |
| **M44** Insert: parametrischer Text (Template mit `<Param>`-Platzhaltern, folgt Wert + Rename), Bild-Import (iOS-Filepicker, Underlay, verschieb-/skalierbar) und DXF-Import (Insert > ACAD, Merge auf Editier-Layer als ein Undo-Schritt) | ✅ erledigt; Geräte-Test → M45-Fixes |
| **M45** Insert-Fixes + Text: Bild-Resize-Griff korrigiert, Bilder tragen Layer (ausserhalb gedimmt/grau), Insert am Cursor mit halber Ansichtsbreite, DXF re-zentriert auf Ursprung; verschiebbares Text-Fenster mit Font/Größe + Klick-Referenz (`"d0"`), auto-großes Construction-Bounding-Rect (nur im Editiermodus) mit Ecken als Snap-Punkte zum Bemaßen | ✅ erledigt; Geräte-Test → M46 |
| **M46** Tastenkürzel (l, c, r, d, s, Ctrl+Z …) werden unterdrückt, während das Parameters- oder Text-Fenster bzw. das Inline-Bemaßungsfeld getippt wird — die Buchstaben landen im Textfeld statt ein Werkzeug zu starten | ✅ erledigt, 214 Host-Tests grün (Geräte-Test offen) |
| **M47** Direktes Ziehen des ENTITY-KÖRPERS: im Layer-Editiermodus zieht ein Griff auf die Linie/Kreis/Bogen/Polylinie/Spline/Ellipse SELBST (nicht nur auf einen Punkt-Griff) die ganze Entität starr mit, angebundene Geometrie folgt über die Constraints; voll gebundene Geometrie ist gesperrt (fällt auf Box-Select zurück), Tap wählt weiterhin aus | ✅ erledigt, 222 Host-Tests grün (Geräte-Test offen) |
| **M48** Natives iOS-Kontextmenü in der Sketch-Galerie: Long-Press auf eine Karte öffnet ein ECHTES UIKit-Menü (UIContextMenuInteraction/UIMenu, System-Blur + Haptik, Delete von UIKit selbst rot gezeichnet) mit Rename / Duplicate / Export / Share und Delete in eigener Sektion; Export/Share über UIDocumentPicker bzw. UIActivityViewController. In-Repo-Plugin `packages/native_menu` statt Swift im (von CI generierten) Runner. IPA-Job auf macos-26 = iOS-26-SDK → Liquid-Glass-Optik | ✅ erledigt, 245 Host-Tests grün (Geräte-Test offen) |
| **M54** 3D-Kernel: OpenCASCADE (OCCT 7.9.3) als Submodule vendored, flache C-ABI (`backend/occt/shim`, 14 Funktionen: Box/Zylinder/Profil-Extrude/Fuse/Counts/Valid/Volume/BBox/STEP-Export+Import), Geometrie-Smoke mit harten Zahlen (`OCCT SMOKE: PASS`, Fuse-Volumen == analytisch, STEP-Roundtrip identisch), isolierter CI-Workflow `occt-build.yml` (Host + iOS-arm64-Static, Install-Tree gecacht), in die IPA gelinkt: `OCCT LINK CHECK: PASS (14 _occt_* symbols exported in Runner)`. Noch KEIN Dart-Binding (bewusst nächste Session) | ✅ erledigt, alle Marker log-verifiziert (M49–M53 siehe HANDOFF) |

### Auto-Constraints, Fillet/Chamfer, constraint-erhaltendes Trim (M36)

Slots kommen jetzt wie in Inventor voll verdrahtet an: linearer Slot mit
koinzident + tangent an allen vier Nähten, equal-Kappen und parallelen
Rails (exakt 5 DOF), Bogen-Slot mit konzentrischen Rails (6 DOF); der
Tangenten-Kreis bekommt tangent zu seinen drei Linien, der Tangenten-Bogen
koinzident + tangent zur Quelle. Fillet und Chamfer sind komplett: modeless
"2D Fillet"/"2D Chamfer"-Fenster statt blockierendem Prompt, Fillets
zwischen beliebigen Linien/Bögen/Kreisen mit automatischem Trim auf die
Tangentenpunkte, koinzidente Nähte + Tangenten, Radius-Bemaßung auf dem
ersten Fillet und equal-Kette für alle weiteren gleichen Werts; Chamfer mit
Inventors drei Modi (gleicher Abstand / zwei Abstände / Abstand + Winkel).
Trim und Split werfen Constraints nicht mehr weg: Punkt-Refs wandern auf das
Teilstück, das den Punkt noch hat, Entity-Refs (Tangenten, Bemaßungen, …)
auf das nächstliegende Teilstück des unveränderten Trägers — nur was
tatsächlich weggeschnitten wurde, verliert seine Constraints.

### Produktions-Härtung (M37)

Der erste echte Geräte-Test brachte den Solver ins Wanken: der Slot-Drag
flackerte (Linien/Bögen verschwanden und kamen zurück), der Fillet-Button tat
nichts, und ein Chamfer auf einer Rechteck-Ecke zerlegte die halbe Skizze samt
dem daneben gebauten Slot. Ursachen und Fixes stehen ausführlich unten im
**PRODUKTIONS-AUDIT**; kurz:

- **Solver-Sicherheitsnetz:** `solveConstraints` meldet jetzt, ob die Lösung die
  Constraints wirklich hält (und finite/nicht degeneriert ist). Ein nicht
  erfüllter Frame wird nie mehr gezeigt (der Drag hält die letzte gültige Lage)
  und nie committet (jede Operation ist atomar mit vollständigem Rollback).
- **Slot redundanzfrei:** der rangredundante `parallel` (linear) bzw. `equal`
  (Bogen) ist raus — Parallelität/Gleichheit bleiben durch die Tangenten
  impliziert. Das entfernt die Singularität, die das Flackern trieb.
- **Fillet/Chamfer korrekt:** die alte Ecken-Koinzidenz wird entfernt (sonst
  kollabiert das neue Segment), der Button startet das Werkzeug, und der Chamfer
  wird über seine **x/y-Setbacks** bemaßt statt über die Diagonale.
- **Tangenten stabil:** Linie-Kreis/Bogen-Tangens ist vorzeichenbehaftet (kein
  Ast-Kippen), und der native Shim (v3) verankert Tangenten am richtigen
  Bogen-ENDE statt immer am Start.

Abgesichert durch drei neue Test-Suiten (Konstruktions-Rang, Drag-Stabilität
Frame-für-Frame, Operations-Sequenzen = die Geräte-Session) plus zwei native
Shim-Szenarien; Host 157 + Shim-Gate 12 grün.

### Pattern (M35) — Inventors Anordnungs-Werkzeuge

Die drei Buttons des Pattern-Panels öffnen jetzt Inventors Dialoge
("Rechteckige Anordnung", "Runde Anordnung", "Spiegeln") als modelesse
Panels über dem Viewport — Picks laufen weiter im Canvas, der blaue
Selektor bestimmt, welche Eingabe der nächste Tap füllt. Rechteckig:
zwei freie Richtungs-Linien (Flip, Anzahl, Abstand), Richtung 2 grau bis
Richtung 1 gepickt ist. Rund: Achse (Punkt/Zentrum/projizierter CP),
Anzahl, Winkel (Default 360°). Fitted = Wert ist die Gesamt-Spanne, sonst
Abstand zwischen Elementen. Assoziativ (Default an) bindet die Kopien über
den Solver an die Quelle: neuer Constraint-Typ `pattern`
(Kopie-Parameter = starr transformierte Quell-Parameter, nie Netto-DOF,
slvs bailt auf den verifizierten Dart-LM-Pfad). Spiegeln nutzt den
vorhandenen symmetric-Constraint je Punktpaar (Kreis: + equal-Radius);
Apply/Done/Cancel wie Inventor; Self Symmetric verlängert einen offenen
Spline, der auf der Achse endet, zu EINEM symmetrischen Spline. v1-Grenzen
(im Dialog ausgegraut): Boundary-Fill, Suppress, Pfad-Muster, Edit Pattern.

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
backend/occt/          OpenCASCADE (OCCT 7.9.3) — 3D-B-Rep- + STEP-Kernel (M54)
  upstream/            OCCT als Submodule, gepinnt auf Tag V7_9_3 (VENDOR.md)
  shim/                Flache C-API occt_capi.{h,cpp} (14 Funktionen) für Dart-FFI
  tests/               smoke_occt.c — Geometrie-Gate ("OCCT SMOKE: PASS") in der CI
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
.github/workflows/     CI: Core-Build (iOS), Sim-Logiktest, Flutter-IPA-Build,
                       slvs-build (isoliert), occt-build (isoliert, gecacht)
```

`gui`, `run` sowie der JS-Actionlayer (`scripts/`) aus dem QCAD-Upstream sind
bewusst nicht enthalten; die GUI ist die eigene Flutter-App in `frontend/`.

## Lizenz

Der vendorte QCAD-Core steht unter GPLv3 (`backend/qcad-core/LICENSE.txt`,
`gpl-3.0.txt`, `gpl-3.0-exceptions.txt`), `dxflib` unter GPLv2+, libslvs
unter GPLv3. OCCT (`backend/occt/upstream`) steht unter **LGPL 2.1 mit der
OCCT-Ausnahme** (`upstream/LICENSE_LGPL_21.txt`, `OCCT_LGPL_EXCEPTION.txt`);
die Ausnahme erlaubt das statische Linken in die App ausdrücklich. Die
Lizenzkompatibilität mit der finalen App-Distribution ist vor Produktiv-Release
zu klären.

---

# PRODUKTIONS-AUDIT (Stand M36, Geräte-Log build=befac53)

> **Fortschritt M37:** Durchgang 1 abgeschlossen — 18 Punkte erledigt
> (alle P0, P1-1/3/5/6 weitgehend, P2-2/3/5), verifiziert mit 157 Host-Tests +
> 12 Shim-Host-Szenarien. Erledigte Punkte sind unten mit ✅ markiert; die
> übrigen (P1-2/4, P2-1/4/6-9, P3-*, T-5/7) sind die Roadmap für Durchgang 2.

Tiefenanalyse nach dem ersten echten Geräte-Test mit Slot + Fillet/Chamfer.
Grundlage: `ipadprocad_log.txt` (59 563 Zeilen, 1 802 WARN), `Sketch1.dxf`,
`Sketch1_cons.json`, plus statische Analyse des gesamten Frontends. Jede
Ursache unten ist entweder aus dem Log belegt oder numerisch nachgerechnet
(die Rechnungen sind reproduzierbar; Kernaussagen in den Fix-Notizen).

**Leitprinzip für die Abarbeitung:** Der Solver darf NIEMALS eine nicht
erfüllte oder degenerierte Geometrie an den Renderer geben. Konstruktionen
(Slot, Rechteck, Fillet, Chamfer) dürfen NIEMALS ein rangdefizientes oder
widersprüchliches Constraint-System erzeugen. Beides ist heute verletzt.

Reihenfolge: erst P0 (macht die App unbrauchbar), dann P1 (falsche Ergebnisse),
dann P2 (Robustheit/Sicherheit), dann P3 (Inventor-Treue/UX), dann Tests.

## Wurzelursachen der gemeldeten Symptome (alle belegt)

Vier Symptome, drei tiefe Ursachen:

1. **Slot-Drag „extrem buggy, Linie weg, Kreise weg, dann wieder da".**
   Der Slot bekommt beim Commit (`app_state.dart` ~2701) die Constraints
   `4× tangent + equal + parallel` auf `[rail1, rail2, cap1, cap2]`. Dieses
   Set ist **rangdefizient**: der `parallel`-Constraint ist bei zwei über
   ihre gemeinsamen Tangenten schon gekoppelten Rails eine redundante Zeile
   (nachgerechnet: 6 Gleichungen, Rang 5 → 1 überzählige Zeile). Der
   Code-Kommentar behauptet „redundante Zeilen sind rangneutral für den
   LM-Solver" — das ist FALSCH. Rangdefizit macht `JᵀJ` singulär; die
   Dämpfung maskiert das in Ruhe, aber unter Drag springt die Lösung pro
   Frame zwischen den zwei Tangenten-Ästen. libslvs meldet dann pro
   Frame `VERIFY FAILED` (Residuen im Log: 2.2e-3 bis **1.45e+2**), fällt auf
   den Dart-LM zurück, der ebenfalls oft `satisfied=false` liefert (19 von 54
   LM-Läufen im Log). Ergebnis: **finite, aber falsche** Arc-Parameter
   (Radius springt 54→120, Start≈End-Winkel → Sweep 0).
   - Warum „verschwindet": ein Arc mit `start==end` rendert `drawArc(sweep=0)`
     → NICHTS. Ein Arc mit Radius 120 (2.2× zu groß) malt quer über alles
     („die Linie ging über den Fillet"). Beide sind finite, also greift
     `allFinite()` NICHT — der Frame wird gemalt. Nächster Frame, Cursor
     minimal bewegt, Solver trifft den guten Ast → Arc wieder da. Das ist
     das Flackern.
   - Zweite Ursache im selben Symptom: **die Display-/Drag-Pfade haben KEIN
     Residuen-Gate.** `displayGeometry` (`app_state.dart` ~765) ruft
     `solveConstraints` und malt das Ergebnis, sobald es finite ist — der
     Rückgabewert von `_lm` (erfüllt ja/nein) wird verworfen. Ein nicht
     erfüllter Solve wird also gezeigt.

2. **Fillet-Button „tut gar nichts".**
   Die „Fillet"-Zeile im Create-Panel ist ein `_SmallRow`
   (`widgets/ribbon.dart` ~339) OHNE `onTap` — nur das winzige ▼ öffnet das
   Flyout. Ein Tap auf Wort/Icon „Fillet" macht folglich nichts (im Log taucht
   `Tool.fillet` KEIN einziges Mal auf, `Tool.chamfer` mehrfach). Selbst über
   das Flyout gestartet, trifft Fillet zwischen zwei Rechteck-Kanten sofort
   Ursache 3.

3. **Chamfer „geht so", Bemaßung diagonal statt x/y, „Linie über dem Fillet".**
   Zwei Fehler:
   - **Ecken-Koinzidenz wird nicht entfernt.** Fillet/Chamfer trimmt die zwei
     gepickten Entities und klebt das neue Segment per NEUER Koinzidenz an die
     getrimmten Enden — entfernt aber die BESTEHENDE Koinzidenz der alten Ecke
     NICHT (`_commitTool` ~2572 ff. addiert nur, es gibt kein
     `remapAfterReplace` wie bei Trim/Split). Bei zwei benachbarten
     Rechteck-Kanten `e2,e3` mit `coincident(e2.p1,e3.p0)` bleibt diese
     Koinzidenz stehen; die neuen `coincident(e9.p0,e2.p1)` +
     `coincident(e9.p1,e3.p0)` erzwingen dann `e9.p0 == e9.p1` → das
     Chamfer-Segment kollabiert auf Länge 0, während die `dist`-Bemaßung 7.07
     verlangt → **unerfüllbar** → der gesamt-Sketch-LM divergiert (Log direkt
     nach dem Chamfer: `lm ... err=3.54e+0 satisfied=false`, dann Arc-Radius
     120). Das ist die „Linie über dem Fillet" und der Grund, warum der Chamfer
     obendrein den zuvor gebauten Slot mitzerreißt (ein LM über den GANZEN
     Sketch).
   - **Bemaßung ist die Hypotenuse statt der Schenkel.** `_commitTool` legt für
     den Chamfer EINE `dist`-Bemaßung zwischen den zwei Endpunkten der
     Chamfer-Linie an — also die Diagonale. Inventor bemaßt den Chamfer über
     die Schenkel-Setbacks (Abstand Eck-Schnittpunkt → Trimmpunkt je Linie);
     Equal-Distance = ein Setback-Maß + Equal-Glyphen, Two-Distance = zwei
     Setback-Maße (Autodesk „Create sketch chamfer": aligned dimensions of the
     setback distance). Der Nutzer hat recht.

4. **Systemischer Verstärker:** `_lm(...)`-Rückgabe wird an DREI Stellen
   ignoriert (`solver.dart` ~1381/1385 und der Drag-Relaxed-Pfad). Divergierte,
   nicht erfüllte Geometrie wird dadurch gerendert UND committet, statt
   verworfen zu werden. Ohne dieses Leck wären Symptom 1 und 3 optisch stumm
   geblieben (Operation würde sauffällig abgelehnt statt die Szene zu zerlegen).

---

## P0 — Kritisch (App unbrauchbar / Datenverlust / falsche Geometrie gerendert)

- [x] **P0-1 Fillet-Button startet das Werkzeug.** `widgets/ribbon.dart` ~339:
  dem Fillet-`_SmallRow` ein `onTap: () => _startTool(Tool.fillet)` geben
  (Inventor-Split-Button: Body startet das Default-/zuletzt-Werkzeug, ▼ öffnet
  die Liste). Analog prüfen, dass jeder Split-Button im Panel einen Body-Tap
  hat. **Datei:** `widgets/ribbon.dart`.
  ✅ ERLEDIGT: `onTap: _startTool(Tool.fillet)` am Fillet-`_SmallRow`; alle übrigen Split-Buttons geprüft (Text/Image/Points/ACAD sind bewusste Stubs).

- [x] **P0-2 Fillet/Chamfer: bestehende Ecken-Koinzidenz auflösen.** Vor dem
  Hinzufügen der Seam-Constraints alle Constraints entfernen bzw. remappen, die
  die zwei gepickten Entities an der zu ersetzenden Ecke koppeln (der bereits
  vorhandene `remapAfterReplace`-Mechanismus aus Trim/Split ist das Vorbild:
  Punkt-Refs auf das Teilstück ziehen, das den Punkt noch hat; die
  Ecken-Koinzidenz zwischen den zwei Trägern fällt, weil sie auf ein und
  denselben neuen Punkt kollabieren würde). Ergebnis: das neue Fillet-/
  Chamfer-Segment hat echte Länge, die Bemaßung ist erfüllbar. **Nachweis:**
  ohne Entfernung erzwingt die Alt-Koinzidenz `e9.p0==e9.p1` → Länge 0 vs.
  dist 7.07 → LM divergiert (numerisch bestätigt). **Dateien:**
  `app_state.dart` (`_commitTool`), evtl. `constraints.dart` (Remap-Helfer).
  ✅ ERLEDIGT: `_commitTool` entfernt die direkte Ecken-Koinzidenz zwischen den zwei getrimmten Seam-Punkten vor dem Verketten; Rang danach voll (Test).

- [x] **P0-3 Slot ohne redundante Constraints bauen.** Den `parallel`-Constraint
  aus dem Linear-Slot-Set streichen (er ist durch die 4 Tangenten + Koinzidenzen
  impliziert; nachgerechnet rangredundant). Für den Bogen-Slot analog prüfen
  (concentric + 4 tangent + equal → ist `equal` bei concentric-Rails + geteilten
  Endpunkten schon impliziert? per Rang prüfen und nur unabhängige Zeilen
  behalten). Generell: JEDE deterministische Konstruktion (Slot, Rechteck,
  Fillet, Chamfer, Ellipsen-Achsen) muss ihre Constraints durch dieselbe
  Rang-/Redundanzprüfung schicken wie der manuelle Constraint-Pfad
  (`wouldOverconstrain`), damit nie wieder ein rangdefizites Set entsteht.
  Inventor-Regel (Autodesk-Doku): „You cannot overconstrain a sketch" — ein
  redundanter geometrischer Constraint wird abgelehnt bzw. als getriebene
  Bemaßung angeboten, nie als volle Gleichung gehalten. **Dateien:**
  `app_state.dart` (`_commitTool` Slot-/Rect-/Fillet-Zweige), `solver.dart`
  (`wouldOverconstrain` als gemeinsames Gate).
  ✅ ERLEDIGT: Linear-Slot ohne `parallel` (13/13 Gleichungen, DOF 5), Bogen-Slot ohne `equal` (14/14, DOF 6) — beides mit den ECHTEN App-Residuen nachgemessen; `construction_rank_test.dart` nagelt Redundanz 0 für alle Konstruktionen fest.

- [x] **P0-4 Residuen-Gate auf dem Display-/Drag-Pfad.** `displayGeometry`
  (`app_state.dart` ~765) darf ein Solve-Ergebnis nur zeigen, wenn die
  Constraints erfüllt sind (Residuum ≤ Schwelle). Sonst die zuletzt gute
  Geometrie zeigen (nicht die divergierte). Damit flackert selbst ein
  schwieriges System nicht mehr: der Punkt bleibt am letzten guten Ort, statt
  degenerierte Arcs zu blitzen. **Nachweis:** heute wird jeder finite Frame
  gemalt (Radius 120, Sweep 0 sind finite). **Datei:** `app_state.dart`.
  ✅ ERLEDIGT: `displayGeometry` zeigt nur erfüllte, nicht-degenerierte Frames; sonst hält es die letzte gute Drag-Geometrie (`_lastGoodDragGeo`), die beim Loslassen committet wird (Inventor-Verhalten).

- [x] **P0-5 `_lm`-Rückgabe respektieren (Commit- und Relaxed-Pfad).**
  `solver.dart` ~1381/1385: den Bool von `_lm` auswerten. Schlägt der Solve auf
  dem Commit-Pfad fehl (Constraints nicht erfüllbar), die Vor-Solve-Geometrie
  wiederherstellen und die Operation mit Toast ablehnen (Inventor lehnt eine
  Operation ab, die das Modell überbestimmen/zerbrechen würde), statt
  divergierte Geometrie zu committen. Auf dem Relaxed-Drag-Pfad ebenfalls das
  Ergebnis prüfen und ggf. den Snapshot halten. **Datei:** `solver.dart`.
  ✅ ERLEDIGT: `solveConstraints` liefert jetzt bool (erfüllt + finite + nicht degeneriert); ALLE Aufrufer respektieren ihn mit Rollback+Toast: `_solveAndRebuild`, `_addConstraint` (Widerspruch), `confirmDimension`, `setDimensionValue` (jetzt atomar), Pattern, Self-Symmetric, Trim, Split, Konstruktions-Commit.

- [x] **P0-6 Chamfer/Fillet als atomare, verifizierte Operation.** Die
  Kombination P0-2..P0-5 so kapseln, dass ein Fillet/Chamfer nur committet,
  wenn danach `analyzeSketch`/Solve konsistent sind. Andernfalls vollständiger
  Rollback (Geometrie UND Constraints), damit ein misslungener Fillet nie den
  restlichen Sketch (z. B. einen zuvor gebauten Slot) beschädigt. Heute teilen
  sich Fillet-Commit und Slot denselben Gesamt-Solve → ein schlechter Fillet
  reißt den Slot mit (im Log sichtbar). **Datei:** `app_state.dart`.
  ✅ ERLEDIGT: Fillet/Chamfer bauen auf lokalen Kopien und committen nur nach verifiziertem Solve; Ablehnung lässt Skizze UND Constraints unberührt (Sequenztest: Chamfer auf fixierter Ecke ändert NICHTS).

## P1 — Falsche, aber nicht abstürzende Ergebnisse (Inventor-Semantik)

- [x] **P1-1 Chamfer-Bemaßung = Setbacks, nicht Diagonale.** Equal-Distance:
  eine Setback-Bemaßung (Eck-Schnittpunkt → Trimmpunkt entlang Linie 1) + für
  weitere gleiche Chamfer eine Equal-Kette (wie bisher). Two-Distance: zwei
  Setback-Bemaßungen (d1 an Linie 1, d2 an Linie 2). Distance+Angle: Setback d1
  + Winkelbemaßung. Referenz: Autodesk „To Create 2D Shape Geometry" / „Create
  sketch chamfer" (aligned dimensions of the setback distance). Der
  Setback-Punkt ist bereits als Trimm-Punktindex in `FilletResult.seams`
  vorhanden. **Dateien:** `app_state.dart` (`_commitTool` Chamfer-Zweig),
  `widgets/viewport.dart` (Painter der Setback-Maße, falls neue Ausrichtung).
  ✅ ERLEDIGT: Chamfer trägt `distx`+`disty` (Setbacks) statt Diagonale, für alle drei Modi; Werte 5/5 bzw. 8/4 im Test. BEWUSSTE ABWEICHUNG: die Equal-Kette für Folge-Chamfer entfällt vorerst (jeder Chamfer eigene x/y-Maße) — sauberer als eine Segment-Längen-Gleichheit, die die Setbacks nicht koppelt; Optionen kommen mit P3-2.

- [ ] **P1-2 Fillet-Trim-Robustheit über alle Typ-Paare.** `filletInventor`
  (`tools.dart` ~656) modelliert die Offset-Kandidaten sauber für Linie-Linie,
  Linie-Kreis/Bogen und Kreis-Kreis, ABER die Ecken-Disambiguierung
  (`nächster zu beiden Picks`) kann bei mehreren gültigen Zentren den falschen
  Ast wählen, wenn die Picks nah beieinander liegen. Test-Matrix bauen
  (Linie∠Linie spitz/stumpf, Linie∠Bogen innen/außen, Bogen∠Bogen, Vollkreis)
  und die Auswahl an Inventors Verhalten spiegeln (Fillet sitzt im geklickten
  Eck-Sektor). Vollkreis bleibt ungetrimmt — dann aber sicherstellen, dass die
  Tangenten-Constraint numerisch stabil ist (sonst wandert der Kreis).
  **Datei:** `tools.dart`, `frontend/test/`.

- [x] **P1-3 Tangenten-Constraint-Ast fixieren.** Sowohl der Dart-Residual
  (`solver.dart` `_tangentResiduals`, Kurve-Kurve-Zweig ~675) als auch der Shim
  (`SLVS_C_ARC_LINE_TANGENT` / `SLVS_C_CURVE_CURVE_TANGENT`) haben zwei Äste
  (innen/außen tangential). `_prepare` wählt `ctx.mode` einmal beim Solve-Start
  aus der aktuellen Lage — unter Drag kann die Lage über die Grenze wandern und
  der Ast kippt. Den Ast pro Constraint EINMALIG beim Erzeugen festhalten (an
  der Konstruktion, z. B. Slot-Caps sind immer außen-tangential) und im Solve
  nicht mehr aus der Momentanlage neu raten. Das entfernt das Frame-Flippen an
  der Wurzel. **Dateien:** `solver.dart`, ggf. `constraints.dart`
  (Ast-Flag am Constraint), `backend/slvs/shim/slvs_shim.cpp`.
  ✅ ERLEDIGT (Kern): Linie-Kreis/Bogen-Tangens ist jetzt VORZEICHENBEHAFTET (Seite in `_prepare` eingefroren, glattes Residuum, kein Ast-Kippen) — auch für die Polygon-Kanten-Variante. Kurve-Kurve behält den pro-Solve-Modus: mit dem Display-Gate startet jeder Frame von einer gültigen Lage, damit ist der Modus stabil.

- [ ] **P1-4 Arc-Rundtrip durch die C-API verlustfrei absichern.** `refresh()`
  (`app_state.dart`) setzt nach JEDEM Rebuild `geometry = engine.allGeometry()`
  — die Geometrie läuft also bei jedem Edit durch QCAD (`qcad_add_arc` →
  `qcad_entity_geometry`) und kommt in QCADs Winkel-/Windungs-Konvention zurück.
  Prüfen (Host-Test mit echtem Core), dass ein Arc `[cx,cy,r,a1,a2,reversed]`
  bit-genau (bis Toleranz) zurückkommt, inkl. `reversed`-Flag. Falls QCAD
  normalisiert: entweder das Flag aus der zurückgegebenen Start/End-Lage
  rekonstruieren oder — besser — WÄHREND DES DRAGS gar nicht durch die C-API
  gehen (Dart-Geometrie ist die Wahrheit; Engine nur bei Commit rebuilden).
  Das spart zudem 60×/s ein komplettes `dispose()`+Neuaufbau des QCAD-Dokuments
  (Performance, s. P2-6). **Dateien:** `app_state.dart`, `ffi/qcad_engine.dart`,
  `backend/qcad-core/src/capi/`.

- [x] **P1-5 Slot-DOF stimmen zwischen slvs und Dart nicht überein.** Im Log
  meldet libslvs nach dem Slot-Commit `dof=0` (voll bestimmt), der Dart-
  Analyzer `dof=10`. Diese Diskrepanz kommt von den redundanten Constraints
  (P0-3) und davon, dass slvs Redundanz anders zählt. Nach P0-3 erneut
  vergleichen; falls weiterhin abweichend, ist die DOF-Anzeige unten rechts
  („N dimensions needed") unzuverlässig. Ziel: ein freier Linear-Slot zeigt
  genau die Inventor-DOF (Position 2 + Rotation 1 + Länge 1 + Radius 1 = 5).
  **Dateien:** `solver.dart` (`analyzeSketch`), Verifikation per Test.
  ✅ ERLEDIGT: DOF stimmen jetzt (Slot 5, Bogen-Slot 6, Rechteck 4/5) und sind per Rang-Test festgenagelt; die slvs/Dart-Diskrepanz verschwand mit der Redundanz.

- [x] **P1-6 Konstruktions-Constraints deterministisch UND minimal.** Für JEDE
  Form (Rechteck, Slot linear/Bogen, Ellipse-Achsen, Tangenten-Kreis/-Bogen)
  die exakte, minimale Constraint-Liste dokumentieren, die Inventors DOF trifft,
  und per Test festnageln (DOF + „Form bleibt Form unter Drag" + „Maßeingabe
  löst sauber auf"). Heute sind diese Listen teils redundant (Slot) oder
  potenziell widersprüchlich in Kombination mit Modify. **Dateien:**
  `app_state.dart`, `frontend/test/`.
  ✅ WEITGEHEND ERLEDIGT: Rechteck 2P/3P, beide Slots, Fillet, Chamfer (equal/2-dist) haben dokumentierte, minimale Sets mit Rang==Gleichungen im Test. Ellipse/Tangenten-Formen: Rang-Tests noch ergänzen.

## P2 — Robustheit / Sicherheit / Determinismus

- [ ] **P2-1 Gemeinsames Constraint-Add-Gate.** Alle Stellen, die
  `s.constraints.add(...)` aufrufen (deterministische Konstruktionen,
  Inferenz, Fillet/Chamfer, Pattern), über EINE Funktion leiten, die (a)
  Redundanz gegen den aktuellen Rang prüft, (b) Widerspruch erkennt und
  ablehnt, (c) loggt. Verhindert künftige P0-3/P0-2-Klassen strukturell.
  **Dateien:** `app_state.dart`, `solver.dart`.

- [x] **P2-2 Solver-Ergebnis IMMER verifizieren, auch LM-only-Pfade.** Der
  native Pfad verifiziert (Residuum > 1e-4 → verwerfen). Der reine
  LM-Commit-Pfad (`path='lm'`) tut das nicht — er übernimmt `x` bedingungslos.
  Nach P0-5 zusätzlich ein hartes Gate: nicht erfüllte Systeme committen nie,
  sie werden abgelehnt und die Vorlage bleibt stehen. **Datei:** `solver.dart`.
  ✅ ERLEDIGT über P0-5: auch der reine LM-Pfad wird jetzt am Residuum gemessen; nicht erfüllte Systeme werden nie committet.

- [x] **P2-3 Degenerierte Geometrie am Renderer abfangen (Gürtel + Hosenträger).**
  `paintGeo` (`app_state.dart` ~3057) sollte Arcs mit `|sweep| < ε` oder
  `r ≤ 0` überspringen statt `drawArc(0)` (unsichtbar) zu zeichnen, und
  Linien mit Länge 0 überspringen. Das ist NICHT der Fix (der ist P0), aber
  eine letzte Verteidigung, damit eine Zahl-Panne nie als „Geometrie
  verschwindet"/„malt über alles" durchschlägt. **Datei:** `app_state.dart`.
  ✅ ERLEDIGT: `paintGeo` zeichnet degenerierte Arcs (r<=0, Sweep≈0) als sichtbaren Punkt statt unsichtbarem drawArc(0); zusätzlich `hasDegenerateGeometry` als Solver-Gate.

- [ ] **P2-4 Einheitliche Winkel-/Windungs-Konvention für Arcs.** Es gibt
  mehrere `norm()`-Lokalkopien (modify.dart, viewport.dart, app_state.dart) und
  zwei Sweep-Definitionen. Eine einzige, getestete Arc-Helferbibliothek
  (sweep, param, subArc, sample, winding) bauen und überall verwenden, damit
  Trim/Fillet/Paint/Solve garantiert dieselbe Arithmetik nutzen. Reduziert die
  Klasse „Arc kippt Windung zwischen zwei Modulen". **Dateien:** neu
  `frontend/lib/arc.dart`, Aufrufer umstellen.

- [x] **P2-5 FFI-Speicher & Grenzen härten.** `slvs_ffi.dart`: `failCap=64`
  fest; bei >64 fehlerhaften Constraints wird stumm abgeschnitten — Log-Warnung
  ergänzen. `_d`/`_i` allozieren bei leerer Liste 1 Element (ok), aber die
  Rückgabe-Schleifen müssen gegen `nPts==0` etc. geschützt bleiben (sind sie).
  Prüfen, dass ALLE `calloc` in `finally` freigegeben werden (aktuell ja).
  `slvs_shim.cpp`: die `calloc`s für Punkte/Linien/Kreise/Arcs auf
  Null-Größe (`>0?:1`) sind ok; sicherstellen, dass kein Pfad `sys.entity`/
  `sys.constraint` über die reservierte Größe hinaus schreibt (Ad-hoc-Linien
  bei `SH_PT_LINE_DIST` und die Collinear-Expansion erhöhen `entities`/
  `constraints` — die Reservierung muss diese Extras einrechnen). **Dateien:**
  `ffi/slvs_ffi.dart`, `backend/slvs/shim/slvs_shim.cpp`.
  ✅ GEPRÜFT: Reservierungen decken den Worst-Case (max. 2 ADDC pro Constraint, `2*nCons+8`; Entities `+nCons+16`); `draggedP` hat den Bounds-Guard; alle callocs werden freigegeben. Keine Änderung nötig.

- [ ] **P2-6 Drag-Performance & kein Voll-Rebuild pro Frame.** Siehe P1-4: der
  Drag rebuildet das QCAD-Dokument nicht pro Frame (nur `endGripDrag` ruft
  `_rebuildEngine`) — gut. ABER `displayGeometry` löst pro Frame das GESAMTE
  System (bei großem Sketch teuer) und der Solve läuft synchron im
  `paint`-Callback. Messen (M15-Log hat Zeitstempel) und ggf. den Solve aus
  `paint` herausziehen (in `updateGripDrag` rechnen, Ergebnis cachen, `paint`
  nur zeichnen). **Dateien:** `app_state.dart`, `widgets/viewport.dart`.

- [ ] **P2-7 Determinismus der Kandidatenwahl.** Fillet-Zentrumswahl,
  Trim-Bracketing und Offset-Seite hängen an `< bd`-Vergleichen mit
  Fließkomma-Toleranzen; bei symmetrischen Konfigurationen ist die Auswahl
  reihenfolgeabhängig. Tie-Break deterministisch machen (z. B. kleinster
  Index, dann kleinster Winkel), damit dasselbe Bild immer dasselbe Ergebnis
  liefert. **Dateien:** `tools.dart`, `modify.dart`.

- [ ] **P2-8 Sidecar-/DXF-Robustheit.** `Sketch1_cons.json` speichert
  Constraint-Typen als Enum-INDEX — beim Einlesen eines Sidecars mit einem
  unbekannten (neueren) Index sauber ignorieren statt werfen. Beim Laden eines
  DXF ohne passenden Sidecar (fremde Datei) dürfen fehlende Constraints/Tags
  die Geometrie nicht verlieren. Round-Trip-Test mit absichtlich kaputtem
  Sidecar. **Dateien:** `constraints.dart` (De-/Serialisierung), `app_state.dart`.

- [ ] **P2-9 Autosave-Sicherheit.** Sicherstellen, dass ein Crash MITTEN im
  Solve (P0 macht das seltener, aber nie null) keine halbgeschriebene
  DXF/Sidecar hinterlässt: atomar schreiben (temp + rename). Prüfen, ob der
  aktuelle Save das schon tut. **Dateien:** `app_state.dart`,
  `ffi/qcad_engine.dart`.

## P3 — Inventor-Treue & Workflow-Lücken (aus der Doku, nicht abstürzend)

- [ ] **P3-1 Fillet/Chamfer an einer echten Ecke ohne Vor-Trim.** Inventor
  („Place a chamfer at a corner where two lines meet, an intersection, or two
  nonparallel lines"): auch der Fall „zwei Linien treffen sich schon in einer
  Ecke" muss sauber gehen (genau der Rechteck-Fall). Nach P0-2 verifizieren,
  dass Ecke → Chamfer/Fillet die Ecke ersetzt und die Nachbarschaft (die zwei
  weiteren Rechteck-Ecken) intakt bleibt.

- [ ] **P3-2 „Create Dimensions" / „Equal to Parameters" als Optionen.**
  Inventors Chamfer-/Fillet-Dialog hat Schalter „Create Dimensions" (Maße
  anlegen ja/nein) und „Equal to Parameters" (weitere = erstem). Heute sind
  Maß+Equal-Kette hart verdrahtet. Als Toggles in den modelessen Dialog
  aufnehmen. **Dateien:** `widgets/pattern_dialog.dart` (Fillet/Chamfer-Dialog),
  `app_state.dart`.

- [ ] **P3-3 Chamfer Distance+Angle & Two-Distance Flip.** „Flip"-Knopf für die
  Richtungswahl bei Two-Distance (Autodesk: „click Flip to change the direction
  of the chamfer distances"). D1 gehört an die ERSTE gepickte Linie — Pick-
  Reihenfolge sichtbar machen. **Dateien:** `widgets/pattern_dialog.dart`,
  `tools.dart`.

- [ ] **P3-4 Trim/Extend für getaggte Polylines (Spline/Ellipse).** Steht schon
  als Grenze in HANDOFF; für „production ready" nötig, sonst wirkt Trim an
  Kurven kaputt. **Dateien:** `modify.dart`, `spline.dart`.

- [ ] **P3-5 Fillet gegen Spline/Ellipse.** Ebenfalls Grenze; mind. sauber
  ablehnen mit Toast statt undefiniert. **Datei:** `tools.dart`.

- [ ] **P3-6 Bogenlängen-Bemaßung, Kreis-Tangentenabstand, Winkel-Quadrant.**
  Aus M21-Ideenliste; Inventor kann das, aktuell fehlt es. **Dateien:**
  `app_state.dart`, `solver.dart`, `widgets/viewport.dart`.

- [ ] **P3-7 Über-/Unterbestimmung dem Nutzer klar anzeigen.** Wenn eine
  Bemaßung überbestimmen würde, Inventors Dialog „getriebene Bemaßung anlegen?"
  konsistent für ALLE Bemaßungs-/Constraint-Pfade (heute nur teils). Nach P2-1
  natürlicher Anschluss. **Dateien:** `app_state.dart`.

- [ ] **P3-8 Pattern v1-Grenzen** (Boundary-Fill, Suppress, Edit Pattern,
  Pfad-Muster) — bekannt, für Vollausbau notieren. **Dateien:**
  `widgets/pattern_dialog.dart`, `app_state.dart`.

## Tests & CI — Lücken, die diese Klasse Bugs durchgelassen haben

Kernproblem: die 134 Host-Tests prüfen NUR den End-Zustand einzelner
Operationen, nicht die **Solver-Stabilität unter Drag** und nicht
**Operationen in Kombination** (Chamfer während ein Slot existiert). Genau da
lagen die Bugs.

- [x] **T-1 Drag-Stabilitätstests.** Für jede Form (Rechteck, Slot, Ellipse,
  Kreis+Bogen mit Tangente) einen Grip N Frames entlang einer Bahn ziehen und
  nach JEDEM Frame asserten: alle Residuen ≤ Schwelle, kein Arc mit Sweep 0
  oder r≤0, kein Sprung der Arc-Parameter > Toleranz zwischen Frames
  (Anti-Flacker-Test). Hätte P0-1/P0-3/P0-4 sofort gefangen. **Datei:**
  `frontend/test/drag_stability_test.dart` (neu).
  ✅ `drag_stability_test.dart` (9 Tests): Slot-/Rechteck-/Fillet-/Tangentenkreis-Drags Frame für Frame (finite, nicht degeneriert, Residuum ≤ 1e-4, kein Radius-Teleport), inkl. Folter-Drag in die Degenerationszone und Park-auf-letztem-Gut-Verhalten; dazu ein 8-ms-Budget pro Drag-Solve.

- [x] **T-2 Rangtest jeder Konstruktion.** Für Rechteck/Slot/Fillet/Chamfer/
  Ellipse: Jacobi-Rang == Anzahl unabhängiger Gleichungen (keine Redundanz),
  DOF == Inventor-Erwartung. Hätte P0-3 sofort gefangen. **Datei:**
  `frontend/test/construction_rank_test.dart` (neu).
  ✅ `construction_rank_test.dart` (8 Tests): Rang == Gleichungen (Redundanz 0) + Inventor-DOF für Rechteck 2P/3P, beide Slots, Fillet- und Chamfer-Ecken.

- [x] **T-3 Kombinations-/Sequenztests.** Slot bauen → Chamfer am Rechteck →
  asserten, dass der Slot unverändert bleibt und alles erfüllt ist. Fillet →
  Trim → Split-Ketten. Hätte den „Chamfer zerreißt den Slot"-Fehler gefangen.
  **Datei:** `frontend/test/operation_sequence_test.dart` (neu).
  ✅ `operation_sequence_test.dart` (6 Tests): die komplette Geräte-Session (Rechteck+Slot+Kreis, zwei Chamfer) — Slot bleibt bit-identisch; Fillet-Kette treibt beide Radien; abgelehnte Ops ändern NICHTS.

- [x] **T-4 Chamfer-/Fillet-Bemaßungstests.** Setback-Maße statt Diagonale
  (P1-1), Equal-Kette, alle drei Chamfer-Modi, Ecke-ohne-Vor-Trim (P3-1).
  **Datei:** `frontend/test/fillet_chamfer_test.dart` (erweitern).
  ✅ m36-Chamfer-Tests auf Setback-x/y umgestellt inkl. Rang- und Residuen-Assertions.

- [ ] **T-5 „Nie divergiertes Rendern"-Invariante.** Ein Test-Harness, das nach
  jeder Operation `allFinite` UND „alle Residuen erfüllt" UND „keine
  degenerierte Entity" prüft — als generischer Wächter über die ganze
  Test-Suite. **Datei:** `frontend/test/invariants_test.dart` (neu).

- [x] **T-6 Shim-Host-Gate um Slot/Fillet erweitern.** `shim_test.c` deckt
  Slot-Tangenten und die Ast-Wahl nicht ab; Szenarien ergänzen (Rail-Cap
  außen-tangential, Radius stabil unter Zug). **Datei:**
  `backend/slvs/tests/shim_test.c`.
  ✅ `shim_test.c` +2 Szenarien: Slot löst NATIV (result OKAY, inkrementeller Drag bleibt parallel/equal) und Fillet-Tangente am Arc-ENDE exakt — Host-Gate: 12/12 PASS.

- [ ] **T-7 Geräte-Rauch-Marker für Solver-Gesundheit.** Optionaler Debug-
  Zähler „VERIFY FAILED pro Session" ins Log; Ziel nach den Fixes: 0 unter
  normaler Bedienung (heute 1 802 WARN in einer Session). Dient als
  Regressions-Signal beim nächsten Geräte-Test.

## Reihenfolge der Abarbeitung (Vorschlag)

1. P0-5 + P0-4 + P2-3 zuerst (Sicherheitsnetz: nie wieder divergiertes/
   degeneriertes Rendern — macht die App SOFORT benutzbar, auch bevor die
   Wurzeln sauber sind).
2. P0-2 + P0-3 + P0-1 (Fillet/Chamfer/Slot an der Wurzel korrekt).
3. P1-1 + P1-3 (Chamfer-Maße + Tangenten-Ast).
4. P2-1 (gemeinsames Gate) + T-1..T-3 (die Tests, die das alles festnageln).
5. Rest P1/P2, dann P3.

Jeder Schritt schließt mit `flutter test` (alle grün) + wo möglich Shim-Host-
Gate. Erst danach ein neuer IPA-Build und der nächste Geräte-Test.

## Durchgang 1 (nach Geräte-Test) — was zusätzlich gefunden wurde

Beim Tiefen-Audit kam eine Klasse latenter Native-Solver-Fehler ans Licht, die
im Geräte-Log unsichtbar blieb, weil das Dart-Verify sie stumm auffing:

- **Shim-Tangenten waren am falschen Arc-Ende verankert.** SolveSpaces
  `ARC_LINE_TANGENT`/`CURVE_CURVE_TANGENT` sind ENDPUNKT-verankert
  (`other`/`other2` wählen Start/Ende, `constrainteq.cpp`); der Shim übergab
  immer `other=0` (Start). Für Fillet-Bögen mit Naht am ENDE war die native
  Gleichung damit 90° falsch; bei Slots stimmte sie nur zufällig auf der
  symmetrischen Mannigfaltigkeit. Fix: Shim v3 liest die Naht-Flags aus `val`
  (Bit 0/1), die Dart-Seite bestimmt sie aus der echten Geometrie
  (`_tangentSeamFlags`). Host-Gate deckt beide Fälle ab.
- **Kreis-Tangenten sind in libslvs nicht ausdrückbar** (Kreise haben keine
  Endpunkte; `CURVE_CURVE_TANGENT` ssassert'et auf einem Kreis). Die Dart-Seite
  BAILT jetzt sauber auf den LM-Pfad statt eine falsche/crashende Gleichung zu
  packen. Gleiches Gate für Tangenten ohne gemeinsamen Endpunkt und für
  Shim-Version < 3.
- Der Verify-Reject-Tanz pro Drag-Frame (1 802 WARN in einer Session) hatte
  damit ZWEI Quellen: redundante Konstruktions-Constraints (behoben, P0-3) und
  falsch verankerte native Tangenten (behoben, Shim v3). Ziel für den nächsten
  Geräte-Test: VERIFY-FAILED-Zähler = 0 (T-7).

## Durchgang 2 (Geräte-Test M37-Build) — Befund & Fixes (M38)

Der zweite Geräte-Test bestätigte den Durchgang-1-Erfolg messbar — **3 WARN
statt 1 802, 0× VERIFY FAILED** — und legte die nächste Schicht frei. Alle
Punkte sind aus Log/DXF belegt und auf dem Host exakt reproduziert (die
Session ist jetzt ein permanenter Regressionstest).

- **Slot faltete sich erneut — diesmal KONTINUIERLICH.** Die Host-Wiedergabe
  der vier Cap-Drags zeigt: jede Zwischenlage war einzeln erfüllt (Residuen
  ≤ 3.6e-8), der Ast-Wechsel passierte DURCH die degenerierte Lage hindurch —
  pro Solve neu abgeleitete Tangenten-Seiten können das prinzipiell nicht
  verhindern. **Fix:** der Tangenten-Ast ist jetzt PERSISTENT
  (`Constraint.tanBranch`, Sidecar-Key `tb`): einmal beim ersten Solve nach
  Erzeugen/Laden erfasst, danach unveränderlich — ein Drag kann eine Tangente
  nicht mehr umklappen (Inventor-Verhalten), er parkt an der Grenze.
- **Committete Drags trugen Drag-Budget-Residuen.** `endGripDrag` übernahm den
  letzten guten Frame (Gate ≤ 1e-2); auf dem Gerät lagen die Slot-Nähte danach
  über der 1e-6-Naht-Toleranz → JEDE spätere Operation bailte auf den LM-Pfad,
  und der r=5-Fillet an einer intakten Ecke wurde fälschlich abgelehnt
  (err=3.42), während r=50 nach einem Dialogwechsel nativ gelang. **Fix:**
  `endGripDrag` SETTLED vor dem Commit (voller Solve, 80 Iterationen) und
  normalisiert Arc-Winkel (`normalizeArcAngles`; das Gerät hatte -8.0..4.6 rad
  auf einem Cap). Committete Skizzen liegen wieder bei ~1e-8.
- **Fillets: jede bekommt ihr eigenes Radius-Maß** (Nutzer-Spezifikation,
  analog zu den Chamfer-Setbacks; die Equal-Kette entfiel — sie ließ alle
  Folge-Fillets ohne sichtbares Maß). Label sitzt außen an der Bogenmitte.
- **Trim/Split binden ihre Schnittpunkte** (Inventor): jeder NEUE Endpunkt
  einer Trim-/Split-Operation wird koinzident gebunden — Punkt-auf-Punkt, wenn
  er einen bestehenden Punkt trifft (Split-Zwilling), sonst Punkt-auf-Kurve
  auf den Cutter. Dafür wurde Punkt-auf-Kreis/Bogen als Residuum + nativer
  Pfad ergänzt (**Shim v4:** `SH_POINT_ON_CIRCLE` → `SLVS_C_PT_ON_CIRCLE`,
  Host-Szenario [13]). Vorher ENTFERNTEN Trims nur Constraints (Log: 55 → 49).
- **Center-Point-Bindung war für deterministische Formen ausgefallen** (seit
  M34/M36 lief die Punkt-Inferenz nur noch im `autoConstrain`-Zweig). Der
  Punkt-Teil ist jetzt als `inferPointBindings` ausgekoppelt und läuft für
  Rechtecke/Slots/Tangenten-Formen zusätzlich — beschränkt auf VORBESTEHENDE
  Geometrie + CP (`bindOnlyBefore`), jede Kandidatin durch das
  Überbestimmungs-Gate. Eine Ecke auf (0,0) erdet wieder.
- **Koinzidenz-Werkzeug: zweiter Pick auf gestapelten Punkten** löste auf
  DENSELBEN Punkt auf (Log: `e17.p1,e17.p1` abgelehnt). Der zweite Pick
  schließt den ersten jetzt aus und trifft den Punkt der ANDEREN Entität.

Host-Suite: **161 Tests grün** (inkl. Geräte-Session als Regression,
tanBranch-Roundtrip, Trim-auf-Kreis nativ, Stacked-Pick); Shim-Host-Gate:
**13/13 PASS**. Ziel für Geräte-Test 3: Slot bleibt unter beliebigen Drags ein
Slot; Trim-Stücke hängen zusammen; Ecke-auf-CP erdet; jede Rundung trägt ihr R.

## M38.1 + M39 — Trim-Bind-Upgrade & Undo/Redo pro Skizze

- **Trim-Fix (M38.1):** Werden von zwei sich kreuzenden Konturen (Rechtecke
  oder einzelne Linien) beide Seiten getrimmt, liegen die zwei neuen
  Endpunkte exakt aufeinander — sie werden jetzt Punkt-auf-Punkt gebunden.
  Vorher blockierte die Punkt-auf-Kurve-Bindung des ERSTEN Trims das Upgrade
  und machte den point-on-point redundant, das Gate verwarf ihn still
  (Geräte-Log: „constraints 22 -> 22"). Jetzt: on-curve-Bindung wird beim
  Stapeln ENTFERNT und durch point-on-point ersetzt; Ablehnungen werden
  geloggt. Regressionen: Rechteck-Session + 4 Linien-Varianten.
- **Undo/Redo (M39):** Ctrl+Z / Ctrl+Shift+Z (auch Ctrl+Y), immer nur in der
  aktuellen Skizze. Snapshot-Journal PRO SketchModel (strukturelle Isolation):
  volle Tiefkopien (Geometrie inkl. aller Tags, Constraints über den
  Sidecar-Codec, Layer + Auge/Schloss), ein Checkpoint am einzigen
  Mutations-Choke-Point `_rebuildEngine` (+ Auge/Schloss/Layer-Anlegen),
  dedupliziert, unbegrenzt bis zum Sitzungsanfang. Restore ist exakt (kein
  Replay, kein Solve), bricht schwebende Picks ab, journaliert sich nie
  selbst, ist während eines Drags gesperrt.

Host-Suite: **173 Tests grün**; Shim-Host-Gate unverändert **13/13 PASS**.

## M40 — Construction-Geometrie (Format > Construction)

Inventors Construction-Linetype: Auswahl + Klick auf den neuen
Construction-Button im Format-Panel konvertiert Geometrie in dünn +
gestrichelt gerenderte Construction-Geometrie, nochmal Klick zurück —
Constraints, Bemaßungen, Snapping, Trim und Drag funktionieren exakt wie bei
normaler Geometrie (der Stil ist reines Rendering und reitet im
styles.json-Sidecar). Lineare Slots erzeugen ihre ACHSE zwischen den
Cap-Zentren jetzt automatisch als Construction-Linie, koinzident gebunden —
rank-gemessen redundanzfrei, Slot behält 5 DOF. Nebenbei gefixt: Trim/Move/
Rotate/Mirror/Stretch/Offset warfen den Linienstil (auch Centerlines!) still
weg — `_carry` trägt ihn jetzt immer mit. Suite: **179 Tests grün**.

## M47 — Direktes Ziehen des Entity-Körpers (Body-Drag)

Bisher ließen sich im Layer-Editiermodus nur PUNKT-Griffe ziehen (Endpunkte,
Zentren, Vertices). Jetzt kann man eine Linie, einen Kreis, einen Bogen, eine
Polylinie, eine Spline oder eine Ellipse direkt am KÖRPER anfassen und die
ganze Entität starr verschieben — genau wie in Inventor, wo ein Zug an der
Linie selbst (nicht an einem Griff) das Element translatiert und der Solver
angebundene Geometrie nachführt.

**Wie es funktioniert.** Der Body-Drag ist bewusst in die bestehende
Griff-Zug-Maschinerie eingebettet statt als paralleler Pfad: ein
Body-Griff-Sentinel (`Grip.body`, `idx = -1`, `kind = 'body'`) landet in
`AppState.dragGrip`, sodass `displayGeometry`-Vorschau, Painter,
Snap-Marker und der `endGripDrag`-Commit (Settle + `normalizeArcAngles` +
atomarer Rebuild) unverändert greifen. Neu ist nur:
`translateGeo(g, delta)` verschiebt jede Entität starr (Linie: beide
Endpunkte; Kreis/Bogen: Zentrum, Radius/Winkel bleiben → Endpunkte reiten
mit; Polylinie/Spline/Ellipse: alle Vertices), und `displayGeometry` meldet
beim Body-Drag ALLE Punkte der Entität als Drag-Wunsch an den Solver
(`dragged`-Set), sodass das Element rigide zieht, während angebundene
Geometrie über die Constraints folgt.

**Inventor-Semantik + Sicherheitsnetz.**
- Eine voll gebundene Entität (kein freier Punkt in `analysis.freePoints`)
  wird NICHT gezogen — sie ist starr platziert und würde nur zurückschnappen;
  die Geste fällt sauber auf Box-Select zurück (`beginBodyDrag` verweigert als
  zweite Verteidigungslinie, `dragGrip` bleibt null → Update/End sind No-Ops).
- Projektionen (gepinnte Referenzgeometrie) und Fremd-Layer sind nicht
  körper-ziehbar (dieselbe Scope-Regel wie Griffe/Selektion).
- Der eigentliche Zug beginnt LAZY beim ersten Move: ein stationärer Druck
  bleibt ein Tap (→ Selektion über den Listener) und löst KEINEN Rebuild/
  Undo-Schritt aus. Ein echter Zug (> Slop) unterdrückt umgekehrt den
  Tap-Select. Ein zweiter Finger bricht den Body-Drag ab (Pan/Zoom).
- Kein Snapping während des Body-Drags: eine reine Translation folgt dem
  Finger exakt (der beliebige Greifpunkt auf einen Vertex zu snappen ließe die
  ganze Entität springen).

Jeder gezeigte Frame erfüllt dieselben Invarianten wie der Punkt-Drag (finite,
nicht degeneriert, Constraints erfüllt — sonst wird die letzte gültige Lage
gehalten), und die committete Skizze ist erfüllt.

**Tests:** `m47_body_drag_test.dart` (8): `translateGeo` starr pro Typ
(Linie/Kreis/Bogen/Polylinie+Spline, Layer-/Spline-Tag erhalten); freie Linie
translatiert um das Drag-Delta; Kreis verschiebt Zentrum, Radius bleibt; voll
gebundene Linie verweigert den Body-Drag; angebundene Linien führen den
gemeinsamen Endpunkt nach (Constraint-erhaltend). Suite: **222 grün**.

## M49 — Split, exakt wie Inventors 2D-Skizzen-Split

Split existierte seit M5 als Button, verhielt sich aber nicht wie Inventor: es
schnitt am ANGEKLICKTEN PUNKT, zerlegte einen Kreis in N Bögen (einen pro
Schnittpunkt), verweigerte geschlossene Polylinien und kannte weder
Constraint-Vererbung noch Vorschau. M49 setzt Autodesks dokumentierten Vertrag
eins zu eins um.

**Der Schnitt liegt auf dem nächsten Schnittpunkt, nicht unter dem Cursor.**
Inventor: *"the Split command splits a selected curve to the nearest
intersecting curve"*. Der Klick sagt nur, WELCHE Kurve und WO ENTLANG man ist;
bei mehreren Schnittpunkten gewinnt der dem CURSOR nächste (entlang der Kurve
gemessen).

**Offene und geschlossene Träger sind verschieden.**
- Linie, Bogen, offene Polylinie/Spline haben bereits zwei Enden: EIN Schnitt
  am nächsten INNEREN Schnittpunkt → zwei Stücke. Ein Schnittpunkt exakt auf
  einem Endpunkt trennt nichts ab und zählt nicht.
- Kreis und geschlossene Polylinie haben keine Enden, die einen einzelnen
  Schnitt begrenzen könnten. Inventor läuft deshalb vom Cursor in BEIDE
  Richtungen bis zum ersten Treffer: die überfahrene Spanne plus ihr
  Komplement — immer genau zwei Stücke. Ein Split-Stück ist nie wieder eine
  Schleife, geschlossene Polygone zerfallen in zwei offene Ketten.

**Split löscht nie.** Ohne etwas zum Schneiden passiert schlicht nichts. Das
Löschen ist Trims Verhalten (*"If you select a curve with no physical or
virtual intersections, the Trim command deletes the curve"*), nicht Splits.

**Constraints nach Autodesks Regel.** *"Both segments of the split inherit the
Horizontal, Vertical, Parallel, Perpendicular, and Collinear constraints of the
original. Equal and Symmetric constraints are broken when necessary."* Das
generische `remapAfterReplace` (M36) gibt eine Entity-Constraint an GENAU EIN
Stück — richtig für Trim, wo das andere weg ist. Ein Split behält beide, also
gibt es `remapAfterSplit`: eine horizontale Linie wird zu zwei horizontalen
Hälften, Equal/Symmetric werden verworfen. Bemaßungen bleiben erhalten, und die
beiden Hälften werden am Schnittpunkt über `_bindCutPoints` zusammengehalten.

**Bedienung.** Hover zeigt den Split VORHER: die überfahrene Spanne wird blau
hervorgehoben, die Schnittpunkte als roter Punkt mit Ring markiert. Die Sitzung
bleibt für mehrere Splits offen; ein Rechtsklick (Maus) wechselt im Ring
Split → Trim → Extend, ohne die Sitzung zu beenden; Esc beendet sie.
Projizierte Geometrie ist wie überall gesperrt.

**Tests:** `m49_split_test.dart` (21): Schnitt am Schnittpunkt statt am Klick;
nächster von mehreren; Schnittpunkt auf dem Endpunkt schneidet nicht; ohne
Schnittpunkt kein Split UND keine Löschung; Bogen behält Radius und
Gesamt-Sweep; Kreis liefert genau zwei Bögen mit erhaltenem Vollwinkel; die
überfahrene Spanne ist die richtige; Tangente kann nicht splitten; geschlossene
Polylinie → zwei offene Ketten; offene Polylinie; Layer/Stil bleiben; alle fünf
vererbten Constraint-Typen landen auf BEIDEN Stücken; Equal/Symmetric fallen
weg; fremde Constraints bleiben unberührt; End-to-End über `AppState` inkl.
Verklebung am Schnittpunkt und Sperre für Projektionen; Rechtsklick-Ring;
Sitzung bleibt offen. Suite: **269 grün**, `flutter analyze` ohne neue Issues.

## M50 — Abgespeckter Ribbon

Der Ribbon zeigte alles gleich prominent, auch was man fast nie anfasst. M50
trennt zwei Dinge sauber: Befehle, die nur ihre **dauerhafte Breite** verlieren
(sie sind ein Tipp weiter unter dem ▼ am Panel-Titel), und totes Chrome, das
**wirklich verschwindet**.

**Hinter den ▼ gewandert (weiter erreichbar):**
- *Constrain*: Smooth (G2), Constraint Settings, Show Constraints. Das Gitter
  faellt auf 11 Zellen in 4 statt 5 Spalten — schmaler bei gleicher Hoehe.
- *Insert* (jetzt Insert + Format + Manage in einem Panel): Points, Centerline,
  Center Point, Driven Dimension, Show Format. Sichtbar bleiben Image, ACAD,
  Construction und Parameters.
- *Modify*: Extend, Move, Copy, Rotate, Scale, Stretch. Sichtbar bleiben Trim,
  Split und Offset.

**Entfernt:** `+`, Suche und Menue im Model-Browser; das Menue in der
Tab-Leiste; das Wort „Home" neben dem Haus; der Schloss-Toggle in jeder
Layer-Zeile (ein Schloss markiert jetzt nur noch GESPERRTE Layer, gesperrt wird
per Rechtsklick); die Statuszeile „N degrees of freedom" unten links, weil
unten rechts dasselbe als „N dimensions needed" steht; und die drei ▼ an
„Start New Layer", „Create" und „Finish", die auf nichts zeigten.

**M51 — Geraete-Test-Fixes.** Der erste M50-Build war kaputt: `_panel` schrieb
eine Widget-Variable auf eine Closure um, die dieselbe Variable einfing, also
inflatete jeder Frame `Builder -> GestureDetector -> Builder -> ...` bis zum
Stack Overflow. Folge: die drei ▼ rendern nie, und die Frame-Pipeline steckt in
der Exception-Behandlung — was sich als kaputtes Pan/Zoom anfuehlt. Behoben
durch ein eigenes `final` fuer das innere Widget. Derselbe Bug war auch der
Grund, warum sich der Ribbon angeblich nicht im Widget-Test pumpen liess; die
Suite ist wieder da (14 Tests) und ihr erster Test faengt genau diese
Rekursion. Ausserdem: das Overflow-Menue oeffnet nach UNTEN statt nach oben,
der Statusleisten-Streifen faerbt sich mit dem Ribbon (bzw. der Galerie) mit,
und die Menuezeilen koennen nicht mehr ueberlaufen.

## M53 — End of Sketch wie Inventors EOP + Apple-Pencil/Touch komplett

**End-of-Sketch-Marker (Inventors End of Part, auf Layer gemappt).** Die
Zeile im Model-Browser ist jetzt der echte Marker: per Drag nach oben/unten
verschiebbar (Escape bricht die Verschiebung ab, wie Inventor), alles
DARUNTER ist zurueckgerollt — gedimmt (45%) im Browser, ohne Auge, nicht
gezeichnet, nicht pickbar, nicht snapbar, nicht editierbar; Bemaßungen und
Constraint-Glyphen der Entities darunter verschwinden mit (constraintVisible
haengt an geoVisible). Neue Layer entstehen OBERHALB des Markers (Inventor:
neue Features landen ueber dem EOP). Rechtsklick/Long-Press auf den Marker:
Move to Top / Move to End / **Delete all layers below** (mit Bestaetigung,
atomar = EIN Undo-Schritt, Constraint-Refs remappt, gestrandete "0"-Entities
werden mit geloescht und die leere "0" gepruned). Jede Layer-Zeile bietet
"Move End of Sketch here" (Inventor 2013: Move EOP Marker). Der Marker
faehrt im Undo-Journal und im Layer-Sidecar (v3, `eos`) mit; alte Sidecars
laden mit Marker am Ende. Solver-Entscheid: zurueckgerollte Geometrie bleibt
im Gleichungssystem (nichts kann sie greifen oder neu referenzieren, sie
wirkt als unbeweglicher Anker) — dadurch ist der Marker-Move in beide
Richtungen sofort und verlustfrei, kein Re-Solve, kein Drift.

**Apple Pencil + Touch, komplett (Trackpad/Maus unveraendert).**
- **Press-Drag-Release-Zeichnen mit dem Pencil:** Pencil 1/2 haben KEIN
  Hover — zwischen Tap 1 und Tap 2 gaebe es kein Gummiband. Darum ankert
  der Aufsetzpunkt den ersten Punkt (gesnappt), der Zug zeigt die Vorschau
  LIVE mit Snapping (und HUD/Dynamic Input aus M52 greift, weil toolClick
  hudApply selbst anwendet), das Abheben setzt den zweiten Punkt. Ein
  blosser Tap bleibt klassisches Klick-Klick. Nur Geometrie-Tools
  (toolMeta); Bemaßung/Modify bleiben reine Picks. Bei Kontakt erscheint
  der Snap-Marker sofort (onPointerDown), waehrend des Zugs folgt er dem
  Stift (onPointerMove) — Hover-faehige Pencils (Pro/M2) hatten das schon
  ueber onPointerHover, exakt wie die Maus.
- **Palm Rejection:** Touches, die landen waehrend der Pencil unten ist,
  werden abgewiesen — gezaehlt (M52-Kontrakt: Count FIRST), aber nie Klick,
  nie Tap, und der Scale-Recognizer verweigert ihnen den Eintritt
  (`_PalmAwareScale.isPointerAllowed`), damit der Handballen einen Strich
  nie in Pan/Zoom kippt.
- **Zwei-Finger-Tipp = Undo, Drei-Finger-Tipp = Redo (Procreate).** Der
  Klassifikator (lib/touch.dart, host-getestet) trennt Tipp von Pan/Pinch
  ueber Bewegung (>18 px) und Dauer (>350 ms) und wird von jeder
  Nicht-Touch-Aktivitaet vergiftet. Haptik bei Ausloesung; unterdrueckt
  waehrend Textfeld/HUD-Eingabe.
- **Ein Finger:** auf Griff/Body/Text/Bild zieht (mit ~1.8x Fangradius,
  touchSlop), auf leerer Flaeche PANNT er — der Pencil behaelt die
  Box-Selektion. Mit aktivem Tool pannt der Finger (Pencil setzt Punkte,
  Finger navigieren). Zwei Finger: Pan + Pinch wie gehabt.
- **Long-Press (Pencil und Finger, 600 ms, still) = Rechtsklick-Rolle:**
  in der Split/Trim/Extend-Familie springt er zum naechsten Werkzeug (M49),
  sonst Quick-Menue am Finger: OK (bei genug Punkten der variablen Tools),
  Cancel (Esc), plus Line/Circle/Rectangle/Dimension im Edit-Mode — damit
  hat reiner Touch endlich Enter UND Esc.
- **Pencil-Hardware (native_menu-Plugin, UIPencilInteraction):**
  **Squeeze** (Pencil Pro) oeffnet das Quick-Menue an der Spitze
  (hoverPose-Anker, Fallback letzte Stiftposition) — Apples eigene
  Squeeze-Semantik. **Doppel-Tipp** = Familie durchschalten, sonst Esc,
  sonst letztes Zeichenwerkzeug wieder scharf (lastDrawTool). Beide
  respektieren die Systemeinstellung (preferredTap/SqueezeAction .ignore
  wird nie weitergereicht).
- **Fat-Finger-Toleranzen ueberall:** Klick-Picks, Bemassungslabels,
  Bild-Loeschkreuz, Center-Point, Snap-Radius skalieren per touchSlop nur
  fuer PointerDeviceKind.touch; Pencil und Maus bleiben praezise.

Tests: `m53_end_of_sketch_test.dart` (Marker-Default/Insert-Above, Rollback
sichtbar+Selektion+enterEdit, Ein-Schritt-Undo, Delete-Below atomar mit
Remap, deleteLayer-Verschiebung, Sidecar-Roundtrip inkl. prae-M53) und
`m53_touch_test.dart` (Tap-Klassifikator: 2/3 Finger, Bewegung, Timeout,
Vergiftung, Cancel, 1/4 Finger; touchSlop).

**M53-Nachtrag (Geraete-Feedback).** (1) Die HUD-Boxen sitzen jetzt NEBEN der
Geometrie statt darauf: der Block wandert 26 px in Strichrichtung UEBER die
Spitze hinaus und waechst von der Geometrie weg — hinter dem Linienende,
radial ausserhalb des Kreisrands, ausserhalb der gezogenen Rechteck-Ecke;
ohne Richtung (erster Klick) wie bisher rechts unten vom Cursor. (2)
Pfeiltasten wechseln die HUD-Felder: Rechts/Runter = hudTab, Links/Hoch =
hudTabBack (neu, gleicher Lock-und-Weiter-Kontrakt rueckwaerts) — auf dem
Rechteck also w <-> h in beide Richtungen. (3) Press-Drag-Release-Zeichnen
funktioniert jetzt auch mit EINEM FINGER (Live-Vorschau, Fat-Finger-Snap
~1.8x; zwei Finger pannen/zoomen weiter, Procreate-Logik); nur bei
Nicht-Geometrie-Tools (Bemassung/Modify) pannt der einzelne Finger weiter.
Test: m53_hud_arrows_test.dart.

