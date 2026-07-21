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

> **Stand dieser Session (Kopf = M48, natives Kontextmenue):** M48 ist neu
> und host-getestet (**245 Tests gruen**, `flutter analyze` ohne neue Issues).
> Der IPA-Job baut jetzt auf **macos-26 (Xcode 26 / iOS-26-SDK)** — siehe M48.
>
> **Stand davor (Kopf = commit `05727ec` + M46 + M47):** letzte
> Arbeiten M41–M47, alle host-getestet (**222 Tests gruen**, `flutter analyze`
> ohne neue Issues). Kurz:
> - **M41** Inventor-Parameter/Ausdruecke im Bemassungs-Edit-Feld (d0/d1,
>   Formeln, Referenzen, fx:-Anzeige).
> - **M42** Hover-Highlight auf Bemassungs-Labels; ausserhalb des
>   Layer-Editiermodus sind Bemassungen/Constraints/DOF/Construction
>   unsichtbar. **M42-Fix** Tastatur-Race beim Referenz-Klick.
> - **M43** Parameters-Fenster (fx, verschiebbar) mit User-Parametern.
> - **M44** Insert: parametrischer Text, Bild-Import, DXF-Import (iOS-Picker).
> - **M45** Insert-Geraete-Fixes (Bild-Resize-Griff, Layer-Dimming,
>   Cursor-Platzierung, DXF-Rezentrierung) + verschiebbares Text-Fenster
>   (Font/Groesse/Klick-Referenz `"d0"`) + auto-grosses Construction-
>   Bounding-Rect mit Ecken-Snap-Punkten.
> - **M46** Tastenkuerzel werden unterdrueckt, waehrend ein Textfeld
>   (Parameters/Text/Inline-Bemassung) getippt wird.
> - **M47** Direkter Body-Drag: Linie/Kreis/Bogen/Polylinie/Spline/Ellipse am
>   KOERPER (nicht nur am Punkt-Griff) starr verschieben; angebundene Geometrie
>   folgt ueber die Constraints. Eingebettet in die Griff-Zug-Maschinerie
>   (`Grip.body`-Sentinel in `dragGrip`, neue `translateGeo`, Body-Drag meldet
>   ALLE Entity-Punkte als `dragged`). Voll gebundene Geometrie ist gesperrt
>   (faellt auf Box-Select zurueck), Projektionen/Fremd-Layer nicht ziehbar,
>   Begin lazy beim ersten Move (Tap waehlt weiter aus, kein No-Op-Rebuild),
>   kein Snapping (reine Translation). `m47_body_drag_test.dart` (8 Tests).
>
> **Offene Punkte fuer die naechste Session:**
> - Geraete-Test von M41–M47 steht aus (Host-Tests gruen, IPA aus Run
>   `05727ec`/spaeter ziehen und auf dem iPad pruefen). Fuer M47 auf dem Geraet
>   pruefen: Body-Drag fuehlt sich per Pencil/Finger fluessig an, die
>   Tap-vs-Drag-Trennung (Greifpunkt-Toleranz `_gripPx`=12 px) stimmt, und der
>   Zug an einer angebundenen Linie fuehrt die Nachbargeometrie erwartungsgemaess
>   nach (natives libslvs = weicher Wunsch, waehrend der Host-LM-Pfad ALLE
>   Entity-Punkte hart friert — auf dem Geraet also potenziell "weicher").
> - Text-Bounding-Rect ist ein Painter-Overlay mit Snap-Punkten, KEINE echte
>   Solver-Geometrie (siehe M45): an die Ecken kann man bemaßen, die Kanten
>   sind aber keine selektierbaren, constrainbaren Entities. Volle
>   Solver-Integration (wie projizierte Geometrie gepinnt) waere der naechste
>   grosse Schritt, falls gewuenscht.
> - `file_picker` ist die erste Plugin-Abhaengigkeit (M44) — CI-Pod-Install
>   im iOS-Build von `05727ec`/spaeter verifizieren.


- **M1 — Headless-Core-Build + iOS-CI: ERLEDIGT** (statische Libs, arm64/iphoneos).
- **M2 — C-Wrapper: ERLEDIGT & validiert**; in M5 um Geometrie-Abfrage erweitert
  (`qcad_entity_ids`, `qcad_entity_geometry`), lokal per Compile-Check gegen die
  echten QCAD-Header validiert; Runtime-Validierung via erweiterten smoke.c im
  M3-Sim-CI-Job (Marker lesen!).
- **M3 — Headless-Logiktest iOS-Simulator: ERLEDIGT** (smoke.c jetzt inkl.
  Geometrie-Query-Checks — Log des naechsten Runs pruefen).
- **M4 — Mock-Phase ABGESCHLOSSEN** (create-panel.html = verbindliche 1:1-Spec,
  UI-Details siehe Abschnitt unten).
- **M5 — Grundausbau ERLEDIGT & CI-validiert (Run 29145382350, alle 3 Jobs
  gruen, LOGS GEPRUEFT):**
  - `frontend/` KOMPLETT NEU: 1:1-Flutter-Port des Mocks (Ribbon alle 8 Panels
    + Exit/Finish + Home-Sketch-Panel, Flyouts mit exakten Eintraegen,
    Model-Browser inkl. Origin-Expander/Kontextmenue/Edit-Highlight,
    Layer-Edit-Modus mit grauen Achsen + gelbem projizierten CP, Home-View
    mit Recent-Karten, untere Tab-Leiste). Alter main.dart (8e241b3) ERSETZT.
    Struktur: lib/main.dart, theme.dart, svg_icons.dart (Mock-SVGs verbatim,
    flutter_svg), app_state.dart, ffi/qcad_engine.dart, widgets/{ribbon,
    model_browser,viewport,home_view,bottom_tabbar}.dart
  - Echtes Zeichnen ueber das Backend: Line, Circle (Center), Rectangle
    (Two Point, geschlossene Polyline), Arc (Three Point) via FFI; Rendering
    aus dem QCAD-Dokument (qcad_entity_ids/qcad_entity_geometry — Linux-Smoke
    UND iOS-Sim-Smoke PASS inkl. Geometrie-Checks). Uebrige Buttons sichtbar,
    ohne Funktion. Fallback-Engine (Dart) wenn Libs nicht gelinkt; Start-
    Marker: `DART SMOKE: PASS (backend=qcad-ffi|dart-fallback)`.
  - Save/Load: DXF pro Skizze + Preview-PNG in App-Documents (Autosave bei
    Finish/Tab-Schliessen/Home); Recent-Karten zeigen echte Skizzen, die 6
    Design-Dummies nur im Erststart.
  - Eingabe: Maus/Keyboard; Trackpad-2-Finger-Pan + Pinch-Zoom (PointerPanZoom)
    integriert, Scrollrad zoomt, Esc bricht Tool ab. Touch-Gesten spaeter.
  - **IPA: CI-Job `m5-flutter-ipa` liefert Artefakt `ipadprocad-unsigned-ipa`**
    (unsigniert, ~15 MB, Retention 3 Tage — pro Run neu erzeugt). Verifiziert:
    "M5 LINK CHECK: PASS" + alle 14 `_qcad_*`-Symbole per nm EXPORTIERT im
    Runner-Binary (DynamicLibrary.process() findet sie). Installation:
    Artefakt laden, entzippen -> ipadprocad-unsigned.ipa, per Sideloadly oder
    AltStore aufs iPad (re-signiert mit eigener Apple-ID).

  **CI-Fix-Erkenntnisse M5 (fuer die Zukunft):**
  - Qt-Static-Link fuer Xcode NICHT per Archiv-Glob: die QQml*Foreign-
    Registrierungsobjekte GENERIERT der Qt-CMake-Finalizer im Konsumenten-
    Build, sie existieren nicht im Qt-Paket. Loesung: Device-Smoke mit
    `-DQCAD_CAPI_SMOKE=ON` bauen und die exakte Linkzeile via
    `ninja -C build -t commands` extrahieren (Ninja hat KEIN link.txt),
    mit `ci/parse_link_txt.py` in OTHER_LDFLAGS uebersetzen (cwd=Build-Root).
  - qcad_* ueberleben per `-force_load libipadprocad.a` +
    `-Wl,-exported_symbols_list` (`_qcad_*`); qios-Plugin NIE linken
    (interponiert main). IPHONEOS_DEPLOYMENT_TARGET=14.0 im pbxproj sedden
    (Target-Settings schlagen xcconfig).
  - `strings | grep -q` unter pipefail = SIGPIPE-Falle -> `grep -c` nutzen.

  **Offen fuer M6:**
  - Nutzer-Test des IPA auf dem iPad (App-Start-Marker `DART SMOKE:` in der
    Konsole pruefen — MUSS `backend=qcad-ffi` melden, nicht dart-fallback).
  - Sim-CI-Job, der den DART-SMOKE-Marker der Flutter-App captured
    (M2-Restschuld formal; Symbole sind exportiert, Runtime on device offen).
  - Weitere Werkzeuge aus der frueheren Tool-Engine (Dimension, Modify, Snap),
    Layer-Zuordnung im Backend (aktuell eine Backend-Layer "0",
    Layer-Zuordnung nur Dart-seitig), Touch-Gesten.

- **M8-Fix / M9–M11 — Parametrik + echter Constraint-Solver (libslvs): ERLEDIGT
  & CI-validiert (Run 168b35e, beide Workflows alle Jobs gruen, Schritt-Status
  gelesen). NUR GERAETE-TEST OFFEN.**
  - QCAD hat KEINEN Constraint-Solver (Maintainer bestaetigt, kein geplant) →
    Pfad B: SolveSpace-Solver `libslvs` (GPLv3, C-API) via FFI eingebettet,
    QCAD bleibt fuer Geometrie/DXF.
  - **M9** `backend/slvs/`: libslvs vendored (nur C++-stdlib, keine Deps),
    baut STATISCH fuer iOS (arm64/iphoneos, min 14.0) → `build-ios/libslvs.a`.
    Eigener Workflow `slvs-build.yml` (Host-Smoke + iOS-Static, beide gruen).
  - **M9.2** FFI-Shim `backend/slvs/shim/slvs_shim.{h,cpp}`: eine flache
    C-Funktion `slvs_solve(...)` ueber libslvs; deckt alle CTypes +
    Dimensionen ab (H/V, coincident, point-on-line, parallel/perp, collinear,
    concentric, equal, tangent, symmetric, dist/dist-x/-y, dia/rad, angle,
    dragged). `tests/shim_test.c` asserted die realen App-Szenarien numerisch
    (Rechteck+Breite, Kreis-Durchmesser, Punkt-auf-Linie, X/Y-Mass, Ueber-
    bestimmung, Drag) → „ALL SHIM TESTS PASS" (Host-CI-Gate).
  - **M10** Dart: `frontend/lib/ffi/slvs_ffi.dart` (Bindings via
    DynamicLibrary.process()); `solver.dart` `_trySolveWithSlvs()` zerlegt den
    Sketch → Punkte+Entities, mappt Constraints, ruft nativ, VERIFIZIERT das
    Ergebnis ueber die vorhandenen Dart-Residuen und faellt bei Nicht-Erfuellung
    / ungelinktem Symbol / ungemapptem Feature (smooth) auf den Dart-LM-Solver
    zurueck → libslvs ist STRIKT SICHER (nie schlechter als vorher).
  - **M10 UX** (Inventor): Auto-Constraints IMMER an (Button entfernt,
    `autoConstrain` final true); DOF-Faerbung pro Entity (weiss=voll bestimmt,
    violett-blau 0xFF9A8CF5=unterbestimmt, blau=selektiert); Live-Bemassungs-
    Preview (nach Auswahl folgt das Mass dem Cursor, Klick platziert); Masse
    mm-Default + cm/m-Eingabe; klareres Coincident-Icon; Rechteck/Polyline
    Auto-H/V + Ecken-Auto-Coincident/Point-on-Line.
  - **M11** iOS-Link: neuer Job-Schritt baut `libslvs.a`, `ffi.xcconfig`
    `-force_load libslvs.a` + Export `_slvs_*`, Link-Check greppt den Shim-
    Marker „iPadProCAD SLVS shim" per `strings` im Runner (analog QCAD-Check,
    PASS). → auf dem Geraet ist `SlvsFfi.available` true, `solveConstraints`
    nutzt den echten Solver.
  - **OFFEN (nur auf dem iPad pruefbar, hier nicht):** Laufzeit-Verhalten des
    nativen Solvers + der neuen UX auf dem Geraet. Das Verify+Fallback-Netz
    garantiert nur „nicht schlechter als Dart-Solver", nicht die exakte
    Wunsch-Semantik. Beim Test: Rechteck geht auf Masseingabe sauber auf,
    Faerbung weiss/violett stimmt, Bemassungs-Preview folgt dem Cursor,
    Auto-Constraints ohne Button. IPA-Artefakt aus dem M5-Job (unsigniert).

- **M11-Fix — Fenster wieder heil (Geraete-Test 1): ERLEDIGT.** Auf dem iPad war
  der Ribbon zerrissen und der Model-Browser weg: ein RangeError im
  Constrain-Grid liess den Build-Callback werfen, im RELEASE-Build ersetzt
  Flutter das dann durch ein graues ErrorWidget (kein roter Debug-Screen) —
  daher der graue Block statt Viewport/Browser. MERKE: grauer Kasten in der App
  = geworfene Exception, nicht Layout-Pfusch.

- **M12 — Auto-Coincident auf den projizierten Center Point: ERLEDIGT
  (Geraete-Test 2 offen).** Symptom: eine Rechteck-Ecke rastet per 'origin'-Snap
  exakt auf den CP, blieb aber frei verschiebbar. Ursache: der projizierte CP ist
  KEINE Entity — der Viewport malt ihn nur per `map(0,0)`, und
  `inferConstraints` vergleicht neue Punkte ausschliesslich gegen vorhandene
  Entities (`j < newIdx`). Zum Ursprung gab es also nichts zu binden.
  - Loesung: Sentinel `kProjCenter = -1` (`constraints.dart`) als Punkt-Ref auf
    den CP. `inferConstraints` erzeugt bei `|q| < 1e-6` ein echtes
    Coincident `PRef(-1,0) <-> PRef(neu,p)` — mit Vorrang vor Endpunkt- und
    Point-on-Line-Inferenz.
  - Der Dart-LM-Solver konnte das SCHON: `_pointAt` liefert fuer `ent < 0`
    Offset.zero (keine freien Parameter), `residualCount` zaehlt 2 Gleichungen
    -> Punkt ist voll bestimmt, DOF sinkt um 2, Faerbung wird weiss.
  - libslvs: `pOf` mappt `ent < 0` jetzt auf einen LAZY angelegten Punkt
    `addPoint(0,0, fix: true)`. Ohne das waere das Constraint stillschweigend
    gefallen, das Verify-Netz haette gegriffen und JEDE Skizze mit Ursprungs-Snap
    waere auf den Dart-Solver zurueckgefallen.
  - Fallstrick mitgefixt: `constraintGlyphs` haette `gs[-1]` indiziert ->
    RangeError -> grauer Screen (siehe M11-Fix). Guards jetzt ueber `isRealPt`.
  - Ebenfalls mitgefixt: `remapAfterRemove` hat beim Loeschen einer Entity
    `anchors` und `driven` verschluckt — Fix-Constraints verloren ihren Anker,
    Referenzbemassungen wurden wieder treibend.
  - NICHT enthalten: der CP ist weiterhin nicht als manuelles Constraint-/
    Bemassungsziel pickbar (`_projCpSelected` im Viewport ist nur ein Farb-
    Toggle aus dem Mock). Mit dem Sentinel waere das jetzt leicht nachzuruesten.

- **M13 — Voll bestimmte Punkte sind nicht mehr von Hand ziehbar + Lock immer
  anwendbar: ERLEDIGT (Geraete-Test offen).**
  - **Grip-Drag:** ein gegroundeter Punkt liess sich weiter mit der Maus greifen
    und verschieben und sprang beim naechsten Solve zurueck. Ursache:
    `displayGeometry` PINNT den gezogenen Punkt hart am Cursor
    (`pinned: {(ent,idx)}`), das schlaegt jedes Constraint — beim Loslassen
    gewinnt dann wieder das Coincident. Inventor laesst voll bestimmte Geometrie
    gar nicht erst anfassen: der Grip-Hittest im Viewport ueberspringt jetzt
    Grips, deren Punkt nicht in `analysis.freePoints` liegt (Geste faellt auf
    Box-Select durch), `beginGripDrag` guardet zusaetzlich.
  - **FALLE dabei:** `Grip.idx` ist NICHT immer ein Punktindex — ein Kreis hat
    genau 1 Punkt (Mittelpunkt), seine Radius-Grips tragen idx 1..4. Der Filter
    greift darum nur fuer `idx < ptCount(entity)`, sonst waeren Kreise nicht mehr
    skalierbar gewesen.
  - **Lock/Fix:** war "manchmal nicht anwendbar", weil `_addConstraint` JEDES
    Constraint durch `wouldOverconstrain` schickt. Fix traegt 2 Gleichungen pro
    Punkt bei; hatte das Ziel weniger freie DOF uebrig, stieg der Rang nicht um 2
    -> abgelehnt. Fix ist aber kein normales geometrisches Constraint: es groundet
    Geometrie WO SIE IST (Anker = aktuelle, bereits geloeste Position), kann also
    nie widersprechen — libslvs modelliert es nicht mal als Gleichung, sondern
    setzt `fixed[gi]=1`. Fix ist jetzt vom Ueberbestimmungs-Test ausgenommen und
    wird nur noch abgelehnt, wenn dasselbe Ziel (oder die besitzende Entity)
    schon gelockt ist.
  - **Mitgefixt:** `analysis` haengt an AppState, wurde aber beim Wechsel auf
    einen BEREITS OFFENEN Tab nicht neu berechnet — die DOF-Faerbung zeigte dann
    die vorige Skizze, und mit dem neuen Grip-Filter waeren die falschen Punkte
    gesperrt gewesen. `_reanalyze()` haengt jetzt an goHome/openSketch/closeTab.

- **M14 — Live-korrekter Drag, Bemassung auf Rechteckkanten, Hover-Highlight:
  ERLEDIGT (Geraete-Test offen).**
  - **Drag (der eigentliche Bock).** Symptom: beim Ziehen einer Ecke wurde die
    "vertikale" Kante schraeg und der gegroundete Punkt wanderte mit; erst beim
    naechsten sauberen Solve sprang alles zurueck. Kette aus DREI Fehlern:
    1. `SH_DRAGGED` war auf `SLVS_C_WHERE_DRAGGED` gemappt. Das ist ein HARTES
       Constraint ("Punkt ist exakt hier") und ueberstimmt damit die echten.
       Nachgemessen: Vertical + gelocktes Ende + Zug nach (25,55) ergab (25,55)
       — das Vertical wurde einfach ignoriert.
       RICHTIG ist `Slvs_System.dragged[]` (slvs.h Z.160): "causes the solver to
       favor that parameter, and attempt to change it as little as possible".
       Das ist der WEICHE Wunsch. Ergebnis jetzt: (0,55) — x haelt, y gleitet.
    2. Der Shim warf konvergierte Loesungen weg: libslvs faltet
       `REDUNDANT_OKAY` auf `SLVS_RESULT_INCONSISTENT` (lib.cpp), der Shim
       kopierte Koordinaten aber nur bei OKAY zurueck. Jetzt auch bei
       INCONSISTENT — das Dart-Verify entscheidet, ob es taugt.
    3. Der Dart-Fallback fror die gezogenen Parameter ein (`frozen[]`). Bei
       unerreichbarer Cursor-Position rechnet LM dann einen Least-Squares-
       Kompromiss, der die CONSTRAINTS verbiegt. Jetzt freeze-then-relax:
       erst Cursor exakt versuchen, und nur wenn die Constraints so nicht
       halten, Freeze fallen lassen und die Skizze zurueck auf die
       Constraint-Mannigfaltigkeit ziehen.
    - Regressionstests im Host-CI-Gate: `shim_test.c` [7] (Constraint gewinnt,
      Punkt gleitet, Anker unbewegt) und [8] (Rechteck bleibt Rechteck, Anker
      haelt, Breite kollabiert nicht).
  - **Bemassung auf Rechteckkanten.** `buildDimensionAt` kannte nur
    line/circle/arc — ein Rechteck ist aber EINE geschlossene Polyline, also kam
    `null` zurueck und es passierte gar nichts. `_dimensionClick` loest den Klick
    jetzt auf das Segment darunter auf (`polySegmentAt`) und bemasst dessen zwei
    Ecken: echte treibende Laengenbemassung ueber den vorhandenen
    Punkt-zu-Punkt-Pfad, inklusive ausgerichtet/horizontal/vertikal.
    NICHT enthalten: Winkelbemassung zwischen zwei Polyline-Kanten (braucht
    Entity-Refs auf Linien).
  - **Hover-/Pick-Highlight.** Es gab gar keinen Entity-Hover-State. Neu:
    `hoverEnt` / `hoverEdge` (bei Polylines die exakte Kante unter dem Cursor)
    und `pickedEdge`; der Painter legt einen Halo UNTER die Geometrie, damit die
    DOF-Faerbung darueber lesbar bleibt. Picks von Bemassungs-/Constraint-Tools
    bleiben markiert, bis das Kommando fertig ist.

- **M15 — Diagnose-Log auf dem Geraet: ERLEDIGT.** Der Logger existierte, aber
  `solver.dart` hatte NULL Log-Aufrufe (der Drag-/Solver-Pfad war blind), und
  `_write` machte `flush:true` PRO ZEILE — bei 60 Solves/s haette das genau die
  Interaktion abgewuergt, die es aufzeichnen soll.
  - Jetzt gepuffert (120 Zeilen / 400 ms / Lifecycle), WARN+ERROR sofort
    synchron (ueberlebt harten Crash). `Log.every(key, ms)` drosselt die
    60-Hz-Pfade. Rotation bei 8 MB, Commit-SHA per `--dart-define=GIT_SHA`.
  - `diag.dart`: reproduzierbare Dumps von Geometrie + Constraints, dazu
    `geoFinite`/`allFinite`/`maxAbs` und `gripStr` (zeigt, ob `grip.idx`
    ueberhaupt ein Punktindex ist — bei Kreisen ist er das fuer die vier
    Radius-Grips NICHT).
  - LOG-PFAD: Dateien-App > Auf meinem iPad > ipadprocad > logs >
    `ipadprocad_log.txt` (die Info.plist-Keys setzt der M5-Job bereits).
  - SCHRANKEN (zugleich Fix): `displayGeometry` laeuft INNERHALB von
    `CustomPainter.paint`. Eine Exception dort bricht den Paint ab, alles danach
    bleibt ungemalt — das sieht aus, als waere die Geometrie verschwunden. Und
    NaN/Inf laesst Skia kommentarlos fallen. Beides wird jetzt abgefangen,
    geloggt und auf die letzte gute Geometrie zurueckgefallen; `solveConstraints`
    verweigert nicht-endliche Ergebnisse, der Paint-Loop guardet pro Entity.

- **M16 — Geometrie strikt an Layer gebunden + Sichtbarkeits-Auge: ERLEDIGT
  (Geraete-Test offen).** Vorher kannte die Engine ueberhaupt keine Layer,
  `s.layers` war eine reine Namensliste, und zeichnen ging auch ohne Edit-Mode —
  "jede Linie gehoert zu einem Layer" war damit schlicht nicht wahr.
  - **Backend:** C-API um `qcad_layer_add` / `qcad_set_current_layer` /
    `qcad_entity_layer` erweitert. `addEntity` bindet die Entity VOR dem
    Einfuegen an den aktuellen Layer (`RLayer` + `REntity::setLayerId`) —
    dadurch ueberlebt die Zuordnung den DXF-Roundtrip. Die Export-Liste ist
    `_qcad_*` (Wildcard), neue Symbole sind also automatisch dabei.
  - **FALLE (wichtigste Lehre):** `Geo` traegt jetzt einen `layer`, und der
    SOLVER SCHREIBT BEI JEDEM SOLVE JEDE ENTITY NEU. Ohne `Geo.withData()`
    (behaelt den Layer) waere nach dem ersten Drag die ganze Skizze auf Layer 0
    gelandet. Darum: `withData`/`onLayer` statt roher Konstruktor, und
    Modify/Fillet stempeln den Quell-Layer an den FUNKTIONSGRENZEN
    (`_sameLayer`/`_sameLayerAll`), nicht an ~20 Konstruktionsstellen.
  - **Edit-Mode:** `selectTool` und `toolClick` verweigern ausserhalb des
    Edit-Modes, das Ribbon bricht schon vor dem Parameterdialog ab. Neue
    Geometrie wird im `_commitTool` zwingend auf `editingLayer` gestempelt — das
    ist die EINZIGE Stelle, an der Geometrie entsteht. `_rebuildEngine` loggt
    laut, wenn eine Entity einen dem Sketch unbekannten Layer traegt.
  - **Auge:** pro Layer im Model Browser. Unsichtbare Layer werden nicht gemalt,
    nicht gepickt, nicht gesnappt, haben keine Grips und fliegen aus der
    Selektion. Sichtbarkeit filtert NIE die Geometrieliste — Constraint-Refs
    sind index-basiert, es wird nur uebersprungen. Snap darf gefiltert werden
    (`Snap` traegt keine Indizes), Grips NICHT (die tragen welche).
  - **Persistenz:** Layerliste kommt beim Laden aus dem Dokument zurueck (DXF
    Gruppencode 8); leere Layer + Auge-Zustand liegen in `<name>.layers.json`.

- **M17-Fix — Ribbon-Buttons waren fast alle tot (Hit-Test), Flyout wieder
  garantiert gefuellt.** Vom Nutzer gemeldet: „nur ein Werkzeug benutzbar, die
  Werkzeuge im Dropdown gehen nicht, Dropdown-Hintergrund durchsichtig".
  - **URSACHE (die eigentliche Lehre):** `GestureDetector` ist per Default
    `deferToChild`. Das Kind ist ueberall im Ribbon ein `Container` mit
    **`decoration:`** — und das ist eine `DecoratedBox`, die NIE einen Hit-Test
    schluckt. (`Container(color:)` waere eine `ColoredBox` und schluckt ihn
    sehr wohl — genau darum funktionierten die Model-Browser-Zeilen die ganze
    Zeit.) Getroffen hat also nur, was selbst hit-testbar ist: `Text`
    (`RenderParagraph.hitTestSelf == true`). Folge: grosse Create-Buttons nur
    auf dem Label-Wort klickbar, **jede icon-only Zelle (Constrain-Grid,
    Modify-Grid) komplett tot** (flutter_svg malt in eine RenderBox, die keinen
    Hit meldet), und im Flyout landete alles ausser dem Label-Text auf der
    hit-opaken `ColoredBox` des Menues → Tap wurde verschluckt, es passierte
    schlicht NICHTS.
  - **FIX:** `behavior: HitTestBehavior.opaque` auf `_Hover` (der Wrapper hinter
    JEDEM Ribbon-Button) und `_FlyRow`. Das ▼ hatte es schon — darum liess sich
    das Flyout immer oeffnen, aber nichts darin auswaehlen. Verschachtelung
    bleibt korrekt: das ▼ liegt tiefer im Hit-Test-Pfad und gewinnt die Arena,
    der Button-Body startet weiter das Default-Tool (Inventor-Verhalten).
  - **REGEL:** Jeder Ribbon-/Menue-Tap-Target braucht ein explizites
    `HitTestBehavior.opaque`. Ein Button, dessen einziges Kind ein Icon ist, ist
    ohne das nicht anklickbar — und faellt in keinem Analyzer-Lauf auf.
  - **DURCHSICHTIGES MENUE = LAYOUT-BUG, NICHT PAINT-BUG (die zweite Lehre).**
    Der Save-Layer/`BoxShadow`-Verdacht aus M7 war FALSCH — darum hat ihn
    wegzunehmen auch nichts geaendert. Wahre Ursache: ein `Positioned(left/top)`
    im Stack wird mit UNBESCHRAENKTEN Constraints gelayoutet, und
    `CrossAxisAlignment.stretch` in einer Column heisst
    `BoxConstraints.tightFor(width: constraints.maxWidth)` — also
    **tightFor(width: INFINITY)**. Jede Menuezeile bekam eine unendliche Breite.
    `BoxConstraints(minWidth: 186)` ist ein BODEN, keine DECKE, hat also nichts
    abgefangen. Im Debug-Build wirft das („was given an infinite size during
    layout"); im RELEASE-IPA sind die Asserts aus, die Groesse bleibt unendlich,
    Impeller verwirft den nicht-finiten `drawRect` (= die Fuellung) und malt nur
    noch die finiten Glyphen. Ergebnis: Icons und Labels schweben ohne Panel
    ueber der Skizze.
  - **FIX:** endliche Breite erzwingen — `ConstrainedBox(minWidth: 186,
    maxWidth: 320)` + `IntrinsicWidth` (haengt sich weiter an die breiteste
    Zeile, wie im Mock). Dieselbe Falle im Model-Browser-Kontextmenue
    (`_CtxRow` nutzt `width: double.infinity` unter demselben unbeschraenkten
    `Positioned`) → dort `maxWidth: 260` ergaenzt.
  - **REGEL:** Ein Overlay-Menue darf NIE die unbeschraenkten Constraints des
    Stacks erben. Immer eine harte Breiten-Decke setzen. Und: ein Fehler, der
    NUR im Release-IPA auftritt und im Debug wirft, ist fast immer eine
    verletzte Layout-Invariante — nicht der Rasterizer.
- **M18 — Produktionsreifes Layer-System (Lock / Rename / Delete / Move + ehrliches
  "0"): IMPLEMENTIERT, aber LOKAL NICHT GEBAUT.** Das Arbeits-Environment hatte
  weder Flutter (Dart-SDK-Host blockiert) noch Qt/Cmake, also steht die
  Verifikation ueber CI (`flutter analyze` + iOS-Build) UND der Geraete-Test noch
  aus. Frontend-only, nutzt bewusst den vorhandenen Backend-Layer-Pfad
  (Entity->Layer-Bindung + DXF-Roundtrip) — KEINE neue C++-API, damit der
  iOS-Build nicht durch ungetesteten Core-Code kippt.
  - **Ursache des Nutzer-Bugs ("alles landet auf Layer 0"): GEFUNDEN + GEFIXT in
    M19 (siehe unten).** Die fruehere Vermutung "IPA vor M16" war FALSCH — der
    Bug steckte im C-API: `qcad_set_current_layer` setzte nur den eigenen
    QString, aber NICHT den Dokument-Current-Layer, und `RTransaction` stempelt
    jede neue Entity mit `doc->getCurrentLayerId()` (== "0"). Empirisch mit dem
    echten QCAD-Core reproduziert und verifiziert.
  - **Lock:** `SketchModel.lockedLayers`. Gesperrter Layer bleibt sichtbar, ist
    aber read-only (kein Werkzeug, kein Pick/Drag/Constrain/Dimension, nie
    Editier-Layer). `geoEditable` + `enterEdit` respektieren es; Padlock im Model
    Browser neben dem Auge, im Kontextmenue Lock/Unlock.
  - **Rename:** stempelt alle Entities des Layers via `Geo.onLayer` um (ueberlebt
    so den DXF-Roundtrip), zieht Eye/Lock/Edit-Status mit. "0" ist gesperrt, und
    nach "0" umbenennen ist verboten (reserviert).
  - **Delete:** entfernt die Geometrie hoechster-Index-zuerst und remappt die
    index-basierten Constraints (`remapAfterRemove`, exakt wie Trim/Split). "0"
    kann nicht geloescht werden. Mit Bestaetigungsdialog.
  - **Move (Selektion -> Layer):** re-stempelt die aktuelle Selektion auf den
    Ziel-Layer. Das ist der Weg, ALTE Skizzen zu retten, deren Geometrie auf "0"
    gestrandet ist: (ausserhalb des Edit-Mode) alles per Box-Select waehlen ->
    Rechtsklick Ziel-Layer -> "Move N here".
  - **Ehrliches "0":** die Pflicht-DXF-Ebene "0" ist wie in AutoCAD nicht
    umbenennbar/loeschbar und wird NUR angezeigt, solange sie Geometrie traegt;
    leer fliegt sie aus dem Browser (`_pruneEmptyBaseLayer`) — kein Phantom mehr.
    Neue Skizzen starten weiterhin ohne Layer (Zeichnen erst nach "Start New
    Layer", Design-Vorgabe M16).
  - **Persistenz:** Sidecar jetzt versioniert (v2) mit Reihenfolge + hidden +
    locked; das alte `{layers,hidden}` wird weiter gelesen. Basis-"0" wird nur mit
    Geometrie persistiert, damit sie nach dem Leeren nicht zurueckkehrt.
  - **Reference-Darstellung:** im Edit-Mode wird Geometrie fremder/gesperrter
    Layer gedimmt (grau, `refPaint`) gemalt, damit die DOF-Farben des aktiven
    Layers lesbar bleiben.
  - **Bewusst NICHT enthalten (jeweils mit Grund):** per-Layer-Farbe fuer die
    Geometrie — kollidiert mit der Inventor-DOF-Faerbung (weiss=voll bestimmt,
    violett=unterbestimmt), die die App traegt; und Backend-Persistenz der
    Layer-Attribute (Farbe/Off/Locked) im DXF-Layertable — dafuer waere neue
    C++-API (`RLayer` get/set + Enumerate) noetig gewesen, die hier ohne Build
    nicht testbar war. Beides sind saubere Folge-Schritte (siehe unten).
  - **Geaenderte Dateien:** `frontend/lib/app_state.dart`,
    `frontend/lib/widgets/model_browser.dart`, `frontend/lib/widgets/viewport.dart`.
  - **Naechster Schritt fuer Backend-Persistenz (falls gewuenscht):** die
    C-API-Skizze steht — `qcad_layer_count`/`qcad_layer_name_at` zum Enumerieren
    plus get/set fuer Farbe (RColor r/g/b), Sichtbarkeit (`RLayer::setOff`) und
    Lock (`RLayer::setLocked`), jeweils per `RTransaction` wie `ensureLayer`,
    dann persistiert QCADs DXF-Exporter die Attribute automatisch. Erst mit
    lokalem Qt-Build testen (Layer-Roundtrip via `save_dxf`/`load_dxf`).

- **M19 — "Alles landet auf Layer 0" GEFIXT (Backend), + Z-Order + Log-Ort.
  Empirisch verifiziert (echter QCAD-Core, Linux-Build).**
  - **Root Cause (endlich gefunden):** `RTransaction` stempelt beim Speichern
    JEDE neue Entity mit `doc->getCurrentLayerId()` und ueberschreibt damit ein
    zuvor per `setLayerId` gesetztes Layer (RTransaction.cpp ~660: "place entity
    on current layer"). Das C-API setzte in `qcad_set_current_layer` nur sein
    eigenes `doc->currentLayer` (QString) + `ensureLayer`, aber NIE den
    Dokument-Current-Layer. Also blieb `getCurrentLayerId()` == "0", und jede
    Entity landete auf "0" — obwohl `qcad_set_current_layer` 1 (Erfolg) lieferte
    und die Layer sogar korrekt angelegt/ins DXF geschrieben wurden.
  - **Fix (1 Zeile):** in `qcad_set_current_layer` zusaetzlich
    `doc->doc->setCurrentLayer(lid)`. Danach: Entities landen in-memory auf
    "Layer 1"/"Layer 2", ueberleben den DXF-Roundtrip, und das DXF zeigt
    `LINE -> Layer 1` / `CIRCLE -> Layer 2`. Reproduktion + Fix mit dem echten
    Core auf Linux gebaut und ausgefuehrt (nicht nur Code-Review).
  - **Smoke-Test erweitert (`tests/smoke.c`):** der Bug konnte nur shippen, weil
    smoke.c NIE Layer testete. Jetzt: current-layer setzen -> Linie -> pruefen,
    dass `qcad_entity_layer` den Layer liefert (nicht "0"), + DXF-Roundtrip. CI
    (Linux-Host UND iOS-Simulator via `simctl`) faellt jetzt bei Regression.
  - **Z-Order (Frontend):** der Viewport-`CustomPaint` war nicht geclippt, also
    malte eine ver­schobene/gezoomte Skizze ueber Ribbon (oben) und Model Browser
    (links) — und weil der Viewport in der Column/Row DANACH gemalt wird, lag die
    Geometrie obenauf. Fix: `ClipRect` um den Painter (viewport.dart).
  - **Log-Datei (Frontend):** `Log.init()` leitet den Pfad aus `$HOME` ab (auf
    iOS teils leer -> Temp-Verzeichnis, das die Files-App NICHT zeigt — daher
    Skizzen sichtbar, aber kein Log). Neu: `Log.retarget(docsDir)` aus
    `AppState.init` schiebt das Log (inkl. Historie) ins ECHTE Documents-Verz.
    neben die Skizzen (`On My iPad > ipadprocad > logs > ipadprocad_log.txt`).
  - **Altbestand:** bereits auf "0" gestrandete Geometrie (Skizzen vom kaputten
    Build) bleibt auf "0", bis sie verschoben wird — dafuer ist M18 "Move N here".
  - **Geaenderte Dateien:** `backend/qcad-core/src/capi/qcad_capi.cpp`,
    `backend/qcad-core/src/capi/tests/smoke.c`, `frontend/lib/widgets/viewport.dart`,
    `frontend/lib/log.dart`, `frontend/lib/app_state.dart`.

- **OFFENER BUG (naechster Schritt):** Beim Ziehen von Punkten eines KREISES oder
  BOGENS verschwindet die ganze Geometrie, bis losgelassen wird. Verdacht:
  `grip.idx` ist bei Kreisen nur fuer `idx < ptCount` (= 1, der Mittelpunkt) ein
  Punktindex — die vier Radius-Grips tragen idx 1..4. Der M15-Build loggt genau
  das (`gripStr`, `moveGrip`-Ein/Ausgabe, Solver-Pfad, NaN-Erkennung); mit dem
  Log vom Geraet ist die Ursache direkt sichtbar. Die M15-Schranken verhindern
  bereits, dass der Viewport dabei ausgeloescht wird.

- **M6–M8 — Grips/Modify/Snap, Constraints, Bemaßung: ERLEDIGT.**
- **M9–M14 — SolveSpace-Solver (libslvs, FFI) + Dart-LM-Fallback,
  Auto-Coincident auf den projizierten CP, Lock, live-korrekter Drag:
  ERLEDIGT.** Architektur: slvs nativ, jede Lösung wird per Residuen-Check
  verifiziert; scheitert oder bailt slvs, übernimmt der Dart-LM-Solver.
- **M15 — Diagnose-Log auf dem Gerät (Files-App): ERLEDIGT.**
- **M16/M17 — Layer-Bindung + Editier-Scope + Auge: ERLEDIGT.**
- **M18–M20 — Layer-System produktionsreif; "alles auf Layer 0"-Backend-Fix;
  Bögen verschwanden beim Drag (slvs-Writeback verlor das
  Richtungs-Flag): ERLEDIGT** (Details in den Commit-Messages 7d8106a,
  37d707d, 0a89d28).
- **M21 — Inventor-komplette Bemaßung: ERLEDIGT** (Abschnitt unten).
- **M22 — Splines produktionsreif: ERLEDIGT** (Abschnitt unten).
- **M23 — Ellipse = 3 Definitionspunkte: ERLEDIGT** (Abschnitt unten).
- **M24 — Ellipsen-Feinschliff + Inline-Bemaßungseingabe: ERLEDIGT.**
- **M25 — Projizierter CP bemaßbar + Mittellinien + Ellipsen-Achsen als
  gebundene Entities: ERLEDIGT** (Abschnitt unten).
- **M26 — Inventor-DOF-Färbung (Träger-Analyse, Kanten-Färbung, Status):
  ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M27 — Bemaßung antippen/doppeltippen -> Wert-Editor (Label-Rect-
  Treffertest): ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M28 — Polylinien-Kanten als Bemaßungs-Teilnehmer (conEdges, 'ang4'):
  ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M29 — Tangente mit Splines (Endpunkt-Tangente, LM-only): ERLEDIGT,
  Geräte-Test offen** (Abschnitt unten).
- **M30 — Tastatur-Shortcuts D/L/C/R/S/Strg+S: ERLEDIGT, Geräte-Test
  offen** (Abschnitt unten).
- **M31 — Tangente mit Polylinien-KANTEN + Klick-Auflösung: ERLEDIGT,
  Geräte-Test offen** (Abschnitt unten).
- **M32 — Project Geometry (Inventor) + Show-Constraints/DOF default aus:
  ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M33 — Project Geometry alle Typen + Hover/Active-Button + Fremd-Layer-
  Selektionssperre: ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M34 — Rechtecke als vier Linien + Kanten-Projektion + Hover/Gelb-Fixes:
  ERLEDIGT, Host-Tests grün (94), Geräte-Test offen** (Abschnitt unten).
- **M35 — Pattern-Panel funktional (Rechteckige/Runde Anordnung, Spiegeln,
  Inventor-Dialoge): ERLEDIGT, Host-Tests grün (114), Geräte-Test offen**
  (Abschnitt unten).
- **M36 — Form-Auto-Constraints (Slots, Tangenten-Kreis/-Bogen), Fillet/
  Chamfer komplett wie Inventor, Trim/Split erhalten Constraints:
  ERLEDIGT, Host-Tests grün (134); im Geräte-Test traten Bugs zutage
  (Slot-Drag, Fillet-Button tot, Chamfer) → in M37 behoben** (Abschnitt unten).
- **M37 — Produktions-Härtung nach Geräte-Test: ERLEDIGT, Host-Tests grün
  (157) + Shim-Host-Gate (12), Geräte-Test offen.** Solver-Sicherheitsnetz
  (nie divergiertes Rendern/Committen, atomare Ops), Slot/Fillet/Chamfer an
  der Wurzel korrekt (redundanzfrei, Ecken-Koinzidenz-Entfernung, x/y-Setback-
  Bemaßung), Fillet-Button startet, Shim v3 (endpunktverankerte Tangenten).
  Voller Audit + Restpunkte im README (Abschnitt unten).
- **M38 — Zweiter Geräte-Test → Ast-Persistenz (`tanBranch`), Drag-Settle,
  Trim/Split-Koinzidenzen (+ Shim v4 Punkt-auf-Kreis), CP-Bindung für
  deterministische Formen, Fillet-Maß je Rundung, Pick-Dedupe: ERLEDIGT,
  Host 161 + Shim-Gate 13 grün, Geräte-Test offen** (Abschnitt unten).

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

---

## M21 — Vollständiges Bemaßungssystem (Inventor-Pick-Matrix)

**Was:** Der Dimension-Tool-Click ist jetzt eine Zustandsmaschine über eine
GEMISCHTE Auswahl (`conPts` + `conEnts` gleichzeitig erlaubt). Jeder Klick
erweitert die Auswahl, wenn die Kombination gültig ist, sonst platziert er.
Die Matrix steht in `AppState._dimensionClick` / `buildDimensionAt`
(app_state.dart) und im README.

**Neue Bemaßungsarten:**
- `pline` — senkrechter Punkt-Linie-Abstand. `pts = [Punkt, LinieA, LinieB]`
  (drei PRefs, KEINE Entity-Referenz — funktioniert dadurch auch für
  Polylinien-Segmente). Nativ: neuer Shim-Code `SH_PT_LINE_DIST` (=20),
  Shim-Version 2. Der Shim baut eine Ad-hoc-Linien-Entity über die zwei
  Punkte (kostet keine Parameter) und setzt `SLVS_C_PT_LINE_DISTANCE`.
- `ang3` — 3-Punkt-Winkel, `pts = [Strahl, SCHEITEL, Strahl]`. Läuft bewusst
  IMMER über den Dart-LM-Solver (Bail in `_trySolveWithSlvs`): der Shim hat
  keinen 3-Punkt-Winkel, und ein stummer Drop wäre schlimmer als LM.

**Fallstricke, die schon eingebaut/umschifft sind:**
1. **Vorzeichen von PT_LINE_DISTANCE.** SolveSpace' Residuum ist
   `proj = (a.y-b.y)(a.x-p.x) - (a.x-b.x)(a.y-p.y)` (constrainteq.cpp,
   PointLineDistance, Workplane-Zweig) — das ist das NEGATIVE des "üblichen"
   cross(b-a, p-a). Der Shim wertet exakt SolveSpace' Ausdruck aus und
   signiert das Ziel passend, sonst spiegelt der Solver den Punkt durch die
   Linie. Host-Tests 9/10 prüfen beide Seiten. Der Dart-LM-Pfad friert die
   Seite analog in `_prepare` ein (`ctx.sign`).
2. **Versions-Gate.** Ein VOR M21 gebautes IPA hat Shim v1 und würde den
   unbekannten Code 20 einfach überspringen → jede Verify schlägt fehl →
   Dauerschleife in den Fallback. Deshalb: `SlvsFfi.version` (aus
   `slvs_shim_version()`), und `_trySolveWithSlvs` bailt bei
   `pline && version < 2` sofort. Frischer Build nötig für den nativen Pfad.
3. **PRef braucht Wert-Gleichheit.** `conPts.contains(pt)` dedupliziert die
   Auswahl; mit Identity-Equality war jeder Re-Klick "neu". `==`/`hashCode`
   sind jetzt auf PRef implementiert (constraints.dart).
4. **Kreis-Kombinationen sind KEINE neuen Arten.** Kreis+Punkt, Kreis+Kreis
   laufen als gewöhnliche `dist`-Bemaßung über den Mittelpunkts-PRef
   (`getPt(circle, 0)` = Zentrum) — Serialisierung, slvs-Packung und Renderer
   existierten schon. Kreis+Linie und parallele Linien laufen als `pline`
   mit dem Zentrum bzw. einem Endpunkt der zweiten Linie als Messpunkt.
5. **Parallel-Erkennung** für Linie+Linie (Abstand statt Winkel) liegt bei
   sin(0.5°) — `_linesParallel`. Inventor bietet bei parallelen Linien den
   Linearabstand an; ein Winkelmaß zwischen (fast) parallelen Linien wäre
   ohnehin degeneriert.

**Rendering (viewport.dart `_paintDimension`):** `pline` zeichnet die
Maßlinie zwischen Punkt und Lot-Fußpunkt (gestrichelte Verlängerung, wenn der
Fußpunkt außerhalb des Segments liegt). `ang`/`ang3` zeichnen jetzt einen
echten Winkelbogen durch die Textposition (Scheitel = Schnittpunkt bzw.
mittlerer Pick), gestrichelte Strahl-Verlängerungen bei `ang3`.

**Tests:** `backend/slvs/tests/shim_test.c` Szenarien 9/10 (CI-Gate "ALL SHIM
TESTS PASS" deckt sie ab). NEU: `frontend/test/dimension_kinds_test.dart` +
`dimension_picks_test.dart` (18 Tests) und ein `flutter test`-Gate im
m5-flutter-ipa-Job. Auf dem Host läuft Engine.create() im Dart-Fallback und
der Solver ohne libslvs im LM-Pfad — genau die Pfade, die getestet werden
sollen.

**Offen / Ideen:** Tangenten-Varianten für Kreis-Abstände (Inventor: Auswahl
Mittelpunkt vs. Tangente beim Platzieren), Bogenlängen-Bemaßung, Winkel über
Quadranten-Umschaltung beim Platzieren.

---

## M22 — Spline-Fixes: Tag-Verlust beim Commit, periodische geschlossene Splines, Klick-auf-Start

**Symptom:** Während des Zeichnens sah der Spline korrekt aus (Kurve +
Kontrollpunkte), nach Enter waren es nur noch gerade Linien ohne
Kontrollpunkte. Außerdem war "Spline auf seinem Startpunkt beenden" buggy.

**Ursache 1 (der Hauptbug):** `SketchModel.refresh()` stellt die Spline-Tags
nach dem Engine-Roundtrip per Index aus dem VORHERIGEN `s.geometry` wieder
her. Beim allerersten Commit existiert der neue Spline im alten Stand aber
noch nicht — sein Index liegt hinter `prev.length`, das Tag fiel weg, und der
Spline wurde als gerade Polyline gerendert. Fix: `refresh({List<Geo>?
tagSource})` — `_rebuildEngine` übergibt die MASSGEBLICHE Liste `gs`, aus der
die Engine gerade gebaut wurde (`_committed(s, tags: gs)`). Zusätzlich
kopiert `refresh` die Engine-Liste jetzt (`List.of`), weil die
Fallback-Engine eine unveränderliche Liste liefert und das Re-Tagging sonst
wirft.

**Ursache 2:** Geschlossene CV-Splines waren mathematisch falsch: geklemmter
Knotenvektor + 3 angehängte CVs lässt die Kurve auf cv[0] STARTEN, aber auf
cvIn[2] ENDEN (geklemmt endet auf dem letzten CV) — sichtbare Lücke/Ecke am
Startpunkt. Fix: geschlossene CV-Splines sind jetzt ein echter PERIODISCHER
kubischer B-Spline (uniforme Knoten, k CVs umgeschlagen, ausgewertet auf
[t_k, t_n]); Start==Ende exakt, C2-glatt am Stoß. Offene bleiben geklemmt
(Kurve beginnt/endet auf erstem/letztem CV, wie Inventor).

**Ursache 3 (UX):** Zum Schließen musste man exakt (1e-6!) auf den Start
klicken UND danach noch Enter drücken. Jetzt: Klick auf den Startpunkt (ab 3
gesetzten Punkten, Toleranz 8/zoom als Fallback wenn Snap aus) schließt und
committet SOFORT — Inventors Geste. Der Snap auf den Startpunkt existierte
schon (extraPoints in computeSnap).

**Sichtbarkeit:** CV-Splines zeigen bei Hover/Selektion jetzt ihr
Kontrollpolygon (gestrichelt) + Punktmarker — ohne das waren die
Off-Curve-Kontrollpunkte unsichtbar und der Spline wirkte uneditierbar.
Fit-Splines brauchen das nicht (Punkte liegen AUF der Kurve).

**Tests:** `frontend/test/spline_test.dart` — Tag überlebt Rebuild,
periodischer Schluss (exakt + kein Knick), Fit-Spline schließt + läuft durch
alle Fit-Punkte, Tool schließt bei Klick auf Start. Der Tag-Test fährt den
echten `refresh(tagSource:)`-Pfad über die Dart-Fallback-Engine.

**Bekannte Grenzen:** Spline-Punkte sind im Solver weiterhin freie
Polyline-Vertices (Constraints/Bemaßungen auf Kontroll-/Fit-Punkte gehen,
Tangenten-Handles wie in Inventor gibt es noch nicht). DXF exportiert
weiterhin die Kontrollpolygon-Polyline (R_NO_OPENNURBS) + Sidecar-Tag.

---

## M23 — Ellipse: 3 Definitionspunkte statt 96-Vertex-Polygon

**Symptom:** Eine Ellipse war eine geschlossene Polyline aus 96 Sample-
Punkten — 96 Grips, 96 Snap-Vertices, 96 freie Solver-Punkte, und "eine
Kurve" war sie nie.

**Fix:** Gleiche Architektur wie Splines (Tag an einer Polyline, Kurve wird
Dart-seitig erzeugt): `Geo.ellipseTag` an einer 3-Punkt-Polyline
`[Zentrum, Hauptscheitel, Nebenscheitel]` — exakt Inventors Ellipsen-Grips.
Alle Tag-Erhaltungspfade (refresh/tagSource, Sidecar, modify.keepTag,
isSpline-Guards für Mittelpunkt-Snap und Bemaßungs-Kantenpick) greifen
automatisch, weil sie auf `spline != straight` prüfen.

- `ellipseCurve` (spline.dart) sampelt die Kurve; der Nebenscheitel trägt nur
  seine Komponente SENKRECHT zur Hauptachse bei — die Ellipse kann also nie
  scheren, egal was Solver oder Drag mit den Rohpunkten machen.
- `normalizedEllipse` wird in `_rebuildEngine` auf jede Ellipse angewandt
  (der eine Trichter für alle Edits): ein abgedrifteter Nebenscheitel wird
  exakt auf die Nebenachse zurückgesetzt, damit der Grip auf der Kurve liegt.
- `moveGrip` (snap.dart) hat Inventor-Semantik: Zentrum-Grip verschiebt die
  ganze Ellipse, Hauptscheitel rotiert/streckt (Nebenscheitel folgt senkrecht,
  b bleibt), Nebenscheitel ändert nur die Nebenausdehnung.
- Snap bietet Zentrum + alle VIER Quadranten an (die zwei gespiegelten werden
  aus den gespeicherten Scheiteln berechnet).

**Kompatibilität:** Früher gezeichnete 96-Punkt-Ellipsen bleiben gewöhnliche
Polylines — sie rendern unverändert, werden aber nicht rückwirkend
konvertiert. DXF exportiert wie bei Splines das Definitions-Polygon +
Sidecar-Tag (die C-API hat kein qcad_add_ellipse; REllipseEntity existiert im
Core, ein natives Ellipsen-Entity im C-API wäre der nächste Schritt für
sauberen DXF-Export).

**Tests:** 6 neue in spline_test.dart (Builder-Tag, Quadranten, Scher-
Immunität, Normalisierung, Zentrum-/Hauptscheitel-Grip). 28 gesamt, alle grün.

---

## M24 — Ellipsen-Feinschliff + Inline-Bemaßungseingabe

1. **Hover-Highlight:** Der Hover-Pfad zeichnete für JEDE Polyline nur die
   eine Kanten-Halo (`haloEdge`) — bei Splines/Ellipsen war das eine schräge
   Gerade statt der Kurve. Getaggte Polylines highlighten jetzt über
   `paintGeo` (zeichnet die Kurve), nur gerade Polylines behalten die
   Kanten-Halo.
2. **Ellipsen-Achsen:** Haupt- und Nebenachse werden immer als gestrichelte
   Mittellinien gezeichnet (paintGeo, ellipseTag-Zweig) — sie tragen die
   Zentrum-/Quadranten-Punkte, auf die man bemaßt und constraint.
3. **Ellipse als Kurve in der Bemaßungs-Matrix:** `isCurve` umfasst jetzt
   ellipseTag (Zentrum = Vertex 0). Vorher fing der Polyline-Zweig in
   `_dimensionClick` die Ellipse ab, bevor sie als Entity gepickt werden
   konnte — Ellipse+Linie/Punkt/Kreis funktionierte gar nicht.
4. **Vertex vor Kante:** Ein Punkt-Pick gewinnt IMMER gegen den Entity-Pick
   (Inventors Prioritität) — vorher gewann beim ersten Klick die Entity,
   wodurch "Endpunkt, Endpunkt" als "Linie, eigener Endpunkt" gelesen wurde.
   Der EIGENE Endpunkt einer gepickten Linie erweitert nicht zu pline=0,
   sondern platziert.
5. **_distKind nach Inventors Regionen:** über/unter der Bounding-Box des
   Punktpaars → horizontal (distx), links/rechts → vertikal (disty),
   diagonal/entlang der Normalen → fluchtend. Vorher entschied nur der
   Normalen-Winkel, was unvorhersehbar wirkte.
6. **Inline-Bemaßungseingabe statt Dialog:** Textfeld direkt AUF der
   Bemaßung (Position via _worldToScreen, im Stack über dem Painter).
   Öffnet nach dem Platzieren einer neuen Bemaßung und beim Tippen auf eine
   bestehende. Enter committet, Esc bricht ab, Klick daneben committet
   (Inventor behält die Bemaßung). Einheiten wie gehabt (mm/cm/m, Winkel in
   Grad). Der Over-Constrained-Dialog (getrieben/abbrechen) bleibt ein
   Dialog — das ist eine Entscheidung, kein Werteintrag. _askValue ist weg.

**Tests:** flow_probe_test.dart fährt die Flows durch AppState.toolClick:
Linie+Ellipsenzentrum → pline, Ellipsenkörper als Kurven-Pick →
Zentrum↔Linie, Platzierungsregionen distx/disty/dist. 31 gesamt.

---

## M25 — Projizierter Center Point bemaßbar + Ellipsen-Achsen als echte Mittellinien

**Teil 1 — Projizierter Center Point (Ursprung):** War als Pick angeboten
(`_nearestPointRef` liefert `PRef(kProjCenter, 0)`), aber die Konsumenten
dereferenzierten roh mit `getPt(gs[ent])` — beim Sentinel −1 flog das bzw.
die Guards (`ent < 0 → return`) warfen die Bemaßung beim Rendern weg. Neuer
Helfer `refPt(gs, ref)` (constraints.dart) löst JEDEN Punkt-Ref auf,
inklusive Ursprung. Umgestellt: `measureDim` (alle Punkt-Arten),
`_distKind`, der komplette Bemaßungs-Painter, die Pick-Halos. Merkregel im
Code: Bemaßungs-Konsumenten benutzen NIE rohes getPt auf PRefs.

**Teil 2 — Mittellinien (Centerline-Stil):** `Geo.style`
(styleNormal/styleCenterline) analog zum Spline-Tag: withStyle/withData/
onLayer erhalten ihn, eigener Sidecar `<name>.styles.json`, UND — der beim
Testen gefundene Kernbug — `refresh()` stellt den Stil jetzt wie den
Spline-Tag wieder her (vorher wurde jede Mittellinie beim ersten Edit wieder
durchgezogen gerendert). Rendering: Linien mit styleCenterline zeichnen
gestrichelt (paintGeo), sind aber VOLLWERTIGE Entities: verschiebbar,
bemaßbar, constraintbar. Ribbon: Format → "Centerline (toggle selected)"
schaltet den Stil der Selektion um (Inventors Format-Toggle).

**Teil 3 — Ellipsen-Achsen sind jetzt ECHTE Mittellinien-Entities:** Beim
Commit einer Ellipse entstehen zwei Achsen-Linien (Quadrant+ → Quadrant−)
im Centerline-Stil, an die Ellipse gebunden über
  coincident(Achsende A, Ellipsen-Scheitel) ×2 und
  midpoint(Ellipsen-ZENTRUM auf Achsenlinie) ×2
= 8 LINEARE Gleichungen für die 8 Linienparameter → weder über- noch
unterbestimmt, Achse ziehen treibt die Ellipse durch den Solver. WICHTIG:
Die erste Formulierung (symmetric um die jeweils andere Achse) koppelte die
Achsen nichtlinear und blieb im LM-Solver reproduzierbar in einem lokalen
Minimum ~0.3 % daneben hängen — deshalb NEUER Constraint-Typ
`CType.midpoint` (Punkt = Mittelpunkt einer Linie), ans ENDE des Enums
angehängt (Sidecar speichert den Enum-INDEX!), LM-Residual linear,
slvs-nativ über den existierenden Shim-Code SH_MIDPOINT (12), Glyph ⫧.
Die dekorative Achsen-Zeichnung aus M24 ist raus — die Achsen sind jetzt
Geometrie. LM-Iterationsbudget 25 → 80 (bricht bei Konvergenz früh ab).

**Tests:** m25_test.dart — Punkt+Ursprung-Bemaßung, Linie+Ursprung (pline),
Ellipsen-Commit erzeugt 2 gebundene Achsen (midpoint×2 + coincident≥2),
Achsen folgen der (gepinnten) Ellipse exakt durch den Solver,
Centerline-Stil überlebt den Engine-Roundtrip. 36 gesamt, alle grün.

---

## M26 — Inventor-DOF-Färbung: Träger-Analyse statt Alle-Punkte-Regel

**Symptom (Nutzer):** Beim Rechteck wurden alle Linien erst weiß, wenn das
GANZE Rechteck bestimmt war. In Inventor wird eine Linie schon weiß, wenn
nur noch ihre Länge frei ist (z. B. Ecke fixiert + H/V-Constraint).

**Recherche (belegt):** Autodesk-Forum "Bug: Line colour updates as fully
constrained when it isn't" — akzeptierte Antwort eines Autodesk-Engineers
nach Rückfrage beim Inventor-Team: Linien mit fixierter Richtung + Lage
werden im Fully-Constrained-Schema gefärbt, obwohl keine Längenbemaßung
existiert; die Endpunkte sind SEPARATE Entities mit eigenem Zustand. Ein
Rechteck ist in Inventor vier einzelne Linien → Kanten färben unabhängig.

**Ursache bei uns:** `entityFull` im Viewport-Painter verlangte, dass JEDER
Punkt der Entity aus `freePoints` verschwunden ist. Eine Linie mit freier
Länge hat einen beweglichen Punkt → blieb violett. Und ein Rechteck ist EINE
Polyline mit EINEM Paint → nichts wurde weiß, bis der letzte Vertex fest war.

**Fix (solver.dart):** `analyzeSketch` extrahiert jetzt die ECHTEN
Nullraum-Basisvektoren aus der RREF (vorher nur movable-Booleans — die
Basis stand schon da und wurde weggeworfen). Pro Basisvektor (= eine noch
mögliche Bewegung erster Ordnung) wird pro Träger geprüft, ob er sich ändert:
- Linie/Kante a→b: lose, wenn ein Endpunkt SENKRECHT zur Kante wandert
  (ändert Richtung/Offset). Bewegung NUR entlang der Kante = freie Länge
  → Träger bleibt fest → weiß. Test: cross(d, δ)/|d| beider Endpunkte.
- Kreis/Bogen: Träger = (cx, cy, r) — die Params o..o+2. Freie
  Bogen-ENDWINKEL (o+3, o+4) zählen nicht (Endpunkte = eigene Entities).
- Getaggte Polylines (Spline/Ellipse): lose, wenn irgendein Param beweglich
  (die Kurve IST ihre Definitionspunkte) — wie bisher, eine Farbe.
- Gewöhnliche Polylines: PRO KANTE (geschlossen n, offen n-1 Segmente).
Ergebnis in `SketchAnalysis.looseCarriers` (Set<(ent, seg)>) +
`carrierFixed(ent, [seg])` + Helper `carrierSegCount(Geo)`. `freePoints`
bleibt UNVERÄNDERT — Grips, Drag-Sperre und DOF-Pfeile hängen weiter daran
(richtig so: der freie Endpunkt einer weißen Linie bleibt ziehbar).
Toleranz: Basisvektor auf max|v| normiert, Schwelle 1e-5 (numerischer
Jacobian mit h=1e-6 rauscht darunter).

**Fix (viewport.dart):** `entityFull` → `segFull(i, seg)` über
`carrierFixed`. Gewöhnliche Polylines werden (wenn nicht selektiert/
Referenz) Kante für Kante mit der Farbe IHRER Kante gemalt statt als ein
Path. Neu außerdem Inventors Status unten rechts im Viewport:
„N dimensions needed" / „Fully Constrained" (aus `analysis.dof`, das es
schon immer gab und das nie angezeigt wurde).

**WICHTIGE ERKENNTNIS aus dem Testen (Erwartung war erst falsch):** Beim
Rechteck mit EINER fixierten Ecke + H/V werden nur die ZWEI Kanten durch
die Ecke weiß. Die gegenüberliegenden Kanten (rechts/oben) bleiben violett
— korrekt, denn ihre Trägergerade VERSCHIEBT sich mit der freien Breite/
Höhe (x=w wandert mit w). Erst die Breiten-Bemaßung macht die rechte Kante
weiß (ihre Länge = Höhe bleibt frei), die Höhen-Bemaßung dann alles. Das
ist exakt Inventors Verhalten und exakt das Szenario des Nutzers („die
Linie, die an der voll bestimmten Ecke hängt").

**Tests:** `frontend/test/m26_test.dart` (9 Tests): Linie fix+H mit freier
Länge → weiß + Endpunkt bleibt freePoint; NUR Längenbemaßung → violett
(Träger transliert/rotiert noch); Rechteck-Progression (Ecke→2 Kanten weiß,
+Breite→3, +Höhe→alles, dof 2→1→0); L-Form über coincident (Kette:
Kante 2 erst weiß, wenn Kante 1 bemaßt ist); Kreis Zentrum fix + freier
Radius → violett, +rad-Bemaßung → weiß; unconstrained → alles lose; voll
bestimmt → looseCarriers leer; carrierSegCount-Konvention. 45 gesamt, alle
grün (flutter test, Host = Dart-Fallback-Engine + LM-Pfad wie in der CI).

**Grenzen:** Erste Ordnung (Nullraum am aktuellen Punkt) — ein Träger, der
nur in höherer Ordnung beweglich wäre, würde weiß gefärbt; praktisch
irrelevant, Inventor arbeitet genauso lokal. Der Status-Text zählt dof als
"dimensions needed" (Inventor zählt genauso Parameter, nicht Bemaßungen).

---

## M27 — Bemaßung antippen/doppeltippen öffnet den Wert-Editor

**Symptom (Nutzer):** Doppeltipp auf eine bestehende Bemaßung sollte sie
editieren — tat es aber nicht (und Einzeltipp meist auch nicht).

**Zwei Ursachen:**
1. Der Treffertest (`dimensionAt`) verglich den Tipp mit `textPos`. Für die
   'dist'-Arten berechnet der Painter die Label-Position aber NEU (Mitte der
   Maßlinie + 10px-Normalenversatz) — der Text liegt gar nicht bei textPos.
   Bemaßungen waren dadurch fast nicht antippbar.
2. Wenn der Editor doch aufging, traf der ZWEITE Tipp eines Doppeltipps den
   „Klick woanders committet"-Zweig und schloss das gerade geöffnete Feld
   sofort wieder.

**Fix:** Der Painter protokolliert jetzt die SCREEN-Rects der wirklich
gezeichneten Labels (`AppState.dimLabelRects`, im Paint gefüllt); Tipps
treffen gegen diese Rects (+8px Finger-Toleranz, oberstes Label gewinnt),
mit dem alten Anker-Test nur noch als Fallback vor dem ersten Paint. Ein
erneuter Tipp auf DASSELBE Label hält den Editor offen (Text neu
selektiert) statt zu committen — Einzel- UND Doppeltipp editieren damit.
Außerdem Inventor-Verhalten ergänzt: Ist das Bemaßungs-Tool aktiv, öffnet
ein Tipp auf ein bestehendes Label dessen Editor statt einen neuen Pick zu
starten. Tests: `frontend/test/m27_test.dart` (5 Widget-Tests, pumpen den
echten Viewport).

---

## M28 — Polylinien-Kanten als Bemaßungs-Teilnehmer ('ang4')

**Symptom (Nutzer):** Punkt→Linie und Linie→Linie funktionierten nicht —
in seinen Skizzen sind die „Linien" meist RECHTECK-Kanten, also Segmente
EINER geschlossenen Polyline ohne eigenen Entity-Index.

**Ursache:** Die Pick-Matrix behandelte einen Kanten-Klick nur als ERSTEN
Pick (→ zwei Eckpunkte). Nach einem Punkt-, Linien- oder Kanten-Pick fiel
der Polyline-Zweig durch (verlangte leeres Pick-Set) → toter Klick oder
falsche Platzierung; `buildDimensionAt` lieferte teils null.

**Fix (app_state.dart):** Neuer Pick-Container `conEdges`
(List<(PRef, PRef)>), überall mit conPts/conEnts zurückgesetzt. Kanten
kombinieren jetzt wie Linien: Punkt+Kante → pline (senkrechter Abstand),
Linie/Kreis/Bogen/Ellipse+Kante → pline (Zentrum bzw. paralleler Spalt)
oder Winkel, Kante+Kante (erste Kante = das gepickte Eckpaar) → paralleler
Spalt oder Winkel. Erste-Pick-Verhalten (Kante = zwei Ecken, Länge,
kombiniert mit Punkt zu ang3) bleibt UNVERÄNDERT — Tests hängen daran.
Eigene Ecke der Kante und dieselbe Kante nochmal platzieren statt zu
erweitern; ein Punkt erweitert nie ein Set, das schon eine Kante enthält.

**Neue Bemaßungsart 'ang4'** (Winkel Linie/Kante ↔ Kante): pts =
[a1,a2,b1,b2], Winkel zwischen den Strahlen a1→a2 und b1→b2 — der
Linie-Linie-Winkel über PUNKTE, weil eine Kante keinen Entity-Ref hat.
Vollständiger Satz nach Checkliste: Residual + Count + Vorzeichen-Prepare
(wie 'ang', hält die Windung), measureDim (auf [0,180] gefaltet wie 'ang'),
Painter (Bogen am Schnittpunkt der Träger via _angleArc), slvs-Bail
automatisch über die Kind-Whitelist (LM-only wie 'ang3', Kommentar
erweitert). Damit ist die alte M14-Lücke „Winkel zwischen zwei
Polyline-Kanten" geschlossen. Viewport: Halo auch für conEdges-Kanten;
Editor-Suffix ° über _isAngleKind.

**Tests:** `frontend/test/m28_test.dart` (7): Punkt→Kante, Linie→Kante
parallel (Spalt) und 45° (ang4), Kante→Kante 90°, Kreis→Kante,
ang4-Treiben durch LM auf 30°, Regressionen pt-pt / Linie+Punkt /
Linie‖Linie. Merker daraus: Ein Felgen-Klick nahe dem Kreiszentrum pickt
das ZENTRUM (Punkt schlägt Entity innerhalb 10/zoom — Inventor-Priorität);
Test nutzt einen größeren Kreis. 57 Tests gesamt, alle grün.

**Grenzen:** Winkel-Quadrantenwahl bei Platzierung fehlt weiterhin (gilt
für 'ang' UND 'ang4'); Kante als ERSTER Pick bleibt bewusst das Eckpaar
(Länge) statt Linien-Semantik — dokumentierte M21-Entscheidung.

---

## M29 — Tangenten-Constraint mit Splines

**Symptom (Nutzer):** In Inventor funktioniert Tangente auch Spline↔Linie
und Spline↔Kreis — bei uns wies die UI Splines mit „Tangent needs at least
one curved entity" ab (round() prüfte nur arc/circle).

**Inventor-Semantik (umgesetzt):** Spline-Tangente wirkt am Spline-
ENDPUNKT. Mathe-Grundlage in unserem Code: Die End-Tangente läuft bei
BEIDEN Spline-Arten exakt entlang der beiden Definitionspunkte am Ende —
fitCurve dupliziert die Endpunkte (Catmull-Rom-Phantome ⇒ Ableitung bei
t=0 ∝ P1−P0) und die offene CV-B-Spline ist GEKLEMMT (Knoten 0×4…1×4 ⇒
Endtangente entlang CV1−CV0). Das Residual nutzt daher direkt diese zwei
Punkte: glatt in den Parametern, identische Formel für beide Arten.

**Umsetzung:**
- UI (`_constraintClick`, cTangent): Splines (splineCv/splineFit, offen)
  sind gültige Teilnehmer. Das beteiligte ENDE wird beim Klick aufgelöst:
  das Ende, das der anderen Entity näher liegt (distToEntity) — gespeichert
  als PRef im Constraint (pts, ein Ref pro Spline). GESCHLOSSENE Splines
  → Toast, kein Constraint (kein Ende). Linie+Linie weiter abgewiesen.
- Residual (1 Gleichung, wie Inventors 1-DOF-Tangente, normiert):
  Spline+Linie cross(EndDir, LinienDir)=0; Spline+Kreis/Bogen
  dot(EndDir, Endpunkt−Zentrum)=0 (Tangente ⊥ Radius); Spline+Spline
  cross der beiden End-Tangenten. residualCount validiert die End-Refs.
- KEINE Berührungs-Gleichung: wie in Inventor liefert Tangente nur die
  Richtung; den Kontakt stellt der Nutzer über Koinzidenz her (sonst gäbe
  es Redundanz-Warnungen bei Koinzidenz+Tangente).
- slvs: expliziter Bail für Tangente mit Polyline-Beteiligung (der Shim
  kennt keine Splines) → verifizierter Dart-LM-Pfad.

**Tests:** `frontend/test/m29_test.dart` (7): Fit-Spline-Ende wird an
horizontale Linie gedreht; CV-Spline-Ende ⊥ Kreisradius; DOF-Analyse zählt
genau 1 Gleichung; UI löst das NÄCHSTE Ende auf; geschlossener Spline
abgewiesen; Linie+Linie abgewiesen; Regression Kreis+Linie-Tangente.

**Grenzen:** Tangente an geschlossene Splines und an beliebiger
Kurvenstelle (nicht Ende) fehlt; Smooth (G2) mit Splines weiter gesperrt;
Ellipse↔Linie-Tangente (andere Mathematik, kein Endpunkt) offen.

---

## M30 — Tastatur-Shortcuts

Im Viewport-Focus-Handler (der schon Esc/Enter behandelt): **D** Bemaßung,
**L** Linie, **C** Kreis (Zentrum), **R** Rechteck (2-Punkt) — über
selectTool, das außerhalb eines Layers weiter blockiert und den Hinweis
toastet. **S** beendet den aktuellen Layer (finishEdit mit Speichern) bzw.
legt außerhalb eines Layers einen neuen an und betritt ihn (startNewLayer).
**Strg+S / Cmd+S** speichert (saveSketch + Toast). Shortcuts feuern NIE,
während der Inline-Bemaßungseditor tippt (_inlineDim-Guard — dessen
Key-Events bubbeln durch den Ancestor-Focus). Kein const-Map mit
LogicalKeyboardKey (Analyzer-Error: überschreibt ==) — if-Kette.
Tests: `frontend/test/m30_test.dart` (4 Widget-Tests; Merker: Toasts
starten Timer, Tests müssen sie mit pump(6s) ablaufen lassen).

---

## M31 — Tangente mit Rechteck-Kanten + Klick-basierte Auflösung

**Symptom (Nutzer, mit Geräte-Log belegt):** Tangente Spline ↔ Rechteck-
Kante ging weiterhin nicht. Log: „REJECTED tangent/ pts=e4.p0 ents=0,4 —
would over-constrain".

**ZWEI Ursachen (beide aus dem Log ablesbar):**
1. Das M29-Residual kannte als Partner nur line/circle/arc. Für die
   gewöhnliche POLYLINE (das Rechteck) lieferte es konstant 0 → Nullzeile
   im Jacobian → Rang wächst nicht → der Redundanz-Check in _addConstraint
   hielt die Gleichung für wirkungslos und LEHNTE AB. (Gleicher latenter
   Bug: Kreis/Bogen ↔ Rechteck-Kante.) MERKER: Ein Constraint, dessen
   Residual für eine Kombination fehlt, wird nicht etwa ignoriert — er wird
   als „would over-constrain" abgelehnt, weil die Nullzeile den Rang nicht
   hebt. Diese Fehlermeldung ist dann IRREFÜHREND.
2. Im Nutzer-Sketch lagen BEIDE Spline-Enden auf Rechteck-Ecken —
   „nächstes Ende zum Partner" war ein Unentschieden und wählte p0 statt
   des angeklickten p8-Endes. Ende (und Kante) müssen aus den KLICKS
   aufgelöst werden.

**Fix:**
- Neues Feld `conEntClicks` (parallel zu conEnts, NUR von _constraintClick
  gefüllt, überall mit conEnts geleert; Längen-Mismatch → Fallback auf die
  alte Heuristik). Spline-Ende = Ende näher am Klick AUF dem Spline;
  Polyline-Kante = polySegmentAt am Klick auf der Polyline.
- cTangent akzeptiert gewöhnliche Polylines als linien-artige Partner.
  Constraint-pts-Layout: [Spline-End-Ref(s)…, Kanten-Eckpaar(e)…].
  Rechteck+Rechteck bleibt abgewiesen (nichts Gekrümmtes).
- Residuals ergänzt: Spline-Ende ∥ Kante (cross, normiert) und
  Kreis/Bogen ↔ Kante (|senkrechter Abstand Zentrum ↔ Kanten-Trägergerade|
  − r, über die zwei Ecken-PRefs — Polyline-Segmente haben keinen
  Entity-Ref, exakt wie bei pline/ang4). residualCount validiert
  nSpl + 2·nPoly Punkt-Refs.
- slvs-Bail griff schon (Tangente mit Polyline-Beteiligung → LM).

**Tests:** `frontend/test/m31_test.dart` (5): 1:1-Nachbau des Nutzer-
Sketches aus dem Log (Spline-Enden auf zwei Rechteck-Ecken, Klick-Reihen-
folge des Logs) → Constraint AKZEPTIERT, korrektes geklicktes Ende p4 und
korrekte linke Kante, +1 Gleichung in der DOF-Analyse; Solver dreht das
End-Chord vertikal an die rechte Kante; Kreis wächst auf Kanten-Träger
(r→15); UI Kreis+Kante baut Kanten-Refs; Rechteck+Rechteck abgewiesen.
73 Tests gesamt, alle grün.

---

## M32 — Project Geometry (Inventor) + Anzeige-Defaults

**Nutzerwunsch:** Show Constraints und die DOF-Anzeige default AUS; und
Projizieren wie in Inventor: Linien ANDERER Layer (plus X-/Y-Achse und der
eh schon projizierte Centerpoint) in den Editier-Layer projizieren — gelb,
laufend quell-aktualisiert, im Ziel-Layer nicht verschiebbar.

**Defaults:** `showConstraints = false`, `showDof = false` (app_state).

**Modell — das Projektions-Tag:** `Geo.proj` (int), exakt dieselbe Mechanik
wie Spline-/Stil-Tag: App-State, DXF round-trippt eine normale Linie, Tag
im Sidecar (`<name>.proj.json`, Index→proj), von `refresh(tagSource:)`
und ALLEN Copy-Methoden (`withData/onLayer/asSpline/withStyle/withProj`)
getragen — der Solver überschreibt jede Entity bei jedem Solve, eine
vergessene Stelle macht aus der Projektion eine normale Linie.
Werte: >=0 Quell-Entity-Index; projAxisX=-2; projAxisY=-3; projBroken=-4
(Quelle gelöscht → Projektion friert ein, wie Inventors kranke Referenz).

**Solver-Integration (solver.dart, zentral statt an jedem Call-Site):**
`solveConstraints` ist jetzt ein Wrapper: (1) `syncProjections(gs)` kopiert
jede Projektion von ihrer Quelle (Achsen = feste lange Linie ±kProjAxisSpan
durch den CP), (2) `_withProjectionPins` hängt implizite fix-Constraints an
beide Endpunkte, (3) innerer Solve, (4) **NOCHMAL syncProjections** — die
Pins halten die Projektion auf der VOR-Solve-Position der Quelle; bewegt
der Solve die Quelle selbst (Bemaßung auf dem Quell-Layer), hinge die
Projektion sonst einen Solve hinterher (Test hat's gefangen).
`analyzeSketch` bekommt dieselben Pins → Projektionen sind voll bestimmt,
ihre Punkte fehlen in freePoints → der bestehende Drag-Block macht sie
unverschiebbar, ohne neuen Code. Bemaßung GEGEN eine Projektion treibt
dadurch die andere Geometrie (Inventor-Referenz-Semantik).

**UI:** Der bisher funktionslose Ribbon-Button „Project Geometry" startet
`Tool.project`. `_projectClick`: eigener Pick über ALLE sichtbaren Layer
(_pickEntity ist absichtlich auf den Editier-Layer beschränkt). Linie auf
anderem Layer → Projektion (engine.addLine auf Editier-Layer + tagSource
mit withProj). Kein Treffer + Klick nahe y=0 → X-Achse, nahe x=0 →
Y-Achse. Abgewiesen mit Toast: Nicht-Linien, gleicher Layer, Duplikate.
Modify-Tools (Trim etc.) weisen Projektionen ab. Painter: gelb (0xFFE8C84A)
vor der DOF-Färbung. Löschen: `remapProjectionsAfterRemove` (constraints.
dart) an allen drei removeAt-Stellen (deleteLayer, trim, split) — Quelle
weg → projBroken, höhere Quell-Indizes rücken nach.

**Grenzen:** Nur Linien + Achsen projizierbar (Kreise/Bögen/Splines wie in
Inventor wären der nächste Schritt: brauchen sync für circle/arc-Daten und
Pins auf cx,cy,r); Projektion einer Projektion durch den Duplikat-Guard
abgedeckt (liegt exakt auf der Quelle); kein „Break Link".

**Tests:** `frontend/test/m32_test.dart` (8): Defaults aus; Projektion
erzeugt getaggte Kopie auf Layer B; Quelle per Bemaßung getrieben →
Projektion folgt im SELBEN Solve; Pinning (freePoints leer, Bemaßung gegen
Projektion bewegt die freie Linie, Projektion ±1e-6 unbewegt); X-Achse per
Klick nahe y=0; Ablehnungen (Kreis/gleicher Layer/Duplikat); Quell-Layer
löschen → projBroken + eingefroren + solve-stabil; Trim verweigert.
81 Tests gesamt, alle grün.

---

## M33 — Project Geometry: alle Typen, Hover, Button-Highlight, Fremd-Layer-Sperre

**Nutzer-Feedback nach Geräte-Test M32:** Linien projizieren funktioniert;
Kreise/Ellipsen (Splines ungetestet) nicht; Project-Button soll bis Escape
leuchten; im Project-Modus soll projizierbares unter dem Finger
hervorgehoben werden; und grau dargestellte Geometrie ANDERER Layer darf im
Edit-Modus überhaupt nicht mehr anfassbar sein (außer im Project-Modus).

**Alle Typen projizierbar:** `_projectClick` kopiert die Quelle jetzt als
GLEICHEN Typ (onLayer+withProj — Spline-/Ellipse-Tag reist automatisch mit)
und legt sie typrichtig in die Engine (addLine/addCircle/addArc mit
reversed/addPolyline mit closed). `syncProjections` kopiert generisch den
Datenvektor bei Typ-Gleichheit. **Pinning generisch:** fix auf JEDEN
ptCount-Punkt deckt alles ab (Bogen: Zentrum+beide Enden bestimmen r und
Winkel; Polyline/Spline/Ellipse: alle Definitionspunkte) — einzige Lücke
ist der Kreis-RADIUS (ptCount=1), der eine zusätzliche rad-Dimension als
Pin bekommt.

**UI:** `_BigWide` hat jetzt `active` (reicht an das vorhandene
`_Hover.activeHighlight` durch) — der Project-Button leuchtet, solange
`app.tool == Tool.project` (Escape → cancelTool → aus). Hover im
Project-Modus: `pickVisibleAny` (aus _projectClick extrahiert, öffentlich)
über ALLE sichtbaren Layer; hervorgehoben wird nur, was projizierbar ist —
fremder Layer UND noch nicht auf den Editier-Layer projiziert
(`_isProjectedOnto`). Der bestehende Halo-Painter übernimmt den Rest.

**Fremd-Layer-Selektionssperre:** `selectAt` und `boxSelectFinish`
überspringen im Edit-Modus alles, was nicht `geoEditable` ist (und
Unsichtbares). Grau = reine Referenz, exakt Inventor. Projektionen LIEGEN
auf dem Editier-Layer und bleiben damit selektierbar (löschbar); außerhalb
des Edit-Modus bleibt alles antippbar. Modify-Tools waren durch _pickEntity
schon immer gescoped, der M32-Projektions-Guard bleibt zusätzlich.

**Tests:** `frontend/test/m33_test.dart` (6): Kreis projiziert + Radius
gepinnt + folgt Zentrum UND Radius der Quelle; Bogen + Rechteck (closed-
Flag) als typgleiche Kopien; Spline MIT Tag + gepinnt; Hover nur auf
unprojizierten Fremd-Entities (nach Projektion aus, außerhalb Project-Modus
Fremd-Layer nie); Selektion: Quelle nicht antippbar, Projektion schon, Box-
Select gescoped; ohne Edit-Modus weiter alles selektierbar. m32-„circle
rejected"-Test an das neue Verhalten angepasst. 87 Tests, alle grün.

**Grenzen:** Achsen-Projektion weiterhin nur X/Y per Klick nahe der Achse;
kein Break-Link; Projektion einer Projektion über Duplikat-Guard gedeckt.

---

## M34 — Rechtecke = vier Linien; Kanten-Projektion; Hover-/Gelb-Fixes

**Geräte-Feedback zu M33:** (1) Klick auf eine Rechteck-Seite projizierte
das GANZE Rechteck statt nur der Linie; (2) Hover-Highlight im Project-
Modus funktionierte auf dem Rechteck nicht (Kreis/Spline ok); (3) die
projizierten Rechteck-Linien waren weiß statt gelb. Und grundsätzlich:
Rechtecke sollen wie in Inventor VIER Linien mit Constraints sein, nie
eine Polyline.

**Rechteck-Modell (die große Änderung):** Alle vier Rect-Tools
(rectTwoPoint/rect3P/rect2PC/rect3PC) liefern aus buildToolGeometry jetzt
`_rectLines` — vier Linien-Entities. `_commitTool` setzt deterministisch
die Constraints (statt Inferenz): 4× coincident an den Ecken; achsparallele
Tools zusätzlich 2× horizontal + 2× vertical (dof 4: x,y,w,h); die
rotierten 3-Punkt-Tools 3× perpendicular (der vierte rechte Winkel wäre
redundant; dof 5 inkl. Rotation). Jede Seite ist einzeln selektier-,
bemaß-, constraint- und projizierbar — die ganzen Polyline-Kanten-
Sonderwege (M26 Per-Edge-Färbung, M28 conEdges, M31 Kanten-Tangente, M34
Kanten-Projektion) bleiben für POLYGONE, SLOTS und BESTANDS-Sketches mit
Polyline-Rechtecken voll in Kraft — alte Dateien funktionieren unverändert.

**Kanten-Projektion:** Neues Geo-Feld `projSeg` (Segment-Index in der
Quell-Polyline, -1 = ganze Entity), von ALLEN Copy-Methoden + refresh
getragen (withProj(src, [seg])). _projectClick löst bei gewöhnlichen
Polylines das geklickte Segment via polySegmentAt auf und erzeugt EINE
Linie mit (proj, projSeg); syncProjections spiegelt die zwei Quell-
Vertices (wrap bei geschlossen); Duplikat-Guard pro (Quelle, Segment) —
weitere Kanten derselben Polyline bleiben projizierbar (auch im Hover:
_isProjectedOnto zählt nur Ganz-Projektionen). Sidecar `.proj.json`
speichert int (alt, M32-kompatibel) ODER [proj, projSeg]; Loader liest
beide Formate.

**Hover-Fix:** Der Halo-Painter zeichnet gewöhnliche Polylines NUR über
hoverEdge — mein M33-Hover setzte hoverEdge=null → Rechteck ohne
Highlight. Jetzt setzt der Project-Hover hoverEdge über polySegmentAt.

**Gelb-Fix:** Der M26-Per-Edge-DOF-Painter lief auch für projizierte
Polylines und übermalte projPaint → Guard `!isProjection`, projizierte
Polylines (ganz, aus M33-Bestand) sind als Ganzes gelb.

**Tests:** `frontend/test/m34_test.dart` (7): 2P-Rect → 4 Linien, 4×
coincident + 2H + 2V, dof 4, Seite einzeln selektierbar; Corner-Drag hält
Rechteck-Form (H/V + Ecken); 3P-Rect → 3× perpendicular, dof 5; Polygon-
Kante projiziert als eine Linie mit projSeg, zweite Kante ok, Duplikat
abgelehnt; Kanten-Projektion folgt der verbreiterten Quelle; Hover setzt
hoverEdge (und bleibt für unprojizierte Kanten aktiv); projSeg übersteht
alle Copy-Methoden. m33-Erwartung (Ganz-Rechteck) auf Kante umgestellt.
94 Tests, alle grün.

**MERKER:** Neue Rechtecke haben KEINE pickedEdge/conEdges-Semantik mehr
nötig (jede Seite ist eine Linie) — beim Testen auf dem Gerät prüfen, dass
Bemaßung/Tangente/Projektion mit den neuen 4-Linien-Rects den normalen
Linien-Pfad nehmen.

---

## M35 — Pattern-Panel: Rechteckige/Runde Anordnung + Spiegeln (Inventor)

Die drei bisher funktionslosen Pattern-Buttons (Ribbon, Panel 4) sind jetzt
echte Werkzeuge mit Inventor-Dialogen. Recherche-Grundlage: die originalen
Inventor-Sketch-Dialoge ("Rechteckige Anordnung", "Runde Anordnung",
"Spiegeln") — Layout, Selektoren, Optionen und Verhalten wurden 1:1
übernommen, in die App-Palette übersetzt und für Touch skaliert.

**Dialog-Architektur (`widgets/pattern_dialog.dart`, neu):** Der Dialog ist
MODELESS — er schwebt oben rechts über dem Viewport (Stack in Viewport2D)
und die Picks laufen weiter über den Canvas. Welcher Eingabe ein Tap
zufließt, bestimmt der AKTIVE Selektor (blauer Rahmen, Inventors Sprache);
`AppState._patternClick` routet: Geometry = Multi-Pick (Tap toggelt),
Direction 1/2 = Linien-Pick, Achse = Punkt-Pick (inkl. projiziertem CP),
Spiegelachse = Linien-Pick (nie Teil der Selektion). Zustand lebt in einer
`PatternSession` (`app_state.dart`); Esc/Cancel verwirft sie als Ganzes,
Enter = OK. Die aktuelle Selektion seedet den Geometry-Pick-Set (Inventor).

**Rechteckige Anordnung:** Direction 1/2 sind beliebige Linien (nicht
notwendig senkrecht), je Flip-Toggle, Anzahl (inkl. Original) und Abstand.
Direction 2 bleibt grau bis Direction 1 gepickt ist — Inventors Flow.
**Runde Anordnung:** Achse (Punkt/Zentrum/projizierter CP), Flip, Anzahl,
Winkel (Default 360°). **Fitted** (im ">>"-Bereich, Default an): der Wert
ist die GESAMT-Spanne, gleichmäßig geteilt (360° teilt durch n statt n-1,
damit erstes und letztes Element nicht zusammenfallen); aus: der Wert ist
der Abstand ZWISCHEN Elementen. Beides getestet.

**Assoziativität (Checkbox, Default an):** Kopien sind über den Solver an
die Quelle gebunden. Neuer Constraint-Typ `CType.pattern` (ans ENDE des
Enums, Sidecar-kompatibel): ents=[Quelle, Kopie], anchors=[kind, …] mit
kind 0 = Translation (dx,dy) bzw. 1 = Rotation (cx,cy,angle). Residuen:
JEDER Parameter der Kopie = transformierter Parameter der Quelle (Punkte
durch die starre Abbildung, Radius gleich, Bogen-Winkel um die Rotation
verschoben, WRAPPED für glatte Gleichungen) — Kopie-Params == Kopie-
Gleichungen, ein Pattern fügt also nie Netto-DOF hinzu und kann für sich
nie überbestimmen (Test). Der slvs-Shim kennt den Typ nicht → expliziter
Bail auf den verifizierten Dart-LM-Pfad (HANDOFF-Regel: nie stillschweigend
droppen). Assoziativität aus = freie Kopien ohne Constraints (Inventor:
Assoziativität entfernen macht aus dem Muster lose Geometrie).

**Spiegeln:** hält die Kopien über den VORHANDENEN symmetric-Constraint —
exakt Inventors Doku ("Symmetric constraints are applied between the
mirrored geometry"): Linie = 2 Punktpaare, Kreis = Zentrum symmetric +
equal-Radius, Bogen = 3 Punktrefs (die redundante Radius-Zeile ist rang-
neutral für LM und DOF-Analyse), Polyline/Spline/Ellipse = je Vertex.
Apply erzeugt und lässt den Dialog offen (Picks geleert), Done schließt,
Cancel verwirft — Inventors Drei-Knopf-Verhalten. **Self Symmetric** (nur
anwählbar bei genau EINEM offenen Spline): endet der Spline auf der
Spiegelachse (Toleranz 8px/zoom), wird er zu EINEM symmetrischen Spline
verlängert — Definitionspunkte gespiegelt angehängt, Paare i↔2n-2-i per
symmetric gebunden, Mittelpunkt per point-on-line auf der Achse gepinnt.

**Preview:** `patternPreview()` zeichnet die anstehenden Kopien hellblau in
den Viewport (wie der Modify-Ghost, gedeckelt bei 600 Entities). Picks
leuchten: Geometry mit dem Pre-Select-Halo, Richtungs-/Achsen-/Spiegel-
Picks blau.

**Bewusste v1-Grenzen (im Dialog sichtbar ausgegraut, wie Inventor vor dem
Pick):** Grenzen/Umgrenzung (Boundary-Fill), Suppress einzelner Instanzen,
Muster entlang Pfad, nachträgliches Edit Pattern (Transformation ist beim
Commit numerisch eingefroren — die Richtung folgt ihrer Linie NICHT nach).
Zentrierlinien-Stil wird auf Kopien übernommen; der Projektions-Tag
bewusst nicht (Projektionen sind nicht patternbar, Toast).

**Tests (`test/m35_test.dart`, 20 neu, gesamt 114):** Dialog-Flow inkl.
Pick-Routing, Fitted an/aus, zwei Richtungen + Flip, Assoziativität unter
Drag (Quelle editieren → Kopie folgt; Achse im Test geerdet, sonst darf
der Solver legitim die Achse drehen), keine Netto-DOF, Validierungs-Toasts,
360°-Rundmuster um den projizierten CP, Bogen-Winkel-Rotation,
Radius-Folge, Flip-Richtung, Spiegel-Symmetric-Set + Drag-Folge,
Spiegelachse nie in der Selektion, Apply-Verhalten, Self-Symmetric
(verlängert + verweigert bei Abstand zur Achse), Sidecar-Roundtrip von
CType.pattern, Remap beim Löschen der Quelle.

---

## M36 — Form-Constraints, Fillet/Chamfer komplett, Trim erhält Constraints

Drei Baustellen aus dem Geräte-Test: (a) Slots (und weitere Formen) kamen
OHNE ihre Inventor-Auto-Constraints an, (b) Fillet/Chamfer waren rudimentär
(nur Linie-Linie, blockierender Radius-Prompt, keinerlei Constraints),
(c) Trim/Split warfen ALLE Constraints/Bemaßungen des getroffenen Elements
weg.

**(a) Auto-Constraints der Formwerkzeuge (deterministisch im Commit, wie
die M34-Rechtecke — nie über Inferenz):**
- Linearer Slot (`slotCC`/`slotOverall`/`slotCP`, Entities [rail1, rail2,
  cap1, cap2]): koinzident + tangent an allen vier Nähten, equal zwischen
  den Kappen, parallel zwischen den Rails (durch die Tangenten impliziert,
  aber für Inventors Glyphen mitgeführt — redundante Zeilen sind
  rang-neutral für LM und DOF-Analyse). Ein Slot hat danach exakt 5 DOF
  (Position, Rotation, Länge, Radius) — getestet, auch unter Drag.
- Bogen-Slot (`slot3A`/`slotCPA`, [outer, inner, capA, capB]): konzentrisch
  zwischen den Rails, koinzident + tangent an den Nähten, equal-Kappen;
  6 DOF (Zentrum, Rail-Radius, Kappen-Radius, zwei Sweeps) — getestet.
  Naht-Zuordnung siehe `_linearSlot`/`_arcSlot` (capA läuft outer.start →
  inner.start usw.).
- Tangenten-Kreis (`circleTangent`): tangent zu allen drei gepickten Linien
  (Picks werden im Commit über `nearestLineIdx` re-attributiert).
- Tangenten-Bogen (`arcTangent`): koinzident auf den Quell-Endpunkt +
  tangent zur Quelle — deterministisch STATT Inferenz (die hätte die
  Koinzidenz vom Endpunkt-Snap dupliziert).
- Polygon bleibt bewusst ohne Regelmäßigkeits-Constraints (eine Polyline
  hat keine Kanten-Entities für equal — bekannte Grenze, unten gelistet).

**(b) Fillet/Chamfer wie Inventor (`filletInventor`/`chamferInventor` in
tools.dart, Session + modeless Dialog):**
- Kein blockierender Prompt mehr: `FilletSession` (app_state) + das kleine
  "2D Fillet"/"2D Chamfer"-Fenster (pattern_dialog.dart) schweben wie in
  Inventor — Werkzeug bleibt scharf, je zwei Picks = eine Ecke, Werte
  zwischen den Ecken editierbar, letzte Werte bleiben über Sessions
  erhalten.
- Fillet zwischen ALLEN Kombinationen aus Linie/Bogen/Kreis: Fillet-Zentrum
  = Schnitt der Offset-Träger (Linie um r zur Pick-Seite, Kreis/Bogen auf
  R+r bzw. |R−r|), Kandidat mit minimaler Summe der Pick-Abstände gewinnt
  (Inventors Ecken-Disambiguierung). Linien und Bögen werden auf die
  Tangentenpunkte getrimmt (Bögen über den Tangenten-WINKEL am näheren
  Ende); VOLLKREISE bleiben ganz (kein Ende zum Trimmen) — die Tangente
  landet trotzdem.
- Constraints: koinzident an beiden Nähten (`FilletResult.seams` liefert
  Entity + getrimmten Punktindex; `jointPt` mappt auf pt1/pt2 des Bogens
  bzw. pt0/pt1 der Fase) + tangent zu beiden Trägern.
- Inventors Ketten-Verhalten: das ERSTE Fillet eines Werts bekommt seine
  Radius-BEMASSUNG (dimKind 'rad'), alle weiteren mit gleichem Wert eine
  equal-Constraint aufs erste; Wert ändern startet eine neue Kette
  (`firstIdx` reset in `filletNotify`).
- Chamfer mit Inventors drei Modi: 0 = gleicher Abstand, 1 = zwei Abstände
  (d1 auf den ERSTEN Pick), 2 = Abstand + Winkel (Winkel von Linie 1 zur
  Fase, Strahl-Schnitt mit Linie 2). Nur Linie-Linie (wie Inventor).
  Gleicher-Abstand-Fasen: erste bekommt Längen-Bemaßung, weitere equal.
- Preview läuft weiter über `buildToolGeometry` (Params werden von der
  Session in `toolParams` gespiegelt).

**(c) Trim/Split erhalten Constraints (`remapAfterReplace` in
constraints.dart):** Statt `remapAfterRemove` (alles weg) werden Constraints
des ersetzten Elements gehalten, wo sie noch Sinn ergeben — exakt Inventors
Verhalten:
- Punkt-Refs wandern positionsbasiert (Toleranz 1e-6) auf das Teilstück,
  das den Punkt noch HAT; Punkte im weggetrimmten Spann verlieren ihre
  Constraint.
- Entity-Refs (tangent, parallel, Bemaßungen, …) wandern auf das Teilstück,
  das den übrigen Beteiligten der Constraint am nächsten liegt (der Träger
  ist unverändert, die Constraint bleibt also geometrisch gültig); ohne
  Kontext (H/V, Radius-Bemaßung) aufs GRÖSSTE Teilstück. Kreis→Bogen ist
  dabei abgedeckt (Radius-Bemaßung, Tangenten etc. funktionieren auf beiden
  Typen).
- Entity-Level-Fix (anchors = alte Gesamtform) und pattern-Mitgliedschaften
  werden fallen gelassen — die gespeicherte Form existiert nicht mehr.
  Kollabiert eine 2-Entity-Constraint auf ein und dasselbe Teilstück, fällt
  sie ebenfalls.
- Split behält damit ALLES (alle Punkte überleben); eine Gesamtlängen-
  Bemaßung über den Schnitt spannt danach über beide Teilstücke — getestet.
- Nebenbefund gefixt: Trim hinterließ ein LÄNGE-0-Reststück, wenn der
  Schnitt genau auf einem Endpunkt lag (`_notDegenerate`-Filter im
  Trim-Pfad). Nach Trim/Split läuft jetzt zusätzlich `solveConstraints`,
  damit erhaltene Bemaßungen sofort wieder erfüllt sind.

**Tests (`test/m36_test.dart`, 20 neu, gesamt 134):** Slot-Constraint-Sets +
DOF (5 bzw. 6) + Drag-Erhalt, Tangenten-Kreis/-Bogen, Fillet Linie-Linie
(Trim, Nähte, Radius-Dim), equal-Kette + Ketten-Reset bei Wertänderung,
Linie-Bogen-Fillet (Tangenten, Bogen-Trim über Winkel), Kreis-Teilnehmer
ungetrimmt, Chamfer alle drei Modi (inkl. d1-auf-ersten-Pick und
Winkel-Geometrie), Parallel-Ablehnung, Trim-Erhalt von perpendicular /
Radius-Dim (Kreis→Bogen) / tangent (Kreis→Bogen), Drop der weggetrimmten
Koinzidenz, Split-Vollerhalt, Drop von Entity-Fix, Gesamtlängen-Dim über
den Schnitt.

> **HINWEIS (M37):** Einige M36-Behauptungen oben waren im Geräte-Test FALSCH
> und wurden in M37 korrigiert: der Slot-`parallel` und der Bogen-Slot-`equal`
> sind NICHT „rang-neutral", sondern rangredundant und destabilisierten den
> Solver; Fillet/Chamfer ließen die alte Ecken-Koinzidenz stehen (kollabierte
> das neue Segment); die Chamfer-Bemaßung war die Diagonale statt der
> Setbacks; der Fillet-Button war auf Touch tot. Details unten.

---

## M37 — Produktions-Härtung nach dem ersten echten Geräte-Test

Grundlage: Geräte-Log (`ipadprocad_log.txt`, 59 563 Zeilen, **1 802 WARN**),
`Sketch1.dxf` + Sidecars, plus statische Tiefenanalyse. Der volle Audit steht
im README (Abschnitt „PRODUKTIONS-AUDIT", P0–P3 + Tests, mit Erledigt-Notizen);
hier die Essenz für die nächste Session.

**Vier Geräte-Symptome → drei tiefe Ursachen + ein Verstärker (alle belegt,
teils numerisch nachgerechnet):**

1. **Slot-Drag „extrem buggy, Linie/Kreise weg, dann wieder da".** Der
   `parallel`-Constraint des Linear-Slots ist rangredundant (mit den echten
   App-Residuen gemessen: 14 Gleichungen inkl. parallel = Rang **13**), der
   `equal` des Bogen-Slots ebenso (15 → Rang 14). Rangdefizit macht `JᵀJ`
   singulär → libslvs meldet `inconsistent`, LM driftet; pro Frame springt die
   Lösung auf den falschen Tangenten-Ast → **finite, aber falsche** Arcs
   (Radius 54→120, Start≈End → Sweep 0). Ein Sweep-0-Arc rendert NICHTS
   (verschwindet), ein 2.2×-Radius malt quer (‚Linie über dem Fillet'). Beide
   sind finite → `allFinite()` griff nicht → der Frame wurde gemalt. Zusätzlich
   hatte der Anzeige-/Drag-Pfad KEIN Residuen-Gate.
2. **Fillet-Button tut nichts.** Der Fillet-`_SmallRow` hatte kein `onTap` —
   nur das 14-px-▼ öffnete das Flyout (im Log kommt `Tool.fillet` KEIN Mal
   vor, `Tool.chamfer` mehrfach).
3. **Chamfer „geht so", Bemaßung diagonal, ‚Linie über dem Fillet'.** Die
   bestehende Ecken-Koinzidenz der zwei gepickten Kanten wurde NICHT entfernt →
   erzwang Länge 0 des neuen Segments gegen die Bemaßung → Gesamt-Sketch-LM
   divergierte (`err=3.54 satisfied=false` direkt nach dem Chamfer im Log; riss
   den zuvor gebauten Slot mit). Und die Bemaßung war die Hypotenuse statt der
   Setbacks (Inventor: aligned dimensions of the setback distance).
4. **Verstärker:** `_lm`-Rückgabe wurde an drei Stellen ignoriert → divergierte
   Geometrie wurde gerendert UND committet.

**Latenter Native-Bug, im Audit gefunden (vom Dart-Verify stumm gefangen):**
Der Shim verankerte Tangenten immer am Arc-START (`other=0`). SolveSpaces
`ARC_LINE_TANGENT`/`CURVE_CURVE_TANGENT` sind endpunktverankert (`other`/
`other2`, `constrainteq.cpp`); für Fillet-Bögen mit Naht am ENDE war die native
Gleichung 90° falsch, bei Slots stimmte sie nur zufällig auf der symmetrischen
Mannigfaltigkeit. Kreise haben keine Endpunkte (`CURVE_CURVE_TANGENT`
ssassert'et darauf). Das war die zweite Quelle des WARN-Spams.

**Fixes (5 Commits `befac53..3cb40d4`, alle Tests grün):**

- **Solver-Sicherheitsnetz (P0-4/5, P2-2/3).** `solveConstraints` liefert jetzt
  `bool` = erfüllt (Residuum ≤ 1e-2) **und** finite **und** nicht degeneriert.
  Neue Helfer in solver.dart: `constraintResidualNorm`, `hasDegenerateGeometry`,
  `debugRank` (Rang/Gleichungen/Params — Ground Truth für Redundanztests).
  `displayGeometry` zeigt nur erfüllte Frames, sonst die letzte gute Drag-
  Geometrie (`_lastGoodDragGeo`), committet beim Loslassen (Inventor-Verhalten).
  ALLE Commit-Aufrufer sind jetzt atomar mit Rollback+Toast: `_solveAndRebuild`,
  `_addConstraint` (Widerspruch), `confirmDimension`, `setDimensionValue`
  (echt atomar), Pattern/SelfSymmetric, Trim/Split, Konstruktions-Commit
  (As-Drawn-Fallback). `paintGeo` malt degenerierte Arcs als sichtbaren Punkt
  statt `drawArc(0)`.
- **Fillet/Chamfer (P0-1/2/6, P1-1).** Body-`onTap` startet Fillet. Die
  Ecken-Koinzidenz der zwei getrimmten Seam-Punkte wird vor dem Verketten
  entfernt. Chamfer bemaßt `distx`+`disty` (Setbacks) statt Diagonale, alle
  drei Modi. Beide bauen auf lokalen Kopien und committen nur nach
  verifiziertem Solve (sonst voller Rollback — der zuvor gebaute Slot bleibt
  bit-identisch, Sequenztest beweist es).
  BEWUSSTE ABWEICHUNG von M36: die Equal-Kette für Folge-Chamfer entfällt
  (jeder Chamfer eigene x/y-Maße); Fillet behält Radius-Dim + equal-Kette.
- **Slot (P0-3).** Linear-Slot ohne `parallel`, Bogen-Slot ohne `equal`.
  Parallelität/Kappen-Gleichheit sind durch die Tangenten/Konzentrik impliziert
  und bleiben funktional erhalten (Test prüft Kreuzprodukt bzw. Radien-
  Gleichheit nach dem Solve).
- **Tangenten (P1-3 + Shim v3).** Linie-Kreis/Bogen-Residuum vorzeichenbehaftet
  (Seite in `_prepare` eingefroren; glatt, ast-stabil), auch die Polygon-
  Kanten-Variante. Shim v3: `slvs_shim_version()==3`, Naht-Enden in `val`
  (Bit 0/1), vom Aufrufer aus der Geometrie bestimmt (`_tangentSeamFlags`).
  Kreis-Tangenten, nahtlose Tangenten und Shim < v3 bailen sauber auf LM.

**Tests (gesamt Host 157, Shim-Gate 12):**
- `construction_rank_test.dart` (8): Rang == Gleichungen (Redundanz 0) +
  Inventor-DOF für Rechteck 2P/3P, beide Slots, Fillet-/Chamfer-Ecken.
- `drag_stability_test.dart` (9): Drags Frame für Frame über den ECHTEN
  Anzeige-Pfad (finite, nicht degeneriert, Residuum ≤ 1e-4, kein Radius-
  Teleport), Folter-Drag in die Degenerationszone, Park-auf-letztem-Gut,
  8-ms-Budget pro Drag-Solve.
- `operation_sequence_test.dart` (6): die Geräte-Session (Rechteck+Slot+Kreis,
  zwei Chamfer) — Slot bleibt bit-identisch; Fillet-Kette treibt beide Radien;
  abgelehnte Ops ändern NICHTS.
- `shim_test.c` +2: [11] Slot löst NATIV (result OKAY; inkrementeller Drag hält
  parallel+equal), [12] Fillet-Tangente am Arc-ENDE exakt.
- `m36_test.dart`: Slot-Tests auf redundanzfreie Sets, Chamfer-Tests auf
  x/y-Setbacks umgestellt.

**Offen aus dem Audit (Prioritäten im README, Abschnitt PRODUKTIONS-AUDIT):**
P1-2 (Fillet-Trim-Robustheit alle Typpaare), P1-4 (Arc-Rundtrip durch die
C-API verlustfrei absichern / während Drag nicht durch die Engine gehen),
P2-1 (EIN gemeinsames Constraint-Add-Gate), P2-4 (eine Arc-Helferbibliothek
statt mehrerer `norm()`-Kopien), P2-6..P2-9 (Perf/Determinismus/Sidecar/
Autosave), P3-1..P3-8 (Inventor-Dialog-Optionen, Trim/Fillet für Splines/
Ellipsen, Bogenlängen-/Winkel-Bemaßung), T-5/T-7 (Invarianten-Wächter +
VERIFY-FAILED-Zähler = 0 als Geräte-Regressionssignal).

**Nächster Geräte-Test — worauf achten:** 0 (statt 1 802) `VERIFY FAILED`
unter normaler Bedienung, stabiler Slot-Drag, Fillet-Button reagiert,
Chamfer zeigt 5/5 statt 7.07.

---

## M38 — Zweiter Geräte-Test: Ast-Persistenz, Settle, Trim-Bindungen, CP-Fix

Log-Bilanz des M37-Builds: **2 863 Zeilen, 3 WARN, 0 VERIFY FAILED** (vorher
59 563 / 1 802). Die Session wurde vollständig auf dem Host reproduziert und
ist als `device_replay_test.dart` permanent. Kernbefunde und Fixes:

1. **Slot-Faltung, zweite Art.** Nicht mehr Frame-Flackern, sondern ein
   KONTINUIERLICHER Ast-Wechsel durch die degenerierte Lage (jeder Frame
   einzeln erfüllt, Residuen ≤ 3.6e-8 in der Host-Wiedergabe). Per-Solve-
   Seitenwahl kann das nicht verhindern. → `Constraint.tanBranch` (Sidecar
   `tb`): Ast einmalig beim ersten Solve erfasst, danach fix; Kurve-Kurve
   analog (innen/außen). Drags parken an der Grenze statt umzuklappen.
2. **Drag-Commit ohne Settle.** endGripDrag übernahm den letzten guten Frame
   mit bis zu 1e-2 Residuum; auf dem Gerät lagen Slot-Nähte danach über der
   1e-6-Naht-Toleranz von `_tangentSeamFlags` → jede Folge-Operation bailte
   auf LM, ein r=5-Fillet an intakter Ecke wurde fälschlich abgelehnt
   (LM err=3.42), r=50 gelang nach Dialogwechsel nativ. → endGripDrag löst
   voll nach (80 It.) und normalisiert Arc-Winkel (`normalizeArcAngles`).
3. **Fillet-Maße:** JEDE Rundung trägt ihr eigenes `rad`-Maß (Label außen an
   der Bogenmitte); Equal-Kette entfernt — Nutzer-Spezifikation, konsistent
   mit den Chamfer-Setbacks.
4. **Trim/Split-Koinzidenz** (`_bindCutPoints`): neue Schnitt-Endpunkte binden
   Punkt-auf-Punkt (Split-Zwilling) oder Punkt-auf-Kurve auf den Cutter.
   Punkt-auf-Kreis/Bogen neu als Residuum + **Shim v4** `SH_POINT_ON_CIRCLE`
   (`SLVS_C_PT_ON_CIRCLE`, Host-Szenario [13]; Versions-Gate im Packer).
5. **CP-/Punkt-Bindung für deterministische Formen** war seit M34/M36 aus
   (Inferenz lief nur im autoConstrain-Zweig). Punkt-Teil ausgekoppelt als
   `inferPointBindings(..., bindOnlyBefore: firstNew)` und für Rechtecke/
   Slots/Tangenten-Formen aktiv; jede Kandidatin durchläuft
   `wouldOverconstrain`. Tests, die Formen unabsichtlich auf (0,0) zeichneten,
   wurden verschoben; die Erdung selbst ist als Regression festgenagelt.
6. **Pick-Duplikat im Koinzidenz-Werkzeug:** zweiter Punkt-Pick schließt den
   ersten aus (`_nearestPointRef(exclude:)`), trifft also auf gestapelten
   Punkten die ANDERE Entität (Geräte-Log: `e17.p1,e17.p1` abgelehnt).

Stand: Host **161** Tests grün, Shim-Gate **13/13**. Erwartung Geräte-Test 3:
Slot bleibt unter beliebigen Drags ein Slot; Trim-Stücke hängen zusammen;
Ecke-auf-CP erdet; jede Rundung zeigt ihr R; weiterhin 0 VERIFY FAILED.

---

## M38.1 — Trim-Bind-Fix: gestapelte Schnittpunkte werden point-on-point

Geräte-Befund (Log der Session vom 17.07.): zwei Rechtecke bzw. zwei gekreuzte
Linien, von beiden je ein Span weggetrimmt — die beiden neuen Endpunkte liegen
exakt aufeinander, blieben aber nur point-on-curve gebunden und konnten
auseinandergezogen werden. Ursache in `_bindCutPoints`: (a) der
„bereits gebunden"-Check nahm JEDE Koinzidenz als Blocker, auch die schwache
on-curve; (b) die on-curve-Bindung des ersten Trims machte den späteren
point-on-point um genau eine Gleichung redundant → `wouldOverconstrain` lehnte
ihn STILL ab (Log zeigte „cut-bind … pts=e6.p1,e9.p0", Zählerstand unverändert).
Fix: der Block greift nur noch bei vorhandenem point-on-point (pts >= 2); ein
gefundener point-on-point ENTFERNT die subsumierte on-curve-Bindung (Upgrade
statt Stapeln, geloggt als „cut-bind upgrades …"); tryAdd-Ablehnungen werden
geloggt. Regressionen: `trim_stacked_points_test.dart` (Rechteck-Session) und
`trim_crossing_lines_test.dart` (4 Varianten: h/v + schräg, beide
Reihenfolgen) — alle fallen auf dem Vor-Fix-Stand, grün danach.

## M39 — Undo/Redo: Snapshot-Journal pro Skizze (Ctrl+Z / Ctrl+Shift+Z)

**Architektur.** Jede `SketchModel` besitzt ihre EIGENEN zwei Stacks
(`_undoStack`/`_redoStack` mit `UndoSnap`-Einträgen) — Isolation zwischen
Skizzen ist damit strukturell, nicht Buchhaltung. Ein `UndoSnap` ist eine
vollständige Tiefkopie des committeten Zustands: Geometrie (Geos mit kopierten
data-Listen, alle Tags: layer/spline/style/proj/projSeg), Constraints über den
bewährten Sidecar-JSON-Codec (round-trippt value, driven, textPos, anchors,
tanBranch), Layer-Liste + Auge/Schloss. Wiederherstellen ist dadurch EXAKT —
kein Replay, keine inversen Operationen, kein Solve, kein Drift; die Historie
enthält nur Zustände, die schon einmal verifiziert committet wurden.

**Ein Choke-Point.** Da die C-API add-only ist, läuft JEDE Mutation der App
durch `_rebuildEngine` — dort sitzt genau EIN `s.checkpoint()` (unterdrückt
via `_restoringHistory`, sonst würde Undo sich selbst journalieren). Identische
Folgezustände werden dedupliziert: eine Operation mit Doppel-Rebuild kostet
trotzdem nur einen Schritt. Die drei Mutationen OHNE Rebuild checkpointen
explizit: Layer-Auge, Layer-Schloss, leeren Layer anlegen. Baseline: der
`SketchModel`-Konstruktor legt Eintrag 0 an; `openSketch` ruft nach dem Laden
`resetHistory()` — Laden ist keine Bearbeitung, Undo geht „bis zum Anfang"
dieser Sitzung und niemals darüber hinaus. Journal bewusst unbegrenzt
(Snapshot einer 100-Entity-Skizze ≈ zweistellige KB).

**Restore-Pfad** (`AppState.undo()/redo()` → `_applyHistory`): bricht alle
laufenden Picks ab (toolPoints, pattern, filletSess, pendingDim, conPts/Ents/
Edges, modEntity, Selektion), verlässt den Editiermodus, falls der Layer im
Zielzustand fehlt/versteckt/gesperrt ist, und stellt über `_rebuildEngine`
wieder her (Journal-Geos werden beim Restore erneut kopiert — nie aliasen).
Während eines Grip-Drags ist Undo gesperrt. Ansonsten Toast „Nothing to
undo/redo.". View-Zustand (Zoom, Tool, DOF-Anzeige) ist absichtlich NICHT Teil
des Journals — wie Inventor.

**Shortcuts** (viewport.dart, M30-Block): Ctrl+Z = Undo, Ctrl+Shift+Z und
Ctrl+Y = Redo (Ctrl schließt Cmd auf dem iPad ein). Immer nur die AKTUELLE
Skizze.

**Tests:** `undo_redo_test.dart` (7): Zeichnen→Undo-auf-leer→Redo exakt;
komplette Session (Linien, Trims, Bemaßungs-Edit) verlustfrei bis zum Anfang
zurück und wieder vor, inkl. Stabilität bei Hin-und-her; neuer Edit nach Undo
tötet den Redo-Zweig; strikte Pro-Skizze-Isolation (Undo in B lässt A und
dessen eigene Historie unberührt); Layer-Ops (anlegen/Auge/Schloss) undoable;
Restore bricht schwebende Picks ab und journaliert sich nicht selbst;
M38-Trim-Upgrade round-trippt durchs Journal. Suite: **173 grün**.

## M40 — Construction-Geometrie (Inventors Format > Construction)

Recherchiert gegen die Inventor-Doku: Linetypes sind Normal / Construction /
Centerline / Reference; Construction dient dem Constrainen normaler Geometrie,
ist voll bemaß-/constrainbar; Workflow = Format-Panel-Toggle (Auswahl +
Klick konvertiert, nochmal Klick zurück). Die Profile-Consumption-Seite ist in
2D bedeutungslos — Construction ist hier ein reiner Linientyp.

**Implementierung.** Neuer Stil `Geo.styleConstruction = 2` im bestehenden
Style-Slot (rides styles.json-Sidecar unverändert generisch, DXF unberührt).
Rendering in `paintGeo`: dünner (0.55× strokeWidth, geklonter Paint — nie den
Caller-Paint mutieren) + fein gestrichelt (5/4) für ALLE Typen; Kreise/Bögen/
Polylines/Splines dashen über `_dashedChain` (Punktkette mit DURCHLAUFENDER
Phase, kein Muster-Neustart pro Sample). Toggle `toggleConstructionSelected()`
teilt sich `_toggleStyleSelected` mit der Centerline (Inventor-Semantik:
gemischte Auswahl → erst alle konvertieren, uniforme → zurück zu Normal).
Ribbon Format-Panel Zeile 2: Construction | Centerline | Center Point (3×21px,
neues 'constr'-Icon). Solver/Snap/Picking/Dimensionen unterscheiden NICHT nach
Stil — Construction verhält sich exakt wie normale Geometrie.

**Slot-Achse.** `_linearSlot` liefert jetzt 5 Entities: [rail1, rail2, cap1,
cap2, ACHSE] — die Achse ist eine Construction-LINIE zwischen den beiden
Cap-Zentren (Inventor). Der Commit bindet ihre Endpunkte koinzident auf die
Zentren: +4 Parameter, +4 Gleichungen → Slot behält seine 5 DOF, Redundanz 0
(rank-gemessen im Test). Bogen-Slots bekommen (noch) keine Auto-Achse: jede
volle Anbindung eines Construction-Bogens (concentric + beide Enden) ist
messbar um genau 1 Gleichung redundant — offen, in Known limits notiert.

**Beifang-Fix:** `_carry` in modify.dart kopierte Layer + Spline-Tag, aber
NICHT den Linienstil — Trim/Move/Rotate/Mirror/Stretch/Offset setzten damit
jede Centerline still auf Normal zurück. Jetzt trägt `_carry` den Stil immer
mit (Trim-Stücke einer Construction-Linie bleiben Construction).

**Tests:** `construction_geometry_test.dart` (6): Toggle hin/zurück, gemischte
Auswahl, Bemaßung TREIBT eine Construction-Linie, Slot-Achse rank-clean mit
5 DOF, Achsen-Drag bewegt den Slot kohärent, Stil überlebt Trim + Undo-Journal.
Slot-Erwartungen in m36/operation_sequence/device_replay auf 5 Entities
angepasst (Achtung: hartkodierte Folge-Indizes!). Suite: **179 grün**.

## M41 — Inventors Parameter-/Ausdrucks-System für Bemaßungen

Recherchiert gegen die Inventor-Doku (Edit box reference, Parameters in
models, Formulas and equations): jede Bemaßung IST ein Modell-Parameter mit
Auto-Namen d0, d1, …; das Edit-Feld parst volle Ausdrücke ("Name = Ausdruck"
benennt um/erstellt, Syntaxfehler werden ROT gezeigt); auf dem Bildschirm
steht nur der BERECHNETE Wert (fx:-Prefix bei gleichungsgetriebenen
Bemaßungen), der rohe Ausdruck erscheint beim erneuten Öffnen wieder; und
während das Feld offen ist, fügt ein Klick auf eine ANDERE angezeigte
Bemaßung deren Parameternamen an der Cursorposition ein ("if the value is
displayed in the graphics window, you can click it to enter its name").

**Implementierung.** Neues `lib/params.dart`: Tokenizer + rekursiver
Abstiegsparser mit Inventors Präzedenz (+ - * / ^ % , ^ rechtsassoziativ),
Klammern, `;` als Mehrfach-Argument-Trenner (Inventor meidet das Komma wegen
des EU-Dezimalkommas — das Komma ALS Dezimaltrenner wird akzeptiert),
Einheiten-Suffixe mm/cm/m bzw. deg/rad + ul, Konstanten PI/E, Funktionen
sin/cos/tan (GRAD wie Inventors Default), asin/acos/atan (liefern Grad),
sqrt/abs/floor/ceil/round/exp/ln/log/sign/min/max/pow. Bewusst KEINE volle
Einheiten-Algebra (kein mm^3-Fehler) — numerische Auswertung in der
Basis-Einheit (mm bzw. Grad). `Constraint` trägt `paramName` ('nm') und
`expr` ('ex') im Sidecar — damit round-trippt auch das Undo-Journal (M39)
beides automatisch.

**Pipeline (app_state.dart):** `ensureParamName(s)` vergibt d0, d1, … bei
Erstellung UND beim Laden alter Sidecars. `setDimensionText` ist der eine
Commit-Pfad (Umbenennen mit Referenz-Nachzug per Wortgrenzen-Regex, Zyklen-/
Selbstreferenz-/Kollisions-Ablehnung, bloße Zahl → expr=null, kein fx);
`dimTextValid` ist die Live-Validierung fürs rote Feld. Nach JEDEM Solve
(`_rebuildEngine`-Tail, hinter `_refreshDriven`) läuft `_chaseExpressions`:
Ausdrücke zum Fixpunkt auswerten (Ketten in einem Pass), dann erneut lösen,
max. 3 Runden, `_inExprChase`-Guard gegen Rekursion; ein unerfüllbarer
Ausdruckswert friert auf den letzten konsistenten Zahlen ein (Rollback wie
M37, nie divergiert committen). Getriebene (Referenz-)Bemaßungen sind
referenzierbar — ihre Nachmessung nach dem Solve zieht die Abhängigen nach;
selbst editierbar sind sie weiterhin nicht. Gelöschte Referenz: der Wert
bleibt EINGEFROREN, der Ausdruck zeigt sich beim nächsten Edit rot (Inventor
hält den letzten guten Wert).

**Viewport:** Edit-Feld zeigt `d3 = ` als Prefix, den ROHEN Ausdruck (falls
vorhanden), färbt live rot, Enter mit rotem Inhalt bleibt offen, Klick-weg
committet Gültiges und behält sonst den gemessenen Wert (neu platzierte
Bemaßung bleibt wie in Inventor in jedem Fall bestehen); Klick auf ein
anderes Bemaßungs-Label fügt dessen Namen ein statt zu committen.
`confirmDimensionText` journaliert ZWEI Schritte (Anlegen mit Messwert,
dann Text anwenden) — Undo schält sie einzeln ab.

**Tests:** `dimension_expressions_test.dart` (9): Engine (Präzedenz,
Einheiten, Komma, Funktionen, Fehlerfälle), Auto-Namen, Ausdruck treibt
Geometrie, Referenz-Kette propagiert durch zwei Stufen, Umbenennen zieht
fremde Ausdrücke nach + Kollisionsschutz, Zyklen/Selbstreferenz/Unbekannte
abgelehnt ohne Seiteneffekt, getriebene Referenz, Sidecar-Round-Trip,
Undo/Redo durchs Journal. Suite: **188 grün**.

## M42 — Hover-Feedback + Sichtbarkeit außerhalb des Editiermodus

**Hover-Highlight auf Bemaßungs-Labels** (Maus/Trackpad): das Label unter dem
Cursor bekommt einen blauen Rahmen + helleren Hintergrund, wann immer ein
Klick darauf etwas TUT — im normalen Layer-Editiermodus (Tap öffnet den
Wert-Editor; aktiv bei Tool none und dimension) und während das M41-
Ausdrucks-Feld offen ist (Klick fügt den Parameternamen ein; das EIGENE
Label wird nie markiert). Implementierung: `_hoverDimLabel` im Viewport-State
(onPointerHover gegen die `dimLabelRects` des letzten Frames), als
`hoverDim` in den Painter gereicht, `_paintDimension(highlight:)` zeichnet
Rahmen/Hintergrund. Touch hat kein Hover — reine Zusatz-Affordanz.

**Sichtbarkeit wie Inventor:** ohne aktiven Editier-Layer (`inEditMode`
false) sind Skizzen-Annotationen unsichtbar — Bemaßungen (ihre Tap-Rects
werden GELEERT, sonst träfen Taps Geister-Labels), Constraint-Glyphen,
DOF-Pfeile UND Construction-Geometrie (`isConstruction`-Skip in der
Entity-Schleife). Die normalen Linien (inkl. Centerlines) bleiben sichtbar.
Beim Betreten des Editiermodus kommt alles zurück.

**Tests:** `m42_visibility_test.dart` (4): Rects leer außerhalb / gefüllt im
Editiermodus / wieder geleert beim Verlassen; Hover-Pfad + Tap öffnet den
Editor; Klick auf ein ANDERES Label während des offenen Ausdrucks-Felds
fügt `d1` ein statt zu committen; Construction-Skip wirft nicht. Harness-
Hinweis: der Test pumpt den Baum nach editingLayer-Wechseln NEU (keine
Listener-Verdrahtung im Test). Suite: **192 grün**.

## M42-Fix — Geräte-Test: Referenz-Klick verlor gegen die Tastatur

Symptom auf dem iPad: das andere Bemaßungs-Label highlightete korrekt, aber
der Klick darauf COMMITTETE das Ausdrucks-Feld statt den Parameternamen
einzufügen; dazu „zufälliges" Springen der Ansicht beim Öffnen/Schließen des
Editors. Ursache (Log 1a856af, Session 01:24): drei Solves mit unveränderten
cons=11 = drei Klick-weg-Commits. Der Tap AUSSERHALB des TextFields
unfokussiert per Flutter-Default schon beim Pointer-DOWN → iOS-Tastatur
faehrt ein/aus → Scaffold resized → map() (verankert bei size/2) verschiebt
JEDES Label zwischen Down und Up → der Up-Hit-Test verfehlte das sichtbar
getroffene Label → „Klick daneben" → Commit. Dasselbe Resize erklaert die
Pan/Zoom-Spruenge.

Drei Fixes: (1) `resizeToAvoidBottomInset: false` am Scaffold — die
CAD-Leinwand reflowt NIE mit der Tastatur (Editor kann in der unteren
Bildhaelfte von der Tastatur verdeckt sein — bekannt, spaeter clampen);
(2) `_downDimHit`: das Label unter dem Finger wird beim Pointer-DOWN
gecaptured und ist fuer den Klick autoritativ (auch fuer Label-Tap im
Dimension-Tool); (3) `onTapOutside: (_) {}` am Editor-TextField — Commit vs.
Referenz-Einfuegen entscheidet ausschliesslich `_handleClick`, der
Default-Unfocus rennt nicht mehr dagegen. Regressionstest: Down auf dem
Label, Label wird VOR dem Up verschoben (simuliertes Tastatur-Relayout), Up
an der alten Position → Editor bleibt offen, `d1` eingefuegt. Suite:
**193 gruen**.

## M43 — Inventors Parameters-Fenster (Manage > fx Parameters)

Neuer Ribbon-Panel „Manage" mit fx-Button (zwischen Format und Modify) —
oeffnet ein MODELESSES, per Titelleiste VERSCHIEBBARES Fenster ueber dem
Viewport (`widgets/parameters_dialog.dart`, Position lebt als `_paramsPos`
im Viewport-State, geclampt). Tabelle wie Inventor: Model Parameters (alle
Bemaßungen: Name-Zelle editierbar mit Referenz-Nachzug, Equation-Zelle mit
der vollen M41-Grammatik + Live-Rot, getriebene Bemaßungen read-only
„(reference)", Value-Spalte) und User Parameters (Add-Button, Auto-Name
User_1…, Loeschen nur unreferenziert — sonst Toast mit dem Nutzer).
Waehrend eine Equation-Zelle fokussiert ist, fuegt ein Tap auf ein
Bemaßungs-Label im Viewport dessen Parameternamen an der Cursorposition ein
(`AppState.paramRefSink`, vom FocusListener der Zelle gesetzt/geraeumt; der
Viewport prueft den Sink VOR der normalen Klick-Behandlung und nutzt den
Down-Zeit-Hit aus dem M42-Fix; Hover-Highlight ist dann ebenfalls aktiv).

**Engine:** `UserParam {name, expr?, value}` in params.dart (+ JSON-Codec),
`SketchModel.userParams`, eigener Sidecar `<name>.params.json`, UndoSnap um
`uparams` erweitert (sameAs, _takeSnap, Restore) — Journal round-trippt.
`paramTable` = Bemaßungen + User-Params; `_depGraph`/`_cycleIfRefs`
verallgemeinern die Zyklen-Pruefung ueber BEIDE Arten (Bemaßung↔User-Param
gemischte Ketten); `_renameRefs` fegt auch User-Ausdruecke;
`_applyExprValues` wertet User-Params im selben Fixpunkt aus (Domaene mm).
APIs: addUserParam, setUserParamText (Grammatik wie Bemaßung inkl.
„Name = …"), renameUserParam, deleteUserParam (Referenz-Guard),
userParamTextValid, renameDimParam (Name-Zelle der Model-Zeile);
User-Param-Aenderungen checkpointen EXPLIZIT (eine reine Wert-Aenderung
ohne abhaengige Geometrie rebuildet die Engine nicht).

**Tests:** `m43_parameters_test.dart` (5): CRUD + Rename-Nachzug beide Wege,
gemischte Kette User→Dim→User→Dim propagiert bis in die Geometrie, Zyklus
ueber Arten hinweg + Delete-Guard, Validierung spiegelt Commit-Regeln,
Codec- und Journal-Round-Trip. Suite: **198 gruen**.

## M44 — Insert: parametrischer Text, Bild-Import, DXF-Import (iOS-Filepicker)

**Parametrischer Text** (Inventors Skizzentext mit eingebetteten Parametern):
Template mit `<Name>`-Platzhaltern, die als AKTUELLER Parameterwert rendern
(Zahl getrimmt) und jeder Wert-Aenderung UND jedem Rename folgen
(`_renameRefs` fegt jetzt auch Templates via `renameInTemplate`). Unbekannte
Namen bleiben woertlich stehen (Inventor zeigt das rohe Token bis der
Parameter existiert). Text-Tool im Sketch-Panel: Tap platziert, Dialog nimmt
Template (mehrzeilig) + Hoehe (mm); Tap auf vorhandenen Text oeffnet den
Edit-Dialog (mit Delete), Drag verschiebt. Text ist ECHTER Inhalt — auch
ausserhalb des Editiermodus sichtbar (im Gegensatz zu M42-Annotationen).

**Bild-Einfuegen** (Insert > Image): iOS-Dokumentpicker (`file_picker`,
FileType.image) → Datei wird NEBEN die Sidecars kopiert (Picker-Temp stirbt
mit der Session), zentriert mit 100 mm Breite platziert, Aspekt aus den
Pixelmassen. Bild ist ein Underlay (unter aller Geometrie gezeichnet).
Antippen selektiert (blauer Rahmen + Resize-Griff unten rechts, Loesch-X oben
rechts); Drag verschiebt, Eck-Griff skaliert aspekterhaltend. Async-Decode
mit `_imgCache` (ui.Image), Broken/Loading zeigt einen Platzhalterrahmen.

**DXF-Import** (Insert > ACAD): iOS-Picker (FileType.custom, .dxf) →
`importDxf` laedt in eine Wegwerf-`SketchModel` mit demselben Backend-Loader,
der Skizzen oeffnet, re-homed die Entities auf den Editier-Layer (oder Default)
und committet sie als EINEN Journal-Schritt durch die normale Solve/Rebuild-
Pipeline. Leerer/kaputter Import wird mit Toast abgelehnt, ohne Seiteneffekt.

**Modell/Persistenz:** `SketchText` und `SketchImage` in `inserts.dart`
(+ JSON-Codecs), `SketchModel.texts`/`.images`, eigene Sidecars
`<name>.texts.json` / `.images.json`, UndoSnap um `texts`+`images` erweitert
(sameAs/_takeSnap/Restore) → Journal round-trippt beide. Test-Hook
`docsDirForTest` (@visibleForTesting), weil Bild-Copy `_sketchDir` braucht
und der Host-Test keinen Path-Provider hat.

**Tests:** `m44_inserts_test.dart` (5): Template-Rendering (Substitution,
Trim, Unbekanntes woertlich, Refs, Rename), Text folgt Wert+Rename +
CRUD/Move-Journal, Text/Bild-Codec-Round-Trip, Bild Insert/Move/Resize
(Aspekt fix + Journal), DXF-Import (nur natives Backend — Merge auf Layer,
EIN Undo-Schritt, Garbage abgelehnt; auf der Dart-Fallback-Engine
uebersprungen wie die bestehende DXF-Abdeckung). Suite: **203 gruen**.

CI-Hinweis: `file_picker` bringt iOS-Pod-Code — integriert automatisch ueber
den bestehenden CocoaPods-Flow (`flutter build ios --config-only` → Podfile).
Basis-Dokument/Bild-Picking nutzt UIDocumentPicker, braucht KEINE
Info.plist-Usage-Strings.

## M45 — Geraete-Test-Fixes (Insert) + Text-Fenster & Bounding-Rect

Aus dem Geraete-Log (build 173239b): Bild-Resize ging nicht, DXF-Import
landete unsichtbar bei ~10000,-2600. Behoben plus die gewuenschten
Text-Erweiterungen.

**Bild-Fixes.** (1) Resize-Griff-Trefferzone war im FALSCHEN Eck: die Griffe
werden an den SCREEN-Ecken gezeichnet (dst.bottomRight/topRight), der
Hit-Test testete aber die WELT-Rect-Ecken — und Screen-unten = -Welt-y, also
lagen sie ueber Kreuz. Beide Hit-Tests (Resize + Loesch-X) rechnen jetzt in
Screen-Koordinaten ueber `_worldToScreen`. (2) Bilder tragen ihren
Editier-Layer (`SketchImage.layer`); ausserhalb dieses Layers werden sie
gedimmt + entsaettigt gezeichnet (ColorFilter-Matrix, ~40% Deckkraft),
Griffe/Selektion nur auf dem eigenen Layer. (3) Insert platziert AM CURSOR
(`app.insertAnchor` = letzte Zeigerposition, im Viewport bei hover/down
gesetzt) mit Breite = 0.5 * aktuelle Ansichtsbreite (`viewWidthWorld`).

**DXF-Fix.** `importDxf` misst die Bounding-Box der eingelesenen Entities
(Kreise/Boegen inkl. Radius) und verschiebt sie so, dass ihr Mittelpunkt auf
dem URSPRUNG liegt — DXF traegt absolute Modellkoordinaten, die sonst weit
ausserhalb der Ansicht liegen. Log nennt jetzt den Versatz.

**Text-Fenster (statt AlertDialog).** Neues verschiebbares, modeless
`TextEditorWindow` im Stil des Parameter-Fensters (`text_editor_window.dart`,
Position `_textWinPos`): mehrzeiliges Template-Feld, **Font-Dropdown**
(Roboto/Helvetica/Courier/Georgia/Menlo) und **Groesse (mm)**, Live-Preview.
Waehrend das Feld fokussiert ist, fuegt ein Tap auf ein Bemassungs-Label
dessen Namen IN ANFUEHRUNGSZEICHEN ein (`"d0"`, vom Nutzer so gewuenscht) —
`AppState.textRefSink`, gleiche Viewport-Routing-Logik wie der Parameter-
`paramRefSink` (Down-Zeit-Hit, Hover-Highlight). Editier-Session-Lifecycle
(`beginTextEdit/endTextEdit`, `editingText`/`editingTextIsNew`): eine
frisch platzierte, leer abgebrochene Text-Instanz wird verworfen und
erzeugt via `placeholder:true` KEINEN Undo-Schritt; Commit checkpointet.

**Bounding-Rect (Construction-Stil, messbar).** `textBoundsWorld` misst den
gerenderten String automatisch (Font + Hoehe, gemeinsamer Top-Level-Measurer
`measureSketchText`) und liefert das Welt-Rect ab der Unten-Links-Anker-
position. Gezeichnet als DUENN GESTRICHELTES Rechteck im Construction-
Linetype-Look, NUR im Layer-Editiermodus und nur fuer Texte auf dem
Editier-Layer. `textSnapPoints` bietet die 4 Ecken + 4 Kantenmitten dem
Snapper an (via `_snapped` → `computeSnap` extraPoints), sodass Bemassungen
UND neue Geometrie an eine Textbox andocken/messen koennen.

WICHTIGE Design-Einschraenkung (fuer die naechste Session dokumentiert): das
Text-Rect ist KEINE echte Solver-Geometrie, sondern ein Painter-Overlay mit
Snap-Punkten. Man kann also Bemassungen/Geometrie AN die Box-Ecken snappen
und so bemaßen, aber die Box-Kanten sind keine eigenstaendig selektierbaren
Entities und nehmen nicht an Constraints teil. Voll-solver-integrierte
Text-Rects (wie projizierte Geometrie gepinnt) waeren ein groesserer,
riskanter Umbau des Rebuild-Pfads — bewusst aufgeschoben.

**Tests:** `m45_inserts_fixes_test.dart` (6): Bild-Layer + View-Breite,
Font/Layer-Round-Trip, Bounding-Rect-Groesse + Ecken-Snap-Punkte,
Snap-Punkte nur auf Editier-Layer, DXF-Rezentrierung (natives Backend),
Editier-Session-Lifecycle. Suite: **209 gruen**.

## M46 — Tastenkuerzel in Editier-Fenstern unterdruecken

Geraete-Feedback: `l` startete das Linien-Werkzeug, obwohl das Text- oder
Parameters-Fenster offen war und getippt wurde. Ursache: die Buchstaben-
Shortcuts im ancestor-`Focus.onKeyEvent` des Viewports feuerten, weil der
Fokus in bestimmten Situationen nicht (mehr) im TextField lag bzw. der
Viewport ihn zurueckholte.

Fix (viewport.dart): VOR jeder Viewport-Tastenbehandlung wird geprueft, ob
gerade getippt wird — `typing = _inlineDim != null || app.editingText != null
|| app.showParams || _editableHasFocus()`. Wenn ja: `KeyEventResult.ignored`,
d.h. der Viewport fasst die Taste nicht an (weder Buchstaben-Shortcuts noch
Escape/Enter — Escape soll die Feld-Bearbeitung abbrechen, Enter sie
bestaetigen; beides ist Sache des TextFields). Die drei App-State-Flags sind
der deterministische Backstop (unabhaengig vom Fokus-Routing);
`_editableHasFocus()` scannt zusaetzlich das primary-focus-Element auf ein
`EditableText`, damit kuenftige Text-Fenster automatisch mitgeschuetzt sind.

**Tests:** `m46_shortcut_suppression_test.dart` (5): Baseline L→Linie; bei
offenem Parameters-Fenster feuern L/C/R/D NICHT; bei offenem Text-Editor
feuert L nicht; nach Schliessen des Fensters geht L wieder; Ctrl+Z ist
ebenfalls unterdrueckt. Suite: **214 gruen**.

## M48 — Natives iOS-Kontextmenue in der Sketch-Galerie

Long-Press auf eine Karte im Home-Tab oeffnet ein ECHTES UIKit-Menue
(`UIContextMenuInteraction` + `UIMenu`): System-Blur, Haptik, Karte hebt ab.
Eintraege: Rename / Duplicate / Export / Share, und **Delete in eigener
Sektion, von UIKit selbst rot gezeichnet** (wir setzen nur `.destructive` —
niemals selbst einfaerben).

**WARUM EIN PLUGIN UND KEIN SWIFT IM RUNNER (die eigentliche Lehre).** Es gibt
kein `frontend/ios/` im Repo — CI baut es bei JEDEM Run neu mit
`flutter create`. Handgeschriebenes Swift im Runner-Target waere also jedes Mal
weg. Ein Plugin als **path-Dependency** umgeht das komplett: CocoaPods zieht
`packages/native_menu` ueber `.flutter-plugins-dependencies` (von
`flutter pub get` erzeugt) im bestehenden `flutter build ios --config-only`.
Exakt der Weg, den `file_picker` (M44) schon geht — der Pfad ist also erprobt.
Eine frühere Session hielt das faelschlich fuer einen harten Blocker.

**Architektur.** Flutter malt in EINE UIView. Eine `UiKitView` pro Karte waere
teuer und der Preview trotzdem leer (die Pixel gehoeren Flutter). Stattdessen
haengt EINE `UIContextMenuInteraction` an der FlutterView, und Dart published
laufend die Trefferrechtecke der Karten. Der Delegate schlaegt den Punkt nach;
ein Treffer liefert ein `UIMenu`, ein Fehlschlag `nil` — dann reicht UIKit den
Touch unveraendert an Flutter durch.

**Sicherheitsnetze (der Sinn des Entwurfs):**
- Die Interaction haengt NUR dran, solange Targets existieren. Home verlassen
  disposed `HomeView`, das published eine leere Liste und ENTFERNT sie — der
  Long-Press/Drag des CAD-Viewports kann nie verdeckt werden.
- Ausserhalb iOS ist jeder `NativeMenu`-Einstieg ein No-Op (`Platform.isIOS`),
  die Host-Suite sieht also nie einen Platform-Channel.
- Rechtecke werden am Scroll-Viewport geclippt: eine weggescrollte Karte im
  Cache-Extent darf keinen Press beanspruchen.
- Der abhebende Preview ist das VORHANDENE 380x240-Preview-PNG des Sketches,
  kein Snapshot der Metal-Ebene (unter Impeller unzuverlaessig).
- **FALLE:** share/export MUESSEN einen Popover-Anker bekommen. Ein Sheet ohne
  `sourceRect` wirft auf dem iPad `NSGenericException` — das ist ein Absturz,
  kein Schoenheitsfehler.
- **FALLE:** Export nutzt `asCopy: true`. Mit `false` VERSCHIEBT der Picker den
  Sketch aus Documents heraus.

**Dateioperationen.** `deleteSketch` / `renameSketch` / `duplicateSketch` /
`sketchExportPath` laufen alle ueber `AppState.sketchFileSuffixes` — EINE Liste
aller zehn Dateien pro Sketch. Neue Sidecars MUESSEN dort eingetragen werden,
sonst verliert ein Rename sie stillschweigend.

**FALLE (die wichtigste):** `deleteSketch` wirft den Sketch aus der SESSION,
BEVOR es Dateien anfasst. `finishEdit`/`goHome`/`closeTab` speichern
automatisch — ein noch offenes Model haette die Dateien nach dem Loeschen
froehlich zurueckgeschrieben. Ein Test pinnt genau das.

`SketchModel.name` ist final, darum wird ein OFFENER Sketch beim Umbenennen
gespeichert, verworfen und aus den umbenannten Dateien neu geoeffnet —
korrekt, zum Preis des Undo-Journals dieses Sketches.

**CI: IPA-Job auf `macos-26`.** Das Menue ist so oder so ein echtes `UIMenu`,
aber das AUSSEHEN einer System-Komponente folgt dem SDK, gegen das gelinkt
wurde, nicht unserem Code. Gegen das iOS-17-SDK (macos-14) rendert es in
Pre-26-Kompatibilitaetsoptik; gegen das iOS-26-SDK uebernehmen
System-Komponenten Liquid Glass automatisch, ohne Codeaenderung. Der Umzug ist
ohnehin erzwungen: macos-14-Images sind seit 2026-07-06 deprecated und ab
2026-11-02 tot.

Bewusst nur `m5-flutter-ipa` umgezogen — `build-core-ios` und
`m3-ios-sim-logic` bleiben auf dem erprobten macos-14, damit der Radius EIN Job
und EINE Zeile ist. Beide Labels sind arm64 (keine Host-Arch-Aenderung).
Deployment-Target bleibt 14.0 (Xcode 26 akzeptiert praktisch >= 12.0, trotz
dokumentierter 15; Qt-iOS braucht >= 14.0). Xcode 27 hebt den Boden auf 15.0.

Erster Job-Schritt ist ein Toolchain-Report mit `sw_vers`,
`xcodebuild -version`, der iOS-SDK-Version und einer expliziten Zeile
`LIQUID GLASS CHECK: PASS|WARN`. Nach der Projektregel „gruener Haken ist kein
Beweis" ist DAS der Marker, den man liest.

**RISIKO / REVERT:** Die echte Unbekannte ist Qt 6.7 + Xcode-26-Toolchain beim
Bauen von qcad-core. Stirbt der Job im Core-Build waehrend die Flutter-Schritte
gesund sind: die eine Zeile `runs-on` zurueck auf `macos-14`. Der Feature-Commit
ist unabhaengig und braucht keine Runner-Aenderung — man behaelt das native
Menue und verliert nur das Glas. Ist Qt der einzige Verlierer, ist der saubere
Fix ein Split: core+slvs auf macos-15 als Artefakte bauen, IPA hier linken
(alte `.a` linken problemlos gegen einen neueren ld).

**Nebenbei (Geraete-Feedback):** Der „CAD"-Titel im Home-Tab ist weg — nur noch
der runde „+" (die Galerie IST die Startseite). Und der Home-Tab in der unteren
Leiste laeuft jetzt buendig bis an den linken Rand in den Bildschirmradius
hinein; `_Tab.leftPad` schiebt nur den INHALT (Icon + Label) um 28 nach innen,
damit ihn die Ecke nicht abschneidet. Hintergrund und blaue Unterstreichung
fuellen die Ecke.

**Tests:** `native_context_menu_test.dart` (14): Menue-Vertrag (IDs,
Reihenfolge, Sektionen, destructive-Flag), das `toMap()`-Wire-Format, das der
Swift-Parser woertlich liest, No-Op ausserhalb iOS, und jede Dateioperation
inkl. der Autosave-Wiederauferstehungs-Sperre. Suite: **245 gruen**.

**Nicht enthalten / offen:** Rename- und Delete-Bestaetigung sind weiterhin
Flutter-`AlertDialog`s (nur das Kontextmenue selbst ist nativ). Die UIKit-Haelfte
ist auf dem Host nicht testbar — Geraete-Test steht aus: Long-Press hebt die
Karte ab, Delete ist rot, Export/Share oeffnen als Popover AN der Karte (kein
Absturz), und im CAD-Viewport darf ein langer Druck NICHTS ausloesen.

## M49 — Split, exakt wie Inventors 2D-Skizzen-Split

Split gab es schon (M5-Ribbon, `splitEntity` in `modify.dart`), aber es war
NICHT Inventors Verhalten: es schnitt am ANGEKLICKTEN PUNKT, zersaegte einen
Kreis in N Boegen (einen pro Schnittpunkt), verweigerte geschlossene Polylinien
komplett und kannte weder Constraint-Vererbung noch Hover-Preview.

**Autodesks Vertrag (recherchiert, Inventor-Hilfe "To Split, Trim, or Extend
Curves"), den M49 jetzt eins zu eins umsetzt:**
- "splits a selected curve to the NEAREST INTERSECTING CURVE" — der Schnitt
  liegt auf einem Schnittpunkt, NIE unter dem Cursor. Der Klick sagt nur,
  WELCHE Kurve und WO ENTLANG man ist.
- "When multiple intersections are possible, Inventor selects the nearest one"
  — naechster Schnittpunkt zum CURSOR, entlang der Kurve gemessen.
- "Both segments of the split inherit the Horizontal, Vertical, Parallel,
  Perpendicular, and Collinear constraints of the original. Equal and
  Symmetric constraints are broken when necessary."
- Bemassungen bleiben erhalten.
- Hover zeigt den Split VORHER an ("pause over a curve to preview the split").
- Rechtsklick wechselt innerhalb der Sitzung zu Trim/Extend, Esc/Done beendet;
  die Sitzung bleibt fuer MEHRERE Splits offen.
- **Split loescht NIE.** Das ist Trims Verhalten ("no physical or virtual
  intersections -> the Trim command deletes the curve"), nicht Splits.

**Umsetzung.**
- `modify.dart`: neuer `SplitPlan {cuts, pieces, hovered}` — EIN Codepfad fuer
  Preview und Ausfuehrung. `planSplit` / `splitEntity` / `splitPoints`.
- OFFENE Traeger (Linie, Bogen, offene Polylinie/Spline) haben schon zwei
  Enden, also EIN Schnitt am naechsten INNEREN Schnittpunkt -> zwei Stuecke.
  Ein Schnittpunkt exakt AUF einem Endpunkt schneidet nichts weg und zaehlt
  deshalb nicht.
- GESCHLOSSENE Traeger (Kreis, geschlossene Polylinie) haben keine Enden, die
  einen einzelnen Schnitt begrenzen koennten. Inventor laeuft darum vom Cursor
  in BEIDE Richtungen bis zum ersten Treffer: die ueberfahrene Spanne plus ihr
  Komplement — immer GENAU zwei Stuecke, nie N.
- Neue Bogenlaengen-Parametrisierung fuer Polylinien (`_polyCumLen`,
  `_polyParam`, `_polyPointAt`, `_polySub`), damit geschlossene Polygone
  korrekt in zwei OFFENE Ketten zerfallen (ein Split-Stueck ist nie wieder
  eine Schleife).
- Layer, Linienstil und Spline-Tag reiten ueber das vorhandene `_carry` mit.
- `constraints.dart`: `remapAfterSplit` + `kSplitInherited` / `kSplitBroken`.
  Das generische `remapAfterReplace` gibt eine Entity-Constraint an GENAU EIN
  Stueck (richtig fuer Trim, wo das andere weg ist) — ein Split behaelt beide,
  also bekommt eine horizontale Linie zwei horizontale Haelften.
- `app_state.dart`: `splitPreview()`, `cycleModifyTool()` (Rechtsklick-Ring
  Split -> Trim -> Extend), Split loggt jetzt sein Constraint-Delta wie Trim.
- `viewport.dart`: Preview malt die ueberfahrene Spanne blau und die
  Schnittpunkte als roten Punkt mit Ring. Rechtsklick (nur Maus) geht in den
  Tool-Ring und zaehlt nie als Tool-Klick.

**FALLE:** `m36_test.dart` pinnte die ALTE Regel ("Horizontal ueberlebt auf
EINEM Stueck"). Das widerspricht Autodesks Doku und wurde auf 2 korrigiert —
mit Kommentar, dass M49 die Erwartung abloest. Wer die Zahl zurueckdreht,
bricht die Inventor-Treue.

**Status:** host-getestet. `flutter test` **269 gruen** (vorher 245, +21 neue
in `test/m49_split_test.dart` + 3 in bestehenden Suites), `flutter analyze`
**12 Issues, alle vorbestehend** (die `unused_local_variable`-Warnung in
`modify.dart:65` steht so auch in HEAD, per `git show` geprueft) — also keine
neuen. Lokal mit Flutter 3.24.5 im Container verifiziert, nicht nur behauptet.
**Geraete-Test steht aus.**

## M50 — Ribbon abgespeckt + totes Chrome entfernt

Zwei VERSCHIEDENE Operationen, die man nicht verwechseln darf:

**(A) VERSCHOBEN, nicht geloescht.** Selten gebrauchte Befehle verlieren ihre
dauerhafte Ribbon-Breite und sitzen jetzt hinter dem ▼ neben dem PANEL-TITEL.
Sie sind alle weiter erreichbar — wer sie beim Aufraeumen wirklich loescht,
macht das Gegenteil des Gewuenschten.
- **Constrain ▾**: Smooth (G2), Constraint Settings, Show Constraints.
  Das Gitter faellt auf 11 Zellen und von 5 auf **4 Spalten** — schmaler UND
  gleich hoch (3 Reihen).
- **Insert ▾** (= Insert + Format + Manage in EINEM Panel): Points, Centerline,
  Center Point, Driven Dimension, Show Format. Auf der Flaeche bleiben nur
  Image, ACAD, Construction, Parameters (2x2, zwei `_SmallRow`-Spalten).
- **Modify ▾**: Extend, Move, Copy, Rotate, Scale, Stretch. Auf der Flaeche
  bleiben Trim, Split, Offset (eine Spalte).

**(B) WIRKLICH ENTFERNT** (totes Chrome, tat nie etwas):
- Model-Browser: `+`, `🔍`, `☰`
- Tab-Leiste: `☰` und das Wort „Home" (das Haus reicht, Icon jetzt 15 px)
- Der immer sichtbare Schloss-TOGGLE in der Layer-Zeile. Neu `_LockedMark`:
  ein Schloss erscheint **nur bei GESPERRTEN** Layern. Sperren/Entsperren
  laeuft ueber das Rechtsklick-/Long-Press-Menue (dort wo auch Rename/Delete
  sitzen), es ist also nichts unerreichbar geworden.
- Die Statuszeile unten LINKS („N degrees of freedom"). Unten RECHTS steht
  dasselbe als „N dimensions needed" / „Fully Constrained" — als Anweisung
  statt als Zahl. Eine Statuszeile reicht.
- Die ▼ an „Start New Layer", an „Create" und an „Finish" (zeigten auf nichts).

**Technik.** Neu `OverItem` / `_OverMenu` / `_OverRow` neben dem vorhandenen
`FlyItem`/`_FlyMenu`: die Overflow-Eintraege tragen einen ROHEN SVG-String
(die Icon-Maps unterscheiden sich je Panel: CN/IN/MD) und einen freien
Callback, damit auch Toggles und Settings hineinpassen — nicht nur Tools.
`_panel()` bekommt `overId` + `over`; Titel plus ▼ werden zusammen zum
Hit-Target. Das Menue oeffnet nach OBEN (`bottom:`), weil die Panel-Titel
unten sitzen. **Dieselbe Endlich-Breiten-Disziplin wie `_FlyMenu`** —
`ConstrainedBox` + `IntrinsicWidth`; siehe die lange Notiz dort: ein
`Positioned`-Kind eines `Stack` bekommt UNBESCHRAENKTE Constraints, und eine
unendliche Breite laesst Impeller im Release-Build die Fuellung weglassen.
`_SmallRow` bekommt optional `iconWidget` (Parameters nutzt Inventors
kursives „fx" — Schrift, keine Grafik). `_FormatGrid` und die toten
`cornerDd`/`cornerDdBelow`-Parameter sind raus.

**FALLE (wichtig fuer die naechste Session):** Der Ribbon laesst sich auf dem
Host NICHT in einem Widget-Test pumpen. `pumpWidget(MaterialApp(Scaffold(
Ribbon(app))))` kehrt nie zurueck — kein Timeout, keine Exception, einfach
haengen (mit einem Minimal-Probe isoliert). Verdacht: `flutter_svg` beim
Rastern der ~40 Icons unter `flutter_tester`. Deshalb pumpt KEIN einziger
Test im Repo den Ribbon — alle Widget-Tests nehmen HomeView, Viewport oder
Dialoge. Eine vorbereitete `m50_ribbon_slimming_test.dart` (17 Tests) musste
darum wieder raus; sie blockierte die ganze Suite. **M50 ist ausschliesslich
GERAETE-getestet, nicht host-getestet.** Wer den Haenger loest, sollte sie
neu schreiben — die Testluecke ist real.

**Status:** `flutter test` **269 gruen** (unveraendert, M50 fuegt keine Tests
hinzu), `flutter analyze` ohne neue Issues. Die drei `prefer_const_*`-Lints,
die CI in `m49_split_test.dart` fand (CI faehrt einen strengeren Lint-Satz als
lokal), sind gefixt. **Geraete-Test von M49 UND M50 steht aus.**

## M51 — Geraete-Test-Fixes: der Ribbon baute UEBERHAUPT nicht

Der erste Geraete-Build von M50 (`e5bb0a9`) war kaputt. Symptome laut Nutzer:
„die Pfeile sind nicht da" und „Pan/Zoom ist ploetzlich total buggy". Das Log
sagt genau warum: **25 ERROR-Zeilen, alle `Stack Overflow` in
`ComponentElement.performRebuild` / `Element.inflateWidget`** — in JEDEM Frame.

**Wurzelursache (mein Fehler in M50, und eine Falle, die jeder trifft):**
```dart
Widget title = Row(...);
title = Builder(builder: (_) => GestureDetector(child: title)); // FALSCH
```
Eine Dart-Closure faengt die **VARIABLE**, nicht deren Wert. Wenn der Builder
laeuft, zeigt `title` laengst auf den Builder SELBST → jeder Build inflatet
`Builder -> GestureDetector -> Builder -> ...` bis der Stack platzt. Deshalb:
- die drei Panel-Titel (Constrain/Insert/Modify) rendern nie → **keine ▼**,
- der Frame-Pipeline verbringt jeden Frame in der Exception-Behandlung →
  **Pan/Zoom fuehlt sich kaputt an**.

Fix: das innere Widget in ein EIGENES `final` (`titleRow`), Ternaerausdruck
statt Reassignment. **Nie eine Widget-Variable auf etwas umschreiben, das sich
selbst einfaengt.**

**LEHRE, die eine ganze Testluecke aufloest:** in der M50-Session „haengte"
`pumpWidget(Ribbon(...))` im Host-Test — ohne Timeout, ohne Exception. Ich habe
das `flutter_svg` zugeschrieben und die Suite geloescht. **Das war falsch.** Es
war exakt DIESE Rekursion: der Test baute einen unendlich tiefen Baum. Nach dem
Fix pumpt der Ribbon in ~1 s. `m50_ribbon_slimming_test.dart` ist wieder da
(14 Tests) — und ihr ERSTER Test ist genau dieser Regressionsschutz: den Ribbon
ueberhaupt zu pumpen faengt den Bug. Wer wieder einen „unerklaerlichen" Haenger
im Widget-Test sieht: **zuerst nach selbstreferenzierenden Closures suchen**,
nicht nach der Rendering-Library.

**Weitere Fixes derselben Runde:**
- **Overflow-Menue oeffnet nach UNTEN** (`top:` statt `bottom:`). Nach oben
  kletterte es ueber den Ribbon bis in die iOS-Statusleiste; nach unten haengt
  es wie jedes andere Flyout ueber der Zeichenflaeche. Ein Test pinnt die
  Richtung (Menue-Eintrag liegt tiefer als der Titel).
- **Statusleisten-Streifen faerbt sich mit.** Der von `SafeArea` reservierte
  Bereich (Uhr/Batterie) wird von dem gemalt, was HINTER der SafeArea liegt —
  vorher die Scaffold-Viewport-Farbe, waehrend direkt darunter der Ribbon in
  `T.panel` sitzt: eine sichtbare Naht quer ueber den Bildschirm. Jetzt
  faerbt eine `ColoredBox` um die SafeArea mit: `T.panel` in der Skizze,
  `T.galleryBg` auf Home.
- **`_OverRow` kann nicht mehr ueberlaufen** (`Flexible` + Ellipsis,
  maxWidth 320). Der Widget-Test zeigte „RenderFlex overflowed by 14 pixels".
- **Pointer-Zaehlung im Viewport wieder symmetrisch.** Der M49-Rechtsklick-
  Zweig kehrte VOR `_pointers++` zurueck, waehrend `onPointerUp` immer
  dekrementiert — die Zaehlung driftet, und der naechste echte Finger sieht
  aus wie der erste (Pan/Zoom statt Zeichnen). Jetzt wird zuerst gezaehlt.

**Status:** `flutter test` **283 gruen** (269 + 14 wiederhergestellte),
`flutter analyze` ohne neue Issues. Geraete-Test von M49/M50/M51 steht aus.

## Gesamtstand & Arbeitsweise (Stand M40, für die nächste Session)

**Was die App kann:** Skizzieren (Linie, Kreis, Bogen, Rechtecke, Polygon,
Slot, Ellipse mit gebundenen Achsen-Mittellinien, CV-/Fit-Splines),
Layer-System mit Editier-Scope/Lock/Auge, Snapping (Vertex, Mittelpunkt,
Zentrum, Quadranten, projizierter CP), Grips mit Inventor-Semantik,
Constraints (coincident, collinear, concentric, fix, parallel,
perpendicular, h/v, tangent, smooth, symmetric, equal, midpoint, pattern) mit
Auto-Inferenz, Inventors komplette Bemaßungs-Pick-Matrix inkl. pline/ang3
und Inline-Werteingabe, getriebene (Referenz-)Bemaßungen, Mittellinien-Stil,
DXF-Speicherung mit Sidecars (Constraints, Spline-Tags, Styles),
Pattern-Panel (Rechteckige/Runde Anordnung, Spiegeln inkl. Self Symmetric,
assoziativ über den Solver), Slots/Tangenten-Werkzeuge mit Inventor-Auto-
Constraints, Fillet/Chamfer komplett (Linie/Bogen/Kreis, 3 Chamfer-Modi,
Radius- bzw. x/y-Setback-Bemaßung), constraint-erhaltendes Trim/Split,
Diagnose-Log in der Files-App, **Undo/Redo pro Skizze (Ctrl+Z / Ctrl+Shift+Z)**, **Construction-Linetype (Format-Toggle, Slot-Achse automatisch)**, **M41: Inventors Parameter-/Ausdrucks-System (d0/d1-Namen, Formeln mit Referenzen im Bemaßungs-Edit-Feld, fx:-Anzeige, Klick-Referenz)**. **M37: Slot/Fillet/Chamfer sind jetzt
solverstabil (redundanzfrei, atomar, kein divergiertes Rendern).**

**Solver-Architektur (unverändert wichtig, M37-Ergänzungen):** libslvs nativ
zuerst, jede Lösung wird gegen die Dart-Residuen VERIFIZIERT; bail/fail →
Dart-LM (iterations=80). **`solveConstraints` liefert seit M37 `bool` (erfüllt
+ finite + nicht degeneriert) — NIE einen unerfüllten Solve rendern oder
committen; alle Commit-Pfade sind atomar mit Rollback.** Zwei eiserne Regeln:
(1) keine Konstruktion darf ein rangdefizites Set erzeugen (mit `debugRank`
prüfen, Redundanz muss 0 sein); (2) neue Constraint-/Bemaßungsarten brauchen
IMMER: Residual + residualCount (Dart), Shim-Packung ODER expliziten Bail,
measureDim (bei Dims), Painter, Tests. Shim-Codes: slvs_shim.h; Versions-Gate
über `slvs_shim_version()` (**aktuell 4** — v3 = endpunktverankerte Tangenten
mit Naht-Flag in `val`, v4 = `SH_POINT_ON_CIRCLE`) für neue Codes. Tangenten müssen einen gemeinsamen
Endpunkt haben und dürfen keinen Kreis enthalten, sonst Bail auf LM.

**Test-/CI-Workflow:** `flutter test` in frontend/ (**214 Tests**) + Shim-Host-
Tests via CMake (SLVS_SMOKE=ON, „ALL SHIM TESTS PASS", **13 Szenarien**).
Beide sind CI-Gates. Auf dem Host läuft die Dart-Fallback-Engine + LM-Pfad —
genau die Pfade, die die Tests absichern sollen; das native Verhalten sichert
zusätzlich das Shim-Host-Gate. IPA: Workflow „Core + C-API Build (iOS)",
Artefakt `ipadprocad-unsigned-ipa`. Lokal reproduzierbar mit
heruntergeladenem Flutter-SDK (stable) + CMake — beide Gates grün.

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


**Bekannte Grenzen / nächste Kandidaten:** (M37-Audit-Punkte mit Priorität
stehen ausführlich im README, Abschnitt PRODUKTIONS-AUDIT — hier nur die
fachlichen Grenzen)
- Trim/Extend kennt getaggte Polylines (Splines/Ellipsen) nicht.
- Keine Tangenten-Handles an Fit-Spline-Punkten (Inventors Pfeil-Griffe).
- Kreis-Abstände immer Zentrum-basiert (keine Tangenten-Variante beim
  Platzieren), keine Bogenlängen-Bemaßung, Winkel ohne Quadranten-Wahl.
- DXF exportiert bei Splines/Ellipsen das Definitionspolygon + Sidecar
  (C-API hat kein Spline-/Ellipsen-Entity; REllipseEntity existiert im
  Core — natives qcad_add_ellipse wäre der saubere nächste Schritt).
- Alte 96-Punkt-Ellipsen (vor M23) bleiben gewöhnliche Polylines.
- Pattern v1: kein Boundary-Fill, kein Suppress, kein Edit Pattern (die
  Transformation ist beim Commit eingefroren; Richtung folgt ihrer Linie
  nicht nach), kein Muster entlang Pfad.
- Polygone (eine Polyline) haben keine Regelmäßigkeits-Constraints (keine
  Kanten-Entities für equal — bräuchte einen Segment-Längen-Constraint).
- Fillet trimmt VOLLKREISE nicht (Kreis→Bogen wäre ein Typwechsel); die
  Tangenten-Constraint sitzt trotzdem. Fillet gegen getaggte Polylines
  (Splines/Ellipsen) nicht unterstützt.
- eqCurve erzeugt weiterhin gesampelte Polylines (bewusst: echte Kurve). Bogen-Slots haben noch keine automatische Construction-Achse (jede volle Anbindung eines Construction-Bogens ist um 1 Gleichung redundant — braucht einen 1-Gleichungs-Winkelbind oder eine Sonderbehandlung im Gate).

## M54 — OCCT 3D-Kernel (OpenCASCADE) vendored: C-Shim, Geometrie-Smoke, isolierte CI, iOS-Link

**Ziel & Scope.** Fundament für Inventor-artiges 3D (Skizze extrudieren →
Solid, Boolesche Ops, STEP-Austausch): OpenCASCADE als DRITTER nativer
Kernel neben QCAD (2D/DXF) und libslvs (Constraints). BEWUSST ohne jede
Dart-/Flutter-Änderung — kein `occt_engine.dart`, keine Widgets, kein
`app_state`-Bezug. Ziellinie dieser Session war: IPA baut und exportiert
die Shim-Symbole. Genau das ist erreicht.

**Was liegt wo:**
```
backend/occt/
  upstream/              OCCT als SUBMODULE, gepinnt auf Tag V7_9_3
                         (Commit a016080b; 8.0.0 bewusst NICHT — zu frisch,
                         CMake/Source-Tree umgebaut; siehe VENDOR.md)
  shim/occt_capi.{h,cpp} Flache C-ABI, EXAKT 14 Funktionen: version/
                         shim_version/last_error, make_box, make_cylinder,
                         extrude_polygon, fuse, shape_counts, shape_valid,
                         shape_volume, bbox, export_step, import_step,
                         free_shape. Jeder Entry-Point fängt ALLE
                         OCCT-Exceptions (nichts entkommt später ins FFI).
                         Marker-String: "iPadProCAD OCCT shim" (strings-Check).
  tests/smoke_occt.c     Standalone-C-Smoke mit harten Zahlen (s.u.)
  CMakeLists.txt         Shim-Projekt; konsumiert einen OCCT-Install-Tree
                         via find_package(OpenCASCADE CONFIG)
  VENDOR.md              Pin-Begründung, Lizenz, die EINE Flag-Liste, Traps
.github/workflows/occt-build.yml   isolierter Workflow (paths: backend/occt/**,
                         .gitmodules, er selbst): ubuntu-Host-Smoke +
                         macos-26 iOS-arm64-Static + nm-Symbolcheck
```

**Empirisch verifiziert (Run 29810990247/…286, Marker aus den Logs
gelesen, nicht Häkchen):**
- Host: `OCCT SMOKE: PASS` — Box 6/12/8 Vol 6000.000000; nicht-konvexes
  L-Profil extrudiert 8/18/12 Vol 3000; Zylinder 3 Faces Vol pi*360;
  **Fuse Box∪Zylinder Vol 8785.398163 == analytisch exakt**; STEP-Roundtrip
  Topologie 8/15/10 → 8/15/10, Volumen identisch; Import fehlender Datei
  → NULL ohne Crash. `OCCT HOST + SHIM: PASS`.
- iOS: kompletter OCCT-Cross-Build (5405 Targets) sauber,
  `defined _occt_* symbols in shim archive: 14`, `OCCT IOS STATIC: PASS`.
- m5-IPA: `OCCT MARKER CHECK: PASS` + **`OCCT LINK CHECK: PASS (14 _occt_*
  symbols exported in Runner)`** — via `-force_load libocct_capi.a`, alle
  47 OCCT-Archive auf der Linkzeile (ld64 zieht nur referenzierte Member),
  `_occt_*` in `qcad_symbols.exp`. M5/SLVS/M6-QIOS-Checks weiter PASS,
  M3 PASS, slvs-build per Dispatch grün (strukturell unberührt — paths).
- Diff-Bilanz: NUR neue Dateien + `.gitmodules` (neu, Repo-Wurzel) +
  m1-core-build.yml (m5-Job: 3 neue Steps; nur 2 geänderte Zeilen:
  exp-printf und OTHER_LDFLAGS). 0 Dart-/frontend-Dateien, 0 qcad/slvs.

**OCCT-Build-Konfiguration (die EINE Wahrheit steht in VENDOR.md):**
4 Module ON (FoundationClasses, ModelingData, ModelingAlgorithms,
DataExchange), Rest OFF, alle `USE_*` OFF (`USE_FREETYPE=OFF` ist der
Schlüssel) → NULL Fremdabhängigkeiten. OCCTs CMake zieht benötigte
Toolkits abgeschalteter Module automatisch als Deps
(`EXCTRACT_TOOLKIT_FULL_DEPS`): TKDESTEP→TKXCAF→TKV3d/TKService/TKCAF/…
werden mitgebaut, obwohl Visualization/ApplicationFramework OFF sind.

**Cache-Mechanik (wichtig für Laufzeiten):** iOS-Install-Tree liegt unter
`actions/cache` Key **`occt-ios-arm64-V7_9_3-r1`** — GETEILT zwischen
occt-build.yml und dem m5-Job (identischer Key + Pfad
`backend/occt/install-ios`). Der Key ist gespeichert (occt-ios-Job hat
"Cache saved" geloggt) → künftige m5-Läufe stellen in Sekunden wieder her
statt ~30 min zu bauen. Host analog `occt-host-V7_9_3-r1` (gespeichert).
**Bei Flag-Änderungen den Suffix -r1 in BEIDEN Workflows bumpen** (Cache
ist per Key unveränderlich). Shim wird IMMER frisch gebaut (schnell).

**Lektionen dieser Session (teuer bezahlt, nicht wiederholen):**
1. **iOS-find_package-Falle:** `CMAKE_SYSTEM_NAME=iOS` ⇒ CMake rootet
   JEDES find_package in die iPhoneOS-SDK-Sysroot um
   (`Darwin.cmake: CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY`) —
   `CMAKE_PREFIX_PATH` außerhalb ist unsichtbar, Fehlermeldung sieht aus
   wie "Install kaputt", obwohl der Install perfekt war. Fix (steckt in
   beiden Workflows): `-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH` — der
   Platform-Default ist NOT-DEFINED-geguarded, das Cache-Entry gewinnt.
   OCCT selbst und libslvs rufen kein find_package → nur der Shim traf es.
2. **actions/cache speichert NICHT bei fehlgeschlagenem Job** — zwei
   30-min-OCCT-Builds gingen deshalb verloren, bevor der find_package-Fix
   grün wurde. Wer das je entkoppeln will: actions/cache/restore +
   /save mit `if: always()` direkt nach dem Build-Step.
3. **`shallow = true` in .gitmodules ist eine Falle:** es macht auch den
   FALLBACK `git submodule update --init` shallow (Default-Branch-Spitze,
   die den gepinnten Release-Commit NICHT enthält). Entfernt. Der primäre
   Weg holt explizit `--depth 1` den exakten SHA (GitHub erlaubt
   SHA-Wants; von frischem Clone aus verifiziert).
4. Submodule-Pin ohne Riesen-Clone: `git ls-remote <url> 'TAG^{}'` liefert
   den gepeelten Commit, dann `git update-index --add --cacheinfo
   160000,<sha>,backend/occt/upstream` + .gitmodules von Hand.
5. `ls | head` gehört zur SIGPIPE-Musterklasse (M3/M5) — vermieden.

**Nächste Session (NICHT in dieser erledigt, bewusst):**
- Dart-FFI-Binding `frontend/lib/ffi/occt_engine.dart` gegen die 14
  Funktionen (DynamicLibrary.process(), Muster von qcad/slvs kopieren);
  DART-SMOKE beim App-Start ("backend=occt-ffi …" analog qcad).
- Danach UI: Extrude-Workflow aus der fertigen Skizze (EOP/M53 ist die
  Vorarbeit), 3D-Viewport-Frage klären (OCCT-Visualization ist NICHT
  gebaut — Rendering muss aus Tessellation (TKMesh ist gebaut) + eigenem
  Renderer kommen oder Visualization-Modul nachziehen ⇒ Cache-Key-Bump).
- Shim wachsen lassen, wenn die UI es braucht (Cut/Common, Fillet 3D,
  Transformationen, Tessellation-Export) — Muster: Funktion in
  occt_capi.h/.cpp + Assert im smoke_occt.c + nm-Zahl 14 in BEIDEN
  Workflows und m1-core-build.yml anpassen (drei `-ge 14`-Stellen!).
- IPA-Größe wächst durch OCCT/STEP spürbar (Schema-Code); wenn's stört:
  Linkliste von 47 Archiven auf die tatsächlich gezogenen reduzieren.
