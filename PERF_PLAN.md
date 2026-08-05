# Performance-Analyse — der Plan

Ziel: exakte, wiederholbare Messwerte fuer JEDEN Vorgang der App, erhoben ohne
dass je ein Mac am iPad haengt. Dies ist der Messplan, nicht der Optimierplan —
die Reihenfolge ist Absicht (M75).

---

## 1. Die Randbedingung, genau benannt

Entwickelt wird am iPad. Die CI (`m1-core-build.yml`) baut auf einem
macOS-Runner eine **unsignierte Release-IPA**; SideStore installiert sie
(AUTOINSTALL.md). Zur Laufzeit ist kein Mac im Spiel. Daraus folgt hart:

* Instruments am echten iPad: unmoeglich.
* Metal Frame Capture: unmoeglich.
* Xcode-Organizer-Metriken: unmoeglich (keine App-Store-Verteilung).

Alles andere, was gemeinhin als „dafuer brauchst du einen Mac" gilt, ist
erreichbar — in drei Bahnen.

---

## 2. Was schon da ist, und was verfallen ist

**Gute Substanz.** `lib/perf.dart`: `PerfStat` mit p95, `FrameTiming` getrennt
nach build/raster, Jank-Zaehler, RSS, Gauges, 5-s-Flush nach
`logs/performance_logs.txt`, Rotation bei 4 MB. Dazu
`lib/widgets/perf_overlay.dart` als Live-Anzeige. Die Kostendisziplin in der
Datei stimmt: `Perf.span` ist Stopwatch aus dem Pool plus ein Map-Lookup.

**Verfallen.** M79 dokumentierte 12 Spans. Im Code stehen heute:
`2d.paint`, `3d.push`, `3d.payload`, `kernel.remesh`, `kernel.feature`,
`sketch.solveRebuild`, `sketch.profileLoops`, `sketch.syncProjections`,
`project.partEdges`, `project.syncSolid`.
`2d.underlay`, `2d.underlay.rebuild` und `2d.underlay.hit` sind **weg** — der
Cache, den sie gemessen haben, wurde umgebaut und die Sonden gingen mit.

**Die grosse Luecke.** 43 OCCT- und 15 QCAD-FFI-Einstiegspunkte, **keiner
einzeln gemessen**. `kernel.feature` umklammert einen ganzen Recompute; es kann
nicht sagen, ob die Zeit in `occt_fuse`, `occt_fillet_edges_ex` oder
`occt_mesh_create` liegt.

**Der Ausgang fehlt.** `bug_report.dart` referenziert `Perf.path` nirgends. Die
Zahlen koennen das Geraet also nicht zusammen mit dem uebrigen Beweismaterial
verlassen.

**Das Messgeraet kostet selbst.** Zwei Stellen:
* `PerfStat.add` macht `_samples.removeAt(0)` auf einer 128er-Liste bei jedem
  Sample — O(n)-memmove im Messcode. Gehoert ein Ringpuffer.
* `_PerfOverlayState._sceneLine()` laeuft ueber jedes Feature und summiert
  `mesh.indices.length`, bis zu 5x/s. Bei 34 000 Dreiecken berechnet das
  Overlay der App das Zusehen.

**Der Strukturbefund, noch vor jeder Messung.** Es gibt **keine einzige
Isolate** im Projekt (`grep -rn "Isolate\|compute(" frontend/lib` liefert nur
den CRC-Helfer in `zip_writer.dart`). Alle 58 FFI-Aufrufe laufen synchron auf
dem UI-Thread. Jeder Boolean, jedes Fillet, jede Tessellierung und jeder
STEP-Import ist damit **bauartbedingt** ein Frame-Blocker. Das sagt nicht, wie
lang — dafuer ist die Messung da. Es sagt, wo die Decke haengt.

---

## 3. Drei Bahnen

### Bahn A — Am Geraet, in der App. (Die Wahrheit.)

Die einzige Bahn auf echtem Chip, echtem Impeller, echtem Temperaturbudget.
Alles andere ist Stellvertreter.

**A1 — Span-Abdeckung reparieren und ausbauen.**
* Die verlorenen `2d.underlay*`-Sonden gegen den heutigen Cache neu setzen.
* **Nicht** 58 Aufrufstellen von Hand instrumentieren: `Perf.span` in den
  Lookup-Wrapper von `ffi/occt_engine.dart` / `ffi/qcad_engine.dart` legen,
  dann ist ein neuer Kernel-Aufruf am Tag seiner Entstehung gemessen. Namen:
  `ffi.occt.fuse`, `ffi.occt.fillet_edges_ex`, …
* Spans fuer die blinden Pfade: Geste → Hit-Test → Snap (`snap.dart`),
  `modify.dart`, Undo/Redo, Dokument speichern/laden, STEP-Import/-Export,
  `part_render.dart`, Platform-View-Verkehr (`native_browser_host.dart`,
  `reality_view`-Kanal-Roundtrips).
* `Perf.gauge` auch fuer **Cache-Trefferquoten**, nicht nur Groessen. Ein Cache
  ohne sichtbare Trefferquote ist ein Cache, den man nicht einstellen kann.
* Kostenschranke: den 20-µs-Test aus M79 behalten, plus einen neuen — die
  Gesamt-Sondenlast eines Skript-Laufs bleibt unter 1 %.

**A2 — Ein natives Sonden-Plugin** (`packages/perf_probe`, gleiche
Path-Dependency-Zustellung wie `native_menu`) fuer das, was Dart wirklich nicht
sieht. Der Kommentar in `perf.dart` sagt, CPU-Prozent sei nicht zu bekommen —
das stimmt **aus Dart**. Aus einem Swift/C-Shim nicht:

| Was | API | Warum es zaehlt |
|---|---|---|
| CPU je Thread | `task_threads()` + `thread_info(THREAD_BASIC_INFO)` | Trennt UI-Thread, Raster-Thread, Dart-Helfer. Unterscheidet „die App ist langsam" von „langsam auf dem Thread, der zeichnet". |
| Echter Speicher | `task_info(TASK_VM_INFO)` → `phys_footprint` | Die Zahl, wegen der Jetsam killt. `ProcessInfo.currentRss` ist sie nicht. |
| Restspeicher | `os_proc_available_memory()` | Die Decke. Gehoert neben jede Modell-Oeffnen-Messung. |
| Drossel | `ProcessInfo.thermalState`, `isLowPowerModeEnabled` | Eine Messung bei `.serious` ist mit einer bei `.nominal` nicht vergleichbar. Unter CAD-Dauerlast erreichst du das. |
| Wirklich gezeigte Frames | `CADisplayLink`, `maximumFramesPerSecond` | `FrameTiming` sagt, wie lang ein Frame in der Herstellung war. CADisplayLink sagt, ob er gezeigt wurde — und ob das Panel 60 oder 120 Hz kann. |
| Signposts | `os_signpost` | Intervalle mit den `Perf.span`-Namen, damit ein Instruments-Trace aus Bahn B **deine** Subsystemnamen zeigt statt roher Stacks. |

**A3 — MetricKit.** `MXMetricManager` im Plugin abonnieren. Das ist Apple, das
deine App auf deinem Geraet misst, taeglich, ohne Mac:
* `MXAppLaunchMetric` (Zeit bis zum ersten Draw, als Histogramm),
  `MXAnimationMetric.scrollHitchTimeRatio`, `MXCPUMetric.cumulativeCPUTime`,
  `MXMemoryMetric.peakMemoryUsage`, `MXAppResponsivenessMetric`
  (Hang-Zeit-Histogramm).
* Der Hauptgewinn: `MXDiagnosticPayload` → `MXHangDiagnostic.callStackTree` —
  **ein echter nativer Callstack fuer jeden Hang, den das OS gesehen hat**,
  dazu `MXCrashDiagnostic`. Unsymbolisiert; die CI muss also das dSYM je
  Build-Nummer aufheben (sie stempelt schon `0.1.<run>`), ein kleiner
  Symbolisierschritt macht Namen daraus.
* Payloads als JSON nach `logs/metrickit/`.
* Ehrliche Einschraenkung: Zustellung einmal pro 24 h. Das ist die
  **Hintergrund**-Bahn — sie faengt, was du nicht zu skripten gedacht hast.

**A4 — Der selbstprofilierende Build. Der Punkt, an dem es ueber „so weit
kommt Flutter" hinausgeht.**

Die CI baut eine **zweite** IPA mit `--profile` und eigener Bundle-ID
(`com.prototype.prototype.profile`), damit sie **neben** der Release-App
installiert. Im Profile-Modus laeuft der Dart VM Service **in der App**. Und die
App kann sich mit sich selbst verbinden: `Service.getInfo()` aus
`dart:developer` liefert die lokale Server-URI, das `vm_service`-Paket
verbindet ueber `ws://127.0.0.1:<port>/…` — Loopback, also keine
Local-Network-Berechtigung, kein Bonjour, kein Mac. Danach stehen dieselben
RPCs offen, die DevTools benutzt:

* `getCpuSamples` → der Sampling-Profiler der VM: **echte Dart-Callstacks mit
  Sample-Zahlen.** Ein Flamegraph davon, wohin die UI-Thread-Zeit wirklich
  geht — nicht nur, welcher deiner 40 Spans heiss war.
* `getVMTimeline` → alle Timeline-Ereignisse inklusive der von Flutter selbst
  (build/layout/paint/raster).
* `getAllocationProfile` / `getMemoryUsage` → Allokation je Klasse und
  GC-Druck. Fuer eine App, die staendig Meshes neu baut, liegt hier die
  eigentliche Speichergeschichte.

Ein „Profil aufzeichnen"-Knopf im Debug-Menue nimmt N Sekunden auf, wandelt in
**Chrome-Trace-JSON** und schreibt nach Documents.

Und dann der Teil, der daraus einen iPad-Arbeitsablauf macht: Datei in Files
oeffnen, in Safari an **ui.perfetto.dev** geben, **Flamegraph am iPad lesen**.
Perfetto laeuft vollstaendig im Browser, offline, ohne Server, und liest das
alte Chrome-JSON-Format.

Aufs Etikett gehoert: Profile-Modus kostet ~5–15 % gegenueber Release. Also
Profile-Traces fuer die **Zuordnung** (wo liegt die Zeit), Release-
`performance_logs.txt` fuer die **Absolutwerte**.

**A5 — Der Ausgang.** `bug_report.dart` zum Perf-Bundle erweitern:
`performance_logs.txt` + `_prev`, das Trace-JSON, die MetricKit-Payloads,
Geraet/OS/Thermalzustand/Build, die Gauges — und das Fixture-Modell, das die
Zahlen erzeugt hat. Gleicher ZIP-Writer, gleiches Share-Sheet. Die Regel steht
schon in der Datei: ein Bericht taugt, wenn sich der Fall ausserhalb des
Geraets nachbauen laesst. Fuer Langsamkeit gilt sie genauso.

### Bahn B — Der macOS-Runner. („Mac-Sachen ueber Artefakte.")

Du hast keinen Mac; du mietest 20 Minuten pro Push, und er gibt Dateien zurueck.

**B1 — Skript-Szenarien via `integration_test` im iOS-Simulator.**
`IntegrationTestWidgetsFlutterBinding.traceAction()` / `watchPerformance()`
zeichnet UI- und Raster-Timeline um eine skriptete Interaktion auf und schreibt
`*_timeline.json` plus Zusammenfassung. Jedes Szenario aus dem Katalog wird ein
Test.

**B2 — Instruments, kopflos.**
`xcrun xctrace record --template 'Time Profiler' --device-name '<sim>' --attach <pid>`
um denselben Lauf, dann
`xctrace export --input X.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' --output tp.xml`.
Daraus eine sortierte Funktionstabelle. **Das ist die einzige Bahn mit
Symbolaufloesung im OCCT-Inneren** — welche OCCT-Routine das Fillet frisst. Ein
zweiter Durchgang mit `Allocations` fuer malloc-Verkehr.

**B3 — Artefakte, die am iPad lesbar sind.** Keine `.trace`-Dateien
ausliefern, die du nicht oeffnen kannst. Der Job liefert: einen sortierten
Klartextbericht, ein JSON-Summary und das Chrome-Trace-JSON (in Safari via
Perfetto zu oeffnen). Das Muster, CI-Logs auf einen Debug-Branch zu committen
(`ci-logs-dart`), gibt es schon — als `ci-logs-perf` wiederverwenden.

**B4 — Die Regressionsschranke.** `perf/baseline.json` im Repo, ein Eintrag je
Szenario mit p50/p95. Der Job vergleicht und wird rot (oder kommentiert) bei
>10 % Verschlechterung. Ohne das verrottet jede Optimierung still.

**Die ehrliche Einschraenkung, einmal und laut:** der Simulator ist kein iPad.
Fremde CPU, Host-GPU, kein Temperaturbudget, nicht der Impeller-Pfad der
A-Serie. Bahn-B-Zahlen gelten fuer **relative Regressionserkennung** und fuer
**native Zuordnung**. Sie gelten **nicht** als absolute Frame-Zeiten. Wer eine
Simulator-Millisekunde als iPad-Millisekunde zitiert, wiederholt den
M75-Fehler in neuem Kostuem.

### Bahn C — Kopflose Kernel-Benchmarks. (Schnellste Schleife, wahrscheinlichster Taeter.)

Das C++ unter `backend/` braucht kein iOS.

* **C1** — ein `bench`-CMake-Ziel gegen das C-ABI-Shim: feste Eingabe-Fixtures,
  N Wiederholungen, Mittel/Stdabw/p95 je Operation — `occt_fuse`, `occt_cut`,
  `occt_fillet_edges_ex`, `occt_mesh_create`, `occt_extrude_profile_arcs`,
  `occt_ray_hits`, `occt_import_step`, dazu der slvs-Solve. Google Benchmark
  oder 200 Zeilen Handarbeit; entscheidend sind die Fixtures.
* **C2** — auf `macos-14` laufen lassen: Apple Silicon, arm64, dieselbe
  ISA-Familie wie der iPad-Chip. Relative Kosten uebertragen sich gut,
  Absolutwerte sind optimistisch (Desktop-Takt, kein Temperaturdeckel).
* **C3** — Minuten pro Lauf, ohne Geraet, ohne Flutter. Waehrend man an der
  Mesh-Erzeugung schraubt, ist das die Schleife, die man will; Bahn A
  bestaetigt danach.
* **C4** — pro Operation auch Spitzen-RSS und Allokationszahl. Bei
  Tessellierung wiegen die oft schwerer als die Zeit.

---

## 4. Der Szenarienkatalog

„Jeden Vorgang testen" braucht eine geschlossene Liste, sonst misst man, was
gerade bequem ist. Je Szenario: Fixture, skriptete Interaktion, Leitmetrik,
zustaendige Bahn.

**Fixtures** (nach `perf/fixtures/`, drei Groessen):
* **S** — eine Skizze, ~20 Entities, 3 Features.
* **M** — ~40 Features, mehrere Koerper, aktive Projektionen.
* **L** — der Zahnrad-Fall: ~440 Kanten auf einer Flaeche (in M76/M77 als
  Projektions-Stressfall benannt), 30 000+ Dreiecke.

| # | Szenario | Fixture | Leitmetrik | Bahn |
|---|---|---|---|---|
| 1 | Kaltstart → erstes Bild | — | Zeit bis erstem Draw | A (MetricKit) + B |
| 2 | Dokument oeffnen | S/M/L | Wandzeit, Spitzen-Footprint | A + C |
| 3 | Skizze: freier Zug | M | `frame.build` p95, Jank-% | A + B |
| 4 | Skizze: Solve waehrend Zug | M | `sketch.solveRebuild` p95 | A + C (slvs) |
| 5 | Projektion vom Solid | L | `project.partEdges`, `project.syncSolid` | A + C |
| 6 | Pannen/Zoomen in Skizze | L | `frame.raster` p95, `2d.paint` | A |
| 7 | 3D-Orbit | L | Raster p95, gezeigte FPS (CADisplayLink) | A |
| 8 | Extrusion | M | `kernel.feature`, `ffi.occt.extrude_*` | A + C |
| 9 | Fillet/Fase auf N Kanten | L | `ffi.occt.fillet_edges_ex` | C, dann A |
| 10 | Boolean (fuse/cut/common) | M | `ffi.occt.fuse` … | C, dann A |
| 11 | Re-Tessellierung nach Edit | L | `kernel.remesh`, `sceneTris` | A + C |
| 12 | RealityKit-Szene schieben | L | Aufteilung `3d.payload` vs `3d.push` | A |
| 13 | Modellbrowser (UiKitView) | M | Kanal-Roundtrip, Resize-Stuerme | A |
| 14 | Undo/Redo | M | Wandzeit, Allokationen | A + B |
| 15 | Rollback / EOP verschieben | M | Zeit fuer Vollneubau | A + C |
| 16 | STEP Import/Export | M | Wandzeit, Spitzen-Footprint | C, dann A |
| 17 | Speichern + Neuladen | L | Wandzeit | A |
| 18 | 30-Minuten-Dauerlauf | M | Footprint-Drift, Thermalzustand, Jank-Trend | A |

Szenario 18 wird immer ausgelassen und findet als einziges das Leck. Eine
CAD-Sitzung ist eine Stunde, kein Klick.

---

## 5. Die Methode — wie aus einer Zahl ein Fix wird

Das Projekt hat das teuer gelernt (M75: drei Runden Optimierung in der falschen
Schicht, waehrend das Stocken im 2D-Painter sass). Festschreiben:

1. **Nie ohne Szenarionummer optimieren.** „Fuehlt sich langsam an" ist nicht
   zulaessig. „Szenario 6, Fixture L, Raster p95 = X ms" ist es.
2. **Die Zuordnungsleiter in dieser Reihenfolge herunter:** `frame.total` →
   `build` (Dart) oder `raster` (GPU)? → welcher benannte Span hat den groessten
   Anteil an der Wanduhr? → was sagen die CPU-Samples innerhalb dieses Spans?
   → ist das Blatt Dart oder nativ? → wenn nativ, Bahn B/C fuers Symbol.
3. **Baseline vor jeder Aenderung aufnehmen**, in `perf/baseline.json`, am
   Geraet, bei `.nominal`.
4. **Eine Aenderung, dieselbe Bahn erneut**, danach am Geraet in Bahn A
   bestaetigen. Ein Bahn-C-Gewinn, der in Bahn A nicht auftaucht, lag nicht auf
   dem kritischen Pfad.
5. **Das Delta in die Meilensteinnotiz**, so wie HANDOFF.md alles andere fuehrt.

---

## 6. Reihenfolge

**Phase 1 — das Messgeraet vertrauenswuerdig machen (klein, zuerst).**
`PerfStat` auf Ringpuffer; das Overlay hoert auf, das Modell zu durchlaufen;
`2d.underlay*` zurueck; alle 58 FFI-Einstiege automatisch umwickelt; der
Perf-Log ins Bug-Bundle. Kosten: Stunden. Schaltet frei: jede spaetere Zahl.

**Phase 2 — Bahn C, weil sie gratis ist.**
Bench-Ziel, Fixtures, CI-Job. Kein Geraet, kein Flutter, Minuten pro Lauf. Die
drei groessten Uebeltaeter stehen vermutlich schon hier.

**Phase 3 — Bahn A in die Tiefe.**
`perf_probe` (Threads/Footprint/Thermal/CADisplayLink/Signposts),
MetricKit-Abonnent, die Profile-IPA und die Selbstverbindung an den VM Service
mit Perfetto-Export. Groesster Bau, groesster Ertrag.

**Phase 4 — Bahn B automatisieren + Schranke.**
integration_test-Szenarien, xctrace am Simulator, `baseline.json`,
Regressionspruefung bei jedem Push.

Phase 2 und 3 koennen parallel laufen; Phase 4 braucht den Szenarienkatalog aus
Phase 3.

---

## 7. Was wirklich nicht geht

Damit niemand eine Woche darauf verwendet:

* **GPU-Auslastung in Prozent** — keine iOS-API gibt sie einer Sandbox-App.
  `frame.raster` und die gezeigte Frame-Kadenz sind die ehrlichen Stellvertreter.
* **Metal Frame Capture / GPU-Zeit je Draw-Call am Geraet** — braucht Xcode
  angehaengt.
* **Instruments am physischen iPad** — braucht einen Mac. Nur Simulator, nur CI.
* **Xcode-Organizer-Felddaten** — braucht App-Store-/TestFlight-Verteilung;
  sideloadete Builds melden nie.
* **Energie je Subsystem** — nicht exponiert. Thermalzustand plus CPU-Zeit je
  Thread kommt am naechsten.

Alles andere oben ist erreichbar, ohne je eine Mac-Tastatur anzufassen.
