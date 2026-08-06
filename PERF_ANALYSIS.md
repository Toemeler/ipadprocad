# Performance-Analyse — Runde 1: das Messnetz

Umsetzung von PERF_PLAN.md, Phase 1, plus die Bahn-B-Infrastruktur.

**Hier wird nichts optimiert.** Kein Algorithmus, kein Cache, kein Layout ist
angefasst. Was sich geaendert hat: die App misst sich jetzt selbst, und zwar
flaechendeckend statt an zehn Stellen. Die einzigen Aenderungen mit
Laufzeitwirkung sind drei Reparaturen **am Messgeraet** (Abschnitt 3) — ein
Instrument, das in seinen eigenen Zahlen auftaucht, ist wertlos, und dann waere
die Messung selbst der naechste M75-Fehler.

---

## 1. Befunde aus dem Lesen — vor jeder Messung

Diese fuenf stehen fest, ohne dass eine Zahl erhoben werden musste. Sie sind
der Grund, warum das Messnetz so und nicht anders gespannt ist.

### B1 — Keine einzige Isolate. Alle 58 FFI-Aufrufe auf dem UI-Thread.

`grep -rn "Isolate\|compute(" frontend/lib` liefert genau einen Treffer, und
das ist der CRC-Helfer in `zip_writer.dart`. 43 OCCT- und 15 QCAD-Einstiege
laufen synchron. `occt_engine.dart` sagt es im Kopf sogar selbst: *„Not
thread-safe; call only from the UI thread like qcad/slvs."*

Jeder Boolean, jedes Fillet, jede Tessellierung und jeder STEP-Import ist damit
**bauartbedingt** ein Frame-Blocker. Das ist kein Bug — es ist die Decke. Wie
hoch sie haengt, sagen ab jetzt die 30 `ffi.occt.*`-Spans.

### B2 — Ein 25-Iterationen-Solve laeuft INNERHALB von `CustomPainter.paint`.

`AppState.displayGeometry` (app_state.dart) ruft waehrend eines Grip-Drags
`solveConstraints(..., iterations: 25)`. Der Kommentar darueber sagt es
ausdruecklich: *„NB: this runs INSIDE CustomPainter.paint."*

Und `displayGeometry` hat **sieben** Aufrufer, darunter `_snapped` in
viewport.dart. Ein einzelnes Pointer-Move kann den Solve also mehrfach
bezahlen. Genau dafuer gibt es jetzt `2d.displayGeometry` (Dauer) und
`2d.displayGeometry.solves` (Anzahl): Solves geteilt durch Frames ist die Zahl,
die diese Frage beantwortet. Vorher war sie nicht stellbar.

### B3 — `allEdges()` sind ~440 FFI-Uebergaenge mit je einem calloc/free.

`OcctShape.allEdges()` ruft `edgeInfo(i)` pro Kante, und jedes `edgeInfo`
alloziert 12 Doubles nativ, ruft ueber die Grenze und gibt wieder frei. Der
Zahnrad-Fall aus M76/M77 hat ~440 Kanten auf einer Flaeche. Ein harmlos
aussehendes `allEdges()` ist dort ~440 Uebergaenge und ~440 Allokationspaare.
Jetzt: `ffi.occt.allEdges` (Dauer) + `ffi.occt.edgeInfo.calls` (Anzahl).

### B4 — `allGeometry()` ist nicht ein Uebergang, sondern ~1+3n.

`_FfiEngine.allGeometry()` holt zweimal das Id-Array, dann **pro Entity**: ein
`entityGeometry` zum Groesse-Ermitteln, ein `entityLayer`, ein
`entityGeometry` zum Fuellen, ein malloc/free-Paar und ein
`List<double>.generate`. `app_state.dart:369` kopiert das Ergebnis danach noch
einmal. Jetzt: `ffi.qcad.allGeometry` + `.entities`.

### B5 — Die Instrumentierung war seit M79 verfallen.

M79 dokumentierte zwoelf Spans. Vorgefunden: zehn. `2d.underlay`,
`2d.underlay.rebuild` und `2d.underlay.hit` sind mit dem Umbau des Caches
verschwunden, den sie gemessen haben. Das ist der Normalfall, nicht die
Ausnahme — deshalb sitzt die FFI-Messung jetzt so, dass sie **nicht** verfallen
kann (Abschnitt 2, Prinzip 2).

> **Korrektur zu PERF_PLAN.md, Abschnitt 2.** Dort steht, der Perf-Log fehle im
> Bug-Bundle, weil `bug_report.dart` `Perf.path` nicht kennt. Das stimmt fuer
> jene Datei, aber `bug_capture.dart` reicht `perfText: Perf.path…` sehr wohl
> durch — der Text-Log war schon drin. Was wirklich fehlte, war die
> **maschinenlesbare** Fassung und der rotierte Vorgaenger; beide liegen jetzt
> als `perf_snapshot.json` und `performance_logs_prev.txt` im Bundle.

---

## 2. Wie das Messnetz gespannt ist

Vier Prinzipien, jedes als Antwort auf ein konkretes Problem.

**(1) Auf dem Frame-Pfad kein Closure.** `Perf.span` braucht ein
`T Function()`, und ein Closure, das lokale Variablen faengt, alloziert. Bei
einem Kernel-Aufruf von 40 ms ist das egal. Im 2D-Painter, 18 Phasen mal bis zu
120 Hz, ist es das nicht. Dafuer gibt es neu **`PerfPhases`**: eine
langlebige Instanz, `begin()` / `mark('phase')` / `end()`, ein Map-Lookup pro
Marke, keine Allokation, und die Phasen summieren sich auf die ganze Funktion —
ein Anteil am Ganzen ist also aussagekraeftig.

**(2) Messen, wo es nicht verfallen kann.** Die FFI-Spans sitzen an der
**nativen Aufrufstelle**, nicht um die oeffentliche Methode. Damit misst
`ffi.occt.meshCreate` genau die Zeit im Kernel und nichts sonst, und ein
Refactoring der Dart-Huelle kann die Sonde nicht mitnehmen. Aus demselben Grund
schreibt `Log.step` jetzt seine Dauer in `Perf` (`Log.stepSink`): alle 17
bestehenden `Log.step`-Stellen — die ganze Startsequenz — sind damit gemessen,
ohne eine einzige davon anzufassen.

**(3) Die FFI-Module bleiben abhaengigkeitsfrei.** occt/qcad/slvs sagen im
Kopf, sie haengen nur an `dart:ffi`/`package:ffi`, damit ein Compilefehler der
App sie nie erreicht und sie auf dem Host testbar bleiben. Ein Import von
`perf.dart` (das `dart:io` und `flutter/scheduler` zieht) haette das gebrochen.
Stattdessen: **`ffi/perf_hook.dart`**, eine Datei mit *null* Imports, deren
Hooks per Default nichts tun; `main()` installiert die echten. Ein
un-verdrahtetes Binary — ein Host-Unit-Test — laeuft weiter und zeichnet
schlicht nichts auf.

**(4) Zaehler sind keine Dauern.** `Perf.count` schrieb bisher ein 0-ms-Sample
in dieselbe Tabelle wie die Zeitmessungen. Das verdarb zweierlei: die Zeile des
Zaehlers behauptete avg 0 ms, als waere die Arbeit gratis, und ein Name, der
fuer beides benutzt wurde, bekam seinen Schnitt von jedem Zaehlvorgang gegen
null gezogen. Zaehler haben jetzt eine eigene Tabelle, dazu `Perf.cache(name,
hit)` fuer Trefferquoten — ein Cache, dessen Quote man nicht sieht, ist ein
Cache, den man nicht einstellen kann.

---

## 3. Die drei Reparaturen am Messgeraet

Ausdruecklich keine App-Optimierung. Ohne sie misst das Instrument sich selbst.

| Was | War | Ist |
| --- | --- | --- |
| `PerfStat.add` | `_samples.removeAt(0)` auf 128 Elementen **pro Sample** — O(n)-memmove im Messcode, auf dem Paint-Pfad | Ringpuffer (`Float64List`), Schreiben an Ort und Stelle |
| `_sceneLine()` im Overlay | lief ueber jedes Feature und summierte jede `mesh.indices.length`, bis zu 5x/s | einmal pro Sekunde, dazwischen gecacht |
| `Perf.count` | 0-ms-Sample in der Dauer-Tabelle | eigene Zaehler-Tabelle |

Zusaetzlich neu: `PerfStat.p50Ms` neben p95. Gleich hoch heisst „gleichmaessig
langsam", weit auseinander heisst „meist gut, mit Ausreissern" — das sind
gegensaetzliche Ursachen und gegensaetzliche Fixes.

---

## 4. Was jetzt gemessen wird

**43 Spans, ~18 Zaehler, 10 Gauges, 18 Paint-Phasen, 17 Startschritte.**

### 2D — der Painter, Phase fuer Phase

`2d.paint` (gesamt) zerlegt in: `bg`, `slice`, `editRef`, `entities`,
`gearGhost`, `freehand`, `toolPreview`, `constraints`, `modifyGhost`,
`pattern`, `snap`, `boxSelect`, `cursorHints`, `notice` — und die
Entity-Phase selbst noch einmal in `ent.dofColour`, `ent.halo`,
`ent.projectEdges`, `ent.images`.

`2d.paint.z` faengt alles nach der letzten Marke. **Waechst die je, fehlt eine
Phase** — die Sonde meldet ihre eigene Luecke.

### 2D — Interaktion (der Pfad, der in `2d.paint` NICHT auftaucht)

`2d.snap` (pro Pointer-Move, laeuft zweimal ueber die Geometrie),
`2d.pickEntity` (linear, ~12 Aufrufstellen), `2d.displayGeometry` +
`.solves` (siehe B2).

### 3D

`3d.payload` / `3d.push` (Aufbau vs. Uebergabe an RealityKit),
`3d.hitTest`, `kernel.remesh`, `3d.orbit.events`, Gauges `sceneTris`,
`remeshCount`, `triangles`, `solids`, `features`.

### Kernel — 30 OCCT-Operationen einzeln

`makeBox`, `makeCylinder`, `extrudePolygon`, `extrudeProfile`,
`extrudeProfileArcs`, `sweepProfile`, `loftSections`, `coilProfile`,
`revolveProfile`, `fuse`, `cut`, `common`, `unify`, `filletEdges`,
`chamferEdges`, `transform`, `rayHits`, `revolveHits`, `allEdges`,
`importStep`, `splitSolids`, `meshCreate`, `meshCopyOut` …

**`meshCreate` und `meshCopyOut` sind getrennt, und das ist der Punkt.** Das
eine ist OCCT beim Tessellieren (waechst mit dem B-Rep), das andere ist Dart
beim Kopieren ueber die FFI-Grenze (waechst mit der Dreieckszahl — neun
typisierte Kopien von bis zu hunderttausenden Doubles). Sie wachsen aus
verschiedenen Gruenden und werden an verschiedenen Stellen repariert. Eine Zahl
fuer beides zeigt auf die falsche Schicht — der M75-Fehler im Kleinen.

### Solver

`solve.total`, `ffi.slvs.solve` (nur der native Teil), Gauges
`solve.entities` / `solve.constraints` / `solve.dragged`, Zaehler
`solve.ok` / `solve.unsatisfied`. Ein p95 von 12 ms heisst etwas anderes bei
8 Constraints als bei 300, darum die Gauges neben der Dauer.

### QCAD-Dokument, I/O, Historie, Start

`ffi.qcad.allGeometry` + `.entities`, `addPolyline`, `saveDxf`, `loadDxf`,
`io.savePart`, `io.saveSketch` (per Stopwatch, nicht `span` — die sind async,
und `span` misst einen synchronen Rumpf; ein Future zu umklammern misst, wie
lange das *Erzeugen* des Futures dauerte, also fast nichts, und das laese sich
als „Speichern ist gratis"), `history.undo` / `history.redo`,
`launch.toFirstFrame`, plus `step.*` fuer alle 17 `Log.step`-Stellen.

### Ausgabe

Zusaetzlich zum Textlog jetzt `Perf.jsonSnapshot()` /
`writeJsonSnapshot()` → `performance_snapshot.json`. Der Textlog ist zum
Lesen am iPad, das JSON ist, was gegen `perf/baseline.json` diffbar ist. Beide
liegen im Bug-Bundle.

---

## 5. Was noch dunkel ist (Stand nach M209c)

**Geschlossen seit der ersten Fassung:** Ribbon/Menue (`menu.ribbon.builds`
als Zaehler plus `menu.ribbon.home/part/sketch` als Spans — der Zaehler ist
der interessante Teil: ein Bau kostet Mikrosekunden, die Frage ist, wie oft
er waehrend eines Drags passiert), Platform-View-Verkehr (`rv.setScene/
setOverlays/setCamera` je mit Dauer UND Anzahl, `browser.sig` mit
Trefferquote), `modify.dart` (trim, trimCutAway, extend, offset), das
Dokument-LADEN (`io.openPart`, `io.openSketch`) und die restlichen
QCAD-Einstiege (`addLine`, `addCircle`, `addArc`).

**Zusaetzlich geschlossen in M209d:** die CPU-Projektion in
`part_render.dart` (`render.projectTris`, `render.projectEdges`,
`render.buildSceneSolid`, `render.silhouette` — Kosten skalieren mit der
DREIECKSZAHL, nicht mit dem Bildschirm, also mit dem Modell statt mit dem
Sichtbaren), 2D-Fillet/Fase (`tools.filletChamfer2d`) und die beiden
uebrigen native_menu-Kanaele (`toolbar.*`, `tabbar.*` mit derselben
Signatur-Trefferquote wie der Browser).

**Weiterhin dunkel** — ehrlich benannt, damit niemand die Abdeckung fuer
vollstaendig haelt:

* **Die zwoelf Blatt-Widgets des Ribbons** (`_Big`, `_SmallRow`, `_ConGrid`,
  `_OverRow`, `_FlyMenu`, …). Gemessen sind der Ribbon-Bau als Ganzes und die
  drei Varianten; die Blaetter nicht. Bei ihnen waere ohnehin die ANZAHL die
  Aussage, nicht die Dauer — und die faellt schon mit
  `menu.ribbon.builds` an, weil ein Blatt nicht ohne seinen Ribbon baut.
  Eigene Zaehler lohnen erst, wenn diese Zahl auffaellig ist.
* **Die Dialoge** (`extrude_dialog`, `pattern_dialog`, `gear_dialog`, …). Sie
  stehen still auf dem Schirm, waehrend der Benutzer tippt — ein Dialog, der
  pro Frame neu baut, waere ein Fund, aber ein unwahrscheinlicher.
* **Pattern** in `tools.dart` (Fillet-2D ist jetzt gemessen).
* **Undo/Redo-SPEICHER.** Die Dauer ist gemessen (`history.undo/redo`), die
  Groesse des Journals nicht.

Das sind die naechsten Handgriffe, nicht offene Fragen.

---

## 6. Der Simulator-Artefakt (Bahn B) — GELOEST

**Der Link war die ganze Zeit in Ordnung. Kaputt war die Zusicherung.**

Lauf 12 hat als erster die Annahme geprueft, auf der die Laeufe 4 bis 11
standen — dass `Runner` der Ort ist, an dem die Symbole stuenden. Sie war
falsch:

```
Runner                        52 384 Bytes   qcad=0  occt=0  occtC++=0
Runner.debug.dylib        63 905 296 Bytes   qcad=17 occt=46 occtC++=4538
```

Unter Xcode 26 wird die App in eine **`Runner.debug.dylib`** gebaut; `Runner`
ist ein 52-KB-Startstueck, das sie laedt. Der native Stack ist vollstaendig
verlinkt — 46 `occt_`-Einstiege, 17 `qcad_`-Einstiege, 4538
OCCT-C++-Symbole — und die Pruefung hat acht Laeufe lang das Startstueck
befragt und einen Fehler gemeldet, den es nie gab.

**Damit sind rueckwirkend hinfaellig:** der Verdacht auf
`-exported_symbols_list` (Lauf 10, widerlegt — richtig widerlegt, nur aus dem
falschen Grund gesucht), der pbxproj-Patch (Lauf 11, wirkte, war nie noetig)
und der Schluss „ueber Build-Einstellungen ist der Link nicht erreichbar".
Der Schluss war falsch. `ci/patch_ldflags.py` bleibt als Guertel-und-Hosentraeger
stehen; er schadet nicht, und die Frage, welcher der beiden Wege gewinnt, ist
jetzt ohnehin gegenstandslos.

### Die Lehre, und sie ist nicht die, die Lauf 6 gezogen hat

Lauf 6 schloss: `strings` ohne `-a` sucht unvollstaendig, also nimm `nm`. Das
war eine Verschaerfung der Pruefung — richtig, aber zu klein. Die eigentliche
Lehre lautet:

> **Pruefe, WO du suchst, bevor du haertest, WIE du suchst.**

m5 grept `$APP/Runner`, weil das bei seinem Release-Geraetebuild das ganze
Binary IST. Diese Annahme unbesehen in einen Debug-Simulator-Build unter
neuerem Xcode mitzunehmen, war der Fehler — und er hat sich hinter einer
immer strengeren Pruefung immer besser versteckt. Eine Zusicherung, die aus
einem anderen Kontext stammt, ist im neuen keine gueltige Zusicherung.

Die Pruefung scannt jetzt **jedes Mach-O im Bundle** statt einer geratenen
Datei.

---

## 6a. Wie die Bahn gebaut ist (unveraendert gueltig)

`.github/workflows/sim-perf.yml`, `workflow_dispatch` oder Push auf
`claude/perf-**`. Baut den ganzen nativen Stack fuer **iphonesimulator/x86_64**
nach dem bewaehrten m3-Rezept, baut die Flutter-App dagegen, bootet einen
iPad-Simulator, installiert, startet, laesst die App laufen und **holt
`performance_logs.txt` + `performance_snapshot.json` aus dem Datencontainer
zurueck** (`simctl get_app_container`). Artefakte: `simulator-app` (Runner.app
als Zip) und `perf-capture` (die Logs).

**Warum x86_64:** Das Qt-fuer-iOS-Paket hat als einzige Simulator-Scheibe
x86_64 (der Probe-Schritt in m3 zeigt es: arm64 → Plattform 2 = Geraet,
x86_64 → Plattform 7 = Simulator). Es gibt kein arm64-Simulator-Qt, also
laeuft der ganze Stack x86_64 unter Rosetta auf dem arm64-Runner. Aus demselben
Grund kann der OCCT-Cache nicht mit m5 geteilt werden — anderer Sysroot,
andere Scheibe, eigener Cache-Key.

### Was diese Zahlen wert sind — und was nicht

Flutter lehnt `--profile` und `--release` fuer den Simulator ab
(*„release/profile builds are only supported for physical devices"*); die
Simulator-Engine ist JIT/Debug. Der **Dart**-Teil ist also unoptimiert und
seine Frame-Zeiten sind bedeutungslos.

Der **native** Teil ist es nicht: qcad-core, libslvs und OCCT werden hier mit
`-DCMAKE_BUILD_TYPE=Release` gebaut, genau wie fuers Geraet.

| Aus diesem Job lesen | Aus diesem Job NICHT lesen |
| --- | --- |
| `ffi.occt.*` / `ffi.slvs.*` / `ffi.qcad.*` relativ zueinander | fps, `frame.build`, `frame.raster`, Jank |
| **alle Zaehler** — Aufrufzahlen, Entity-Zahlen, Solves pro Frame, Cache-Quoten | absolute Millisekunden als iPad-Millisekunden |
| strukturelle Regressionen („ruft es jetzt doppelt so oft an?") | alles zur Darstellung |

Wer eine Simulator-Millisekunde als iPad-Millisekunde zitiert, wiederholt den
M75-Fehler in neuem Kostuem. Die Absolutwerte kommen aus Bahn A, vom Geraet.

---

## 7. Als naechstes

1. `sim-perf.yml` einmal laufen lassen, `perf-capture` ziehen — das ist der
   erste echte Datensatz, und er sagt sofort, welche Kernel-Operationen und
   welche Aufrufzahlen aus dem Rahmen fallen.
2. Einen Release-Build aufs iPad, fuenf Minuten normal arbeiten,
   `performance_logs.txt` per Bug-Bundle exportieren — das sind die
   Absolutwerte, gegen die alles andere kalibriert wird.
3. Erst dann Abschnitt 5 schliessen (Menue, Platform-Views, modify/tools).
4. Erst dann `perf/baseline.json` festschreiben und die Schranke ziehen.
5. **Danach** optimieren. Nicht vorher — Regel 1 aus PERF_PLAN.md Abschnitt 5:
   nie ohne Szenarionummer.

---

## 8. M212 — die drei kaputten Fixtures

Der erste Geraetelauf der Selbstfahr-Suite (Build 389, Bundle
`bug20260806T142003`) hat nicht nur Zahlen geliefert, sondern auch drei
Stellen, an denen die Suite **etwas anderes gemessen hat als sie behauptet**.
Eine Fixture, die eine plausible kleine Zahl produziert, ist gefaehrlicher als
gar keine: sie entlastet ein Subsystem, das nie getestet wurde. Alle drei sind
jetzt zu.

### 8.1 `gear.curve` mass 0.000 ms — der Memo

`gearCurve` merkt sich das Ergebnis unter der vollstaendigen geometrischen
Identitaet des Zahnrads. Eine Fixture ist per Definition jedes Mal identisch,
also hat das Szenario **einmal** gerechnet und danach 19 Map-Lookups gemessen —
0.012 ms Wanduhr fuer 20 „Aufrufe". Der Warmup-Durchlauf hat den Cache sogar
schon vor der Messung gefuellt.

Neu: `clearGearCurveCache()` vor jedem Aufruf. Damit misst `gear.curve` die
**kalte** Erzeugung (z transzendente Flankenloesungen plus 4z
Fussrundungen) — das, was ein Teil mit vier Zahnraedern bei jedem Laden zahlt.
Der Trefferpfad wird getrennt als `gear.curve.cached` gemessen; das ist die
Zahl pro Frame. Dazu die Messgroesse `gear.curve.points`: ein ungueltiges
Zahnrad faellt auf seine zwei Rohpunkte zurueck statt zu werfen, und das war
im Timing-Report nicht von „schnell" zu unterscheiden.

### 8.2 `dofColour` ~0 statt 85% — eine Skizze, die niemand zeichnet

Die Faerbung im Painter haengt komplett an einem Guard:

```dart
bool segFull(int i, int seg) => hasAnalysis && app.analysis!.carrierFixed(i, seg);
```

Die Fixture hatte 0.5 Constraints pro Entity (nur `equal` zwischen benachbarten
Kreisen, sonst voellig unabhaengige Geometrie) und **gar keine Analyse**. Der
Guard ist also auf dem ersten Term kurzgeschlossen — fuer jede Entity, in jedem
Frame. Gemessen wurde eine Skizze, die so nie entsteht.

Neu — `constraintFixture` baut jetzt die Dichte der Geraeteskizze (142
Constraints auf 96 Entities, ~1.5 pro Entity) und vor allem die **Kopplung**:

* `coincident` bindet beide Enden jeder Linie an die Mittelpunkte der Kreise,
  die sie verbindet — 2n, und der Grund, warum das System *eine*
  Zusammenhangskomponente ist statt n winziger;
* `equal` ueber benachbarte Kreise — n−1;
* ein `fix` als Erdung, sonst bleiben die drei Starrkoerpermoden und **jeder**
  Carrier kommt lose zurueck (genauso degeneriert wie „alle fest");
* eine Radiusbemassung.

`_appWithSketch` haengt die Constraints an das SketchModel **und** setzt
`app.analysis = analyzeSketch(...)`. Die Analyse entsteht bewusst im
Fixture-Aufbau und nicht im gemessenen Block: die App hat sie fertig, wenn sie
malt, also waere sie dem Painter angelastet Arbeit, die der Painter nicht tut.
Die Fixtures werden pro Groesse gecacht, damit der Aufbau in den
Warmup-Durchlauf faellt.

**Nebenbefund:** `analyzeSketch` war bis hierhin voellig unvermessen. Es baut
eine **Finite-Differenzen-Jacobi-Matrix** (eine volle Residuenauswertung *pro
Parameter*) und reduziert sie dann zeilenweise — und laeuft bei jedem Rebuild,
jedem Solve und jedem Tab-Wechsel. Neu: Span `sketch.analyze` plus
`analyze.entities` / `analyze.constraints` / `analyze.dof`, und ein eigener
Sweep `analysis.sweep.{8,24,64}`. Wenn eine grosse Skizze zaeh ist, stand die
Antwort bisher nirgends im Report.

### 8.3 `2d.snap` tauchte nie auf — die Messstelle fehlte

`ui.snapHover` rief `app.setHover(...)` auf. Das ist die **zweite** Haelfte des
Pointer-Move-Pfads; das Snapping selbst lag in `_snapped` und damit in
`_Viewport2DState`, also unerreichbar fuer alles ausser einer echten Geste.
Ergebnis: `2d.snap` stand in **keinem** einzigen Report, den die Suite je
erzeugt hat, und die Phase las sich als kostenlos.

Der Rumpf ist jetzt top-level (`snapViewportForBenchmark`), und `_snapped`
delegiert dorthin — **nicht** umgekehrt. Diese Richtung ist der Punkt: eine
Benchmark-Kopie haette eine Zahl fuer die Kopie geliefert. Das Szenario faehrt
jetzt die echte Reihenfolge, erst snappen, dann das Ergebnis als Hover
veroeffentlichen.

### 8.4 Zwei Folgekorrekturen

* `solve.drag60` und `ui.drag60` ziehen jetzt an **Entity 1**, nicht 0 — Kreis
  0 ist die Erdung der Fixture, und einen fixierten Punkt zu wuenschen misst
  den Solver beim Scheitern.
* `solve.drag60` **bewegt** den Griff pro Frame. `dragged` sagt nur, *welcher*
  Punkt gehalten wird, es traegt keine Position; ein unveraendertes, bereits
  erfuelltes System 60-mal zu loesen misst den Boden, nicht einen Zug. Die
  `solve.sweep.*` messen weiterhin genau diesen Boden — das ist ehrlich so
  benannt und ist der haeufigste Fall in einer Sitzung.

### Was das fuer die alten Zahlen heisst

`solve.*`, `gear.curve.*` und alle `ui.*` aus Build 389 sind **nicht** mit den
neuen vergleichbar — die Eingabe hat sich geaendert. Das ist der Preis dafuer,
dass die Eingabe vorher falsch war. Die Kernelzahlen (`kernel.*`, insbesondere
der quadratische `allEdges`-Befund) sind unberuehrt.

---

## 9. Der erste Lauf mit reparierten Fixtures (Build 7fb7f8b, Geraet, M4)

Bundle `bug20260806T155703`, iPadOS 27.0, OCCT-Shim v16, Qt 6.7.3.
Leeres Dokument — der Wert steckt komplett in der Selbstfahr-Suite.

Sitzung selbst gesund: 807 Frames, 93.5 fps, 2 Jank-Frames, Start bis erstem
Frame 76.6 ms.

### 9.1 gear.curve — repariert, und Zahnraeder sind entlastet

| Zaehne | Punkte | kalt | Cache-Treffer (200x) |
| ---: | ---: | ---: | ---: |
| 10 | 640 | 0.129 ms | 0.000 ms |
| 20 | 1200 | 0.257 ms | 0.000 ms |
| 40 | 2160 | 0.495 ms | 0.000 ms |

Exakt linear in der Punktzahl (~0.21 us/Punkt), und der Memo traegt: 200
Treffer sind zusammen nicht messbar. Die vier 20-Zahn-Raeder aus Part2 kosten
zusammen rund **1 ms, einmal**. Kein Verdaechtiger.

### 9.2 dofColour — repariert, und die Diagnose kippt

Statisches Malen, 128 Entities: `ent.dofColour` = 0.0008 ms = **0.7%**.
Waehrend eines Zugs, 48 Entities: `ent.dofColour` = 0.1414 ms = **43.3%**.

Und `2d.displayGeometry` misst im selben Szenario 0.1412 ms. Das ist keine
Aehnlichkeit, das ist dieselbe Arbeit: **die Phase heisst falsch.** Zwischen
`mark('editRef')` und `mark('ent.dofColour')` liegen sechs Paint-Objekte und
`app.displayGeometry(s)` — also der DRAG-SOLVE, der in `CustomPainter.paint`
laeuft. Die eigentliche Faerbung (`carrierFixed` pro Entity) steckt in der
Phase `entities` und kostet 0.11 ms bei 128 Entities, ungefaehr linear.

Damit ist die Lesart aus dem Geraetelauf zu korrigieren: „dofColour war 85% des
Malens" hiess **„der Solve im Painter war 85% des Malens"**, nicht „die
DOF-Faerbung ist teuer".

**Und die zwei Solves pro Frame sind jetzt lokalisiert.** 60 gemalte Frames,
`2d.displayGeometry.solves` = 120. Die Phase `constraints` springt von 0.0011 ms
(statisch) auf 0.1426 ms (im Zug) — Faktor 130. Beide Aufrufe stehen im
Painter:

* `viewport.dart:2088` — im Segment `ent.dofColour`
* `viewport.dart:2683` — im Segment `constraints` (`gs2`)

Jeder loest waehrend eines Zugs komplett neu. Zusammen sind das 87% der
Malzeit im Zug fuer *eine* Antwort, die zweimal berechnet wird.

### 9.3 2d.snap — repariert, und ebenfalls entlastet

| pro Pointer-Move | |
| --- | ---: |
| `2d.snap` | 0.0044 ms |
| `2d.pickEntity` | 0.0234 ms |

Snapping ist **5x billiger** als das Picken daneben. Die Phase, die nie in
einem Report stand, ist die guenstigste im Pfad.

### 9.4 NEUER BEFUND — analyzeSketch ist die superlineare Stelle

| Entities | Constraints | DOF | `sketch.analyze` |
| ---: | ---: | ---: | ---: |
| 16 | 25 | 14 | 0.101 ms |
| 48 | 73 | 46 | 0.934 ms |
| 128 | 193 | 126 | **15.694 ms** |

Exponent 16→48: **n^2.04**. Exponent 48→128: **n^2.88**. Der Exponent
*steigt* — die kubische Zeilenreduktion uebernimmt, sobald das System gross
genug ist. Hochgerechnet: ~430 ms bei 400 Entities, ~6 s bei 1000.

Das laeuft bei **jedem Rebuild, jedem Solve und jedem Tab-Wechsel**
(app_state.dart:2163, :2183, :6486). Es ist der beste Kandidat fuer „in 2d habe
ich komplexes Zeug gezeichnet und es war buggy" — und es stand bis M212 in
keinem Report.

### 9.5 Der Solver ist entlastet — mit Zahlen

`ffi.slvs.solve` bei 128 Entities / 193 Constraints: **0.725 ms**. Im Zug bei 48
Entities: 0.114 ms. 420 Solves der ganzen Sitzung: avg 0.169 ms, p95 0.148 ms.

Die 27 ms avg / 3.92 s worst vom ersten Geraetelauf sind damit **nicht
groessenbedingt**. Es bleibt eine Konfiguration, keine Skalierung — und
weiterhin offen.

### 9.6 allEdges — dritte unabhaengige Bestaetigung

| Kanten | `allEdges` | pro Kante | `edgeInfo.calls` |
| ---: | ---: | ---: | ---: |
| 36 | 7.00 ms | 194 us | 36 |
| 144 | 99.66 ms | 692 us | 144 |
| 360 | 607.13 ms | 1687 us | 360 |

Kanten x4.0 → Zeit x14.2 (n^1.92); x2.5 → x6.09 (n^1.97). Die Aufrufzahl ist
**exakt** die Kantenzahl, also genau ein FFI-Uebergang pro Kante — die
Quadratik sitzt vollstaendig im C++, nicht an der Grenze. `repeat` (5x auf
demselben Solid) bleibt bei 99.4 ms Schnitt: kein wiederverwendbarer Aufbau.

Hochgerechnet auf Part2 (~3400 Kanten): **~48 s**. Das ist der Absturz.

`kernel.fillet`: das Finden der Kandidaten (25.56 ms) kostet **2.4x** so viel
wie das Verrunden selbst (10.80 ms).

### 9.7 Rangliste nach diesem Lauf

1. `occt_shape_edge_info` — quadratisch, 48 s auf einem echten Teil, Absturz.
2. `analyzeSketch` — n^2.9, laeuft bei jedem Rebuild/Solve/Tabwechsel.
3. Doppelter `displayGeometry` im Painter — 2 Solves pro gezogenem Frame.
4. Unerklaerte Solver-Spitze (3.92 s) — reproduzierbar noch nicht eingefangen.

Entlastet, mit Zahlen: Zahnradgenerierung, Snapping, DOF-Faerbung, Booleans,
Tessellierung, `allGeometry`, Ribbon-Rebuilds, Start.

---

## 10. M213 — die systematische Runde: was jetzt gemessen wird

Nach M212 waren die drei kaputten Fixtures zu, aber die Abdeckung war schmal:
21 Szenarien gegen rund 45 Werkzeuge, 10 Feature-Arten und ein Dutzend
Dokumentoperationen. "Zeichnen fuehlt sich langsam an" war damit nicht bloss
unbeantwortet — es war **unbeantwortbar**, weil fuer den Akt des Zeichnens
keine Zahl existierte.

Jetzt: **73 Szenario-Definitionen** (mit den Sweeps darin deutlich mehr
Einzelmessungen) in fuenf Modulen, plus 43 neue Span-Namen.

### 10.1 Was neu abgedeckt ist

| Bereich | vorher | jetzt |
| --- | --- | --- |
| Zeichenwerkzeuge | — | alle aus `toolMeta`, generisch getrieben; Spline-Konstruktion UND -Auswertung nach Groesse; Freihand nach Strichlaenge |
| 2D-Fillet/Chamfer | — | `filletInventor`, `chamferInventor`, `filletMaxRadius` |
| Modify | — | trim, trimCutAway, extend, split, offset (einzeln + Kette), transform, stretch, `intersections` — gegen Gittergroesse |
| Constraints | nur Solver + DOF | alle 12 Typen einzeln, Inferenz nach Skizzengroesse, Sidecar-Codec, solve-aus-verletzt, ueberbestimmt |
| 3D-Kernel | 6 Operationen | Extrude x4, Revolve x2, Sweep x3, Loft x2, Coil, Fillet x2, Chamfer, Booleans nach Operandenkomplexitaet + 8er-Fusionskette, Unify, Transform, rayHits, Mesh auf zwei Achsen, plus die Billig-Query-Kontrolle |
| App-Pfade | — | Muster (3 Arten), Undo-Journal, Szenen-Payload + Signatur, Projektion, 3D-Kantenpicken, Mesh-Diagnose, Dokument-Codec, qcad-Neuaufbau |

### 10.2 Zwei Entwurfsentscheidungen, die ueber die Belastbarkeit entscheiden

**Werkzeuge werden aus `toolMeta` getrieben, nicht aus einer Liste.** Ein neues
Werkzeug erscheint ohne neues Szenario im Report. Eine handgepflegte Liste
waere beim ersten neuen Werkzeug veraltet gewesen — und ein veralteter
Benchmark ist schlimmer als ein fehlender, weil er vollstaendig aussieht.

**Platten-I/O ist bewusst draussen.** Die Wandzeit von `savePart` wird von
iOS-Datei-I/O beherrscht, das mit dem Speicherdruck schwankt und im Code nicht
reparierbar ist. Reparierbar ist die Serialisierung davor und danach — die
wird gemessen. Eine Zahl, die sich aus Gruenden ausserhalb des Codes bewegt,
erzeugt Regressionen, die niemand verursacht hat.

### 10.3 Die Falle, in die ich gelaufen bin

Der Shim hat **zwei Profilkodierungen**: `extrudeProfile` und
`extrudePolygon` nehmen (x, y)-PAARE, `extrudeProfileArcs`, `revolve`,
`sweep`, `loft` und `coil` nehmen (x, y, bulge)-TRIPEL. Die falsche zu
uebergeben wirft nicht — die Stelligkeitspruefung gibt null zurueck, das
Szenario meldet eine schnelle Null, und die Operation liest sich als
kostenlos. Jeder Kernelaufruf laeuft deshalb durch einen Waechter, der Nulls
zaehlt, und der Abdeckungstest verlangt, dass diese Zaehler leer sind.

### 10.4 Der Abdeckungstest hat sich sofort bezahlt gemacht

Beim ersten Lauf fielen drei Werkzeuge durch — sie gaben null zurueck und
wurden trotzdem getimt, also als waeren sie die guenstigsten im ganzen
Programm:

* **eqCurve** — `ExprParser` nimmt EINE Funktion einer Variablen `x`; die
  Fixture uebergab ein parametrisches Paar, das Komma wurde abgelehnt.
* **circleTangent** — braucht drei Klicks auf drei VERSCHIEDENE Linien; auf
  der Ring-Fixture landeten die generischen Punkte mehrfach auf derselben.
* **slotOverall** — verlangt Laenge > 2 x Breite.

Genau die M212-Fehlerart, reproduziert in neuem Code. Deshalb pruefen diese
Tests keine Zeiten, sondern **dass jedes Szenario sein Thema erreicht**.

Und: Test und Szenario laufen jetzt durch DENSELBEN Einstiegspunkt. Den Aufruf
im Test nachzubauen ist der Weg, auf dem ein Test gruen bleibt, waehrend der
Benchmark, den er absichern soll, etwas anderes misst.

### 10.5 Sichtbarkeit der CI-Fehler

Der GitHub-Reporter macht pro Test eine Log-Gruppe; bei ~1600 Tests ist das
Log zehntausende Zeilen lang, die Actions-API liefert nur einen begrenzten
Tail, und das Artefakt liegt auf Blob-Storage ausserhalb der Proxy-Freigabe.
Ein roter Build meldete "2 failed" ohne erreichbare Information WELCHE zwei.
Ein `if: failure()`-Schritt gibt die Fehlerzeilen jetzt am Ende noch einmal
aus, wo jeder Tail sie erreicht.

### 10.6 Was weiterhin fehlt

Ehrlich benannt, damit die Abdeckung nicht groesser aussieht als sie ist:

1. **Im C++ selbst.** Wir wissen, dass `allEdges` bei 360 Kanten 607 ms
   kostet; wir wissen nicht, welche Zeile des Shims das ausgibt.
   `kernel.query.edgeInfoOne` grenzt es von aussen ein — mehr geht von Dart
   aus nicht.
2. **Der RealityKit-Renderloop.** Platform View, von Dart aus unsichtbar. Die
   Payload-Szenarien messen alles bis zur Grenze.
3. **Thermik, CPU pro Thread, echter Speicherabdruck, Absturzursache.**
   Brauchen ein natives Plugin (MetricKit / `mach_task_basic_info`); existiert
   noch nicht.
4. **Feature-Rebuild Ende-zu-Ende.** `part.rebuildAll` und
   `kernel.feature.<kind>` sind jetzt instrumentiert, laufen also in einer
   echten Sitzung mit — aber es gibt noch kein Szenario mit fester Eingabe,
   das eine Feature-Kette selbst neu berechnet.

---

## 11. M214 — die Wurzelursache im Quelltext, und was die Maschine selbst sagt

### 11.1 allEdges: nicht mehr gemessen, sondern gefunden

Drei unabhaengige Messungen sagten „quadratisch". Der Quelltext sagt jetzt
**warum**. `occt_shape_edge_info` in `backend/occt/shim/occt_capi.cpp` macht
**pro Aufruf zwei vollstaendige Topologie-Durchlaeufe**:

```cpp
// Zeile 1679 — die Kantenkarte, nur um den Index aufzuloesen
TopTools_IndexedMapOfShape m;
TopExp::MapShapes(shape->s, TopAbs_EDGE, m);

// Zeile 1733 — die Kante-zu-Flaeche-Nachbarschaft, der teure Teil
TopTools_IndexedDataMapOfShapeListOfShape edgeFaces;
TopExp::MapShapesAndAncestors(shape->s, TopAbs_EDGE, TopAbs_FACE, edgeFaces);
```

Der zweite laeuft ueber **jede Flaeche und jede Kante jeder Flaeche**, baut die
komplette Nachbarschaftskarte auf — und wirft sie am Ende des Aufrufs weg.
`allEdges()` ruft die Funktion einmal pro Kante auf:

> n Kanten x O(n) Durchlauf = **O(n^2)**

Das deckt sich exakt mit den gemessenen n^1.92 und n^1.97, und es erklaert,
warum `kernel.allEdges.repeat` flach bleibt: es gibt keinen wiederverwendbaren
Aufbau, weil der Aufbau pro Aufruf neu passiert.

**Nicht repariert** — die Regel steht seit dem ersten Auftrag. Die Reparatur
gehoert in den Shim (ein Durchlauf, der ein Array fuellt, als
Bulk-Einstiegspunkt), nicht in Dart-seitiges Batching: das wuerde die Anzahl
der Grenzuebergaenge senken und die Quadratik unberuehrt lassen.

`kernel.query.edgeInfoOne` misst weiterhin von aussen gegen: EIN `edgeInfo`
auf einem 360-Kanten-Solid, mal 360 gegen das gemessene `allEdges` gehalten.
Stimmen die ueberein, ist der Befund oben von zwei Seiten bestaetigt.

### 11.2 Was die Maschine selbst sagt (PerfProbe.swift)

Bisher endete jede Messung an der Dart-Grenze. Drei Fakten, die darueber
entscheiden, ob eine M4-Zahl etwas ueber einen M2 aussagt, liegen dahinter:

| Messwert | warum er fehlt, wenn er fehlt |
| --- | --- |
| `thermalState` / `thermalOrdinal` | Ein luefterloses iPad drosselt unter anhaltender Last — und die Suite IST anhaltende Last. Ohne Wert an beiden Enden ist eine langsame zweite Haelfte nicht von langsamem Code zu unterscheiden. |
| `footprintMB` (`phys_footprint`) | iOS killt **nicht** auf RSS. Die Sitzung, die beim Fillet starb, meldete 839 MB RSS; die Zahl, auf die es ankam, wurde nie erfasst. |
| `availableMB` (`os_proc_available_memory`) | Wie viel Luft bis jetsam bleibt. Ein Teil, das mit 40 MB Rest oeffnet, ist ein Fillet vom Abschuss entfernt. |
| `threads` (CPU pro Thread) | „180% CPU" sagt nicht, ob UI-Thread, Rasterizer oder IO gemeint ist — und die drei repariert man an verschiedenen Stellen. |
| `physicalMemoryMB`, `lowPowerMode`, `activeProcessorCount` | Geraeteklasse und Energiezustand: der Unterschied zwischen 8-GB-A-Chip und 16-GB-M4 entscheidet mit, welche Teile ueberhaupt zu oeffnen sind. |

`Perf.native` ist eine **eigene** Tabelle, bewusst nicht in `gauges` gefaltet.
Das sind keine Eigenschaften der App, sondern der Maschine, auf der sie gerade
laeuft. Ein Leser muss „der Code wurde langsamer" von „das iPad wurde heiss"
trennen koennen — die Tabellen zu vermischen ist genau der Weg, auf dem diese
Unterscheidung verlorengeht.

Das Bundle zieht die Probe **vor und nach** der Suite (`preSuite.*`,
`postSuite.*`). Ein Thermalzustand, der ueber den Lauf von `nominal` auf
`serious` gestiegen ist, entwertet jeden Vergleich mit den Zahlen aus der
zweiten Haelfte — und das ist nur mit beiden Enden sichtbar.

Bewusst NICHT gebaut: Sampling-Profiler, MetricKit-Abo, os_signpost. Die
brauchen einen Lebenszyklus und einen Zustellweg; das hier ist ein
Pull-Snapshot, den Szenariorunner und Bug-Bundle jederzeit ziehen koennen.

### 11.3 Der Ende-zu-Ende-Rebuild

`app.rebuildPart.{1,3,6}` treibt `recomputeAllFeatures` selbst — die
Orchestrierung ueber den Kernelaufrufen: Profilanordnung, Signatur-Hashing,
die Boolesche Faltung auf den wachsenden Koerper, Mesh-Copy-out, und der
Zusatzdurchlauf, den eine verschobene flaechenverankerte Skizze erzwingt.

Erzwungen (`force: true`), sonst ueberspringt die Build-Signatur den zweiten
Durchlauf und das Szenario misst einen Hash-Vergleich.
`part.rebuildAll` gegen die Summe der `kernel.feature.*` gehalten ergibt den
Dart-Anteil; `part.rebuild.passes` sagt, ob die Schleife mehr als einmal lief.

Damit ist Punkt 4 aus Abschnitt 10.6 zu. Offen bleiben 1 (das Innere des
C++ — jetzt aber durch Quelltextbefund statt Messung beantwortet), 2 (der
RealityKit-Renderloop) und der Sampling-Profiler.
