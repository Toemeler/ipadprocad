# HANDOFF — iPadProCAD

Kurzer, aktueller Übergabestand. Details/Begründungen im README unter „Status".

## Projekt
- 2D-CAD für iPad. Frontend: Flutter. Backend: QCAD-Core (C++, GPLv3) per FFI.
- Ziel-Repo: `github.com/Toemeler/ipadprocad`
- Upstream-Quelle: `github.com/qcad/qcad` (Vendor-Details in `backend/qcad-core/VENDOR.md`)
- Methodik: Backend zuerst im Terminal (Linux) bauen, dann per GitHub Actions als
  iOS-Cross-Compile validieren. Pro Meilenstein pushen und diese Datei aktuell halten.

## Meilensteine
- **M1 — Headless-Core-Build + iOS-CI: ERLEDIGT (grün).**
- M2 — C-Wrapper um den Core + FFI-Anbindung an Flutter. (als Nächstes)
- M3 — Headless-Logiktests auf iOS.
- M4 — Flutter-GPU-Canvas + CI-Screenshots.
- M5 — Touch-/Pencil-Werkzeuge (hier werden `snap`/`grid` reaktiviert).

## Aktueller Stand (M1)
Der Core kompiliert und linkt fehlerfrei lokal (Linux, Qt6) und im CI als
iOS-Cross-Compile (macOS-Runner, Qt 6.7.3, `arm64`, Device). CI erzeugt die
statischen Bibliotheken `libqcadcore.a`, `libqcadentity.a`, `libqcadoperations.a`,
`libqcaddxf.a`, `libdxflib.a`.

Wesentliche Entscheidungen (alle reversibel, im README begründet):
- **Statische Libs** (kein Shared) — passend für iOS-FFI, vermeidet iOS-Linkfehler.
- **iOS-Device-Target** (`iphoneos`), nicht Simulator (install-qt-action liefert
  Device-Qt).
- Zurückgestellt: **opennurbs** (`R_NO_OPENNURBS`, Splines vorerst inaktiv),
  **spatialindex Navel** (Core nutzt `RSpatialIndexSimple`), **snap/grid**
  (Interaktions-Ebene, M5).
- Headless-Kapselung via `QCAD_HEADLESS`; iOS-Portabilität via `QT_CONFIG(process)`
  (kein `QProcess`) und `Q_OS_MACOS` (statt `Q_OS_MAC`) für Dark-Mode.

## Bauen
```
# lokal (Linux, statische Libs), aus backend/qcad-core:
cmake -B build -G Ninja -DBUILD_QT6=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j -- -k 0     # -k 0 = keep-going, zeigt alle Fehler
# Artefakte: release/libqcad*.a, plugins/libqcaddxf.a
```
Abhängigkeiten lokal: `cmake ninja qt6-base-dev qt6-declarative-dev` (+ `qt6-svg-dev`).

## CI-Logs lesen (wichtig)
Der Dev-Container erreicht den Actions-Log-Speicher nicht. Der Workflow committet
die Logs in den Branch `ci-debug-logs`:
```
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-configure.log
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-build.log
```
Run-Status via API: `GET /repos/Toemeler/ipadprocad/actions/runs?branch=main`.
Der Build-Step nutzt `-k 0`, damit ein einziger Lauf alle Compile-Fehler auflistet.

## Nächste Schritte (M2)
1. C-ABI-Wrapper (`extern "C"`) um die benötigten Core-Funktionen (Dokument
   anlegen, Entities hinzufügen/abfragen, DXF laden/speichern).
2. Wrapper + statische Core-Libs zu einer iOS-tauglichen Einheit bündeln
   (statische Lib bzw. XCFramework), Symbole für den App-Link vollständig halten
   (u. a. `isMacDarkMode` für iOS bereitstellen oder Aufruf entfernen, sobald ein
   voller App-Link erfolgt).
3. Dart-FFI-Bindings + minimaler Smoke-Test (Version, Linie anlegen, DXF-Roundtrip).
