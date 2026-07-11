# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status (Stand M5)

| Meilenstein | Stand |
|---|---|
| **M1** Headless-Core-Build + iOS-CI | ✅ erledigt (statische Libs, arm64/iphoneos) |
| **M2** C-ABI-Wrapper (`qcad_capi.h`) | ✅ erledigt & validiert; in M5 um Geometrie-Abfrage erweitert |
| **M3** Headless-Logiktest im iOS-Simulator | ✅ erledigt (`SMOKE: PASS`, inkl. Geometrie-Query-Checks) |
| **M4** UI-Design als interaktiver HTML-Mock | ✅ abgeschlossen (`create-panel.html` = verbindliche 1:1-Spec) |
| **M5** Flutter-App (1:1-Port) + echtes Zeichnen + IPA | ✅ Grundausbau erledigt, CI-validiert (Run 29145382350) |

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
