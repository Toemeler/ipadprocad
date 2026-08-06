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

## 6. Der Simulator-Artefakt (Bahn B) — STAND: GEPARKT, ungeloest

**Kurz: die App baut, aber der native Stack landet nicht im Binary. Sieben
CI-Laeufe haben die Ursache eingekreist und nicht gestellt.**

Was funktioniert (alles bewiesen, nicht vermutet):

| Schritt | Stand |
| --- | --- |
| qcad-core, libslvs, OCCT, Shim fuer iphonesimulator/x86_64 | gruen |
| xcconfig-Injektion inkl. der ninja-Link-Zeile | gruen |
| Flutter-Scaffold, analyze, 1533 Host-Tests | gruen |
| `Runner.app` baut, x86_64, 61 MB, als Artefakt hochgeladen | gruen |
| **Verlinkung des nativen Stacks** | **FEHLT** |

Der Diskriminator aus Lauf 7 sagt: `nm -a` findet im Runner-Binary
**70 Symbole insgesamt** und **null** occt_/qcad_/OCCT-C++-Symbole. Ein
Binary mit force_geladenem OCCT haette Zehntausende. `-force_load` ist also
nie ausgefuehrt worden — und zwar obwohl jede einzelne Voraussetzung stimmt:

* Die drei Archive existieren, sind x86_64, ihre Member tragen platform 7 /
  minos 14.0 / sdk 26.5.
* Der Marker steckt nachweislich IM Archiv.
* `#include "ffi.xcconfig"` steht zur BAUZEIT in `Debug.xcconfig`.
* Im pbxproj gibt es **kein** target-eigenes `OTHER_LDFLAGS`, das die
  xcconfig stechen koennte — der Hauptverdacht ist ausgeschlossen.
* `xcodebuild -showBuildSettings` loest `OTHER_LDFLAGS` MIT allen drei
  `-force_load` und saemtlichen OCCT-Archiven auf.
* `ld` hat kein einziges `ignoring file` gemeldet.

Xcode meldet das Flag also und benutzt es nicht. Was dazwischen passiert,
ist aus der Ferne nicht mehr zu klaeren: `flutter build -v` gibt die echte
`Ld`-Zeile nicht aus (die einzigen force_load-Vorkommen im ganzen Log sind
unsere eigenen Diagnose-Echos), und damit fehlt das entscheidende
Beweisstueck.

### Die drei geplanten Schritte sind abgearbeitet — alle drei negativ

**Schritt 1 (Lauf 9): die echte Ld-Zeile holen.** Fehlgeschlagen, aber nicht
inhaltlich: ein direkter `xcodebuild` scheitert ohne Flutters
Skriptphasen-Umgebung. Die Ld-Zeile ist auf diesem Weg nicht zu bekommen.

**Schritt 2a (Lauf 10): `-exported_symbols_list` weglassen.** Das war die
Hypothese „force_load laedt die Member, und der Linker wirft sie als
verborgen+unreferenziert wieder weg". Ergebnis Zeichen fuer Zeichen
identisch — 70 Symbole, null occt_/qcad_. **Hypothese widerlegt**, der Zweig
„geladen und danach gestrippt" ist aus. Das Flag ist wieder drin.

**Schritt 2b (Lauf 11): OTHER_LDFLAGS aufs Target schreiben**
(`ci/patch_ldflags.py`). Der Patch greift nachweislich: Diagnose 0c zeigt die
Flags in FUENF pbxproj-Konfigurationen, und sie ueberleben bis nach dem Build.
Ergebnis trotzdem unveraendert: 70 Symbole, null occt_/qcad_.

**Damit ist der Befund so scharf, wie er aus der Ferne werden kann:** die
Flags stehen in der xcconfig UND im pbxproj, `xcodebuild -showBuildSettings`
loest sie auf, `ld` laeuft fuers Runner-Target und meldet kein
`ignoring file` — und im Binary ist trotzdem nichts davon. Ueber
Build-Einstellungen ist der Link auf dieser Bahn nicht zu erreichen.

### KORREKTUR: die arm64-Ausweichloesung hilft hier NICHT

Weiter oben stand, der naechste Schritt sei arm64 ohne Qt und qcad-core. Das
war richtig gegen das RISIKO, das dort gemeint war (Rosetta beim Starten),
und es ist falsch gegen DIESEN Fehler: OCCT und libslvs kaemen ueber genau
dieselbe `OTHER_LDFLAGS`-Route herein, die nachweislich nicht ankommt. Eine
andere Architektur repariert keinen Mechanismus.

### Was tatsaechlich weiterfuehrt

1. **Ein lokaler Build**, bei dem sich DerivedData und die echte clang-Zeile
   ansehen lassen. Das ist die billigste Antwort — und die einzige, die diese
   Sitzung strukturell nicht liefern konnte, weil Flutter die Ld-Zeile
   unterdrueckt und ein nackter `xcodebuild` ohne Flutters Umgebung nicht
   laeuft.
2. **Die Verlinkung anders bauen:** den nativen Stack als
   `.xcframework`/dynamisches Framework paketieren und wie eine normale
   Abhaengigkeit einbinden, statt statische Archive per `-force_load` durch
   `OTHER_LDFLAGS` zu schieben. Das umgeht die Frage vollstaendig, statt sie
   zu beantworten — und es ist der Weg, den ein iOS-Projekt ohnehin
   normalerweise geht.

Was **nicht** weiterfuehrt: eine weitere Runde am selben Mechanismus. Elf
Laeufe haben jede erreichbare Stellschraube daran geprueft.

**Zwei Fehler in diesem Verlauf, protokolliert damit sie nicht wiederkommen:**

* Der erste Runner war `macos-14`, gewaehlt „wie m3". m3 kompiliert aber nur
  den C++-Smoke und nie die Swift-Plugins der App; die brauchen den
  iOS-26-SDK (`UnlitMaterial.faceCulling`, bereits mit `#available`
  abgesichert — ein LAUFZEIT-Guard hilft beim Kompilieren nicht).
* Nach Lauf 5 stand hier, der Link sei in Ordnung und nur die Zusicherung
  falsch, weil `strings` ohne `-a` unvollstaendig sucht. Das war ein
  Fehlschluss: mit `-a` ist das Ergebnis dasselbe (0). Die symbolbasierte
  Pruefung war trotzdem die richtige Aenderung — sie hat den Irrtum
  aufgedeckt.
* `actions/cache` deklariert `post-if: success()` und speichert daher nur bei
  gruenem Job. Weil dieser Job jedes Mal scheiterte, lief der
  35-Minuten-OCCT-Build in JEDEM Anlauf neu. Behoben durch getrenntes
  `cache/restore` + `cache/save` mit `if: always()`; ab Lauf 7 ist der Baum
  gespeichert.

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
