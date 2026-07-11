# HANDOFF — iPadProCAD

Übergabestand für die Fortsetzung in einem neuen Chat.

## Projekt
- 2D-CAD für iPad. Frontend: Flutter. Backend: QCAD-Core (C++, GPLv3) per FFI.
- Ziel-Repo: `github.com/Toemeler/ipadprocad`
- Upstream: `github.com/qcad/qcad` (Details: `backend/qcad-core/VENDOR.md`)
- **Nur echten Status berichten** — nie „grün" behaupten, was nicht gebaut wurde.
  CI-Logs lesen, grüner Haken reicht nicht (tee/pipefail-Fallen, siehe unten).

## Auth/Push
PAT wird pro Session neu erzeugt und danach widerrufen. Push nur inline:
`git push https://<PAT>@github.com/Toemeler/ipadprocad.git HEAD:main`
Token NIE in Dateien/.git/config schreiben.

## Meilenstein-Status
- **M1 — Headless-Core-Build + iOS-CI: ERLEDIGT** (statische Libs, arm64/iphoneos).
- **M2 — C-Wrapper: ERLEDIGT & validiert**; in M5 um Geometrie-Abfrage erweitert
  (`qcad_entity_ids`, `qcad_entity_geometry`), lokal per Compile-Check gegen die
  echten QCAD-Header validiert; Runtime-Validierung via erweiterten smoke.c im
  M3-Sim-CI-Job (Marker lesen!).
- **M3 — Headless-Logiktest iOS-Simulator: ERLEDIGT** (smoke.c jetzt inkl.
  Geometrie-Query-Checks — Log des naechsten Runs pruefen).
- **M4 — Mock-Phase ABGESCHLOSSEN** (create-panel.html = verbindliche 1:1-Spec,
  UI-Details siehe Abschnitt unten).
- **M5 — IN ARBEIT (dieser Stand):**
  - `frontend/` KOMPLETT NEU: 1:1-Flutter-Port des Mocks (Ribbon alle 8 Panels
    + Exit + Home-Sketch-Panel, Flyouts mit exakten Eintraegen, Model-Browser
    inkl. Origin-Expander/Kontextmenue/Edit-Highlight, Layer-Edit-Modus mit
    grauen Achsen + gelbem projizierten CP + Finish, Home-View mit Recent-Karten,
    untere Tab-Leiste). Alter main.dart (8e241b3) ERSETZT.
    Struktur: lib/main.dart, theme.dart (Palette), svg_icons.dart (Mock-SVGs
    verbatim, via flutter_svg), app_state.dart (Tabs/Layer/Edit/Tools/Persistenz),
    ffi/qcad_engine.dart, widgets/{ribbon,model_browser,viewport,home_view,
    bottom_tabbar}.dart
  - Echtes Zeichnen ueber Backend: Line, Circle (Center), Rectangle (Two Point,
    als geschlossene Polyline), Arc (Three Point) — via FFI, Rendering aus dem
    QCAD-Dokument (Geometrie-Query). Alle uebrigen Buttons wie im Mock sichtbar,
    ohne Funktion. Ehrlicher Fallback: ohne gelinkte Libs laeuft eine
    Dart-Engine, Start-Marker meldet `DART SMOKE: PASS (backend=qcad-ffi|dart-fallback)`.
  - Save/Load: DXF pro Skizze + Preview-PNG in App-Documents; Autosave bei
    Finish/Tab-Schliessen/Home; Recent-Karten zeigen echte Skizzen (die 6
    Design-Dummies nur im Erststart ohne gespeicherte Dateien).
  - Eingabe: Maus/Keyboard; Trackpad-2-Finger-Pan + Pinch-Zoom integriert
    (PointerPanZoom-Events); Scrollrad zoomt. Esc bricht Tool ab.
    Touch-Gesten bewusst spaeter.
  - CI-Job `m5-flutter-ipa` NEU: Device-Libs bauen, Flutter-Scaffold
    (flutter create + pbxproj/Podfile auf iOS 14.0), FFI-Link per xcconfig
    (force_load libipadprocad.a + exported_symbols_list `_qcad_*` + ALLE
    Qt-Static-Archive ausser qios — qios interponiert main!),
    `flutter build ios --release --no-codesign`, "M5 LINK CHECK"
    (C-API-Versions-String im Runner-Binary), unsigniertes IPA-Artefakt
    `ipadprocad-unsigned-ipa` (Sideload via AltStore/Sideloadly, 3 Tage
    Retention). Logs -> Branch `ci-debug-logs-m5/ci-logs-m5/*`.
  - **NOCH NICHT VALIDIERT / OFFEN:** Flutter-Code wurde ohne lokales Dart-SDK
    geschrieben (Container hat kein Flutter, pub.dev nicht erreichbar); erster
    Beweis ist der CI-Run — LOGS LESEN, gruener Haken reicht nicht.
    Dart-FFI-Runtime-Smoke laeuft erst ON DEVICE (App-Start-Marker); im CI nur
    der Link-Check. Sim-Job, der den DART-SMOKE-Marker der App captured: offen.

## UI-Design-Spec (Stand = create-panel.html, FINAL abgenommen)
Stil: Autodesk Inventor Sketch-Tab, Dark Theme. Palette:
Panel `#292D33`, Flyout `#212429`, Hover `#31363D`, Text `#DDE0E3`, Dim `#9EA4AA`,
Blau (Grips/Akzent) `#3D9BE9`, Constraint-Rot `#E05A56`/`#D65A56`, Gelb `#E8C63F`,
Viewport `#212830`. Ribbon: `width:100vw`, blaue Linie oben
(`2px rgba(47,123,214,.85)`) und unten (`.45`), vertikale Panel-Trenner `#3a3f45`.
Icons: handgezeichnete Inline-SVGs (16/18/26/32/34 px), Sprache: hellgraue
Geometrie, blaue Quadrat-Grips, rote Constraints mit grauen Cursor-Pfeilen/
Häkchen, gelbe Blitze, KEIN Grün außer dem Plus im Layer-Icon.

**Ribbon-Panels in Reihenfolge (nichts hinzufügen/weglassen):**
1. **Layer** — ein großer Button „Start / New Layer" (Layer-Stapel-Icon in
   gestrichelten Ecken + grünes Plus, kleines ▼ unten rechts). Klick = fügt im
   Model-Browser „Layer N" hinzu (Dummy).
2. **Create** — große Buttons Line/Circle/Arc/Rectangle (je ▼-Flyout), rechts
   Spalte: Fillet ▾ / A Text ▾ / + Point. Flyouts (Einträge exakt):
   - Line: Line·Line, Line·Midpoint Line, Spline·Control Vertex,
     Spline·Interpolation, Equation Curve, Bridge Curve
   - Circle: Center Point, Tangent, Ellipse
   - Arc: Three Point, Tangent, Center Point
   - Rectangle: Two Point, Three Point, Two Point Center, Three Point Center,
     Slot Center to Center, Slot Overall, Slot Center Point, Slot Three Point
     Arc, Slot Center Point Arc, Polygon
   - Fillet: Fillet, Chamfer   /   Text: Text, Geometry Text
   Flyout-Einträge zweizeilig (fett + Untertitel), erster Eintrag hervorgehoben.
   Flyouts öffnen DIREKT unter dem geklickten Element (anchor.bottom).
3. **Project Geometry** — nur der große Button (isometrische blaue Ebenen),
   KEIN Dropdown.
4. **Pattern** — Rectangular (blaues Quadrat-Raster), Circular (blauer
   Punktring), Mirror (Dreieckpaar), Titel „Pattern".
5. **Constrain** — großer „Dimension"-Button (weißes |←→|-Glyph) + 5×3-Grid:
   Reihe1: AutoDim(⚡gelb), Coincident, Collinear, Concentric, Lock(rot);
   Reihe2: Show Constraints(⚡), Parallel, Perpendicular, Horizontal, Vertical;
   Reihe3: Constraint Settings, Tangent, Smooth(G2), Symmetric, Equal.
   Rote Glyphen mit grauen Cursor-Pfeilen/Checks, Hatch-Striche bei H/V.
   Titel „Constrain ▼".
6. **Insert** — Image / Points / ACAD (farbige Icons), Titel „Insert".
7. **Format** — Grid: Driven Dimension (oben, colspan), Kugel + Crosshair
   (Crosshair im AKTIV-Rahmen blau), darunter Zeile „Show Format" (colspan,
   darf nicht überlaufen — Grid-Spalten `auto`). Titel „Format ▼".
8. **Modify** (LETZTER Block) — 3×3: Move/Copy/Rotate | Trim/Extend/Split |
   Scale/Stretch/Offset, blaue Inventor-Icons, Titel „Modify".

**Model-Browser links (300px, Inventor-Stil):**
- Header: Tab „Model ✕", „+", rechts 🔍 und ☰.
- Baum: blauer Würfel „Sketch1" (nicht Part1); KEIN Representations-Ordner;
  „Origin"-Ordner mit +/−-Expander → Kinder: X Axis (rot), Y Axis (blau),
  Center Point (**automatisch projiziert**, blauer Grip, Tooltip);
  danach Container `#layers` (hier landen „Layer 1..N");
  unten „End of Sketch" (roter ✕-Kreis).
- Rechtsklick auf Layer-Zeile → Kontextmenü (Dummy): **Edit** (oberster
  Eintrag), Copy, Duplicate, „Export only this layer", „Toggle visibility".
- Rechts daneben Viewport `#212830`.
- ALLES nur Design-Dummy: „Funktionen" sind Flyouts, Origin-Expander,
  Layer-Hinzufügen, Kontextmenü, Edit-Modus, Home/Tabs (siehe unten).

**Layer-Edit-Modus (im Mock umgesetzt, Verhalten übernehmen):**
- „Start New Layer" legt „Layer N" im Browser an UND startet sofort den
  Edit-Modus für diesen Layer.
- Edit-Modus für BESTEHENDE Layer: Doppelklick auf die Layer-Zeile ODER
  Rechtsklick → „Edit".
- Im Edit-Modus:
  - Die aktive Layer-Zeile wird im Model-Browser hervorgehoben
    (Inventor-Stil: Hintergrund `#3A4149`, 1px-Outline `#5A88B5`, Text weiß).
  - Im Viewport erscheinen X- und Y-Achse als **graue Linien** (`#6b7178`,
    1px) und der Center Point als **grauer Punkt** — alle drei NICHT
    interaktiv (pointer-events:none), reine Referenz-Geometrie.
  - ÜBER dem grauen Center Point liegt ein **gelber projizierter Punkt**
    (`#E8C63F`, Rand `#9a8320`, Tooltip „Projected Center Point").
    Regel: **Projiziertes ist GELB. Interagieren kann man NUR mit
    projizierten oder gezeichneten Elementen**, nie mit der grauen
    Roh-Geometrie.
  - Oben rechts im Ribbon erscheint das **Exit-Panel**: großer grüner Haken
    (`#3FA43C`, dicker Strich), Beschriftung „Finish ▼", Panel-Titel „Exit"
    (exakt wie Inventor-Screenshot). Klick auf Finish beendet den Edit-Modus
    (Highlight, Achsen-Overlay und Exit-Panel verschwinden).

**Untere Tab-Leiste (30px, `#14171B`, wie Inventor):**
- Links „🏠 Home", daneben ein Tab pro geöffneter Skizze mit ✕ zum Schließen;
  aktiver Tab heller (`#262B31`) mit 2px blauer Unterkante (`#2f7bd6`);
  ganz rechts ☰. Schließen des aktiven Tabs wechselt zum letzten offenen
  Tab, sonst zurück zur Home-View.

**Home-View (vereinfachte Inventor-Startseite, App-Start-Zustand):**
- KEIN Model-Browser, KEIN Viewport, im Ribbon werden ALLE Panels versteckt;
  einziges Panel/Tool: großer Button „Create New Sketch" (Rechteck-Skizzen-
  Icon mit blauen Grips + grünes Plus), Panel-Titel „Sketch".
- Inhalt: Überschrift „Recent" + Karten-Grid (190px-Karten `#24282D`,
  Hover-Rand blau): dunkle Vorschaufläche (radialer Gradient) mit
  Sketch-Würfel-Icon, darunter Name (fett) + Datum. 6 Dummy-Beispiel-
  Skizzen ohne Inhalt (Bracket_v2, Flange, Plate_120x80, Gasket,
  Shaft_Profile, Cam_Outline). KEIN Sortieren/Suchen/Pinnen (bewusst
  weggelassen — einfacher als Inventor).
- Klick auf eine Karte öffnet die Skizze (Tab entsteht, Model-Browser-
  Wurzel zeigt den Skizzennamen); „Create New Sketch" erzeugt
  Sketch1, Sketch2, … und öffnet sie direkt.

## Frühere funktionierende Tool-Engine (Referenz, aktuell NICHT im Mock)
In einer früheren Iteration dieses Chats existierte eine Canvas-Engine
(ipadprocad-ribbon.html, überschrieben) mit: Line/Polyline/Circle(CR/2P/3P)/
Arc(3P/Center)/Rectangle/Ellipse/Point; Move/Copy/Rotate/Mirror/Scale/Erase/
Offset; Snapping (Endpunkte, Ursprung, projizierte Achsen); Achsen-Projektion;
**Dimension-Tool wie Inventor** (Shortcut `d`): Linie→Platzieren=Länge,
2 Punkte=Abstand, 2 Linien=Winkel (Bogen, Strahl-Wahl nach Platzierung),
Kreis=Radius (R…), Punkt+Linie=Lotabstand; Live-Preview in Rot, Esc bricht ab.
Diese Logik muss in den finalen Mock bzw. direkt in Flutter neu integriert
werden (Design hat Vorrang, Verhalten wie beschrieben).

## Nächste Schritte — M5: Flutter-App (Vorgabe des Nutzers, NICHTS auslassen)
Der Nutzer hat den nächsten Schritt exakt so definiert:

1. **Das GESAMTE Design genau so für Flutter machen.** 1:1-Port des
   HTML-Mocks (`create-panel.html`) — Design, alle Buttons, Funktionen,
   Flyouts, Model-Browser, Layer-Edit-Modus, Finish-Button, Home-View,
   Tab-Leiste, Farben, Icons: **alles exakt gleich wie in diesem Prototyp.**
   Das ist dem Nutzer sehr wichtig: **1:1 wie im HTML.**
2. **Eingabe-Optimierung fürs Erste: Keyboard + Maus am iPad.**
   Touch-Bedienung (Fingergesten auf dem Screen, Long-Press statt
   Rechtsklick etc.) kommt ERST SPÄTER, nicht in dieser Version.
   AUSNAHME (gehört in die ERSTE Version): **Pan mit 2 Fingern auf dem
   Touchpad und Zoom per Pinch auf dem Touchpad** müssen integriert sein.
3. **Erster Funktionsschritt: einfaches Zeichnen mit dem Backend.**
   Einfache Linien, Kreise, Rechtecke und ein paar weitere Grundformen
   werden REAL über das QCAD-Backend (C-API/FFI) umgesetzt.
   **Alles andere bleibt in der UI integriert/sichtbar, ist aber noch
   nicht umgesetzt** (Buttons vorhanden wie im Mock, ohne Funktion).
4. **Saving und Loading auf dem iPad als erster Schritt einrichten,
   ebenso die Preview-Erstellung** (Vorschaubilder der Skizzen für die
   Recent-Karten der Home-View).
5. **Test-IPA-Build erstellen, den der Nutzer auf dem iPad installieren
   kann** — mit diesen einfachen Funktionen und dem QCAD-Backend.

Der Nutzer stellt im neuen Chat **das HTML (`create-panel.html`) und einen
neuen PAT selbst zur Verfügung.**

### Technische Anknüpfung (aus M4-Planung, weiterhin gültig)
- `frontend/` neu aufsetzen (flutter create, ffi ^2.1.0), Ribbon/Browser/
  Canvas/Home/Tabbar als Widgets, SVG-Icons via CustomPainter oder
  flutter_svg; alten `main.dart` (8e241b3) ersetzen.
- XCFramework linken (CI-Artefakt `ipadprocad-ios-capi`) + Qt-iOS-Static-Libs
  (Liste in `src/capi/CMakeLists.txt`); Achtung Qt-main-Wrapper vs.
  Flutter-main (headless: libqios ggf. weglassen).
- Erster echter Dart-FFI-Lauf (M2-Restschuld): `bindings/dart/qcad_ffi.dart`,
  Logik aus `example/qcad_smoke.dart`, Marker `DART SMOKE: PASS`.
- CI-Job macos-14: `flutter build ios --simulator`, install + launch
  --console-pty, Marker-Urteil, **pipefail AUSSEN vor dem Block**, Timeouts,
  Screenshot-Artefakt (retention-days: 3). Für den Nutzer-Test zusätzlich
  Device-Build/IPA (unsigniert bzw. Sideload-fähig, z. B. via AltStore/
  Sideloadly — mit Nutzer klären).
- C-API um Geometrie-Abfrage erweitern (`qcad_entity_geometry(idx,…)`)
  für echtes Rendering aus dem QCAD-Dokument; Save/Load über vorhandenes
  `load/save_dxf` (Dokumente + Preview-PNGs im App-Documents-Verzeichnis).
- Design-Detailhinweise aus der Mock-Review (nicht blockierend, bei
  Gelegenheit): Touch-Trefferflächen erst relevant, wenn Touch kommt;
  Platz für Maß-Eingabe/Statuszeile beim Canvas-Layout einplanen.

## Backend-Kurzreferenz (unverändert, Details im README)
- Build lokal (Ubuntu): cmake+ninja+qt6-base/declarative/svg;
  `cmake -B build -G Ninja -DBUILD_QT6=ON -DCMAKE_BUILD_TYPE=Release`,
  `cmake --build build -j -- -k 0`. Smoke: `-DQCAD_CAPI_SMOKE=ON` →
  `./release/qcad_capi_smoke` = „SMOKE: PASS".
- C-ABI (`src/capi/qcad_capi.h`): qcad_init/version, document_new/free,
  add_line/circle/arc/polyline, entity_count, bounding_box, load/save_dxf.
- Fallstricke: Property-Init-Liste in qcad_capi.cpp (46 Klassen, RColor/
  RLineweight privat=auslassen); Storage/SpatialIndex heap-allozieren, NUR
  RDocument löschen (Doppel-Free); RSettings via QCoreApplication+Org-Name;
  iOS-Configure braucht `-DCMAKE_BUILD_TYPE=Release`; `set -o pipefail` VOR
  `{…}|tee`-Blöcken (zweimal falsches Grün dadurch!); Qt-iOS-Prebuilt:
  arm64=Device, x86_64=Simulator (Rosetta), kein arm64-Sim-Slice;
  `simctl spawn` hängt → install + `launch --console-pty`; Info.plist im CI
  überschreiben; smoke.c nutzt TMPDIR; Apple-Link ohne --start-group.
- Spline/opennurbs, spatialindex, snap/grid, Hatch/Text: zurückgestellt
  (`R_NO_OPENNURBS` etc.) → im UI ausgegraut.
- CI: `.github/workflows/m1-core-build.yml` (build-core-ios +
  m3-ios-sim-logic). Logs werden in Branches committet:
  `ci-debug-logs/ci-logs/*` (M1/M2), `ci-debug-logs-m3/ci-logs-m3/*` (M3).
  `**.md`-Commits triggern kein CI. Artefakt-Retention 3 Tage.

## Nützliche Pfade
```
backend/qcad-core/src/capi/               C-ABI (qcad_capi.h/.cpp, tests/smoke.c)
backend/qcad-core/bindings/dart/          Dart-FFI (noch nie ausgeführt)
.github/workflows/m1-core-build.yml       CI
frontend/                                 VERALTETER erster UI-Wurf (ersetzen)
create-panel.html                         FINALER UI-Mock inkl. Edit-Modus/Home/
                                          Tabs (vom Nutzer bereitgestellt)
```
