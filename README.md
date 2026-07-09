# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status

**M1 — Headless-Core-Build & iOS-CI: erreicht (grün).**

Der vendored QCAD-Core kompiliert und linkt sauber, sowohl lokal unter Linux
(Qt 6, `g++`) als auch im GitHub-Actions-CI als iOS-Cross-Compile (macOS-Runner,
Xcode, Qt 6.7.3, `arm64`). Der CI-Lauf erzeugt fehlerfrei die statischen
Bibliotheken `libqcadcore.a`, `libqcadentity.a`, `libqcadoperations.a`,
`libqcaddxf.a` und `libdxflib.a`.

- [x] Headless-relevante QCAD-Core-Quellen vendored (`backend/qcad-core/`, siehe `VENDOR.md`)
- [x] Root-`CMakeLists.txt` baut den headless Core (Module: `core`, `entity`, `operations`, `io/dxf`, `3rdparty/dxflib`)
- [x] GitHub Action `.github/workflows/m1-core-build.yml`: Cross-Compile auf macOS-Runner für iOS (Qt6 + Ninja), Build mit `-k 0` (keep-going), damit ein Lauf alle Fehler zeigt
- [x] Qt6-Cross-Compile-Toolchain (separate `qt-host`/`qt-ios`-Installationen, `QT_HOST_PATH`, `CMAKE_TOOLCHAIN_FILE`)
- [x] **Statische Bibliotheken** (kein Shared): iOS lädt keine freistehenden `.dylib`; die App linkt die `.a` später per FFI ein. Statische Archive haben zudem keinen Link-Schritt, was die iOS-typischen `_main`-/Plattform-Plugin-Linkfehler vermeidet.
- [x] iOS-Zielkontext = **Device** (`iphoneos`, `arm64`). `install-qt-action` (target `ios`) liefert Device-Qt-Bibliotheken; ein Simulator-Ziel würde am Plattform-Mismatch scheitern. Für reine Cross-Compile-Validierung ist der Device-Build passend und braucht keine Signatur.
- [x] `CMAKE_OSX_DEPLOYMENT_TARGET=13.0` (behebt `std::filesystem`-Fehler in Qt6-Headern); der vorher in `CMakeInclude.txt` erzwungene Wert `12.7` überschreibt den Kommandozeilenwert nicht mehr
- [x] `CMAKE_POSITION_INDEPENDENT_CODE=ON` (statisches `dxflib` in andere Ziele linkbar)
- [x] QtWidgets-Kopplung im Core headless gekapselt (`QCAD_HEADLESS`): `RAction`, `RGuiAction`, `RMainWindow`, `RPropertyEditor` u. a.
- [x] iOS-Portabilität: `QProcess` (auf iOS nicht vorhanden) in `RSPlatform`/`RMetaTypes` hinter `QT_CONFIG(process)` gekapselt; Dark-Mode-Erkennung (`isMacDarkMode`) auf `Q_OS_MACOS` eingegrenzt (statt `Q_OS_MAC`, das iOS einschließt)
- [x] `RMath`: Ausdrucksauswertung via `QJSEngine` (Qt6 `Qml`) korrekt angebunden

### Bewusst zurückgestellte Module (reversibel, dokumentiert)

Diese drei Abhängigkeiten sind für ein sauberes, schlankes M1 deaktiviert. Jede
ist isoliert und mit wenigen Handgriffen reaktivierbar:

1. **opennurbs (NURBS-Splines)** — Compile-Flag `R_NO_OPENNURBS`. `RSpline` nutzt
   den opennurbs-freien Fallback; Spline-Auswertung (Punkt/Winkel) ist inaktiv,
   bis ein opennurbs-gestützter `RSplineProxy` registriert wird. opennurbs bringt
   ~430 Dateien inkl. eigenem zlib/freetype mit und würde jeden iOS-CI-Lauf
   aufblähen. Reaktivierung: `src/3rdparty/opennurbs` vendorn und das Flag entfernen
   (betrifft nur `RSpline`). **Relevanz:** Splines gehören zum DXF-Ziel — vor
   Produktivnutzung zu vervollständigen.
2. **spatialindex „Navel" (libspatialindex)** — nicht vendorte R-Tree-Bibliothek.
   Der Core nutzt stattdessen das mitgelieferte, eigenständige `RSpatialIndexSimple`
   (voll funktionsfähig, für sehr große Zeichnungen weniger performant).
   Reaktivierung: `src/3rdparty/spatialindexnavel` vendorn + `add_subdirectory(src/spatialindex)`.
3. **snap + grid (Interaktions-Ebene)** — Snapping/Raster gehören zur Touch-/
   Pencil-Bedienung, nicht zum headless Core; `snap` ist ein Blatt-Ziel und hängt
   am nicht vendorten `grid`. Reaktivierung im Touch-Meilenstein: `src/grid` + `src/snap`
   vendorn + `add_subdirectory(src/snap)`.

### CI-Debugging-Hinweis
Der Entwicklungscontainer erreicht `blob.core.windows.net` (GitHub-Actions-Log-
Speicher) nicht. Der Workflow committet deshalb bei jedem Lauf die Konfigurations-/
Build-Logs in den Branch `ci-debug-logs` (Step „Commit debug logs"). Von dort sind
sie über `raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/…`
lesbar.

## Status M2

**M2 — C-ABI-Wrapper & iOS-Bundle: erreicht (Wrapper validiert); Dart-FFI noch offen.**

Ein schlanker C-Wrapper (`extern "C"`) kapselt den Core hinter einer stabilen,
FFI-tauglichen Schnittstelle (opaque Handles, keine C++-Typen an der Grenze).
Lokal (Linux/Qt6) läuft ein C-Smoke-Test grün; im iOS-CI wird der Wrapper für
`arm64`/`iphoneos` mitgebaut, auf Architektur verifiziert und zu einer nutzbaren
Einheit gebündelt (kombinierte `.a` + XCFramework).

- [x] Modul `backend/qcad-core/src/capi/` — `qcad_capi.h` (reines C) + `qcad_capi.cpp` (einziger C++/Qt-Übersetzungseinheit); CMake-Ziel `qcadcapi` (STATIC), ins Root-Build eingehängt
- [x] ABI-Oberfläche: Dokument anlegen/freigeben; Linie/Kreis/Bogen/Polylinie hinzufügen; Entity-Anzahl; Bounding-Box; DXF laden/speichern (Pfad); Versionstext (Winkel in Radiant, `double`-Koordinaten, `1`=OK/`0`=Fehler)
- [x] Property-Typen-System selbst registriert: QCADs Bootstrap liegt im ausgeklammerten GUI/Script-Layer, daher ruft `qcad_init()` die `init()`-Kette aller Entity-/Objekttypen selbst auf (privates `RColor`/`RLineweight::init()` ausgelassen — werden intern registriert)
- [x] Ownership korrekt: `RStorage`/`RSpatialIndex` erben von `RRequireHeap` (`doDelete()` = `delete this`) und werden vom `RDocument`-Destruktor freigegeben → heap-allozieren und nur das `RDocument` löschen (behebt einen Doppel-Free beim Teardown)
- [x] `RSettings` über `QCoreApplication`-Organisationsname initialisiert (keine „RSettings not initialized"-Warnungen mehr)
- [x] Lokaler C-Smoke-Test (`src/capi/tests/smoke.c`, Ziel `qcad_capi_smoke`, nur Host): 4 Entities, korrekte Bounding-Box, DXF-Roundtrip erhält die Entity-Anzahl → **PASS**
- [x] CI baut `qcadcapi` für iOS-Device mit (`-k 0`), prüft alle `.a` auf `arm64`, bündelt sie via `libtool` zu `libipadprocad.a` und packt ein `ipadprocad.xcframework` (`ios-arm64` + Header); Upload als Artefakt `ipadprocad-ios-capi`
- [x] CI-Fix (wichtige Lektion): iOS-Configure setzt jetzt `-DCMAKE_BUILD_TYPE=Release` (sonst landen die Libs in `debug/` statt `release/`), und `set -o pipefail` in Verify/Bundle/XCFramework verhindert, dass ein per `tee` maskierter Fehler fälschlich „grün" meldet
- [ ] **Dart-FFI noch offen:** Bindings (`backend/qcad-core/bindings/dart/`) sind geschrieben, aber mangels Dart-SDK im Backend-Build noch nicht ausgeführt/CI-validiert; erste reale Ausführung in M3 (iOS-Device-Test) oder via Desktop-`.so`

### Nächster Schritt: M3
Headless-Logiktests auf iOS: die C-Smoke-Logik als iOS-Device-Test (XCTest) gegen
das erzeugte `ipadprocad.xcframework` ausführen und dort die Dart-FFI-Bindings
erstmals real gegenprüfen. Details/Fallstricke: `HANDOFF.md`.

## Architektur

```
backend/qcad-core/     Vendorter, headless-tauglicher QCAD-Core (C++, GPLv3)
  src/core/            Dokumentmodell, Geometrie/Mathematik, RSpatialIndexSimple
  src/entity/          Entity-Typen (Linie, Kreis, Bogen, Polylinie, Spline, …)
  src/operations/      Modifikations-/Transformationsoperationen
  src/io/dxf/          DXF-Import/-Export (auf dxflib)
  src/3rdparty/dxflib/ DXF-Low-Level-Bibliothek (statisch)
  src/capi/            C-ABI-Wrapper (extern "C") für FFI — Ziel libqcadcapi.a
  bindings/dart/       Dart-FFI-Bindings + Beispiel (noch nicht CI-validiert)
.github/workflows/     CI: iOS-Cross-Compile + C-API-Bundle (macOS-Runner)
```

`gui`, `run` sowie der JS-Actionlayer (`scripts/`) aus dem QCAD-Upstream sind
bewusst nicht enthalten — sie werden erst in Phase 2 (M4/M5) mit der Flutter-GUI
relevant.

## Lizenz

Der vendorte QCAD-Core steht unter GPLv3 (`backend/qcad-core/LICENSE.txt`,
`gpl-3.0.txt`, `gpl-3.0-exceptions.txt`), `dxflib` unter GPLv2+. Die
Lizenzkompatibilität mit der finalen App-Distribution ist vor Produktiv-Release
zu klären.
