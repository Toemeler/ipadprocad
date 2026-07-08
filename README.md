# iPadProCAD

Ein moderner, radikal benutzerfreundlicher 2D-AutoCAD-Klon exklusiv für iPad.

- Frontend: Flutter
- Backend: QCAD-Core (C++), per FFI angebunden
- Komplett touch-/Pencil-gesteuert, kein Kommandozeilen-Interface
- Ziel: Präzision eines technischen CAD-Programms + Eleganz einer modernen Tablet-App

## Status

**M1: Headless-Basis & CI-Setup — in Arbeit**

- [x] Headless-relevante QCAD-Core-Quellen vendored (`backend/qcad-core/`, siehe `VENDOR.md` für Quelle/Commit/Lizenz)
- [x] Root-`CMakeLists.txt` für headless Core-Build (nur `core`, `entity`, `operations`, `io`, `snap`, `spatialindex`, `3rdparty/dxflib`)
- [x] GitHub Action `.github/workflows/m1-core-build.yml`: kompiliert den Core auf macOS-Runner für iOS-Target (Qt6 + Ninja)
- [ ] Compiler-Status: wird nach erstem CI-Lauf hier vermerkt

## Architektur

```
backend/qcad-core/     Vendorter, headless-tauglicher QCAD-Core (C++, GPLv3)
.github/workflows/     CI: Build-Validierung auf macOS/iOS-Simulator-Toolchain
```

`gui`, `run` sowie der JS-Actionlayer (`scripts/`) aus dem QCAD-Upstream sind bewusst nicht enthalten — diese werden erst in Phase 2 (M4/M5) relevant, wenn die Flutter-GUI entsteht.

## Lizenz

Der vendorte QCAD-Core steht unter GPLv3 (siehe `backend/qcad-core/LICENSE.txt`, `gpl-3.0.txt`, `gpl-3.0-exceptions.txt`). `dxflib` steht unter GPLv2+. Lizenzkompatibilität mit der finalen App-Distribution ist vor Produktiv-Release zu klären.
