# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status

**M1: Headless-Basis & CI-Setup — in Arbeit, ein konkreter Blocker offen**

- [x] Headless-relevante QCAD-Core-Quellen vendored (`backend/qcad-core/`, siehe `VENDOR.md` für Quelle/Commit/Lizenz)
- [x] Root-`CMakeLists.txt` für headless Core-Build (nur `core`, `entity`, `operations`, `io`, `snap`, `spatialindex`, `3rdparty/dxflib`)
- [x] GitHub Action `.github/workflows/m1-core-build.yml`: kompiliert den Core auf macOS-Runner für iOS-Target (Qt6 + Ninja)
- [x] Qt6-Cross-Compile-Toolchain-Wiring funktioniert (separate `qt-host`/`qt-ios`-Installationsverzeichnisse, `QT_HOST_PATH`, `CMAKE_TOOLCHAIN_FILE`)
- [x] `CMAKE_OSX_DEPLOYMENT_TARGET=13.0` gesetzt (erforderlich für `std::filesystem` in Qt6-Headern)
- [x] Qt-Komponenten auf iOS-verfügbares Set getrimmt (kein `Widgets`/`PrintSupport`/`OpenGL`/`Sql`/`Qml` in `find_package`)
- [x] `RLocalPeer`/`RSingleApplication` (Single-Instance-GUI-Prozess-Helfer) aus `core`-Target entfernt
- [ ] **Offener Blocker:** `src/core/RMetaTypes.h` inkludiert direkt `QApplication`, `QWidget`, `QDockWidget`, `QListWidget`, `QTreeWidget`, `QTabBar` u.a. — das ist keine Nebensache, sondern zentrale Meta-Type-Registrierung, die im Upstream-Code quer durch `core` genutzt wird. Für einen echten headless Build muss diese Datei chirurgisch entkoppelt werden (z.B. Widget-bezogene `qRegisterMetaType`-Aufrufe hinter ein `#ifdef QCAD_HEADLESS`-Guard setzen), nicht per Ausschluss der ganzen Datei, da andere `core`-Dateien vermutlich Nicht-Widget-Typen daraus brauchen. Das ist die nächste konkrete Aufgabe.
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
