# HANDOFF — iPadProCAD

Übergabestand für die Fortsetzung in einem neuen Chat. Begründungen/Details im
README unter „Status".

## Projekt
- 2D-CAD für iPad. Frontend: Flutter. Backend: QCAD-Core (C++, GPLv3) per FFI.
- Ziel-Repo: `github.com/Toemeler/ipadprocad`
- Upstream-Quelle: `github.com/qcad/qcad` (Vendor-Details: `backend/qcad-core/VENDOR.md`)
- Methodik: Backend zuerst lokal im Terminal (Linux) bauen, dann per GitHub Actions
  als iOS-Cross-Compile validieren. Pro Meilenstein pushen und diese Datei aktuell
  halten. **Nur echten Status berichten** — nie „grün" behaupten, was nicht gebaut
  wurde; zurückgestellte Teile offen dokumentieren.

## Repo & Cold Start (für den neuen Chat)
```
git clone https://github.com/Toemeler/ipadprocad.git
cd ipadprocad
```
- **Auth/Push:** Der alte PAT aus dem vorigen Chat ist widerrufen. Für Pushes einen
  neuen fine-grained PAT erzeugen (nur dieses Repo; Contents/Actions/Workflows R+W)
  und **nur inline** verwenden: `git push https://<PAT>@github.com/Toemeler/ipadprocad.git HEAD:main`.
  Den Token NIE in `.git/config` oder getrackte Dateien schreiben; nach Gebrauch widerrufen.
- **Lokale Build-Abhängigkeiten (Ubuntu):**
  `apt-get install -y cmake ninja-build qt6-base-dev qt6-base-dev-tools qt6-declarative-dev libqt6svg6-dev`
- **Lokaler Build (statische Libs), aus `backend/qcad-core`:**
  ```
  cmake -B build -G Ninja -DBUILD_QT6=ON -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j -- -k 0        # -k 0 = keep-going, zeigt ALLE Fehler
  ```
  Artefakte: `release/libqcad*.a`, `plugins/libqcaddxf.a`.

## Meilensteine
- **M1 — Headless-Core-Build + iOS-CI: ERLEDIGT (grün, zweimal reproduziert).**
- **M2 — C-Wrapper + FFI an Flutter (als Nächstes).**
- M3 — Headless-Logiktests auf iOS.
- M4 — Flutter-GPU-Canvas + CI-Screenshots.
- M5 — Touch-/Pencil-Werkzeuge (hier `snap`/`grid` reaktivieren).

## Stand M1 (Ausgangsbasis für M2)
Der Core kompiliert und linkt fehlerfrei lokal (Linux, Qt6) und im CI als
iOS-Cross-Compile (macOS-Runner, Qt 6.7.3, `arm64`, **Device**). CI erzeugt die
statischen Bibliotheken `libqcadcore.a`, `libqcadentity.a`, `libqcadoperations.a`,
`libqcaddxf.a`, `libdxflib.a`.

Gebaute Module: `core`, `entity`, `operations`, `io/dxf`, `3rdparty/dxflib`
(Root-`CMakeLists.txt`).

Wesentliche Entscheidungen (alle reversibel, im README begründet):
- **Statische Libs** (kein Shared) — passend für iOS-FFI, vermeidet iOS-Linkfehler
  (`_main`/Plattform-Plugin). Auf iOS gibt es keinen Link-Schritt für `.a`.
- **iOS-Device-Target** (`iphoneos`, `arm64`), nicht Simulator (install-qt-action
  liefert Device-Qt). `CMAKE_OSX_DEPLOYMENT_TARGET=13.0`, PIC an.
- Headless-Kapselung via `QCAD_HEADLESS`; iOS-Portabilität via `QT_CONFIG(process)`
  (kein `QProcess`) und `Q_OS_MACOS` statt `Q_OS_MAC` (Dark-Mode).
- **Zurückgestellt (isoliert, reaktivierbar):** `opennurbs` (`R_NO_OPENNURBS`,
  Spline-Auswertung inaktiv), `spatialindex`-Navel (Core nutzt `RSpatialIndexSimple`),
  `snap`/`grid` (Interaktions-Ebene, M5).

## CI-Logs lesen (wichtig)
Der Dev-Container erreicht den Actions-Log-Speicher (`blob.core.windows.net`) nicht.
Der Workflow committet die Logs in den Branch `ci-debug-logs`:
```
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-configure.log
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-build.log
```
Run-Status via API (mit Token): `GET /repos/Toemeler/ipadprocad/actions/runs?branch=main`.
Der Build-Step nutzt `-k 0` (alle Fehler in einem Lauf). Reine `**.md`-Commits
triggern kein CI (`paths-ignore`).

## M2 — konkrete Schritte
1. **C-ABI-Wrapper** (`extern "C"`) über den Core. Neues Modul, z. B.
   `backend/qcad-core/src/capi/` mit `qcad_capi.h` + `qcad_capi.cpp` und eigenem
   CMake-Ziel, das die statischen Core-Libs (`qcadcore`, `qcadentity`,
   `qcadoperations`, `qcaddxf`, `dxflib`) einbindet. Minimale Oberfläche:
   Dokument anlegen/freigeben; Entities hinzufügen (Linie, Kreis, Bogen,
   Polylinie); Anzahl/Bounding-Box abfragen; DXF laden/speichern (Pfad und/oder
   Bytes); Versionstext. Opaque Handles + fehlerarme C-Typen; keine C++-Typen an
   der ABI-Grenze.
2. **Bündeln für iOS:** Wrapper + Core zu einer nutzbaren Einheit für die App
   zusammenfassen (kombinierte statische Lib bzw. XCFramework). CI (Workflow
   erweitern oder M2-Workflow) baut den Wrapper für iOS-Device mit, `-k 0`
   beibehalten.
3. **Symbol-Vollständigkeit beim App-Link:** Sobald ein echter App-/Test-Link
   erfolgt (nicht nur `.a`-Archivierung), tauchen offene Symbole auf. Bekannt:
   `isMacDarkMode()` wird auf iOS derzeit nicht referenziert (Aufrufe auf
   `Q_OS_MACOS` begrenzt) — falls doch benötigt, iOS-Implementierung in einem für
   iOS kompilierten `.mm` bereitstellen. `_main` liefert erst die App (M4).
4. **Dart-FFI-Bindings + Smoke-Test:** Version lesen, Linie anlegen, DXF-Roundtrip
   (schreiben → lesen → Entity-Anzahl prüfen). **Nicht** auf Spline-Geometrie
   prüfen (durch `R_NO_OPENNURBS` inaktiv) und keine Snap-Funktionen erwarten
   (Modul zurückgestellt).

## Nützliche Pfade
```
backend/qcad-core/CMakeLists.txt          Root-Build (Modulliste, globale Defines)
backend/qcad-core/CMakeInclude.txt        gemeinsame Build-Einstellungen (APPLE-Target)
backend/qcad-core/src/core/               RDocument, RDocumentInterface, Geometrie, RSpatialIndexSimple
backend/qcad-core/src/io/dxf/             DXF-Import/-Export (RDxfImporter/RDxfExporter)
.github/workflows/m1-core-build.yml       CI (als Vorlage für M2-Erweiterung)
```
