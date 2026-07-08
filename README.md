# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status

**M1: Headless-Basis & CI-Setup — in Arbeit, letzte bekannte Blocker behoben, Build läuft in CI**

- [x] Headless-relevante QCAD-Core-Quellen vendored (`backend/qcad-core/`, siehe `VENDOR.md` für Quelle/Commit/Lizenz)
- [x] Root-`CMakeLists.txt` für headless Core-Build (nur `core`, `entity`, `operations`, `io`, `snap`, `spatialindex`, `3rdparty/dxflib`)
- [x] GitHub Action `.github/workflows/m1-core-build.yml`: kompiliert den Core auf macOS-Runner für iOS-Target (Qt6 + Ninja)
- [x] Qt6-Cross-Compile-Toolchain-Wiring funktioniert (separate `qt-host`/`qt-ios`-Installationsverzeichnisse, `QT_HOST_PATH`, `CMAKE_TOOLCHAIN_FILE`)
- [x] `CMAKE_OSX_DEPLOYMENT_TARGET=13.0` gesetzt (behebt `std::filesystem`-Fehler in Qt6-Headern)
- [x] Qt-Komponenten auf iOS-verfügbares Set getrimmt (kein `Widgets`/`PrintSupport`/`OpenGL`/`Sql`/`Qml` in `find_package`)
- [x] `RMetaTypes.h` entkoppelt: alle Widget-/PrintSupport-Includes (`QApplication`, `QWidget`, `QDockWidget`, `QMenu`, `QPrinter`, ...) hinter `#ifndef QCAD_HEADLESS` gesetzt, statt die ganze Datei auszuschließen — Nicht-Widget-Metatypes bleiben nutzbar
- [x] `QCAD_HEADLESS`-Compile-Definition eingeführt (`target_compile_definitions(qcadcore PUBLIC QCAD_HEADLESS)`), um Widget-gekoppelten Code in `core` gezielt zu guarden statt ganze Dateien auszuschließen
- [x] `RGuiAction` (Menü-/Toolbar-Verdrahtung), `RSettings` (Stylesheet-/Drucker-/Widget-Farb-Helper), `RPropertyEditor::makeReadOnly`, `RMainWindow` (`QApplication`-Include) chirurgisch entkoppelt: Widget-Funktionalität bleibt für Phase 2 im Code, ist aber unter `QCAD_HEADLESS` inaktiv/stubbed
- [x] `RWidget` (echte `QWidget`-Subklasse) und `RSingleApplication` (echte `QApplication`-Subklasse) aus dem `qcadcore`-Compile-Target entfernt (Header bleiben im Baum für Phase 2, werden von AUTOMOC im Headless-Build nicht mehr verarbeitet)
- [x] `RAction.cpp`: direktes `<QWidget>`-Include durch Forward-Declaration ersetzt (nur Zeiger-Nutzung nötig)
- [ ] Aktueller CI-Lauf (Commit siehe `git log`) validiert diese Änderungen — Ergebnis beim nächsten Sync in diesem Dokument nachtragen
- [ ] Compiler-Status "100% grün": noch nicht erreicht

### CI-Debugging-Hinweis
Der Entwicklungscontainer kann `blob.core.windows.net` (GitHub-Actions-Log-Speicher) nicht erreichen. Der Workflow committet deshalb bei jedem Lauf Konfigurations-/Build-Logs nach `ci-debug-logs` (siehe `.github/workflows/m1-core-build.yml`, Step "Commit debug logs") — das ist der Weg, wie Logs zwischen CI-Lauf und Chat-Session ausgetauscht werden, bis M1 grün ist.

## Architektur

```
backend/qcad-core/     Vendorter, headless-tauglicher QCAD-Core (C++, GPLv3)
.github/workflows/     CI: Build-Validierung auf macOS/iOS-Simulator-Toolchain
```

`gui`, `run` sowie der JS-Actionlayer (`scripts/`) aus dem QCAD-Upstream sind bewusst nicht enthalten — diese werden erst in Phase 2 (M4/M5) relevant, wenn die Flutter-GUI entsteht.

## Lizenz

Der vendorte QCAD-Core steht unter GPLv3 (siehe `backend/qcad-core/LICENSE.txt`, `gpl-3.0.txt`, `gpl-3.0-exceptions.txt`). `dxflib` steht unter GPLv2+. Lizenzkompatibilität mit der finalen App-Distribution ist vor Produktiv-Release zu klären.
