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
  wurde; zurückgestellte Teile offen dokumentieren. (Der grüne Haken allein reicht
  nicht: CI-Logs lesen! Siehe M2-CI-Fix unten — ein per `tee` maskierter Fehler
  hatte einmal fälschlich „grün" gemeldet.)

## Repo & Cold Start (für den neuen Chat)
```
git clone https://github.com/Toemeler/ipadprocad.git
cd ipadprocad
```
- **Auth/Push:** Der PAT aus dem vorigen Chat ist widerrufen (der Nutzer widerruft
  jeden Session-Token nach Gebrauch). Für Pushes einen neuen fine-grained PAT
  erzeugen (nur dieses Repo; Contents/Actions/Workflows R+W) und **nur inline**
  verwenden: `git push https://<PAT>@github.com/Toemeler/ipadprocad.git HEAD:main`.
  Den Token NIE in `.git/config` oder getrackte Dateien schreiben; nach Gebrauch widerrufen.
- **Lokale Build-Abhängigkeiten (Ubuntu):**
  `apt-get install -y cmake ninja-build qt6-base-dev qt6-base-dev-tools qt6-declarative-dev libqt6svg6-dev`
- **Lokaler Build (statische Libs), aus `backend/qcad-core`:**
  ```
  cmake -B build -G Ninja -DBUILD_QT6=ON -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j -- -k 0        # -k 0 = keep-going, zeigt ALLE Fehler
  ```
  Artefakte: `release/libqcad*.a`, `plugins/libqcaddxf.a`, `release/libqcadcapi.a`.
- **Lokaler Wrapper-Smoke-Test (nur Host, optional):**
  ```
  cmake -B build -G Ninja -DBUILD_QT6=ON -DCMAKE_BUILD_TYPE=Release -DQCAD_CAPI_SMOKE=ON
  cmake --build build --target qcad_capi_smoke -- -k 0
  ./release/qcad_capi_smoke        # erwartet: "SMOKE: PASS"
  ```

## Meilensteine
- **M1 — Headless-Core-Build + iOS-CI: ERLEDIGT (grün, mehrfach reproduziert).**
- **M2 — C-Wrapper + FFI an Flutter: WRAPPER ERLEDIGT & VALIDIERT.**
  - C-ABI-Wrapper `src/capi` gebaut; lokal (Linux/Qt6) Smoke grün; iOS-Cross-Compile
    (arm64/iphoneos, Qt 6.7) grün; kombinierte Lib + XCFramework in CI erzeugt.
  - **Offener Rest von M2:** Dart-FFI-Bindings sind geschrieben, aber **noch nicht
    ausgeführt/CI-validiert** (kein Dart-SDK im Backend-Build). Siehe „Stand M2".
- M3 — Headless-Logiktests auf iOS (C-Smoke-Logik als XCTest/Device-Test gegen das
  XCFramework; dort auch die Dart-FFI erstmals real ausführen).
- M4 — Flutter-GPU-Canvas + CI-Screenshots (XCFramework in die App linken, Dart-FFI verdrahten).
- M5 — Touch-/Pencil-Werkzeuge (hier `snap`/`grid` reaktivieren).

## Stand M1 (Ausgangsbasis)
Der Core kompiliert und linkt fehlerfrei lokal (Linux, Qt6) und im CI als
iOS-Cross-Compile. Statische Bibliotheken: `libqcadcore.a`, `libqcadentity.a`,
`libqcadoperations.a`, `libqcaddxf.a` (in `plugins/`), `libdxflib.a`.
Gebaute Module: `core`, `entity`, `operations`, `io/dxf`, `3rdparty/dxflib`.
Entscheidungen (statische Libs; iOS-Device arm64, Deployment 13.0, PIC;
`QCAD_HEADLESS`; `QT_CONFIG(process)` statt `QProcess`; `Q_OS_MACOS`;
zurückgestellt: `opennurbs`/`R_NO_OPENNURBS`, `spatialindex`-Navel →
`RSpatialIndexSimple`, `snap`/`grid`). Alles reversibel, im README begründet.

## Stand M2 (C-ABI-Wrapper — aktueller Fokus)
**Modul:** `backend/qcad-core/src/capi/` — `qcad_capi.h` (reines C) + `qcad_capi.cpp`
(einziger Ort mit C++/Qt/QCAD-Typen). CMake-Ziel `qcadcapi` (STATIC), ins
Root-`CMakeLists.txt` als `add_subdirectory(src/capi)` eingehängt → wird bei jedem
Core-Build mitgebaut. Ausgabe: `release/libqcadcapi.a`.

**ABI-Oberfläche** (opaque `qcad_document*`, keine C++-Typen an der Grenze,
Winkel in Radiant, Koordinaten als `double`, int-Rückgaben 1=OK/0=Fehler):
`qcad_init`, `qcad_version`, `qcad_document_new/_free`, `qcad_add_line/_circle/
_arc/_polyline`, `qcad_entity_count`, `qcad_bounding_box`, `qcad_load_dxf`,
`qcad_save_dxf` (Version NULL/"R12"/"min", Default R2000).

**Validierung:**
- Lokal (Linux/Qt 6.4): `qcad_capi_smoke` = **SMOKE: PASS** — 4 Entities, BBox
  `[0,0]..[100,75]`, DXF-Roundtrip (speichern→laden) erhält die Entity-Anzahl.
- iOS-CI (Run #18, Commit `7fa5e9c`): **echt grün** (Logs geprüft). Alle sechs
  `.a` sind `arm64`; kombinierte `release/libipadprocad.a` (arm64, ~11 MB) via
  `libtool -static`; `release/ipadprocad.xcframework` (`ios-arm64`, mit Headers)
  erzeugt. CI-Artefakt: `ipadprocad-ios-capi`.

**Wichtige Entscheidungen/Fallstricke (unbedingt beachten):**
1. **Property-Typen-Registrierung:** QCADs Bootstrap (`R*Entity::init()` für alle
   Typen) liegt im ausgeklammerten GUI/Script-Layer. `qcad_init()` ruft daher den
   vollständigen Satz selbst auf (Basis `RObject`/`REntity` zuerst, dann 46
   konkrete Klassen). `RColor::init()`/`RLineweight::init()` sind **privat** →
   ausgelassen (werden intern registriert). Die Liste wurde aus den vorhandenen
   `static void init()`-Deklarationen generiert; bei neu gevendorten Entity-Typen
   die Aufrufliste in `qcad_capi.cpp` neu erzeugen.
2. **Ownership / kein Doppel-Free:** `RStorage`/`RSpatialIndex` erben von
   `RRequireHeap` (`doDelete()` = `delete this`). `RDocument::~RDocument()` gibt
   beide via `doDelete()` frei. Daher Storage + SpatialIndex **heap-allozieren**
   und **nur** das `RDocument` löschen (Storage/Index selbst zu löschen → Doppel-
   Free, der Original-Bug). `RDocument`-Ctor ruft `init()` bereits selbst auf.
3. **RSettings-Init:** `RSettings::isInitialized()` == `!qApp->organizationName().isEmpty()`.
   `qcad_init()` legt bei Bedarf eine `QCoreApplication` an und setzt Org-/App-Name
   „iPadProCAD" → keine „RSettings not initialized"-Flut mehr, echtes Settings-
   Backend. Namen nur setzen, wenn leer (Host/GUI-Build könnte sie stellen).
4. **Benigne Warnungen (kein Fehler):** `RDxfExporter: unsupported extension data
   type: 65537` beim Schreiben der Default-Farb-XData von Layer „0" (DXF gültig,
   Roundtrip ok). `libtool: duplicate member name 'mocs_compilation.cpp.o'` beim
   Bündeln (je Ziel ein AUTOMOC-Stub; wird korrekt gemerged).
5. **CI-Fix (falsches Grün behoben, Commit `7fa5e9c`):** (a) iOS-Configure MUSS
   `-DCMAKE_BUILD_TYPE=Release` setzen, sonst landen die Libs in `debug/` und
   Verify/Bundle (die in `release/` suchen) laufen ins Leere. (b) `set -o pipefail`
   in Verify/Bundle/XCFramework, sonst maskiert `tee` einen `exit 1`/libtool-Fehler
   und der Schritt wird fälschlich grün.
6. Der M1-Symbolhinweis (`isMacDarkMode()`) trat nicht auf: Der Linux-Smoke linkt
   sauber, die iOS-Libs archivieren sauber. `_main` liefert erst die App (M4).

## M2 — verbleibende Schritte
1. **Dart-FFI real ausführen:** `bindings/dart/qcad_ffi.dart` (+ `example/
   qcad_smoke.dart`) gegen eine lauffähige Bibliothek testen. Auf iOS ist die
   statische Lib in die App gelinkt → `DynamicLibrary.process()`. Für einen
   Desktop-Test eine SHARED-Variante von `qcadcapi` (.so/.dylib) bauen und
   `QcadBindings.open(<pfad>)` nutzen. Erwartung wie C-Smoke: 4 Entities,
   DXF-Roundtrip erhält Anzahl. **Nicht** auf Spline-Geometrie prüfen
   (`R_NO_OPENNURBS` inaktiv), keine Snap-Funktionen erwarten (Modul zurückgestellt).
   Benötigt das `ffi`-Pub-Paket (in pubspec der Flutter-App bei M4 ergänzen).
2. Danach M3: dieselbe Logik als iOS-Device-Test (XCTest) gegen das erzeugte
   `ipadprocad.xcframework` laufen lassen.

## CI-Logs lesen (wichtig)
Der Dev-Container erreicht den Actions-Log-Speicher (`blob.core.windows.net`) nicht.
Der Workflow committet die Logs in den Branch `ci-debug-logs`:
```
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-configure.log
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-build.log
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-verify.log       # M2: Lib-Verifikation (lipo/arch)
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-bundle.log       # M2: libtool-Kombi-Lib
https://raw.githubusercontent.com/Toemeler/ipadprocad/ci-debug-logs/ci-logs/ci-xcframework.log  # M2: XCFramework
```
Run-Status via API (mit Token): `GET /repos/Toemeler/ipadprocad/actions/runs?branch=main`.
Der Build-Step nutzt `-k 0` (alle Fehler in einem Lauf). Reine `**.md`-Commits
triggern kein CI (`paths-ignore`). Workflow-Datei: `.github/workflows/m1-core-build.yml`
(Anzeigename jetzt „Core + C-API Build (iOS)"; baut Core **und** Wrapper, verifiziert,
bündelt und lädt `ipadprocad-ios-capi` als Artefakt hoch).

## Nützliche Pfade
```
backend/qcad-core/CMakeLists.txt          Root-Build (Modulliste + add_subdirectory(src/capi))
backend/qcad-core/CMakeInclude.txt        gemeinsame Build-Einstellungen (APPLE-Target)
backend/qcad-core/src/capi/qcad_capi.h    C-ABI (reines C, extern "C")
backend/qcad-core/src/capi/qcad_capi.cpp  Wrapper-Implementierung (einziger C++/Qt-TU)
backend/qcad-core/src/capi/CMakeLists.txt Ziel qcadcapi (STATIC) + optional qcad_capi_smoke
backend/qcad-core/src/capi/tests/smoke.c  C-Smoke-Test (Host)
backend/qcad-core/bindings/dart/qcad_ffi.dart          Dart-FFI-Bindings (noch nicht CI-validiert)
backend/qcad-core/bindings/dart/example/qcad_smoke.dart Dart-Beispiel (Desktop/iOS)
backend/qcad-core/src/core/               RDocument, RDocumentInterface, RStorage, RSpatialIndexSimple, RSettings
backend/qcad-core/src/io/dxf/             RDxfImporter/RDxfExporter (direkt genutzt, ohne Registry)
.github/workflows/m1-core-build.yml       CI (Core + C-API, iOS + Bundle)
```
