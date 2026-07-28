# HANDOFF — Prototype

Übergabestand für die Fortsetzung in einem neuen Chat.

## Projekt
- 2D-CAD für iPad. Frontend: Flutter. Backend: QCAD-Core (C++, GPLv3) per FFI.
- Ziel-Repo: `github.com/Toemeler/ipadprocad`
- Upstream: `github.com/qcad/qcad` (Details: `backend/qcad-core/VENDOR.md`)
- **Nur echten Status berichten** — nie „grün" behaupten, was nicht gebaut wurde.
  CI-Logs lesen, grüner Haken reicht nicht (tee/pipefail-Fallen, siehe unten).

## Auth/Push
PAT wird pro Session neu erzeugt und danach widerrufen. Push nur inline:
`git push https://<PAT>@github.com/Toemeler/ipadprocad.git HEAD:main`
Token NIE in Dateien/.git/config schreiben.

## Meilenstein-Status

> **M100 — EOP-Ziehen: die eigentliche Ursache. Und der Hover zeigt jetzt die
> ANTWORT statt eines zweiten Highlights.**
>
> **(1) Warum das Ziehen NIE ging.** Nicht die Slot-Mathematik (die war nach M99
> in Ordnung) — die Zeile liegt in der ListView des Browsers, und ein
> `onVerticalDrag*` eines GestureDetector muss die **Gesten-Arena** gegen das
> Scrollable gewinnen. Die Liste gewann jedes Mal: der Baum scrollte, die Marke
> bewegte sich nie. Deshalb hat ausschliesslich der Menue-Weg funktioniert —
> im Log des Nutzers steht genau ein `End of Part -> after 0 of 3`, und das kam
> von *Move to Top*. Der Zug laeuft jetzt ueber **rohe Pointer-Events auf einem
> Listener**; der nimmt an der Arena gar nicht teil und sieht jedes Event.
> Ein Tipp ohne Weg (< 4 px) committet nichts.
>
> **Logging drin gelassen**, weil das der zweite Anlauf ist und der erste im
> Quelltext richtig aussah: `eop DOWN/MOVE/UP/CANCEL` mit Kind, dy, Delta und
> Slot. Sollte es wieder klemmen, sagt eine einzige Zeile, ob ueberhaupt
> Pointer ankommen oder ob nur die Slot-Rechnung falsch liegt.
>
> **Achtung fuers naechste Mal:** die End-of-SKETCH-Zeile haengt noch am
> GestureDetector und hat damit dasselbe Problem — falls sie sich auch nicht
> ziehen laesst, ist es dieselbe Ursache und dieselbe Loesung.
>
> **(2) Doppel-Highlight beim Koerper-Picken.** Der gehoverte Koerper bekam das
> Preview-Material OBENDRAUF auf die ohnehin gezeichnete Extrusions-Vorschau —
> zwei ueberlagerte Hervorhebungen auf demselben Solid, und genau das sah
> "really off" aus. Der Tint ist weg. Stattdessen zeigt der Hover jetzt die
> **Antwort**: das Ziel der Session wandert auf den gehoverten Koerper und die
> Vorschau wird neu gerechnet — ueber Solid1 sieht man das Ergebnis mit Solid1,
> ueber Solid2 das mit Solid2. Verlaesst man den Hover ohne zu picken, wird das
> vorherige Ziel zurueckgesetzt; Hovern allein darf das Feature nicht
> umhaengen.
>
> **Neu/berührt:** `widgets/model_browser.dart`, `app_state.dart`,
> `reality_scene.dart`.

> **M99 — Vier Nachbesserungen aus dem Extrude-/EOP-Bericht.**
>
> **(1) EOP liess sich GAR NICHT ziehen.** Meine Schnappschuss-Loesung aus M96
> war zweifach falsch. Sie mass Zeilen-Rechtecke, und das haengt daran, dass
> JEDER Feature-Zeilen-GlobalKey einen fertig gelayouteten Context hat — eine
> eingeklappte oder weggeclippte Zeile hat keinen, ihr Mittelpunkt fiel auf
> einen Sentinel zurueck und der Slot schnappte ans Ende. Jetzt wird gar nichts
> mehr gemessen: der Versatz ist `(dy - dyStart) / Zeilenhoehe`, gerundet, auf
> `[0, n]` geklemmt. Nichts nachzuschlagen, nichts das sich unter dem Finger
> bewegen kann.
>
> **(2) Namensfeld nur noch bei New Solid.** Join, Cut und Intersect arbeiten
> auf einem BESTEHENDEN Koerper; dort ein Namensfeld anzubieten lud dazu ein,
> etwas einzutippen, das nichts tut.
>
> **(3) Dropdown ersatzlos weg.** Der Zielkoerper wird gepickt, nicht aus einer
> Liste gesucht — genau den Schritt ersetzt der Pick. Stattdessen zeigt eine
> Zeile den AKTUELLEN Zielkoerper, darunter der Pick-Knopf (jetzt fuer Join,
> Cut UND Intersect, nicht nur Join).
>
> **(4) Browser leuchtete, 3D nicht.** Der Renderer setzt das Material,
> WAEHREND er das Mesh baut — ein Payload, das nur das Material aendert und
> `includeGeometry: false` traegt, wurde still ignoriert. Waehrend eines Picks
> reisen die Solids darum mit Geometrie. Bewusst ALLE, nicht nur der gehoverte:
> wandert der Hover weiter, muss der vorher leuchtende Koerper sein
> Stahl-Material zurueckbekommen, und auch das passiert nur mit Geometrie.
>
> **NOCH OFFEN:** der Nutzer meldet, dass die Auswahl **in 3D** gar nicht
> reagiert. Der Zweig sitzt in `viewport3d._tap` VOR allen anderen, also liegt
> der Verdacht darauf, dass Taps bei offenem Extrude-Dialog den Viewport nicht
> erreichen (Dialog-Overlay faengt sie) — das ist am Geraet in einer Minute zu
> sehen und blind nicht zu entscheiden. Naechster Schritt: im Tap-Pfad loggen
> und pruefen, ob `_tap` waehrend `pickingBody` ueberhaupt gerufen wird.

> **M98 — Der gehoverte Koerper leuchtet jetzt auch in 3D.** Die in M97 offen
> gelassene Luecke ist zu: waehrend `pickingBody` bekommt der Koerper unter dem
> Zeiger das PREVIEW-Material, also dieselbe Hervorhebung, die die Browserzeile
> tintet. Beide Seiten lesen `app.hoverBody` — sie koennen nicht auseinander
> laufen.
>
> **Ganzer KOERPER, nicht ein Feature.** `visibleSolids` schluesselt Solids nach
> FEATURE-Namen; ein Koerper ist der Name, in den mehrere Features bauen.
> `_bodyIsHovered` loest das auf, sonst wuerde nur das Feature aufleuchten, ueber
> dem der Zeiger zufaellig steht — und ein Join aus drei Extrusionen saehe
> zerrissen aus.
>
> **Signatur.** Der Hover muss die Szenensignatur bewegen, sonst wird kein
> Rebuild geschickt und es leuchtet gar nichts (dieselbe Falle wie M95). Das
> Feld ist nur waehrend des Pickens gefuellt, gewoehnliches Hovern kostet also
> nichts — im Test festgenagelt: Signatur vor dem Picken == Signatur nach dem
> Abbrechen.
>
> **Zur Performance-Sorge aus M97:** `_pickSolidFace` laeuft nur, WAEHREND ein
> Pick armiert ist — sonst ist der Zweig ein einzelner bool-Test. `setHoverBody`
> kehrt bei unveraendertem Namen sofort zurueck, eine Bewegung ueber EINEN
> Koerper repaintet also einmal, nicht pro Frame. Ob das am Geraet reicht,
> zeigt erst das Geraet; wenn nicht, ist die naechste Stufe ein Zeit-Throttle
> auf dem Pick, nicht mehr Payload.
>
> **Neu/berührt:** `reality_scene.dart`, `widgets/viewport3d.dart`, Test
> ergaenzt in `test/m97_pick_body_test.dart`.

> **M97 — Zielkoerper ANKLICKEN statt Dropdown + Koerper-Kontextmenue.**
> Damit sind die beiden in M96 offen gelassenen Punkte erledigt.
>
> **Auswahlmodus.** `AppState.pickingBody` / `hoverBody` + `beginPickBody`,
> `cancelPickBody`, `setHoverBody`, `pickBody`. Der Extrude-Dialog bekommt bei
> mehr als einem Koerper einen Knopf "Select body in 3D / browser"; das
> Dropdown bleibt fuer Tastatur/Praezision. **Der Hover liegt bewusst auf
> AppState** — deshalb leuchtet dieselbe Auswahl GLEICHZEITIG in 3D und im
> Model Browser, beide lesen `app.hoverBody`, sie koennen also nicht
> auseinanderlaufen.
>
> 3D: der Body-Pick laeuft VOR allem anderen im Tap-Pfad — solange der Dialog
> wartet, heisst ein Tipp auf einen Koerper "diesen", nicht "auf dieser Flaeche
> skizzieren". Ein Tipp ins Leere bricht ab, wie Esc. Browser: die Koerperzeile
> wird zum Pick, mit Hover-Tint und Zeiger-Cursor; ausserhalb des Modus
> verhaelt sie sich unveraendert.
>
> `pickBody` schaltet zusaetzlich von "New Solid" auf **Join** um: einen
> Zielkoerper zu waehlen und ihn dann still zu ignorieren waere die
> schlechtere Ueberraschung.
>
> **Koerper-Kontextmenue** (Model Browser, Prefix `bd:`): *Use as Target Body*
> (nur bei laufender Extrude-Session), Hide/Show, Rename, **Delete Body** in
> eigener destruktiver Sektion. `renameBody` benennt auf ALLEN Features um, die
> den Koerper bauen, und lehnt Duplikate ab; `deleteBody` entfernt genau diese
> Features, parkt die EOP-Marke am Ende und rechnet neu.
>
> **Neu/berührt:** `app_state.dart`, `widgets/extrude_dialog.dart`,
> `widgets/model_browser.dart`, `widgets/viewport3d.dart`, neuer Test
> `test/m97_pick_body_test.dart`.
>
> **Verifikationsstand:** die Zustandslogik ist host-getestet (kein Hover ohne
> Armierung, kein Armieren ohne Session, Cancel raeumt beides, Rename/Delete
> treffen genau die richtigen Features). **Geraete-Sache und offen:** ob der
> 3D-Hover fluessig genug ist (er laeuft ueber `_pickSolidFace` bei jeder
> Bewegung), und ob der Koerper in 3D sichtbar genug hervorgehoben wird — heute
> faerbt nur die Browserzeile, in 3D zeigt der Hover bislang keine eigene
> Einfaerbung.

> **M96 — Zwei aus dem Extrude-/EOP-Bericht. ZWEI WEITERE SIND OFFEN.**
>
> **(1) New Solid benennt sich selbst.** `setExtrude` setzte den Namen zwar
> schon, aber das Textfeld des Dialogs wird EINMAL in `initState` gebaut und
> folgte der Session nie — man sah den alten Namen und musste ihn tippen. Der
> Controller wird jetzt beim Moduswechsel nachgezogen. Dazu neu
> `PartModel.peekSolidName()`: liefert den naechsten FREIEN Namen, ohne den
> Zaehler zu verbrauchen (der Dialog fragt bei jedem Umschalten, `nextSolidName`
> haette die Nummer jedes Mal hochgezaehlt) und ueberspringt bereits vergebene
> Namen — sonst kann ein umbenannter Koerper dazu fuehren, dass "New Solid"
> still auf einen existierenden Koerper joint.
>
> **(2) EOP-Ziehen war zappelig.** `_slotForDyPart` mass die Feature-Zeilen bei
> JEDER Bewegung live — eine Rueckkopplung: die Marke belegt eine eigene Zeile,
> ihr Verschieben schiebt alle Zeilen darunter um eine Zeilenhoehe, damit
> aendern sich genau die Mittelpunkte, gegen die gemessen wird, und der Slot
> kippt zurueck. Jetzt wird beim Drag-START einmal ein Schnappschuss der
> Zeilenmitten genommen; der kann unter dem Finger nicht mehr wandern. Beim
> Ende, Abbruch und Esc wird er verworfen.
>
> **NICHT umgesetzt, ausdruecklich angefragt — das ist die naechste Runde:**
> * **Koerper durch ANKLICKEN waehlen** statt Dropdown: in 3D und im Model
>   Browser, mit Hover-Highlight in BEIDEN waehrend des Auswahlmodus. Das ist
>   ein eigener Auswahlmodus in der Extrude-Session (Pick-Target-State), plus
>   Hit-Test auf Koerper im 3D-Viewport, plus Hover-Weiterleitung zwischen
>   Browser und Viewport — deutlich groesser als die zwei Fixes oben.
> * **Kontextmenue auf einer Koerper-Zeile im Model Browser.** Die
>   Infrastruktur steht seit M84 (`_kFeaturePrefix`-Muster, `addTarget`,
>   `_showCtxItems`); es fehlt eine Zeilen-Kennung fuer Koerper und ein
>   Menuesatz (sichtbar/umbenennen/loeschen).
>
> **Neu/berührt:** `part_model.dart` (`peekSolidName`), `app_state.dart`,
> `widgets/extrude_dialog.dart`, `widgets/model_browser.dart`, Tests ergaenzt in
> `test/m91_timeline_eop_test.dart`.

> **M95 — Zwei Nachwehen von M93.**
>
> **(1) Nach dem Verlassen der Skizze war sie in 3D weg** und tauchte erst auf,
> wenn man Extrude oeffnete und wieder abbrach. Ursache: seit M93 fehlt die
> OFFENE Skizze absichtlich im Payload (Viewport2D zeichnet sie live) — damit
> aendert Oeffnen UND Schliessen, was die Szene enthaelt. `sceneSignature`
> wusste aber gar nicht, welche Skizze offen ist, also aenderte das Schliessen
> die Signatur nicht, es wurde kein Rebuild geschickt, und die fertige Skizze
> blieb unsichtbar, bis irgendeine fremde Aenderung (der Extrude-Dialog bewegt
> `prev:`) einen Rebuild erzwang. Die Signatur traegt jetzt ein `edit:`-Feld.
>
> **(2) Skizzenlinien in 3D zu dick.** `sketchRadius` war `2.8e-3 * halfH` —
> ein fester Bruchteil der Welthoehe, gewaehlt um "deutlich schwerer" als die
> B-Rep-Kanten zu wirken. In Punkten sind das rund `2.8e-3 * Viewhoehe`, auf
> einem iPad also ~4 pt gegen die 1 pt, die Viewport2D zeichnet. Jetzt aus der
> VIEW hergeleitet statt geraten: die Ansicht zeigt `2*halfH` mm ueber
> `bounds.height` Punkte, ein Punkt sind also `halfH / bounds.height` mm, und
> ein Tube mit genau diesem RADIUS ist einen Punkt breit — dieselbe Strichbreite
> wie in 2D. Fallback auf den alten Kantenwert, solange die View noch kein
> Layout hat.
>
> **Neu/berührt:** `reality_scene.dart`, `packages/reality_view/ios/Classes/
> RealityPartView.swift`, Test ergaenzt in `test/m93_no_double_sketch_test.dart`.
>
> **Verifikationsstand:** die Signatur ist host-getestet; die Strichbreite ist
> Geraete-Sache — die Herleitung stimmt rechnerisch, ob 1 pt in 3D neben den
> Kanten gut aussieht, sagt nur das Geraet.

> **M94 — Ein Polygon am Mittelpunkt ziehen traegt die Form mit.** Gemeldet:
> beim Ziehen am Mittelpunkt soll das Polygon Form und Groesse behalten und nur
> in x/y wandern, sofern keine Constraint etwas anderes sagt.
>
> **Warum es vorher nicht so war:** ein Polygon hat 4 Freiheitsgrade (Mitte
> x/y, Radius, Drehung). Der Mittelpunkt-Griff wuenscht auf 2 davon; Radius und
> Drehung bleiben frei, also DURFTE der Solver unterwegs skalieren oder drehen.
> Alle Constraints waren erfuellt — es war nur nicht gemeint.
>
> **Ohne neue Constraints geloest.** Zusaetzliche Constraints fuer Groesse und
> Drehung wuerden das Polygon ueberbestimmen und uns direkt zurueck in die
> singulaere Normalgleichung bringen, die M92 mit den `n-1` gleichen Kanten
> gerade vermeidet. Stattdessen: `_centreRigidGroup` erkennt die
> Konstruktionskreis-Mitte, an der ein Polygon haengt (Kreis, auf dem >= 3
> Entitaeten per point-on-curve-`coincident` sitzen, plus alles, was ueber
> Punkt-Koinzidenzen daran haengt), verschiebt die GANZE Gruppe starr um dasselbe
> Delta und macht jeden ihrer Punkte zum Drag-Wunsch. Der Solver startet damit
> auf der Loesung, die der Nutzer meint, und sein Minimum-Norm-Schritt haelt sie.
> **Was der Nutzer WIRKLICH constrained hat, gewinnt weiterhin** — der Solve
> laeuft danach normal und zieht zurueck, was die Constraints verlangen.
>
> Ein einzelner Kreis ist keine Form: ohne point-on-curve-Constraints bleibt der
> Mittelpunkt-Zug ein gewoehnlicher Punkt-Zug. Body-Griffe sind unberuehrt.
>
> **Neu/berührt:** `app_state.dart` (`_centreRigidGroup` + Drag-Pfad), neuer
> Test `test/m94_centre_drag_test.dart`.
>
> **Verifikationsstand:** host-getestet ist, dass das Polygon genau die 4 DOF
> hat (weshalb der Mittelpunkt-Zug ueberhaupt mehrdeutig ist) und dass eine
> starre Verschiebung den Constraint-Satz gar nicht erst verletzt — Koinzidenz,
> Gleichheit und Punkt-auf-Kreis sind translationsinvariant, der Solver hat also
> nichts zu korrigieren. **Geraete-Test offen:** wie es sich anfuehlt, und ob
> die Gruppenerkennung auch bei einem Polygon greift, an dem weitere Geometrie
> haengt.

> **M93 — Die offene Skizze wird nur EINMAL gezeichnet.** Mit Screenshot
> gemeldet: im Skizzenmodus stand dasselbe Rechteck zweimal da — das lebende
> 2D-Rechteck unter dem Finger und eine eingefrorene Kopie an der alten Stelle,
> inklusive der Konstruktions-Diagonalen, die in 3D gar nichts zu suchen haben.
>
> **Ursache:** die Skizze wurde von ZWEI Stellen gerendert. `Viewport2D` malt
> sie live in jedem Frame; `_sketchPayloads` schickte sie zusaetzlich an
> RealityKit (und `viewport3d._paintSketch` an den CPU-Pfad), aber die
> RealityKit-Kopie entsteht nur, wenn das Szenen-Payload neu gebaut wird — beim
> Ziehen driften die beiden also auseinander. Das Drag-Log des Nutzers zeigt
> genau das: die 2D-Geometrie folgt dem Finger exakt, die 3D-Kopie bleibt
> stehen. Die Konstruktionslinien kamen durch dieselbe Tuer, denn das Flag
> `editing` war es, das im Payload-Builder Konstruktion ANschaltete.
>
> **Fix:** wer live rendert, besitzt es allein. Die gerade editierte Skizze wird
> weder ins RealityKit-Payload noch in den 3D-CPU-Painter gegeben. Inventor
> haelt hinter einer offenen Skizze das MODELL lebendig — die Koerper, die
> anderen Skizzen —, nicht eine zweite Kopie dessen, was man gerade zeichnet.
> Zusaetzlich filtert der 3D-CPU-Painter Konstruktionsgeometrie jetzt hart
> heraus, damit sie auch auf keinem anderen Weg dorthin gelangt.
>
> **Neu/berührt:** `reality_scene.dart`, `widgets/viewport3d.dart`, neuer Test
> `test/m93_no_double_sketch_test.dart`.
>
> **NOCH OFFEN (vom Nutzer im selben Zug gemeldet, NICHT umgesetzt):** ein
> Polygon soll sich beim Ziehen am MITTELPUNKT starr verschieben — Form und
> Groesse halten, nur x/y wandern —, sofern keine Constraint etwas anderes
> sagt. Heute zieht der Solver am Kreismittelpunkt und laesst Radius und
> Drehung frei (das Polygon hat 4 DOF, der Griff pinnt 2), also kann es beim
> Ziehen skalieren oder rotieren. Braucht einen starren Mitnehm-Modus im
> Drag-Pfad, kein weiteres Constraint — sonst waere das Polygon ueberbestimmt.

> **M91 — Model Browser als ZEITSTRAHL + End of Part.**
>
> **(1) Zeitbasiert.** Der Browser war "erst alle Skizzen, dann alle Features".
> Inventors Browser ist aber eine Historie: was zuletzt entstand, steht unten.
> Neu ordnet `partTimeline(part)` die oberste Ebene nach Entstehungszeit
> (`seq` auf ChildSketch UND ExtrudeFeature, EIN Zaehler pro Part, persistiert)
> — eine nach einer Extrusion angelegte Skizze steht jetzt UNTER ihr. Zwei
> Regeln obendrauf: eine KONSUMIERTE Skizze ist gar keine oberste Zeile (sie
> haengt unter ihrem Feature), und die Kopie einer **geteilten** Skizze wird
> direkt UEBER ihren ersten Consumer gepinnt statt an ihren eigenen Zeitplatz —
> Inventors "a copy of the sketch displays above its parent feature". Das war
> in M84 noch nicht so: dort standen geteilte Skizzen pauschal ganz oben.
>
> **(2) End of Part.** `PartModel.eopAfter` = Zahl der Features UEBER der Marke.
> Alles darunter ist zurueckgerollt: nicht in den Koerper gerechnet, nicht
> gezeichnet (alle vier Zeichen-Praedikate ergaenzt: `app_state`,
> `reality_scene`, zweimal `viewport3d`), im Browser ausgegraut. Gezaehlt wird
> in FEATURES, nicht in Zeilen — Skizzen werden nicht gebaut, ein Ziehen ueber
> sie hinweg waere eine unsichtbare Nulloperation.
>
> **Genau wie im Sketch:** ziehbar mit Live-Vorschau der neuen Position
> (`_dragEop`, gespiegelt zu `_dragEos`), **Esc bricht das Verschieben ab**,
> Sekundaerklick und Long-Press oeffnen dasselbe Menue (nativ auf dem Geraet,
> Overlay sonst) mit *Move to Top* / *Move to End* / *Delete All Features Below
> EOP*. Der Fallback-Overlay ist zu `_showCtxItems` herausgezogen, damit End of
> Sketch und End of Part nicht auseinanderdriften koennen.
>
> **Ein neues Feature landet UEBER einer geparkten Marke**, die dabei nach unten
> rutscht — wie in Inventor, wo neue Arbeit vor die Marke kommt.
>
> **Migration ehrlich:** ein Dokument vor M91 hat nirgends `seq`. Beim Laden
> bekommen erst die Skizzen, dann die Features fortlaufende Nummern — das
> reproduziert EXAKT die alte Blockreihenfolge, ein altes Teil oeffnet also so,
> wie der Autor es verlassen hat. Nur was ab jetzt entsteht, liegt nach echter
> Zeit auf dem Strahl. `eop` wird nur geschrieben, wenn die Marke NICHT am Ende
> steht; unveraenderte Dateien bleiben unveraendert.
>
> **Neu/berührt:** `part_model.dart` (`seq`, `eopAfter`, `PartNode`,
> `partTimeline`, `partBuildOrder`, `applyEndOfPart`, Persistenz + Migration),
> `app_state.dart` (`setEndOfPart`, `deleteBelowEndOfPart`, seq beim Anlegen,
> Zeichen-Praedikat), `reality_scene.dart`, `widgets/viewport3d.dart`,
> `widgets/model_browser.dart` (Zeitstrahl-Aufbau, EOP-Zeile mit Drag/Esc/Menue,
> Ausgrauen), neuer Test `test/m91_timeline_eop_test.dart`.
>
> **Verifikationsstand:** blind geschrieben, CI-Ergebnis siehe Lauf zum Commit.
> Die Modell-Logik ist host-getestet (Reihenfolge, Pinning, Rollback,
> Migration); **Geraete-Sache und offen:** ob sich das Ziehen der EOP-Marke
> genauso anfuehlt wie im Sketch, und ob das Ausgrauen im 3D-Viewport
> ueberzeugt. **Nicht drin:** Umsortieren von Features per Drag (Inventor kann
> das), und Suppress einzelner Features unabhaengig von der Marke.

> **M90 — Der leere graue Klotz unter dem Browser-Kontextmenue.** Gemeldet mit
> Screenshot: Long-Press auf eine Skizzenzeile hebt ein leeres, abgerundetes
> Rechteck in Zeilengroesse aus der Seite, das den Baum verdeckt.
>
> **Ursache, im Code gefunden:** `buildPreview` in `NativeMenuPlugin.swift`
> fuellte den Container IMMER mit der Viewport-Farbe und zeichnete ERST DANACH
> `previewImagePath` hinein. Fuer eine Galeriekarte ist das richtig (sie liefert
> ihr 380x240-PNG). Fuer die in M84 hinzugekommenen Model-Browser-Zeilen gibt es
> kein Bild — also blieb genau der gefuellte Container uebrig: ein grauer Klotz
> mit nichts drin. Die echten Pixel der Zeile sind gar nicht zu bekommen, sie
> liegen in Flutters Metal-Layer — eben deshalb reicht die Galerie ein PNG
> herueber.
>
> **Fix:** neues Feld `lift` auf `NativeMenuTarget` (Default **true**, Galerie
> unveraendert). Zeilen setzen `lift: false`; `buildPreview` gibt dann einen
> UNSICHTBAREN Preview zurueck — kein Hintergrund, leerer `visiblePath`, leerer
> `shadowPath`. Bewusst `nil` NICHT zurueckgegeben: dann wuerde UIKit die
> Flutter-View selbst snapshotten und man haette dasselbe unzuverlaessige
> Ergebnis. Die Zeile bleibt jetzt einfach liegen und nur das Menue faehrt auf,
> so wie iOS-Listenmenues sich verhalten, wenn kein Preview lieferbar ist.
>
> **Nicht nur meine Zeilen:** Layer-Zeilen und "End of Sketch" hatten denselben
> Fehler seit ihrer Einfuehrung (kein Bild → Klotz) und sind mitgefixt. Und die
> Galerie faellt jetzt sauber zurueck, falls eine Karte kein PNG hat — was seit
> M82 vorkommt, wenn ein Part keine zeichenbaren Solids hat.
>
> **Neu/berührt:** `packages/native_menu/lib/native_menu.dart`,
> `packages/native_menu/ios/Classes/NativeMenuPlugin.swift`,
> `widgets/model_browser.dart`, neuer Test `test/m90_menu_lift_test.dart`.
>
> **Verifikationsstand:** die Swift-Seite ist Geraete-Sache; der Host-Test nagelt
> nur fest, dass das Flag wirklich ueber den Kanal geht, sicher defaultet und
> die Galerie ihr Bild behaelt.

> **M87 — Freihand-Spline-Werkzeug.** Mit Pencil oder Finger frei zeichnen,
> beim Loslassen oeffnet ein modeless Fenster am Strichende: **Points**,
> **Smoothing**, **Close if ends meet**, **Snap ends to points**, gruener
> **Finish**-Knopf (oder Enter), Esc verwirft.
>
> **Der Kniff: keine zweite Commit-Strecke.** Das Fitting schreibt sein
> Ergebnis in `toolPoints` — und Vorschau-Painter wie `_commitTool` lesen genau
> die. Die Freihandkurve laeuft damit durch die GEWOEHNLICHE Werkzeugstrecke
> (Layer-Stempel, Constraint-Inferenz, Undo), und die Vorschau ist per
> Konstruktion exakt das, was Finish committet. Committet ist es ein ganz
> normaler `splineFit`-Polyline — danach unterscheidet nichts die Kurve von
> einer geklickten, sie laesst sich ziehen, bemassen und constrainen.
>
> **Pipeline (`lib/freehand.dart`, rein, ohne Flutter-State):**
> 1. **dedupe** — eine ruhende Hand liefert denselben Punkt vielfach; Duplikate
>    verzerren die Bogenlaengen-Verteilung.
> 2. **smooth** — gleitender Mittelwert ueber den ROHSTRICH, VOR dem Resampling.
>    Danach zu glaetten wuerde gegen die Fit-Punkte arbeiten und genau die Ecken
>    verschleifen, die der Nutzer gesetzt hat. Fenster waechst mit der
>    Samplezahl, damit dieselbe Reglerstellung bei kurzem wie langem Strich
>    gleich wirkt. **Enden sind gepinnt** — sie sind der Anfang/das Ende der
>    Zeichnung und das, woran gesnappt wird.
> 3. **resample nach BOGENLAENGE** auf n Punkte — sonst clustern die Fit-Punkte
>    dort, wo die Hand langsam war.
> 4. **snap** — Schliessen gewinnt vor Endpunkt-Snap (wer eine geschlossene
>    Kurve wollte, bekommt eine, statt zwei Enden an zwei Nachbarn). Geschlossen
>    heisst: letzter Punkt EXAKT gleich dem ersten — die Konvention, die
>    `_spline` in tools.dart ohnehin schon liest. Gesnappt werden nur die
>    ENDPUNKTE; innere Fit-Punkte zu ziehen wuerde die Kurve vom gezeichneten
>    Strich wegreissen.
>
> **Nicht-destruktiv:** der Rohstrich bleibt die ganze Sitzung erhalten, jede
> Reglerbewegung fittet neu daraus. Points und Smoothing sind damit in BEIDE
> Richtungen umkehrbar (im Test festgenagelt).
>
> **Eingabe.** Der Strich uebernimmt den Pointer VOR der Klick-/Long-Press-
> Maschinerie, damit Zeichnen nie als Tap durchgeht; ein zweiter Finger bedeutet
> Pan/Zoom und verwirft den angefangenen Strich, statt ihn halbfertig unter der
> wandernden Ansicht stehen zu lassen; eine abgewiesene Handballen-Beruehrung
> zeichnet nicht. Waehrend des Zeichnens malt der Viewport die rohe TINTE
> (duenn, `T.hover`), nach dem Abheben die gefittete Kurve aus `toolPoints`.
> Enter/Esc gehen an das Fit-Fenster, BEVOR die generischen Tool-Handler
> greifen.
>
> **Neu/berührt:** `lib/freehand.dart` (neu), `lib/widgets/freehand_dialog.dart`
> (neu), `app_state.dart` (`Tool.splineFree`, `FreehandSession`, Session-API),
> `tools.dart` (Meta + `buildToolGeometry`), `widgets/viewport.dart`
> (Capture, Tinten-Vorschau, Fenster, Tasten), `svg_icons.dart`
> (`fsplinefree`), `widgets/ribbon.dart` (Flyout-Eintrag "Freehand"), neuer
> Test `test/m87_freehand_test.dart`.
>
> **Verifikationsstand:** blind geschrieben, CI-Ergebnis siehe Lauf zum Commit.
> Die Fitting-Mathematik ist im Host-Test echt geprueft (gleichmaessige
> Bogenlaenge, gepinnte Enden, exaktes Schliessen, Umkehrbarkeit); **alles
> Zeigerbezogene ist Geraete-Sache** und offen: ob der Strich sich gegen
> Palm-Rejection und die M53-Gesten wirklich sauber verhaelt, ob das Fenster an
> der richtigen Stelle aufgeht, und ob 12 % Fensterbreite Glaettung sich gut
> anfuehlt. **Bewusst nicht drin:** Druck-/Neigungsempfindlichkeit, und
> Nachbearbeiten eines bereits committeten Freihandzugs (danach ist es ein
> normaler Spline und wird ueber Griffe editiert).

> **M86 — Zwei gemeldete Spline-Fehler, beide im Code gefunden.**
>
> **(1) Der "Punkt, der keiner ist".** Die Vorschau haengt beim Zeichnen den
> Hover-Punkt an die gesetzten Punkte — richtig fuer die Maus. Ein FINGER und
> ein Pencil ohne Hover haben nach dem Abheben aber keinen Cursor mehr, und
> `setHover` wurde nur bei Down/Move gerufen und NIE geleert
> (`viewport.dart`, `onPointerUp`). `hoverWorld` behielt also den letzten
> Kontaktpunkt, und jede laufende Vorschau behandelte ihn weiter als echten
> Pick: beim Spline ist das ein zusaetzlicher Fit-Punkt, gezeichnet als
> Schwanz ueber den letzten gesetzten Griff hinaus — exakt "es sieht aus als
> waere da ein Punkt, ist aber keiner", und er verschwindet beim Finish, weil
> die committete Geometrie ihn nie hatte. Abheben leert den Hover jetzt;
> hover-FAEHIGE Geraete (Maus, Pencil Pro/M2) melden beim naechsten
> Hover-Event sofort wieder und sind unberuehrt.
>
> **(2) Lange Splines wurden grob.** `bsplineCurve` sampelte **fest 64 Punkte
> ueber die GANZE Kurve**, unabhaengig von der Zahl der Kontrollpunkte. Ein
> Spline mit 40 CVs bekam also unter zwei Samples pro Span und wurde als
> sichtbares Vieleck mit Knicken gezeichnet — und `arcChainResample` kann aus
> bereits zu weit auseinanderliegenden Punkten keine glatte Bogenkette mehr
> gewinnen. Genau das zeigt der Screenshot. `fitCurve` war NIE betroffen, weil
> es `perSeg = 24` PRO SEGMENT sampelt — deshalb degradierten nur die
> CV-Splines. Jetzt skaliert die Samplezahl mit den Spans (24 pro Span, wie
> `fitCurve`), Untergrenze 64 (kurze Splines exakt wie bisher), Obergrenze
> 4000, damit eine 500-Punkt-Kurve nicht 12 000 Samples durch jeden Paint,
> Hit-Test und Snap schickt.
>
> **Neu/berührt:** `widgets/viewport.dart`, `spline.dart`, neuer Test
> `test/m86_spline_fixes_test.dart`.
>
> **NICHT enthalten — bewusst als eigener Meilenstein offen: das
> Freihand-Spline-Werkzeug** (mit Pencil/Finger frei zeichnen, beim Loslassen
> Dialog mit Punktzahl / Glaettung / Snap-Optionen, Live-Vorschau, Finish per
> Icon oder Enter). Das ist kein Fix, sondern ein Werkzeug mit eigenem
> Pointer-Capture, Punktreduktion, modelessem Dialog und Snap-Logik — es
> gehoert in einen eigenen Durchgang, nicht an zwei Bugfixes drangehaengt.
> Entwurf steht, siehe Chat.

> **M85 — Die Split-Buttons im Create-Panel merken sich ihre Variante.**
> Gemeldet: Slot aus dem Rechteck-Flyout waehlen startete zwar den Slot und
> markierte den Button aktiv, aber die Schaltflaeche zeigte weiter RECHTECK —
> und nach Ende/Abbruch des Werkzeugs startete ein Tipp auf den Body wieder
> Rectangle. Inventor ist in beidem klebrig.
>
> **Fix an der richtigen Stelle.** `AppState.ribbonPick` (Map Flyout-Gruppe →
> zuletzt gewaehltes Tool) wird zentral in **`selectTool`** geschrieben, nicht
> im Ribbon — damit aktualisieren Tastenkuerzel und das Long-Press-Quick-Menue
> die Schaltflaeche genauso wie ein Flyout-Klick. `Tool.none` (Esc, Werkzeug
> fertig) gehoert zu keiner Gruppe und kann eine Auswahl daher NIE loeschen;
> genau das ist der zweite Teil des Wunsches. Ein ausserhalb des Editiermodus
> ABGELEHNTES Werkzeug aendert das Gesicht ebenfalls nicht (der Guard steht vor
> der Aufzeichnung).
>
> Das Gesicht selbst loest `_faceFor` auf: solange die Standard-Variante gewaehlt
> ist, bleibt alles exakt wie bisher (die handgezeichneten 34-px-Icons); eine
> Variante setzt ihr eigenes 26-px-Flyout-Icon (auf 34 skaliert) und ihren Namen
> aus `FlyItem.b` ein — also "Slot", "Polygon", "Spline", "Chamfer". Neuer
> `_BigSplit` verdrahtet Gesicht UND Body-Tipp aus derselben Quelle, damit
> sichtbares Icon und ausgeloestes Werkzeug nie auseinanderlaufen koennen.
> Gilt fuer Line / Circle / Arc / Rectangle und die Fillet-Zeile.
>
> `_toolGroup` ist aus `ribbon.dart` nach `app_state.dart` gewandert
> (`toolFlyoutGroup`), weil `selectTool` es jetzt braucht.
>
> **Session-State mit Absicht:** die Auswahl gehoert nicht zum Dokument, wird
> also nicht serialisiert und macht keine Skizze dirty.
>
> **Neu/berührt:** `app_state.dart`, `widgets/ribbon.dart`, neuer Test
> `test/m85_ribbon_sticky_test.dart`.
>
> **Offen:** ob die Auswahl eine App-Sitzung ueberdauern soll (Inventor merkt
> sie sich pro Sitzung — heute genauso); und das 26-px-Icon auf 34 skaliert
> wirkt duenner als die handgezeichneten Grossicons — falls das am Geraet
> stoert, brauchen die zehn Varianten eigene 34-px-Zeichnungen.

> **M84 — Share Sketch (Inventor) + Kontextmenue im Model Browser.** Der seit
> M74 sechsmal aufgeschobene Punkt ist damit erledigt.
>
> **Recherchiert (Autodesk-Doku), nicht geraten:** Der Befehl heisst **Share
> Sketch**, nicht "Reuse". Part Browser Reference: "Selects a sketch already
> used in a feature for use in a new feature. Places a copy of the sketch in the
> browser. **Available only when the sketch was consumed by a feature.**" Das
> Gegenstueck heisst schlicht **Unshare** und ist beschraenkt: "only if a single
> feature shares it and it is next to the feature in the browser". Die zweite
> Haelfte ist eine Browser-Reihenfolge-Bedingung, fuer die unser Baum kein
> Aequivalent hat (die geteilte Kopie steht immer direkt auf oberster Ebene) —
> umgesetzt ist daher nur die Ein-Consumer-Haelfte. Beim Teilen zeigt Inventor
> die Skizze zusaetzlich auf oberster Ebene ("a copy of the sketch displays
> above its parent feature"), die verschachtelte Instanz bleibt unter ihrem
> Feature.
>
> **Symbol — ehrlich:** dass ein geteilter Sketch ein EIGENES Browser-Icon hat,
> belegt nur eine Drittquelle ("a shared sketch typically appears with an
> altered icon ... often accompanied by a 'shared' symbol"), nicht die
> Autodesk-Doku. Die konkrete Grafik ist also NICHT nachgebaut, sondern eigen:
> derselbe blaue Sketch-Wuerfel mit einem kleinen gelben Ketten-Badge. Traegt
> nur die TOP-LEVEL-Kopie — die verschachtelte Instanz behaelt den schlichten
> Wuerfel, sonst waeren die zwei gleichnamigen Zeilen nicht unterscheidbar.
>
> **Umgesetzt.** `ChildSketch.shared` (persistiert, nur wenn true → alte
> Dokumente laden unveraendert), `shareSketch`/`unshareSketch` in `AppState`
> (Teilen macht sichtbar, wie Inventors Workflow es verlangt; Unshare setzt auf
> den Consumed-Default zurueck), Praedikate `consumersOf`/`sketchIsConsumed`/
> `canUnshareSketch` in `part_model.dart`. Browser: geteilte Skizzen erscheinen
> zusaetzlich oben, Badge-Icon, und **native Kontextmenues** (dieselbe
> `native_menu`-Infrastruktur wie die Galerie aus M48, ids praefixiert
> `sk:`/`skn:`/`ft:`, damit sie nie mit einem frei benannten Layer kollidieren):
> Skizze = Edit Sketch / Hide-Show / **Share Sketch** bzw. **Unshare** (jeweils
> nur wenn zulaessig); Feature = Edit Feature / Hide-Show / Rename / Delete.
> Neu dafuer `AppState.renameFeature` (Namen sind reine Anzeige — referenziert
> wird ueber Objektidentitaet —, Duplikate werden abgelehnt).
>
> **Neu/berührt:** `part_model.dart`, `app_state.dart`, `svg_icons.dart`
> (`sharedSketchCubeIcon`), `widgets/model_browser.dart`, neuer Test
> `test/m84_share_sketch_test.dart`.
>
> **Verifikationsstand:** blind geschrieben (kein Flutter/Swift in der Session);
> CI-Ergebnis siehe Lauf zum Commit. **Nicht umgesetzt / offen:** das implizite
> Teilen (Inventor teilt automatisch, wenn man eine konsumierte Skizze als Input
> fuer ein neues Feature waehlt) — heute muss man explizit Share Sketch waehlen.
> Ebenfalls offen: Suppress, Redefine Sketch, und der Geraete-Test (Long-Press
> auf Sketch-/Feature-Zeile oeffnet ein echtes UIMenu, Delete rot).

> **CI-FALLE (M82-Nachtrag, teuer gelernt): Plugin-Swift steckt NICHT im
> Runner-Binary.** Das neue Gate `THUMB CHANNEL CHECK` hat den Build rot gemacht
> — zu Recht in der Form, aber aus dem falschen Grund: gegrept wurde
> `strings $APP/Runner`, und die In-Repo-Pods deklarieren kein
> `static_framework`, also liefert CocoaPods sie als DYNAMISCHE Frameworks. Am
> IPA von Lauf 30309544477 nachgemessen: `"prototype/reality_view"` kommt im
> Runner **0x** vor und in `Frameworks/reality_view.framework/reality_view`
> **2x**. Das Feature war in Ordnung, das Gate war falsch. Es scannt jetzt
> beide Binaries (bleibt damit gueltig, falls der Pod je statisch wird). Wer
> kuenftig eine native Flaeche absichert: **erst nachsehen, wo das Literal
> landet** — `otool -L Runner | grep RealityKit` trifft weiterhin, weil die
> Framework-Verlinkung an die App-Target durchschlaegt, die Swift-STRINGS aber
> nicht.

> **M83 — Ursprungs-Ebenen und -Achsen RAHMEN das Teil.** Bisher waren sie ein
> fester 20x20-mm-Quadrat (`_ext = 10`, "wie im Mock"). Das stimmt nur zufaellig:
> an einem 200-mm-Winkel verschwinden die Ebenen im Bauteil, an einem 2-mm-Stift
> ersaufen sie es. Jetzt hat jede Ebene die **Breite und Hoehe des Teils entlang
> ihrer EIGENEN u/v-Achsen**, plus etwas Rand.
>
> **Asymmetrisch, mit Absicht.** Ein von der Null aus gezeichnetes Teil belegt
> x in [0, 60]; ein symmetrisches Halb-Mass wuerde daraus eine 120-mm-Ebene fuer
> ein 60-mm-Teil machen. `originPlaneRect(part, key)` projiziert die gepolsterte
> Welt-Box auf die Achsen des jeweiligen Frames und liefert
> `(uMin, uMax, vMin, vMax)` — die Ebene ist damit wirklich so breit wie das
> Teil. Rand = 12 % der Ausdehnung, mindestens 1.5 mm (proportional, damit er
> bei jeder Teilegroesse gleich aussieht; mit Untergrenze, damit ein flaches
> Teil trotzdem einen sichtbaren Rand bekommt).
>
> **Zwei bewusste Entscheidungen (bitte gegenlesen):** (1) **Der Ursprung liegt
> immer drin.** Kostet im Normalfall nichts (Teile werden um die Null modelliert)
> und verhindert den entarteten Fall, dass ein weit ausserhalb modelliertes Teil
> seine eigenen Ursprungsebenen von den Achsen und dem Center Point wegzieht, die
> auf ihnen liegen sollen. (2) **Skizzen zaehlen als Inhalt**, nicht nur Solids —
> auf einem frischen Teil existiert die erste Skizze VOR jedem Solid, und eine
> Ebene, die nicht mit ihr mitwaechst, waere das einzige auf dem Schirm, das die
> Zeichnung auf ihr ignoriert. Ein leeres Teil faellt auf die alte feste Groesse
> zurueck (`kOriginExtentDefault = 10`), also ist der Erst-Eindruck unveraendert.
> **Die Achsen spannen dieselbe Box** (`originAxisSpan`), sonst staeche die Triade
> aus einer kleinen Ebene heraus bzw. verschwaende in einem grossen Teil.
>
> **EINE Quelle der Wahrheit.** `originPlaneRect`/`originAxisSpan` in
> `part_model.dart` speisen den RealityKit-Payload, den CPU-Painter UND den
> **Hit-Test**. Das ist kein Stil-Punkt: pickte der Test ein anderes Rechteck als
> gezeichnet wird, waere eine Ebene neben ihrer sichtbaren Kante anklickbar — die
> Fehlerklasse, die der Zwei-Renderer-Split immer wieder produziert. `_ext` ist
> aus `viewport3d.dart` verschwunden.
>
> **Perf.** `partContentBounds` liegt auf dem Pfad JEDES Frames und jeder
> Zeigerbewegung (drei Ebenen im Painter, drei im Hit-Test) und tesselliert
> Skizzenkurven — genau der Trichter, den M63 fuer das Zahnrad memoisieren
> musste. Daher Memo auf einer billigen Signatur (Mesh-Identitaet je Solid,
> gespeicherte Parameter je Skizzen-Geo — nie die Tessellierung), Cache auf dem
> PartModel. Der Walk laeuft einmal pro echter Aenderung statt mehrfach pro Frame.
>
> **Wire-Format:** Ebenen tragen jetzt `uMin/uMax/vMin/vMax`, Achsen `lo/hi`.
> `ext` bleibt als groesstes Halb-Mass zusaetzlich drin, damit ein aelterer
> nativer Build degradiert statt zu brechen (Swift faellt bei fehlenden Keys auf
> das symmetrische Quadrat zurueck).
>
> **Neu/berührt:** `part_model.dart` (Extent-Mathematik + Memo + Cache-Felder auf
> PartModel), `reality_scene.dart` (`_planePayloads`/`_axisPayloads`),
> `packages/reality_view/ios/Classes/PartScene.swift` (PlaneEntity/AxisEntity),
> `widgets/viewport3d.dart` (Painter, Overlay-Painter, Hit-Test; `_ext` entfernt),
> neuer Test `test/m83_origin_extent_test.dart`.
>
> **Verifikationsstand:** wieder BLIND geschrieben — in dieser Session gibt es
> weder Flutter/Dart noch Swift. Was `dart-checks` sagt, steht im CI-Log des
> Pushes; die Swift-Aenderung prueft erst `m5-flutter-ipa`, und wie es AUSSIEHT
> kann nur das Geraet sagen. **Offen fuer die naechste Runde:** ob 12 % Rand am
> Geraet richtig wirken; ob die Ebene beim Skizzieren mitwachsen soll (heute ja,
> weil Skizzen als Inhalt zaehlen — das kann waehrend des Zeichnens unruhig
> aussehen und ist der wahrscheinlichste Punkt, den man zuruecknehmen will).
>
> **Nachtrag (zwei rote Laeufe, beide meine):** (1) 649b20c — `THUMB CHANNEL
> CHECK` rot, siehe CI-Falle oben: das Gate war falsch, nicht das Feature.
> (2) 5790b50 — `flutter analyze`: `g.type.index`, aber `Geo.type` ist ein
> **int** (`static const line = 1, circle = 2, …`), kein Enum. Behoben; dabei
> zwei Folgefehler derselben Sorglosigkeit mitgenommen: der Memo-Schluessel
> enthielt den **Spline-Tag nicht** (identische `data`, voellig andere Kurve bei
> straight/CV/fit/ellipse/gear → veraltete Bounds), und **Konstruktions-
> geometrie zaehlte als Inhalt** — das auto-grosse Bounding-Rect um einen
> Textblock (M45) ist Construction und haette damit die Groesse der
> Ursprungsebenen bestimmt. Beides ausgeschlossen bzw. in den Schluessel
> aufgenommen. (3) 2870349 — `reality_scene_test` nagelte noch den ALTEN Vertrag fest (`ext == 10`); auf den neuen umgestellt: das Rechteck (`uMin/uMax/vMin/vMax`) wird geprueft, `ext` nur noch als groesstes Halb-Mass, plus die Zusicherung, dass ein Teil MIT Geometrie nicht bei der Leer-Groesse bleibt.

> **M82 — Die Vorschau kommt jetzt aus DERSELBEN Engine wie der 3D-Modus, und
> immer aus der Ecke oben-vorne-rechts.** Bisher zeichnete die Galerie-/
> Kontextmenue-Vorschau der CPU-Painter (`paintPartSolids`), waehrend der Live-
> Viewport seit M60 RealityKit ist — gleicher Koerper, zwei Engines, sichtbar
> andere Schattierung und Kantenstaerke.
>
> **(1) Off-Screen-RealityKit-Standbild.** Neuer Plugin-Kanal
> `prototype/reality_view/thumb` (`RealityViewPlugin.registerThumbChannel`,
> Methode `render`): `RealityThumbRenderer` baut eine losgeloeste `PartRenderer`
> in der angeforderten Pixelgroesse, schickt Szene + Kamera durch **exakt den
> Code-Pfad des Viewports**, und liefert PNG-Bytes. Der ARView haengt dafuer
> kurz mit `alpha 0` ganz hinten im Key-Window — ohne Window laeuft die
> Render-Loop nicht und `ARView.snapshot` gibt nil zurueck. Zwei Warmup-Frames
> (`CADisplayLink`), weil in `setScene` hochgeladene MeshResources erst im
> FOLGENDEN Frame sichtbar sind; ein Ein-Frame-Snapshot lieferte die leere
> Viewport-Farbe. Dart: `RealityThumbnailer.render(...)` — wirft nie, gibt
> `null` zurueck, wenn es kein natives RealityKit gibt (Host-Tests, non-iOS,
> iOS < 15, App im Hintergrund, fehlgeschlagener Snapshot).
> **Der CPU-Painter bleibt als Fallback** und ist weiterhin der Pfad, den die
> Host-Tests tatsaechlich ausfuehren.
>
> **(2) Immer oben-vorne-rechts.** `_fitThumbCamera` (privat in `app_state.dart`)
> ist zu `fitThumbCamera` in `part_render.dart` gewandert und wird jetzt an
> BEIDE Engines gereicht — die Framung kann also beim Engine-Wechsel nicht
> kippen. Der gerundete Literal `pol = 0.955` ist durch `kThumbPol =
> acos(1/sqrt(3))` ersetzt: die Welt ist Y-up (die XZ-Ebene traegt Normale +Y),
> also sitzt die Kamera bei az = pi/4 auf +X (rechts) / +Y (oben) / +Z (vorne),
> und die drei Richtungskomponenten sind jetzt bis auf Maschinengenauigkeit
> gleich statt um ~0.02 Grad verkippt. Unabhaengig von der Live-Kamera; nur
> Pan/Zoom passen sich der Silhouette an (`kThumbFill = 0.82`).
>
> **(3) Layering.** `cameraPayload`/`solidPayload` + neuer
> `buildThumbScenePayload` sind nach `lib/reality_payload.dart` ausgelagert
> (haengt NUR an `part_model.dart`), weil `reality_scene.dart` `app_state.dart`
> importiert und der Rueckweg sonst einen Zyklus schliessen wuerde.
> `reality_scene.dart` re-exportiert die Datei, bestehende Importe bleiben
> unveraendert. Die Thumbnail-Szene ist bewusst **geometrie-only**: keine
> Ursprungs-Ebenen/Achsen/CP/Skizzen/Preview/Highlight auf einer Karte.
>
> **Neu/berührt:** `packages/reality_view/lib/reality_view.dart`,
> `packages/reality_view/ios/Classes/RealityViewPlugin.swift`,
> `.../RealityPartView.swift` (`PartRenderer.snapshot`), `lib/part_render.dart`,
> `lib/reality_payload.dart` (neu), `lib/reality_scene.dart`,
> `lib/app_state.dart`, neuer Test `test/m64_thumb_engine_test.dart`.
>
> **Verifikationsstand (nachgetragen, CI-Log gelesen):** Run 30313498504 auf
> b33be2d — `dart-checks` **gruen**: `flutter analyze` ohne Fehler,
> **504 Host-Tests gruen**, darunter alle 6 neuen aus
> `m82_thumb_engine_test.dart` (namentlich im Log). Geschrieben wurde der Code
> allerdings BLIND: in der Session gab es weder Flutter/Dart noch Swift, die
> Gruen-Meldung stammt ausschliesslich aus dem CI-Log, nicht aus lokaler
> Ausfuehrung. Das Swift-Kompilat prueft erst `m5-flutter-ipa`.
>
> **Nachtrag (Werkzeug-/Nummern-Runde nach dem CI-Lauf):**
> 1. **Falsche Meilensteinnummer korrigiert.** Der Stand war M81, nicht M63 —
>    "M64" war bereits vergeben (Szenenkosten, `m64_scene_cost_test.dart`).
>    Alles umbenannt auf **M82**, inkl. Testdatei.
> 2. **Fehlendes CI-Gate nachgereicht.** Jede andere native Flaeche hier hat
>    einen Link-/Marker-Check auf dem gebauten Runner; meine hatte keinen — der
>    Kanal haette stumm fehlen koennen (Tippfehler im Namen, Datei nicht im
>    Pod-Glob) und der Haken waere trotzdem gruen gewesen, waehrend die
>    Vorschau fuer immer auf dem CPU-Painter bleibt. Neu: **THUMB CHANNEL
>    CHECK** in `m1-core-build.yml` — `strings Runner | grep
>    prototype/reality_view/thumb`. Der Name ist auf der Swift-Seite ein
>    LITERAL, auf der Dart-Seite interpoliert (`'$_channelName/thumb'`) und
>    steht dort nie ganz drin; ein Treffer beweist also die Swift-Haelfte.
>    Ehrliche Grenze: das Gate beweist "der Pfad existiert", NICHT "der
>    Snapshot gelingt" — dafuer braucht es Window und Render-Loop, also das
>    Geraet.
> 3. **Offener Punkt (b) gleich behoben statt notiert.** Der Off-Screen-Renderer
>    schickt jetzt **erst `setCamera`, dann `setScene`** (umgekehrt zum Live-
>    Viewport): `setScene` latcht `edgeBuildHalfH` und dimensioniert die
>    Kanten-Tubes fuer DIESEN Zoom, ein frischer Renderer haelt aber noch den
>    Default — die Outlines waeren fuer den falschen Zoom gebaut worden, und
>    das Re-Tubing greift erst ab Faktor 1.8/0.55, was bei genau einem Frame
>    nie passiert. Dazu EIN Retry (6 Frames spaeter), falls der erste Snapshot
>    nil ist, bevor der CPU-Fallback uebernimmt.
>
> **Weiter offen (nur am Geraet zu klaeren):** Warmup-Frame-Zahl bei einem
> grossen Zahnrad; Retina — es wird in Punkten gerendert, das PNG kann also
> 380x240 @2x = 760x480 gross sein, pruefen ob die Karte das will; und ob das
> RealityKit-Standbild optisch wirklich mit dem Viewport deckungsgleich ist.

> **Stand dieser Session (Kopf = M62, Cut/Intersect + Live-Boolean-Vorschau +
> Spline-Extrude-Fix):** Drei Punkte des Nutzers in einem Durchgang, „profes-
> sionell und production ready\":
>
> **(1) Cut & Intersect wie Inventor.** Shim **v5** (`backend/occt/shim`):
> `occt_cut` (`BRepAlgoAPI_Cut`) und `occt_common` (`BRepAlgoAPI_Common`),
> beide mit `has_solid_material`-Guard — ein leeres Ergebnis (Cut entfernt
> alles, disjunkter Intersect) ist ein FEHLER (`occt_last_error` erklaert), kein
> Null-Solid, damit der Aufrufer den alten Body behaelt. `occt_shim_version`→5,
> Marker „Prototype OCCT shim v5\". Dart-FFI: `_cut`/`_common` (gleiche ABI wie
> `_fuse`, im Konstruktor + `instance()`-Lookup + `cut()`/`common()`).
> `part_model.dart`: `PartKernel.cutSolids`/`intersectSolids` (+ geteilter
> `_boolean`-Helper mit `unify`), Top-Level `combineSolids(kernel, output,
> base, tool)`. `recomputeAllFeatures` ist von „nur Join-Kette\" auf **pro Body
> die Op JEDES Features abspielen** umgebaut: Vorgänger-Gate `output != 'new'`,
> dann `combineSolids` → Join/Cut/Intersect; `consumedByJoin` markiert wie
> gehabt die eingeschmolzenen Vorgaenger. `applyExtrude` uebernimmt fuer
> cut/intersect (wie join) den letzten Body-Namen. Dialog (`extrude_dialog.dart`):
> vier kompakte Icon-Toggles (Join/Cut/Intersect/New Solid, SVG im
> Gelb-/Stahl-Look wie `_dirButton`); Cut/Intersect sind gedimmt+inaktiv, wenn
> `app.extrudeHasBooleanTarget` false ist (Basis-Feature).
>
> **(2) Live-Vorschau des ECHTEN Bool-Ergebnisses.** Bisher zeigte
> `_updateExtrudePreview` nur das rohe neue Prisma. Jetzt: Prisma bauen, dann bei
> join/cut/intersect gegen den Ziel-Body (`_extrudeBooleanTarget` → bei NEU das
> letzte Solid-Feature via `lastSolidFeature`/`currentBodySolid`, beim EDITIEREN
> die Akkumulation davor via `bodyBaseBefore`) das tatsaechliche
> `combineSolids`-Ergebnis rechnen, in `s.preview` legen und `s.previewReplacesBody`
> setzen. Der Viewport blendet den Body mit diesem Namen aus — im
> RealityKit-Pfad (M60) via `reality_scene.visibleSolids`, `sceneSignature`
> nimmt `previewReplacesBody` mit auf; im CPU-Painter (`viewport3d._ScenePainter`,
> off-iOS) via Solids- + Occluder-Liste; `_liveSolids` (Pick/Refine) filtert
> ebenso —, sodass das Bool-Ergebnis an seiner Stelle steht statt mit dem alten
> Body zu z-fighten. Jede Dialog-Aenderung (`setExtrude`) rechnet neu.
> Basis-Frame/Prisma-Vorschau (New Solid, kein Ziel) unveraendert.
>
> **(3) Geschlossene Spline liess sich nicht extrudieren.** Ursache mit purem
> Dart-Repro FESTGENAGELT: eine geschlossene **Interpolations-Spline**
> (`fitCurve` in `spline.dart`) sampelt ihren letzten Punkt bei t=1 EXAKT auf
> p[0] und der Sampler haengt p[0] nochmal an. `_profileChain` entfernt nur das
> exakte Duplikat → es bleibt eine Schliess-Kante der Laenge 0, die
> `arc_loop_wire` im Shim verwarf (`chord < 1e-12` → leerer Wire → „outer wire
> construction failed\" → Extrude null). CV-Splines trifft es NICHT (letztes
> Sample ≠ Start). Fix an der Quelle: neue `dedupeClosedLoop` (Toleranz 1e-7 mm,
> weit unter Skizzen-Massstab) in `profileLoops.addLoop` entfernt deckungsgleiche
> Folgepunkte und einen Schluss==Start-Punkt → heilt Extrude UND
> Region/Flaeche/Highlight. Zusaetzlich haertet der Shim `arc_loop_wire`
> (degenerierte Kante `continue` statt Wire zu versenken; MakePolygon-Pfad war
> schon tolerant). Repro-Beleg: Fit-Spline-Schliesskante 0.000 → nach Dedup min.
> Kante 0.766; CV-Spline 0 Duplikate.
>
> **Lokal verifiziert (was ohne Flutter/OCCT ging):** `smoke_occt.c` C-kompiliert
> fehlerfrei (`gcc -Wall -Wextra`), Spline-Dedup + Fold-Algorithmus in purem
> Dart durchgerechnet (`/tmp/repro.dart`, `/tmp/fold.dart` — alle Werte korrekt).
> **Gates, die nur CI/Geraet stellen kann (ehrlich):** Shim-v5-Kompilat gegen
> OCCT, Host-Test-Suite (Flutter), `flutter analyze`, und der **Metal-Render der
> Bool-Vorschau auf dem Geraet**. Symbol-Gates `-ge 31` in `occt-build.yml` +
> `m1-core-build.yml`; Smoke **[17]** Cut (Durchbruch=6000, Operanden intakt,
> Alles-weg=Fehler) + **[18]** Common (Ueberlappung=1000, disjunkt=Fehler).
> **Neu/berührt:** `occt_capi.{h,cpp}`, `smoke_occt.c`, beide CI-Workflows,
> `occt_engine.dart`, `part_model.dart`, `app_state.dart`, `viewport3d.dart`,
> `extrude_dialog.dart`, neuer Test `m62_boolean_test.dart`, `cutSolids`/
> `intersectSolids` in den 3 Fake-Kerneln (m56/m57/m59).
> **Ehrliche Restschuld:** Vorschau beim Editieren eines MITTIG in der Kette
> liegenden Features zeigt nur bis dorthin (nachgelagerte Ops erst nach OK, dann
> korrekt via `recomputeAllFeatures`); Kegel/Kugel/Torus-Silhouetten weiter
> Mesh-Fallback; Spline-Profile weiterhin polygonal tesselliert (Extrude geht
> jetzt, nur eben als Vieleck-Prisma — echte B-Spline-Flaechen waeren separat).
>
> ---
>
> **WERKZEUG-RUNDE (vor der naechsten Fehlersuche).** Die Feedbackschleife war
> der Flaschenhals, nicht das Denken. Drei Aenderungen:
>
> 1. **Neuer Job `dart-checks`** (ubuntu, parallel): `pub get` + `analyze` +
>    `flutter test`. Bisher liefen beide Pruefungen als Step 12/18 INNERHALB von
>    `m5-flutter-ipa`, also erst nach Qt-Install und Core-Build — ein
>    Dart-Tippfehler kostete ~20 min statt ~3. Die Schritte in m5 bleiben
>    zusaetzlich stehen (sie pruefen das `flutter create`-Projekt).
> 2. **Ein Selbstbericht statt zwei Diagnosezeilen.** `logMeshConvention` ist
>    jetzt der reine, testbare `meshSelfReport(id, mesh)` und schreibt EINE
>    Zeile pro neuem Solid: `tris/faces/verts`, `wind`, `out`, **`inward`**,
>    `edges`, `bbox`. Neu und entscheidend ist `inward`: die alte Zeile sagte
>    nur, DASS bei zusammengefuegten Koerpern 0.82/0.63 der Normalen einwaerts
>    zeigen, nicht WELCHE Flaechen. Die Wasserdichtigkeitspruefung lief bisher
>    nur bei `nTri <= 400` und entfiel damit genau bei den interessanten
>    Koerpern; sie laeuft jetzt immer.
> 3. **`test/mesh_conventions_test.dart`** nagelt die auf dem Geraet GEMESSENEN
>    Konventionen fest: Wicklung folgt den Normalen, geschlossene Huelle, eine
>    einzelne invertierte Flaeche wird namentlich gemeldet, und die Seitenwahl
>    in `facePicked` (`n·dir >= 0`) ergibt beim Klick auf die Deckflaeche die
>    TOP- und nicht die Bottom-Ansicht.

> ---
>
> **M60 — RealityKit ersetzt den CPU-Renderer (GPU-Tiefenpuffer).** Antwort auf
> den offenen Punkt (A) aus M59c: Canvas hat KEINEN Z-Buffer, Verdeckung lief
> in Screen-Space (Painter-Algorithmus + Occluder-Gitter + Bias-Margen). Das
> ist bei gekrümmten Flächen und sich durchdringenden Solids grundsätzlich
> fragil — jetzt ersetzt durch echtes GPU-Rendering.
>
> **Architektur (bewusst minimal-invasiv):** Die gesamte Dart-Kamera- und
> Pick-Logik bleibt UNVERÄNDERT (`Cam3`, `_hitOrigin`, `_pickSolidFace`,
> `_tap` — reine Geometrie, bereits getestet). Ersetzt wird NUR die
> Ausgabefläche:
> - Neues In-Repo-Plugin `frontend/packages/reality_view/` (gleicher Pfad wie
>   `native_menu`: Podspec + Swift, von CocoaPods über
>   `.flutter-plugins-dependencies` gezogen — es gibt kein `frontend/ios/`).
> - Swift: `ARView(cameraMode: .nonAR)` als Flutter-`UiKitView`, mit
>   `isUserInteractionEnabled = false`. Die Flutter-Gestenschicht liegt DARÜBER,
>   also greifen Orbit/Pan/Zoom/Tap/Hover unverändert weiter.
> - **Echte Ortho-Kamera:** `OrthographicCameraComponent` (iOS 18+), darunter
>   ein Near-Ortho-`PerspectiveCamera`-Fallback (3° Tele aus großer Distanz).
>   Kamera-Konvention 1:1 aus `part_render.dart` (`dir`, `forward=-dir`,
>   `s=fwd×up`, `u=s×fwd`, vertikale Weltausdehnung `2·halfH`).
> - Alles Weltraum-Geometrische (Solids, Ursprungsebenen, Achsen, Center Point,
>   Skizzen, B-Rep-Kanten, Face-Highlight) sind jetzt RealityKit-Entities →
>   **der Tiefenpuffer erledigt die Verdeckung**. `solidOccluder`,
>   `drawOccludedQuadFill`, `edgeMargin` & Co. werden auf dem Gerät nicht mehr
>   gebraucht. ViewCube, Triade und Meldungs-Toast bleiben Flutter-HUD.
> - **Protokoll** (3 Verben, `prototype/reality_view/<id>`): `setScene`
>   (schwer, nur wenn sich `sceneSignature` ändert), `setOverlays` (leicht:
>   Hover/Sichtbarkeit, pro Pointer-Move), `setCamera` (5 Doubles pro Frame).
>   Mesh-Puffer werden per REFERENZ übergeben (`Float64List`/`Int32List` →
>   StandardMessageCodec-Bytebuffer), nicht kopiert.
> - Der CPU-Painter (`_ScenePainter`/`paintPartSolids`) BLEIBT — für die
>   Galerie-Thumbnails (`_writePartPreview`, headless) und als Nicht-iOS-Pfad
>   (Host-/Widget-Tests). Dort ändert sich nichts.
>
> **Was CI verifizieren kann:** Swift kompiliert/linkt, `-framework RealityKit`
> im Runner (neuer `REALITYKIT LINK CHECK` per `otool -L`), `flutter analyze`,
> und die neuen Host-Tests `test/reality_scene_test.dart` über die REINEN
> Payload-Builder (`lib/reality_scene.dart`): Kamera-Doubles, Solid-Auswahl
> (unsichtbar/`consumedByJoin`/`editing` fallen raus), Puffer-Identität ohne
> Kopie, 9-Doubles-Ebenenframes, Skizzen-Weltmapping, Signatur-Wechsel bei
> Re-Tessellierung, Hover-Face-Auflösung.
>
> **Was RealityKit rendert — und was NICHT (wichtig, häufige Fehlannahme):**
> RealityKit ersetzt ausschließlich die **tiefengetestete Weltgeometrie im
> 3D-Part-Viewport**: Solids, Ursprungsebenen, Achsen, Center Point, Skizzen-
> kurven, B-Rep-Kanten, blaues Face-Prehighlight. WEITERHIN Flutter-Canvas:
> der komplette 2D-Sketcher (`viewport.dart`), `paintPartUnderlay` (geghostetes
> Modell im Skizzenmodus), die Galerie-Thumbnails (`_writePartPreview` →
> `paintPartSolids`, headless), ViewCube, Triade, Toast, sämtliche UI-Chrome
> (Ribbon, Browser, Dialoge) und der gesamte Nicht-iOS-Pfad.
>
> **Dabei gefunden und behoben (sonst Geräte-Regression):** `_paintRegions`
> (blaue Profil-Flächen beim Extrude, hovered/selected) sowie die Hover-
> Dekorationen (Ebenen-Eckringe + Mittelpunkt + gedrehtes Ebenen-Label,
> Achsen-Endringe, CP-Ring) hingen NUR am `_ScenePainter` — der auf iOS nicht
> mehr läuft. Ohne Fix hätte man beim Extrudieren kein Profil-Highlight mehr
> gesehen (Picking lief weiter, nur unsichtbar). Diese Elemente wurden im
> Original OHNE Occluder gezeichnet, sind also reines Screen-Space-HUD: neu als
> `_OverlayPainter` in Flutter ÜBER die RealityKit-Fläche gestapelt —
> verhaltensgleich, ohne Polygon-Triangulierung mit Löchern in Swift.
>
> **Bewusste Verhaltensänderung:** Achsen und Center Point sind jetzt echte
> 3D-Entities und werden damit von Solids VERDECKT; im CPU-Painter schwebten
> sie unverdeckt obenauf. Das entspricht Inventor besser, ist aber am Gerät zu
> bestätigen.
>
> **CI-Runde 1 (Run #162, `2a9302e`) — ehrlich gelesen:** Dart-Seite GRÜN
> (`flutter analyze` 0 errors, alle Host-Tests inkl. `reality_scene_test.dart`
> bestanden, Step 12 + 18). Gescheitert ist NUR Step 19 (`flutter build ios`)
> an **einem** Swift-Typfehler: `Cannot convert value of type 'Int' to expected
> argument type 'Int32'` in `RealityPartView.swift` — `NSNumber.intValue`
> liefert `Int`, `faceHighlightEntity` erwartete `Int32`. Behoben (Signatur
> nimmt jetzt `Int` und konvertiert einmalig intern); zusätzlich präventiv der
> Material-Ternary in `rebuildSolids` durch if/else ersetzt, weil dessen zwei
> Zweige verschiedene konkrete Typen sind (`PhysicallyBasedMaterial` vs
> `SimpleMaterial`) und Swift das auch mit Existential-Annotation ablehnen
> kann. Da Xcode den Build beim ersten Fehler abbricht, kann Runde 2 weitere
> Fehler zutage fördern — das ist der normale Rhythmus ohne lokale Toolchain.
>
> **GERÄTETEST RUNDE 1 (Build `0f04ca2`, iPad, iOS 27) — zwei Funde, beide
> waren die vorab markierten Risiken:** Zuerst das Gute: **RealityKit rendert**,
> die Ursprungsebenen durchdringen sich korrekt → der GPU-Tiefenpuffer arbeitet,
> das Kernziel von M60 ist erreicht. CI-Runde 2 war grün (IPA gebaut, Link-Check
> bestanden).
>
> **(1) Ortho-Maßstab war exakt 2× zu klein** (Risiko Nr. 1, wie vermutet).
> Nachgerechnet gegen den Screenshot mit den Kamerawerten aus dem Part-Sidecar:
> der gelbe Mittelpunkt landet exakt auf der Cam3-Projektion (1310/1136
> gerechnet vs. 1310/1140 gemessen) → Dart-Mathematik und `_OverlayPainter`
> korrekt; die XZ-Ebene misst 1105 px statt 2194 px → **Faktor 1.985 ≈ 2**.
> `OrthographicCameraComponent.scale` ist also die HALBE vertikale
> Weltausdehnung (Unity-`orthographicSize`-Konvention), nicht die volle. Fix:
> `oc.scale = halfH` statt `2*halfH`. Sichtbares Symptom war „die Ebenen sind
> kleiner als ihre Eckpunkte" — die Eckringe zeichnet Dart, die Ebene RealityKit.
>
> **(2) Taps erreichten Flutter nicht** (Risiko Nr. 2, wie vermutet). Ebene
> anklicken tat nichts; `planePicked` loggt `part: child sketch "…" on <key>` —
> diese Zeile fehlt im Gerätelog vollständig, der Tap kam also nie in `_tap` an.
> Beweis, dass NICHT die Pick-Mathematik schuld ist: Hover funktionierte
> (grüne Ebene + Label + Ringe) und nutzt dieselbe `_hitOrigin`. Der Unterschied
> ist die Zustellung — Hover ist ein Pointer-Event, ein Tap ist ein TOUCH und
> läuft auf iOS durch die Touch-Interception der eingebetteten Platform-View.
> Fix: die Gesten-Schicht liegt jetzt als transparente `SizedBox.expand()` im
> Stack ÜBER der RealityKit-Fläche, und die `RealityView` steckt in
> `IgnorePointer` — eine Platform-View darf nie oberstes Hit-Test-Ziel sein.
> Alle Handler (Orbit/Pan/Zoom/Tap/Hover) sind unverändert, nur die
> Verschachtelung hat sich gedreht.
>
> **GERÄTETEST RUNDE 2 (Build `9e5f60c`) — Skalierung + Tap bestätigt, fünf
> Darstellungsfehler mit EINER gemeinsamen Ursache:** Skizzieren und Extrudieren
> funktionieren jetzt. Gemeldet wurden: (a) kein blaues Face-Prehighlight beim
> Skizzenebenen-Pick, (b) bei starkem Zoom KEINE Kantenlinien, (c) bei normaler
> Größe ausgefranste/gesprenkelte Umrisse, (d) Artefakte wenn Ebene und Fläche
> exakt koplanar sind, (e) Skizzen auf Flächen unsichtbar.
>
> **Ursache: Tiefenpuffer-Präzision.** Die Kamera lief mit `near = 0.01`,
> `far = 1_000_000` bei Distanz 100_000. Orthografische Tiefe ist LINEAR, der
> Puffer verteilte 24 Bit also über eine Million Millimeter → ~0.06 mm
> Auflösung. Mein Kantenradius war 0.10 mm, der Highlight-Versatz 0.04 mm —
> beide am oder unter dem Rauschen. Damit erklären sich (a) bis (e) zwanglos:
> alles, was auf oder knapp über einer Fläche liegt, wurde von ihr verschluckt.
>
> **Fixes:** (1) **Szenen-angepasste Tiefenspanne** — `sceneRadius` aus den
> Mesh-Bounds, `pad = max(sceneRadius, halfH) + 10`, `dist = 4·pad`,
> `near/far = dist ∓ 2·pad`. Statt 1e6 mm nur noch ~100 mm Spanne → Auflösung
> um ~4 Größenordnungen besser. (2) **Koplanar-Versatz**: Ursprungsebenen und
> Skizzen werden entlang ihrer eigenen Normalen um einen zoom-skalierten
> Sub-Pixel-Betrag ZUR KAMERA gehoben — die Ebene/Skizze gewinnt gegen eine
> exakt koplanare Fläche, wie gewünscht und wie in Inventor. Dafür sendet Dart
> jetzt die Skizzen-Normale (`'n'`) mit. (3) **Kantenröhren** werden ebenfalls
> zur Kamera versetzt (sie liegen mittig auf der Flächengrenze, halb IM Solid —
> das war das Sprenkeln) und ihr Radius skaliert jetzt mit `halfH`
> (`1.2e-3·halfH`), damit Linien bei jedem Zoom etwa gleich stark bleiben.
> (4) Der Highlight-Versatz skaliert mit (`2e-3·halfH`).
>
> **Offen/unbestätigt:** ob (e) wirklich nur Z-Fighting war — eine VERBRAUCHTE
> Skizze ist per Inventor-Semantik absichtlich unsichtbar (`cs.visible=false`,
> Auge im Browser holt sie zurück). Falls die Skizze auch nach dem Fix fehlt,
> ist es diese Semantik und kein Renderfehler.
>
> **GERÄTETEST RUNDE 3 — die Wicklungs-Konvention war die eigentliche Ursache:**
> Zwei gemeldete Fehler hatten DIESELBE Wurzel, und sie erklärt auch, warum der
> Tiefenpuffer-Fix aus Runde 2 das Highlight nicht heilte. In diesen Meshes
> zeigt die GEOMETRISCHE Wicklungs-Normale nach INNEN — `projectSolidTriangles`
> verwirft Rückseiten mit `n·dir < 0`, also mit genau dieser Konvention
> (vgl. M59b „Facing-Konvention global invertiert").
> - **Face-Prehighlight unsichtbar:** `faceHighlightEntity` hob die Fläche
>   entlang eben dieser Wicklungs-Normalen an — also INS Solid hinein. Mehr
>   Tiefenpräzision machte es nur zuverlässiger unsichtbar. Fix: Anhebung
>   entlang der per-Vertex-Normale (laut `occt_capi.h` autoritativ „OUTWARD").
> - **Teil mit Loch durchsichtig:** die Innenwand eines Lochs kommt aus OCCT
>   mit umgekehrter Face-Orientierung; die GPU cullt streng nach Wicklung und
>   verwarf sie, man sah durchs Loch hindurch. Der CPU-Painter fiel darauf nie
>   herein, weil er pro Dreieck selbst cullt. Fix: `SolidGeom` normalisiert
>   beim Aufbau JEDES Dreieck gegen die Vertex-Normale (Invariante:
>   `gn·vn < 0`), notfalls durch Index-Tausch — damit ist das Culling
>   konsistent, unabhängig von der Kernel-Orientierung.
>
> **Verhaltensänderung auf Wunsch:** die drei Ursprungsebenen werden nur noch
> AUTOMATISCH gezeigt und pickbar, solange das Teil leer ist (`PartModel.hasSolid`
> == false), also für die erste Skizze/Extrusion. Danach skizziert man auf
> Flächen; eine Ebene erscheint nur noch, wenn sie im Browser explizit
> eingeschaltet ist. Gilt einheitlich für RealityKit-Payload, Picking und den
> CPU-Painter; der Host-Test deckt beide Fälle ab.
>
> **Ehrlich offen — Geräte-Test ist das Gate (nichts davon lokal prüfbar, kein
> Xcode/Flutter im Container):**
> 1. **Ortho-`scale`-Semantik:** angenommen `scale = 2·halfH` (volle vertikale
>    Weltausdehnung). Ist es in Wahrheit die HALBE Höhe, ist das Bild exakt 2×
>    verzoomt — dann diese eine Konstante in `applyCameraComponent()` ändern.
>    Erkennbar am Vergleich mit ViewCube/Triade (die weiter Dart rechnen).
> 2. **Gesten durch die Platform-View:** ob der Flutter-`GestureDetector` über
>    einer `UiKitView` wirklich JEDE Geste bekommt (Pinch/Hover/Pencil), ist
>    Verhalten der Embedder-Schicht — die `ARView` ist interaktionsfrei
>    gestellt, aber das ist am Gerät zu bestätigen.
> 3. **Kanten als Röhren mit fester Weltdicke** (r = 0.10 mm): bei starkem
>    Zoom werden sie sichtbar dick, bei starkem Auszoomen dünn. Bewusster
>    v1-Kompromiss (RealityKit hat kein Linien-Primitiv); eine
>    bildschirmkonstante Breite bräuchte ein Custom-Material/Shader.
> 4. **Analytische Kanten (Shim v4) werden noch nicht genutzt** — gezeichnet
>    wird die Kanten-Polylinie. Die M59-Bezier-Exaktheit gilt weiter für die
>    Thumbnails, nicht für die RealityKit-Ansicht.
> 5. **Renderer ist auf iOS 15+ gegattert** (`MeshDescriptor`,
>    `MeshResource.generate(from:)`, `PhysicallyBasedMaterial`, `blending` sind
>    RealityKit-2-APIs). Deployment-Floor bleibt 14.0, weil Qt-iOS das
>    erzwingt → auf iOS 14 bliebe der 3D-Viewport LEER. Zielgerät ist iPad Pro
>    auf iOS 26; sauber wäre, den App-Floor auf 15 zu heben.
> 6. Material ist `SimpleMaterial` (nicht-metallisch) + Key/Fill-Light: eine
>    metallische PBR-Fläche bräuchte Image-Based-Lighting, das eine
>    `.nonAR`-Szene nicht hat (Risiko: schwarz gerendert).
>
> ---
>
> **Nachtrag M59c (weitere Geräte-Fixes, CI-grün auf 78da7d8):** (1)
> **Skizze-auf-Fläche blickte von der falschen Seite:** `facePicked`
> orientierte die Kamera ENTLANG der Außennormale → man sah von innen durch
> die Rückseite. Fix: entlang `-normale` blicken (Fläche zeigt zur Kamera,
> konsistent mit `n·dir < 0`). (2) **Ursprungsebenen lagen VOR dem Modell**
> statt hindurchzugehen: nur der Ebenen-Rand war tiefengetestet, die
> transluzente FÜLLUNG war ein flaches 2D-Polygon ohne Verdeckung. Neu:
> `drawOccludedQuadFill` (rastert die Ebene in ein Gitter, verwirft verdeckte
> Zellen) → die Konstruktionsebene schneidet jetzt durchs Modell wie in
> Inventor. (3) **Komplexe Profile mit Löchern nicht extrudierbar:**
> `regionsFrom` gab EINE Region PRO Schleife zurück, ein Rechteck-mit-Kreis
> wurde also ZWEI Regionen → Auto-Select (nur bei genau 1 Region) griff nie.
> Neu über gerade/ungerade Verschachtelungstiefe: eine in einer anderen
> liegende Schleife ist deren LOCH, keine eigene Region (Insel im Loch = wieder
> Solid). `regionAt` ist jetzt loch-bewusst (Tipp ins leere Loch wählt nichts).
> Der Shim schneidet Löcher bereits (`faceMk.Add(holeWire)`), also extrudiert
> ein Donut jetzt mit Bohrung. m56-Tests korrigiert + Insel-im-Loch-Test. (4)
> **Kanten-Sägezahn an gekrümmten Flächen:** Kanten liegen auf
> Flächengrenzen, Screen-Space-Selbstverdeckung flackerte bei streifenden
> Winkeln. Neu: Verdeckungs-`extra`-Marge (`SceneOccluders.edgeMargin` = 6× der
> Flächen-Bias) für Kanten/Silhouetten/On-Surface-Overlays. **#4 ist eine
> defensive Marge — Artefakt am Gerät noch zu bestätigen (offline nicht exakt
> reproduzierbar).**
>
> **Offen, ehrlich:** (A) Falls die Artefakte am Gerät bleiben, braucht es die
> tiefere Renderer-Überarbeitung — Canvas hat KEINEN Z-Buffer, Verdeckung
> läuft in Screen-Space (Painter-Algorithmus per Zentroid-Tiefe), das ist bei
> gekrümmten Flächen / sich durchdringenden Solids grundsätzlich fragil.
> Flutters `drawVertices` bietet keinen Tiefenpuffer; eine echte Lösung wäre
> ein Fragment-Shader oder Triangle-Splitting. (B) **Skizzenmodus zeigt kein
> 3D-Modell + keinen Navigationswürfel wie Inventor:** die App wechselt im
> Skizzenmodus auf das flache `Viewport2D` (2613 Zeilen mit allen Sketch-Tools,
> Snapping, Gesten). `paintPartUnderlay` zeigt das Modell zwar geghostet
> flach-von-oben (Inventor blickt auch senkrecht auf die Skizze), aber der
> Würfel fehlt. Echtes „im 3D-Viewport skizzieren" hieße den Sketcher in
> Viewport3D nachzubauen — großer, riskanter Umbau, am Gerät nicht offline
> verifizierbar. Bewusst NICHT spekulativ gemacht; wartet auf Geräte-Feedback.
>
> ---
>
> **Nachtrag M59b (Geräte-Fixes, dieselbe Session):** Drei Geräte-Funde
> behoben. **(1) Facing-/Tiefen-Konvention war global invertiert:** Kamera
> blickt entlang `dir`, eine SICHTBARE Fläche zeigt mit der Außennormale zur
> Kamera zurück (`n·dir < 0`) — der Code nahm `> 0` (also Rückseiten) als
> Front. Bei EINEM konvexen Solid fiel das nicht auf (die Silhouette bleibt
> stimmig, daher „shaded smooth"), brach aber Verdeckung, Silhouetten UND
> Licht. Fix konsistent: `front = n·dir < 0`, Headlight von der Kamera
> (`-dir + tilt`, vorher zeigte Licht von hinten → Fläche zur Kamera war am
> DUNKELSTEN), Verdeckung `td > d + bias` (näher = höhere Tiefe). Das war
> zugleich die Ursache der „zerstörten Mesh-Artefakte" (Rückseiten mit falscher
> Wicklung landeten im selben `drawVertices`-Buffer wie die Front und
> flackerten). Offline verifiziert: exakt die halben Dreiecke sind Front,
> Shade 0.42→0.92 (hell zur Kamera), Skizzenlinie durch den Zylinder fern
> verdeckt / nah sichtbar. **(2) Zeichenreihenfolge für koplanare Fälle:**
> Solids ZUERST, dann Ebenen, dann Skizzen — Bias hält eine koplanare Skizze
> sichtbar und, später gezeichnet, liegt sie OBEN (Skizze > Ebene > Geometrie),
> während echt dahinter liegende Overlays weiter pixelgenau von `occ` entfernt
> werden. **(3) `ClipRect`** um den 3D-`CustomPaint` (Geometrie lief sonst über
> den Model-Browser). Zusätzlich **Face-Hover/Tap tiefenpriorisiert** (nähere
> Fläche schlägt die dahinterliegende Ursprungsebene) und **„Solid Bodies(N)"-
> Ordner** über Origin wie in Inventor (`PartModel.solidBodies()`, Body-Augen-
> Toggle `toggleBodyVisible`, Body = Features gleicher `bodyName`). Tests in
> `m59_shaded_edges_test.dart` erweitert (Verdeckung front/back, Solid-Bodies-
> Aufzählung + Toggle). **Alle Konventions-Vorzeichen offline geprüft; CI +
> Gerät noch zu bestätigen.**
>
> ---
>
> **Vorherige Session (M59, „Shaded with Edges" + Skizzen-Verbrauch):**
> Alle Geraete-Rueckmeldungen aus M58 adressiert, in einem Durchgang (Nutzer:
> „Do all phases at once. Make it professional and production ready.").
> **(A) Rendering** komplett neu: Faces per **Gouraud** (`buildSceneSolid` →
> EIN tiefensortierter `ui.Vertices`-Buffer, Vertex-Normalen-Farben,
> `BlendMode.dst`) statt Flat-Facetten → kein Banding, keine AA-Risse, kein
> Anti-Crack-Stroke, KEIN Mesh-Gitter mehr in der transluzenten Vorschau.
> Kanten **analytisch**: Shim **v4** liefert je Kante Kurven-Records
> (Linie/Kreis/Ellipse), je Face 15 Doubles (Typ + Frame + u/v-Range,
> OUTWARD-Normale mit Orientierungs-Vorzeichen), je Dreieck eine Face-ID; der
> Painter zeichnet runde Kanten als exakte Beziers (`genArcCubics`, ≤30°/Span,
> lokal `M59CHECK: PASS` ~3e-4·r). Verdeckte Kanten via Screen-Grid
> (`SceneOccluders`, Bias = max(1.5·meshLin, 1e-3·maxCoord)), Silhouetten
> gekruemmter Flaechen (`cylinderSilhouettes` analytisch + Mesh-Fallback).
> **(B) Joins** sauber: `occt_unify` (`ShapeUpgrade_UnifySameDomain`) nach
> `occt_fuse` — Schweißnaht-Fragmente weg. **(C) Interaktion**: blaues
> Face-Prehighlight beim Ebenen-Pick (`_pickSolidFace` v4, Face-IDs +
> B-Rep-Records; Fallback Vertex-Normalen fuer FakeKernel). **(D) Sketcher**:
> `paintPartUnderlay` zeigt das 3D-Modell UNTER dem 2D-Sketcher (blickt exakt
> entlang des Skizzen-Frames mit Editor-Pan/Zoom — pixelgenau gegen `map()`
> verifiziert — plus Schleier); fertige Skizze bleibt auf ihrer Face;
> **verbrauchte Skizze = Kind der Extrusion** im Browser (Expander,
> Augen-Toggle `toggleSketchVisible`, `'vis'` persistiert; Legacy-Sidecar →
> versteckt). Shim **v4 = 29 Symbole**, Smoke **[16]** (3 Faces, 2
> analytische Kreis-Kanten r=10, Plane/Cylinder-Records, unify(box|box)→6
> Faces volumenerhaltend). Tests: `m59_shaded_edges_test.dart` +
> **geteilte v4-Fixture** `frontend/test/synth_mesh.dart` (M58 nutzt sie mit).
>
> **Restschuld ehrlich:** Silhouetten fuer Kegel/Kugel/Torus nur Mesh-Fallback
> (analytisch nur Zylinder); verdeckte Kanten unterdrueckt statt gestrichelt;
> Spline-Profile weiterhin polygonal; Cut/Intersect fehlen. **Geraete-Test
> offen** (Xcode/Metal nur am Geraet) — CI deckt Kompilat + Host-Tests +
> Render-Mathe, nicht das visuelle Ergebnis am Bildschirm.
>
> ---
>
> **Vorherige Session (M58, glatte Kurven + Join + Face-Sketch):**
> Vier Nutzer-Punkte umgesetzt: (1) Zylinder = ECHTE Zylinderflaeche statt
> N-Gon-Prisma — `arcFitLoop` (part_model.dart, pur, lokal via Dart-SDK-Replik
> verifiziert) macht aus polygonisierten Loops wieder Boegen (x,y,bulge) und
> `occt_extrude_profile_arcs` (Shim **v3, 24 Symbole**, Smoke **[15]**:
> 3 Faces, Volumen analytisch, Mesh-Edges == 2) extrudiert sie exakt;
> Seam-Edges im Mesher unterdrueckt; Painter zeichnet Fill+gleichfarbigen
> Stroke gegen AA-Risse. (2) Adaptive Tessellation beim Zoomen
> (`viewLinearDeflection`/`KernelSolid.refine`, 80 ms Debounce) + endloser
> Zoom 2D/3D. (3) Extrude-Output **Join/New Solid** (Inventor):
> `recomputeAllFeatures` foldet Join-Ketten per `occt_fuse`; Viewport/Preview
> ueberspringen `consumedByJoin`. (4) **Sketch-on-Face**: planare
> Solid-Flaechen per Raycast waehlbar (`facePicked`, `PlaneFrame` mit
> Origin, JSON-`frame`).
>
> **CI-Runde 1 (29875999227/29875999244) ehrlich GELESEN und ROT** — vier
> echte Fehler gefunden und gefixt: (1) Smoke [15]: 2 Halbboegen ergaben
> ZWEI Halbzylinder-Faces (4 Faces, 6 Mesh-Kanten, 2 echte Vertikalkanten!)
> -> `ShapeUpgrade_UnifySameDomain` (neu: TKShHealing gelinkt) verschmilzt
> Faces+Kanten wieder, Volumen war schon exakt analytisch (1570.796327).
> (2) `sketchFrameOf` rief sich per Blanket-sed SELBST auf (Stack Overflow
> in 4 m56-Tests). (3) m57-FakeKernel fehlte `fuseSolids` (Compile-Fail).
> (4) m58-Testerwartungen korrigiert (Quadrat rotationsinvariant; Sag-Bound
> statt falschem ">180 Segmente"). Runde 2 laeuft mit diesem Push.
>
> **EHRLICH OFFEN:** Shim-v3-C++ ist lokal NICHT kompiliert (kein
> OCCT-Checkout) — occt-build.yml ist das Gate; Host-Tests
> (`m58_smooth_solids_test.dart` + angepasstes m56-FakeKernel) laufen erst
> in CI; Geraete-Smoke offen. Arc-Fit erfasst nur Kreis-Runs — Splines/
> Ellipsen bleiben polygonal (naechster Schritt: Segment-Info direkt aus der
> Region-Verkettung). Cut/Intersect fehlen. Face-Pick prueft Planaritaet
> ueber Tessellations-Vertex-Normalen (|dot| >= 0.9999), nicht ueber
> B-Rep-Face-Identitaet.
>
> ---
>
> **Stand dieser Session (Kopf = M56, 3D-Teile + Extrude):** Der komplette
> Workflow steht: **+ > New 3D Part** -> **Start 2D Sketch** -> Ebene im
> 3D-Viewport antippen -> der UNVERAENDERTE 2D-Sketcher zeichnet auf dieser
> Ebene -> **Finish Sketch** -> zurueck im 3D-Teil -> **Extrude** mit dem
> Inventor-Eigenschaftsfenster (Profile-Pick im Viewport, 4 Richtungen,
> Distance A/B, Taper, Body Name, OK/Cancel/+) -> das Solid steht im
> Viewport. Host: **331 Tests gruen** (30 neue in `m56_part_test.dart`),
> `flutter analyze` **0 errors**.
>
> **Was NEU ist (Details unten unter M56):**
> - `backend/occt/shim` -> **v2, 23 Symbole**: `occt_extrude_profile`
>   (Multi-Loop = Loecher, + Taper mit Inventor-Vorzeichen),
>   `occt_transform` (starre Platzierung) und 7 Mesh-Funktionen
>   (Tessellation fuer die Anzeige). Die drei `-ge 14`-Gates in BEIDEN
>   Workflows stehen jetzt auf **23**. `smoke_occt.c` prueft die neuen
>   Pfade mit harten Zahlen ([7]-[14], u.a. Frustum-Volumen analytisch,
>   Loch schrumpft bei positivem Taper, Mesh-Volumen per Divergenzsatz =
>   +6000 als Winding-Beweis).
> - `frontend/lib/part_model.dart` (neu): Ebenen-Frames, Profil-Erkennung
>   (Kanten-Verkettung ueber Endpunkte, Loch-Hierarchie), ExtrudeFeature,
>   Kernel-Bruecke `PartKernel` (Tests injizieren ein Fake, die App
>   NIEMALS — ohne Kernel gibt es kein Fake-B-Rep).
> - `frontend/lib/widgets/viewport3d.dart` (neu): der 3D-Viewport als
>   reiner CustomPainter (0 neue Dependencies) — Ortho-Kamera wie im
>   Dummy, ViewCube mit Face/Edge/Corner-Snap, Triade, Zoom-to-Cursor,
>   Plane-Pick, Profil-Highlight, Painter-sortierte Solids.
> - `frontend/lib/widgets/extrude_dialog.dart` (neu): das
>   Eigenschaftsfenster aus dem Referenz-Screenshot.
> - Icons (CR/MO/WF/PT/PL/AX/PN + Part-Tree) 1:1 aus dem HTML-Dummy
>   nach `svg_icons.dart` portiert.
>
> **OFFENE SCHULD (ehrlich):** wie bei M55 fehlt der GERAETE-Beweis. Auf
> dem Host sind die occt_*-Symbole nicht gelinkt, d.h. `OcctPartKernel`
> meldet korrekt `available == false` und KEIN Solid entsteht — die
> Extrude-Logik ist host-getestet, der echte B-Rep-Pfad (Profil ->
> occt_extrude_profile -> Mesh -> Anzeige) lief noch nie. Auf dem iPad
> muss der erste Start `DART SMOKE: PASS (backend=occt-ffi, shim v2, ...)`
> zeigen; danach das Extrude eines Rechtecks: Solid sichtbar, schattiert,
> mit Kanten. Bis dahin gilt: "verdrahtet, gegated, host-getestet —
> Geraete-Smoke ausstehend".
>
> **Naechste Schritte:** (1) Geraete-Test des Workflows. (2) Die
> restlichen Create-/Modify-Buttons sind bewusst noch Platzhalter
> (Revolve/Sweep/Loft/Hole/Fillet/...) — Muster: Feature-Klasse neben
> ExtrudeFeature, Shim-Funktion + Smoke + die drei Symbol-Gates
> hochzaehlen. (3) Booleans zwischen Features (der Shim kann `fuse`
> bereits; die UI entscheidet noch nicht Join/Cut/Intersect).
>
> **Stand davor (Kopf = M48, natives Kontextmenue):** M48 ist neu
> und host-getestet (**245 Tests gruen**, `flutter analyze` ohne neue Issues).
> Der IPA-Job baut jetzt auf **macos-26 (Xcode 26 / iOS-26-SDK)** — siehe M48.
>
> **Stand davor (Kopf = commit `05727ec` + M46 + M47):** letzte
> Arbeiten M41–M47, alle host-getestet (**222 Tests gruen**, `flutter analyze`
> ohne neue Issues). Kurz:
> - **M41** Inventor-Parameter/Ausdruecke im Bemassungs-Edit-Feld (d0/d1,
>   Formeln, Referenzen, fx:-Anzeige).
> - **M42** Hover-Highlight auf Bemassungs-Labels; ausserhalb des
>   Layer-Editiermodus sind Bemassungen/Constraints/DOF/Construction
>   unsichtbar. **M42-Fix** Tastatur-Race beim Referenz-Klick.
> - **M43** Parameters-Fenster (fx, verschiebbar) mit User-Parametern.
> - **M44** Insert: parametrischer Text, Bild-Import, DXF-Import (iOS-Picker).
> - **M45** Insert-Geraete-Fixes (Bild-Resize-Griff, Layer-Dimming,
>   Cursor-Platzierung, DXF-Rezentrierung) + verschiebbares Text-Fenster
>   (Font/Groesse/Klick-Referenz `"d0"`) + auto-grosses Construction-
>   Bounding-Rect mit Ecken-Snap-Punkten.
> - **M46** Tastenkuerzel werden unterdrueckt, waehrend ein Textfeld
>   (Parameters/Text/Inline-Bemassung) getippt wird.
> - **M47** Direkter Body-Drag: Linie/Kreis/Bogen/Polylinie/Spline/Ellipse am
>   KOERPER (nicht nur am Punkt-Griff) starr verschieben; angebundene Geometrie
>   folgt ueber die Constraints. Eingebettet in die Griff-Zug-Maschinerie
>   (`Grip.body`-Sentinel in `dragGrip`, neue `translateGeo`, Body-Drag meldet
>   ALLE Entity-Punkte als `dragged`). Voll gebundene Geometrie ist gesperrt
>   (faellt auf Box-Select zurueck), Projektionen/Fremd-Layer nicht ziehbar,
>   Begin lazy beim ersten Move (Tap waehlt weiter aus, kein No-Op-Rebuild),
>   kein Snapping (reine Translation). `m47_body_drag_test.dart` (8 Tests).
>
> **Offene Punkte fuer die naechste Session:**
> - Geraete-Test von M41–M47 steht aus (Host-Tests gruen, IPA aus Run
>   `05727ec`/spaeter ziehen und auf dem iPad pruefen). Fuer M47 auf dem Geraet
>   pruefen: Body-Drag fuehlt sich per Pencil/Finger fluessig an, die
>   Tap-vs-Drag-Trennung (Greifpunkt-Toleranz `_gripPx`=12 px) stimmt, und der
>   Zug an einer angebundenen Linie fuehrt die Nachbargeometrie erwartungsgemaess
>   nach (natives libslvs = weicher Wunsch, waehrend der Host-LM-Pfad ALLE
>   Entity-Punkte hart friert — auf dem Geraet also potenziell "weicher").
> - Text-Bounding-Rect ist ein Painter-Overlay mit Snap-Punkten, KEINE echte
>   Solver-Geometrie (siehe M45): an die Ecken kann man bemaßen, die Kanten
>   sind aber keine selektierbaren, constrainbaren Entities. Volle
>   Solver-Integration (wie projizierte Geometrie gepinnt) waere der naechste
>   grosse Schritt, falls gewuenscht.
> - `file_picker` ist die erste Plugin-Abhaengigkeit (M44) — CI-Pod-Install
>   im iOS-Build von `05727ec`/spaeter verifizieren.


- **M1 — Headless-Core-Build + iOS-CI: ERLEDIGT** (statische Libs, arm64/iphoneos).
- **M2 — C-Wrapper: ERLEDIGT & validiert**; in M5 um Geometrie-Abfrage erweitert
  (`qcad_entity_ids`, `qcad_entity_geometry`), lokal per Compile-Check gegen die
  echten QCAD-Header validiert; Runtime-Validierung via erweiterten smoke.c im
  M3-Sim-CI-Job (Marker lesen!).
- **M3 — Headless-Logiktest iOS-Simulator: ERLEDIGT** (smoke.c jetzt inkl.
  Geometrie-Query-Checks — Log des naechsten Runs pruefen).
- **M4 — Mock-Phase ABGESCHLOSSEN** (create-panel.html = verbindliche 1:1-Spec,
  UI-Details siehe Abschnitt unten).
- **M5 — Grundausbau ERLEDIGT & CI-validiert (Run 29145382350, alle 3 Jobs
  gruen, LOGS GEPRUEFT):**
  - `frontend/` KOMPLETT NEU: 1:1-Flutter-Port des Mocks (Ribbon alle 8 Panels
    + Exit/Finish + Home-Sketch-Panel, Flyouts mit exakten Eintraegen,
    Model-Browser inkl. Origin-Expander/Kontextmenue/Edit-Highlight,
    Layer-Edit-Modus mit grauen Achsen + gelbem projizierten CP, Home-View
    mit Recent-Karten, untere Tab-Leiste). Alter main.dart (8e241b3) ERSETZT.
    Struktur: lib/main.dart, theme.dart, svg_icons.dart (Mock-SVGs verbatim,
    flutter_svg), app_state.dart, ffi/qcad_engine.dart, widgets/{ribbon,
    model_browser,viewport,home_view,bottom_tabbar}.dart
  - Echtes Zeichnen ueber das Backend: Line, Circle (Center), Rectangle
    (Two Point, geschlossene Polyline), Arc (Three Point) via FFI; Rendering
    aus dem QCAD-Dokument (qcad_entity_ids/qcad_entity_geometry — Linux-Smoke
    UND iOS-Sim-Smoke PASS inkl. Geometrie-Checks). Uebrige Buttons sichtbar,
    ohne Funktion. Fallback-Engine (Dart) wenn Libs nicht gelinkt; Start-
    Marker: `DART SMOKE: PASS (backend=qcad-ffi|dart-fallback)`.
  - Save/Load: DXF pro Skizze + Preview-PNG in App-Documents (Autosave bei
    Finish/Tab-Schliessen/Home); Recent-Karten zeigen echte Skizzen, die 6
    Design-Dummies nur im Erststart.
  - Eingabe: Maus/Keyboard; Trackpad-2-Finger-Pan + Pinch-Zoom (PointerPanZoom)
    integriert, Scrollrad zoomt, Esc bricht Tool ab. Touch-Gesten spaeter.
  - **IPA: CI-Job `m5-flutter-ipa` liefert Artefakt `prototype-unsigned-ipa`**
    (unsigniert, ~15 MB, Retention 3 Tage — pro Run neu erzeugt). Verifiziert:
    "M5 LINK CHECK: PASS" + alle 14 `_qcad_*`-Symbole per nm EXPORTIERT im
    Runner-Binary (DynamicLibrary.process() findet sie). Installation:
    Artefakt laden, entzippen -> prototype-unsigned.ipa, per Sideloadly oder
    AltStore aufs iPad (re-signiert mit eigener Apple-ID).

  **CI-Fix-Erkenntnisse M5 (fuer die Zukunft):**
  - Qt-Static-Link fuer Xcode NICHT per Archiv-Glob: die QQml*Foreign-
    Registrierungsobjekte GENERIERT der Qt-CMake-Finalizer im Konsumenten-
    Build, sie existieren nicht im Qt-Paket. Loesung: Device-Smoke mit
    `-DQCAD_CAPI_SMOKE=ON` bauen und die exakte Linkzeile via
    `ninja -C build -t commands` extrahieren (Ninja hat KEIN link.txt),
    mit `ci/parse_link_txt.py` in OTHER_LDFLAGS uebersetzen (cwd=Build-Root).
  - qcad_* ueberleben per `-force_load libprototype.a` +
    `-Wl,-exported_symbols_list` (`_qcad_*`); qios-Plugin NIE linken
    (interponiert main). IPHONEOS_DEPLOYMENT_TARGET=14.0 im pbxproj sedden
    (Target-Settings schlagen xcconfig).
  - `strings | grep -q` unter pipefail = SIGPIPE-Falle -> `grep -c` nutzen.

  **Offen fuer M6:**
  - Nutzer-Test des IPA auf dem iPad (App-Start-Marker `DART SMOKE:` in der
    Konsole pruefen — MUSS `backend=qcad-ffi` melden, nicht dart-fallback).
  - Sim-CI-Job, der den DART-SMOKE-Marker der Flutter-App captured
    (M2-Restschuld formal; Symbole sind exportiert, Runtime on device offen).
  - Weitere Werkzeuge aus der frueheren Tool-Engine (Dimension, Modify, Snap),
    Layer-Zuordnung im Backend (aktuell eine Backend-Layer "0",
    Layer-Zuordnung nur Dart-seitig), Touch-Gesten.

- **M8-Fix / M9–M11 — Parametrik + echter Constraint-Solver (libslvs): ERLEDIGT
  & CI-validiert (Run 168b35e, beide Workflows alle Jobs gruen, Schritt-Status
  gelesen). NUR GERAETE-TEST OFFEN.**
  - QCAD hat KEINEN Constraint-Solver (Maintainer bestaetigt, kein geplant) →
    Pfad B: SolveSpace-Solver `libslvs` (GPLv3, C-API) via FFI eingebettet,
    QCAD bleibt fuer Geometrie/DXF.
  - **M9** `backend/slvs/`: libslvs vendored (nur C++-stdlib, keine Deps),
    baut STATISCH fuer iOS (arm64/iphoneos, min 14.0) → `build-ios/libslvs.a`.
    Eigener Workflow `slvs-build.yml` (Host-Smoke + iOS-Static, beide gruen).
  - **M9.2** FFI-Shim `backend/slvs/shim/slvs_shim.{h,cpp}`: eine flache
    C-Funktion `slvs_solve(...)` ueber libslvs; deckt alle CTypes +
    Dimensionen ab (H/V, coincident, point-on-line, parallel/perp, collinear,
    concentric, equal, tangent, symmetric, dist/dist-x/-y, dia/rad, angle,
    dragged). `tests/shim_test.c` asserted die realen App-Szenarien numerisch
    (Rechteck+Breite, Kreis-Durchmesser, Punkt-auf-Linie, X/Y-Mass, Ueber-
    bestimmung, Drag) → „ALL SHIM TESTS PASS" (Host-CI-Gate).
  - **M10** Dart: `frontend/lib/ffi/slvs_ffi.dart` (Bindings via
    DynamicLibrary.process()); `solver.dart` `_trySolveWithSlvs()` zerlegt den
    Sketch → Punkte+Entities, mappt Constraints, ruft nativ, VERIFIZIERT das
    Ergebnis ueber die vorhandenen Dart-Residuen und faellt bei Nicht-Erfuellung
    / ungelinktem Symbol / ungemapptem Feature (smooth) auf den Dart-LM-Solver
    zurueck → libslvs ist STRIKT SICHER (nie schlechter als vorher).
  - **M10 UX** (Inventor): Auto-Constraints IMMER an (Button entfernt,
    `autoConstrain` final true); DOF-Faerbung pro Entity (weiss=voll bestimmt,
    violett-blau 0xFF9A8CF5=unterbestimmt, blau=selektiert); Live-Bemassungs-
    Preview (nach Auswahl folgt das Mass dem Cursor, Klick platziert); Masse
    mm-Default + cm/m-Eingabe; klareres Coincident-Icon; Rechteck/Polyline
    Auto-H/V + Ecken-Auto-Coincident/Point-on-Line.
  - **M11** iOS-Link: neuer Job-Schritt baut `libslvs.a`, `ffi.xcconfig`
    `-force_load libslvs.a` + Export `_slvs_*`, Link-Check greppt den Shim-
    Marker „Prototype SLVS shim" per `strings` im Runner (analog QCAD-Check,
    PASS). → auf dem Geraet ist `SlvsFfi.available` true, `solveConstraints`
    nutzt den echten Solver.
  - **OFFEN (nur auf dem iPad pruefbar, hier nicht):** Laufzeit-Verhalten des
    nativen Solvers + der neuen UX auf dem Geraet. Das Verify+Fallback-Netz
    garantiert nur „nicht schlechter als Dart-Solver", nicht die exakte
    Wunsch-Semantik. Beim Test: Rechteck geht auf Masseingabe sauber auf,
    Faerbung weiss/violett stimmt, Bemassungs-Preview folgt dem Cursor,
    Auto-Constraints ohne Button. IPA-Artefakt aus dem M5-Job (unsigniert).

- **M11-Fix — Fenster wieder heil (Geraete-Test 1): ERLEDIGT.** Auf dem iPad war
  der Ribbon zerrissen und der Model-Browser weg: ein RangeError im
  Constrain-Grid liess den Build-Callback werfen, im RELEASE-Build ersetzt
  Flutter das dann durch ein graues ErrorWidget (kein roter Debug-Screen) —
  daher der graue Block statt Viewport/Browser. MERKE: grauer Kasten in der App
  = geworfene Exception, nicht Layout-Pfusch.

- **M12 — Auto-Coincident auf den projizierten Center Point: ERLEDIGT
  (Geraete-Test 2 offen).** Symptom: eine Rechteck-Ecke rastet per 'origin'-Snap
  exakt auf den CP, blieb aber frei verschiebbar. Ursache: der projizierte CP ist
  KEINE Entity — der Viewport malt ihn nur per `map(0,0)`, und
  `inferConstraints` vergleicht neue Punkte ausschliesslich gegen vorhandene
  Entities (`j < newIdx`). Zum Ursprung gab es also nichts zu binden.
  - Loesung: Sentinel `kProjCenter = -1` (`constraints.dart`) als Punkt-Ref auf
    den CP. `inferConstraints` erzeugt bei `|q| < 1e-6` ein echtes
    Coincident `PRef(-1,0) <-> PRef(neu,p)` — mit Vorrang vor Endpunkt- und
    Point-on-Line-Inferenz.
  - Der Dart-LM-Solver konnte das SCHON: `_pointAt` liefert fuer `ent < 0`
    Offset.zero (keine freien Parameter), `residualCount` zaehlt 2 Gleichungen
    -> Punkt ist voll bestimmt, DOF sinkt um 2, Faerbung wird weiss.
  - libslvs: `pOf` mappt `ent < 0` jetzt auf einen LAZY angelegten Punkt
    `addPoint(0,0, fix: true)`. Ohne das waere das Constraint stillschweigend
    gefallen, das Verify-Netz haette gegriffen und JEDE Skizze mit Ursprungs-Snap
    waere auf den Dart-Solver zurueckgefallen.
  - Fallstrick mitgefixt: `constraintGlyphs` haette `gs[-1]` indiziert ->
    RangeError -> grauer Screen (siehe M11-Fix). Guards jetzt ueber `isRealPt`.
  - Ebenfalls mitgefixt: `remapAfterRemove` hat beim Loeschen einer Entity
    `anchors` und `driven` verschluckt — Fix-Constraints verloren ihren Anker,
    Referenzbemassungen wurden wieder treibend.
  - NICHT enthalten: der CP ist weiterhin nicht als manuelles Constraint-/
    Bemassungsziel pickbar (`_projCpSelected` im Viewport ist nur ein Farb-
    Toggle aus dem Mock). Mit dem Sentinel waere das jetzt leicht nachzuruesten.

- **M13 — Voll bestimmte Punkte sind nicht mehr von Hand ziehbar + Lock immer
  anwendbar: ERLEDIGT (Geraete-Test offen).**
  - **Grip-Drag:** ein gegroundeter Punkt liess sich weiter mit der Maus greifen
    und verschieben und sprang beim naechsten Solve zurueck. Ursache:
    `displayGeometry` PINNT den gezogenen Punkt hart am Cursor
    (`pinned: {(ent,idx)}`), das schlaegt jedes Constraint — beim Loslassen
    gewinnt dann wieder das Coincident. Inventor laesst voll bestimmte Geometrie
    gar nicht erst anfassen: der Grip-Hittest im Viewport ueberspringt jetzt
    Grips, deren Punkt nicht in `analysis.freePoints` liegt (Geste faellt auf
    Box-Select durch), `beginGripDrag` guardet zusaetzlich.
  - **FALLE dabei:** `Grip.idx` ist NICHT immer ein Punktindex — ein Kreis hat
    genau 1 Punkt (Mittelpunkt), seine Radius-Grips tragen idx 1..4. Der Filter
    greift darum nur fuer `idx < ptCount(entity)`, sonst waeren Kreise nicht mehr
    skalierbar gewesen.
  - **Lock/Fix:** war "manchmal nicht anwendbar", weil `_addConstraint` JEDES
    Constraint durch `wouldOverconstrain` schickt. Fix traegt 2 Gleichungen pro
    Punkt bei; hatte das Ziel weniger freie DOF uebrig, stieg der Rang nicht um 2
    -> abgelehnt. Fix ist aber kein normales geometrisches Constraint: es groundet
    Geometrie WO SIE IST (Anker = aktuelle, bereits geloeste Position), kann also
    nie widersprechen — libslvs modelliert es nicht mal als Gleichung, sondern
    setzt `fixed[gi]=1`. Fix ist jetzt vom Ueberbestimmungs-Test ausgenommen und
    wird nur noch abgelehnt, wenn dasselbe Ziel (oder die besitzende Entity)
    schon gelockt ist.
  - **Mitgefixt:** `analysis` haengt an AppState, wurde aber beim Wechsel auf
    einen BEREITS OFFENEN Tab nicht neu berechnet — die DOF-Faerbung zeigte dann
    die vorige Skizze, und mit dem neuen Grip-Filter waeren die falschen Punkte
    gesperrt gewesen. `_reanalyze()` haengt jetzt an goHome/openSketch/closeTab.

- **M14 — Live-korrekter Drag, Bemassung auf Rechteckkanten, Hover-Highlight:
  ERLEDIGT (Geraete-Test offen).**
  - **Drag (der eigentliche Bock).** Symptom: beim Ziehen einer Ecke wurde die
    "vertikale" Kante schraeg und der gegroundete Punkt wanderte mit; erst beim
    naechsten sauberen Solve sprang alles zurueck. Kette aus DREI Fehlern:
    1. `SH_DRAGGED` war auf `SLVS_C_WHERE_DRAGGED` gemappt. Das ist ein HARTES
       Constraint ("Punkt ist exakt hier") und ueberstimmt damit die echten.
       Nachgemessen: Vertical + gelocktes Ende + Zug nach (25,55) ergab (25,55)
       — das Vertical wurde einfach ignoriert.
       RICHTIG ist `Slvs_System.dragged[]` (slvs.h Z.160): "causes the solver to
       favor that parameter, and attempt to change it as little as possible".
       Das ist der WEICHE Wunsch. Ergebnis jetzt: (0,55) — x haelt, y gleitet.
    2. Der Shim warf konvergierte Loesungen weg: libslvs faltet
       `REDUNDANT_OKAY` auf `SLVS_RESULT_INCONSISTENT` (lib.cpp), der Shim
       kopierte Koordinaten aber nur bei OKAY zurueck. Jetzt auch bei
       INCONSISTENT — das Dart-Verify entscheidet, ob es taugt.
    3. Der Dart-Fallback fror die gezogenen Parameter ein (`frozen[]`). Bei
       unerreichbarer Cursor-Position rechnet LM dann einen Least-Squares-
       Kompromiss, der die CONSTRAINTS verbiegt. Jetzt freeze-then-relax:
       erst Cursor exakt versuchen, und nur wenn die Constraints so nicht
       halten, Freeze fallen lassen und die Skizze zurueck auf die
       Constraint-Mannigfaltigkeit ziehen.
    - Regressionstests im Host-CI-Gate: `shim_test.c` [7] (Constraint gewinnt,
      Punkt gleitet, Anker unbewegt) und [8] (Rechteck bleibt Rechteck, Anker
      haelt, Breite kollabiert nicht).
  - **Bemassung auf Rechteckkanten.** `buildDimensionAt` kannte nur
    line/circle/arc — ein Rechteck ist aber EINE geschlossene Polyline, also kam
    `null` zurueck und es passierte gar nichts. `_dimensionClick` loest den Klick
    jetzt auf das Segment darunter auf (`polySegmentAt`) und bemasst dessen zwei
    Ecken: echte treibende Laengenbemassung ueber den vorhandenen
    Punkt-zu-Punkt-Pfad, inklusive ausgerichtet/horizontal/vertikal.
    NICHT enthalten: Winkelbemassung zwischen zwei Polyline-Kanten (braucht
    Entity-Refs auf Linien).
  - **Hover-/Pick-Highlight.** Es gab gar keinen Entity-Hover-State. Neu:
    `hoverEnt` / `hoverEdge` (bei Polylines die exakte Kante unter dem Cursor)
    und `pickedEdge`; der Painter legt einen Halo UNTER die Geometrie, damit die
    DOF-Faerbung darueber lesbar bleibt. Picks von Bemassungs-/Constraint-Tools
    bleiben markiert, bis das Kommando fertig ist.

- **M15 — Diagnose-Log auf dem Geraet: ERLEDIGT.** Der Logger existierte, aber
  `solver.dart` hatte NULL Log-Aufrufe (der Drag-/Solver-Pfad war blind), und
  `_write` machte `flush:true` PRO ZEILE — bei 60 Solves/s haette das genau die
  Interaktion abgewuergt, die es aufzeichnen soll.
  - Jetzt gepuffert (120 Zeilen / 400 ms / Lifecycle), WARN+ERROR sofort
    synchron (ueberlebt harten Crash). `Log.every(key, ms)` drosselt die
    60-Hz-Pfade. Rotation bei 8 MB, Commit-SHA per `--dart-define=GIT_SHA`.
  - `diag.dart`: reproduzierbare Dumps von Geometrie + Constraints, dazu
    `geoFinite`/`allFinite`/`maxAbs` und `gripStr` (zeigt, ob `grip.idx`
    ueberhaupt ein Punktindex ist — bei Kreisen ist er das fuer die vier
    Radius-Grips NICHT).
  - LOG-PFAD: Dateien-App > Auf meinem iPad > prototype > logs >
    `prototype_log.txt` (die Info.plist-Keys setzt der M5-Job bereits).
  - SCHRANKEN (zugleich Fix): `displayGeometry` laeuft INNERHALB von
    `CustomPainter.paint`. Eine Exception dort bricht den Paint ab, alles danach
    bleibt ungemalt — das sieht aus, als waere die Geometrie verschwunden. Und
    NaN/Inf laesst Skia kommentarlos fallen. Beides wird jetzt abgefangen,
    geloggt und auf die letzte gute Geometrie zurueckgefallen; `solveConstraints`
    verweigert nicht-endliche Ergebnisse, der Paint-Loop guardet pro Entity.

- **M16 — Geometrie strikt an Layer gebunden + Sichtbarkeits-Auge: ERLEDIGT
  (Geraete-Test offen).** Vorher kannte die Engine ueberhaupt keine Layer,
  `s.layers` war eine reine Namensliste, und zeichnen ging auch ohne Edit-Mode —
  "jede Linie gehoert zu einem Layer" war damit schlicht nicht wahr.
  - **Backend:** C-API um `qcad_layer_add` / `qcad_set_current_layer` /
    `qcad_entity_layer` erweitert. `addEntity` bindet die Entity VOR dem
    Einfuegen an den aktuellen Layer (`RLayer` + `REntity::setLayerId`) —
    dadurch ueberlebt die Zuordnung den DXF-Roundtrip. Die Export-Liste ist
    `_qcad_*` (Wildcard), neue Symbole sind also automatisch dabei.
  - **FALLE (wichtigste Lehre):** `Geo` traegt jetzt einen `layer`, und der
    SOLVER SCHREIBT BEI JEDEM SOLVE JEDE ENTITY NEU. Ohne `Geo.withData()`
    (behaelt den Layer) waere nach dem ersten Drag die ganze Skizze auf Layer 0
    gelandet. Darum: `withData`/`onLayer` statt roher Konstruktor, und
    Modify/Fillet stempeln den Quell-Layer an den FUNKTIONSGRENZEN
    (`_sameLayer`/`_sameLayerAll`), nicht an ~20 Konstruktionsstellen.
  - **Edit-Mode:** `selectTool` und `toolClick` verweigern ausserhalb des
    Edit-Modes, das Ribbon bricht schon vor dem Parameterdialog ab. Neue
    Geometrie wird im `_commitTool` zwingend auf `editingLayer` gestempelt — das
    ist die EINZIGE Stelle, an der Geometrie entsteht. `_rebuildEngine` loggt
    laut, wenn eine Entity einen dem Sketch unbekannten Layer traegt.
  - **Auge:** pro Layer im Model Browser. Unsichtbare Layer werden nicht gemalt,
    nicht gepickt, nicht gesnappt, haben keine Grips und fliegen aus der
    Selektion. Sichtbarkeit filtert NIE die Geometrieliste — Constraint-Refs
    sind index-basiert, es wird nur uebersprungen. Snap darf gefiltert werden
    (`Snap` traegt keine Indizes), Grips NICHT (die tragen welche).
  - **Persistenz:** Layerliste kommt beim Laden aus dem Dokument zurueck (DXF
    Gruppencode 8); leere Layer + Auge-Zustand liegen in `<name>.layers.json`.

- **M17-Fix — Ribbon-Buttons waren fast alle tot (Hit-Test), Flyout wieder
  garantiert gefuellt.** Vom Nutzer gemeldet: „nur ein Werkzeug benutzbar, die
  Werkzeuge im Dropdown gehen nicht, Dropdown-Hintergrund durchsichtig".
  - **URSACHE (die eigentliche Lehre):** `GestureDetector` ist per Default
    `deferToChild`. Das Kind ist ueberall im Ribbon ein `Container` mit
    **`decoration:`** — und das ist eine `DecoratedBox`, die NIE einen Hit-Test
    schluckt. (`Container(color:)` waere eine `ColoredBox` und schluckt ihn
    sehr wohl — genau darum funktionierten die Model-Browser-Zeilen die ganze
    Zeit.) Getroffen hat also nur, was selbst hit-testbar ist: `Text`
    (`RenderParagraph.hitTestSelf == true`). Folge: grosse Create-Buttons nur
    auf dem Label-Wort klickbar, **jede icon-only Zelle (Constrain-Grid,
    Modify-Grid) komplett tot** (flutter_svg malt in eine RenderBox, die keinen
    Hit meldet), und im Flyout landete alles ausser dem Label-Text auf der
    hit-opaken `ColoredBox` des Menues → Tap wurde verschluckt, es passierte
    schlicht NICHTS.
  - **FIX:** `behavior: HitTestBehavior.opaque` auf `_Hover` (der Wrapper hinter
    JEDEM Ribbon-Button) und `_FlyRow`. Das ▼ hatte es schon — darum liess sich
    das Flyout immer oeffnen, aber nichts darin auswaehlen. Verschachtelung
    bleibt korrekt: das ▼ liegt tiefer im Hit-Test-Pfad und gewinnt die Arena,
    der Button-Body startet weiter das Default-Tool (Inventor-Verhalten).
  - **REGEL:** Jeder Ribbon-/Menue-Tap-Target braucht ein explizites
    `HitTestBehavior.opaque`. Ein Button, dessen einziges Kind ein Icon ist, ist
    ohne das nicht anklickbar — und faellt in keinem Analyzer-Lauf auf.
  - **DURCHSICHTIGES MENUE = LAYOUT-BUG, NICHT PAINT-BUG (die zweite Lehre).**
    Der Save-Layer/`BoxShadow`-Verdacht aus M7 war FALSCH — darum hat ihn
    wegzunehmen auch nichts geaendert. Wahre Ursache: ein `Positioned(left/top)`
    im Stack wird mit UNBESCHRAENKTEN Constraints gelayoutet, und
    `CrossAxisAlignment.stretch` in einer Column heisst
    `BoxConstraints.tightFor(width: constraints.maxWidth)` — also
    **tightFor(width: INFINITY)**. Jede Menuezeile bekam eine unendliche Breite.
    `BoxConstraints(minWidth: 186)` ist ein BODEN, keine DECKE, hat also nichts
    abgefangen. Im Debug-Build wirft das („was given an infinite size during
    layout"); im RELEASE-IPA sind die Asserts aus, die Groesse bleibt unendlich,
    Impeller verwirft den nicht-finiten `drawRect` (= die Fuellung) und malt nur
    noch die finiten Glyphen. Ergebnis: Icons und Labels schweben ohne Panel
    ueber der Skizze.
  - **FIX:** endliche Breite erzwingen — `ConstrainedBox(minWidth: 186,
    maxWidth: 320)` + `IntrinsicWidth` (haengt sich weiter an die breiteste
    Zeile, wie im Mock). Dieselbe Falle im Model-Browser-Kontextmenue
    (`_CtxRow` nutzt `width: double.infinity` unter demselben unbeschraenkten
    `Positioned`) → dort `maxWidth: 260` ergaenzt.
  - **REGEL:** Ein Overlay-Menue darf NIE die unbeschraenkten Constraints des
    Stacks erben. Immer eine harte Breiten-Decke setzen. Und: ein Fehler, der
    NUR im Release-IPA auftritt und im Debug wirft, ist fast immer eine
    verletzte Layout-Invariante — nicht der Rasterizer.
- **M18 — Produktionsreifes Layer-System (Lock / Rename / Delete / Move + ehrliches
  "0"): IMPLEMENTIERT, aber LOKAL NICHT GEBAUT.** Das Arbeits-Environment hatte
  weder Flutter (Dart-SDK-Host blockiert) noch Qt/Cmake, also steht die
  Verifikation ueber CI (`flutter analyze` + iOS-Build) UND der Geraete-Test noch
  aus. Frontend-only, nutzt bewusst den vorhandenen Backend-Layer-Pfad
  (Entity->Layer-Bindung + DXF-Roundtrip) — KEINE neue C++-API, damit der
  iOS-Build nicht durch ungetesteten Core-Code kippt.
  - **Ursache des Nutzer-Bugs ("alles landet auf Layer 0"): GEFUNDEN + GEFIXT in
    M19 (siehe unten).** Die fruehere Vermutung "IPA vor M16" war FALSCH — der
    Bug steckte im C-API: `qcad_set_current_layer` setzte nur den eigenen
    QString, aber NICHT den Dokument-Current-Layer, und `RTransaction` stempelt
    jede neue Entity mit `doc->getCurrentLayerId()` (== "0"). Empirisch mit dem
    echten QCAD-Core reproduziert und verifiziert.
  - **Lock:** `SketchModel.lockedLayers`. Gesperrter Layer bleibt sichtbar, ist
    aber read-only (kein Werkzeug, kein Pick/Drag/Constrain/Dimension, nie
    Editier-Layer). `geoEditable` + `enterEdit` respektieren es; Padlock im Model
    Browser neben dem Auge, im Kontextmenue Lock/Unlock.
  - **Rename:** stempelt alle Entities des Layers via `Geo.onLayer` um (ueberlebt
    so den DXF-Roundtrip), zieht Eye/Lock/Edit-Status mit. "0" ist gesperrt, und
    nach "0" umbenennen ist verboten (reserviert).
  - **Delete:** entfernt die Geometrie hoechster-Index-zuerst und remappt die
    index-basierten Constraints (`remapAfterRemove`, exakt wie Trim/Split). "0"
    kann nicht geloescht werden. Mit Bestaetigungsdialog.
  - **Move (Selektion -> Layer):** re-stempelt die aktuelle Selektion auf den
    Ziel-Layer. Das ist der Weg, ALTE Skizzen zu retten, deren Geometrie auf "0"
    gestrandet ist: (ausserhalb des Edit-Mode) alles per Box-Select waehlen ->
    Rechtsklick Ziel-Layer -> "Move N here".
  - **Ehrliches "0":** die Pflicht-DXF-Ebene "0" ist wie in AutoCAD nicht
    umbenennbar/loeschbar und wird NUR angezeigt, solange sie Geometrie traegt;
    leer fliegt sie aus dem Browser (`_pruneEmptyBaseLayer`) — kein Phantom mehr.
    Neue Skizzen starten weiterhin ohne Layer (Zeichnen erst nach "Start New
    Layer", Design-Vorgabe M16).
  - **Persistenz:** Sidecar jetzt versioniert (v2) mit Reihenfolge + hidden +
    locked; das alte `{layers,hidden}` wird weiter gelesen. Basis-"0" wird nur mit
    Geometrie persistiert, damit sie nach dem Leeren nicht zurueckkehrt.
  - **Reference-Darstellung:** im Edit-Mode wird Geometrie fremder/gesperrter
    Layer gedimmt (grau, `refPaint`) gemalt, damit die DOF-Farben des aktiven
    Layers lesbar bleiben.
  - **Bewusst NICHT enthalten (jeweils mit Grund):** per-Layer-Farbe fuer die
    Geometrie — kollidiert mit der Inventor-DOF-Faerbung (weiss=voll bestimmt,
    violett=unterbestimmt), die die App traegt; und Backend-Persistenz der
    Layer-Attribute (Farbe/Off/Locked) im DXF-Layertable — dafuer waere neue
    C++-API (`RLayer` get/set + Enumerate) noetig gewesen, die hier ohne Build
    nicht testbar war. Beides sind saubere Folge-Schritte (siehe unten).
  - **Geaenderte Dateien:** `frontend/lib/app_state.dart`,
    `frontend/lib/widgets/model_browser.dart`, `frontend/lib/widgets/viewport.dart`.
  - **Naechster Schritt fuer Backend-Persistenz (falls gewuenscht):** die
    C-API-Skizze steht — `qcad_layer_count`/`qcad_layer_name_at` zum Enumerieren
    plus get/set fuer Farbe (RColor r/g/b), Sichtbarkeit (`RLayer::setOff`) und
    Lock (`RLayer::setLocked`), jeweils per `RTransaction` wie `ensureLayer`,
    dann persistiert QCADs DXF-Exporter die Attribute automatisch. Erst mit
    lokalem Qt-Build testen (Layer-Roundtrip via `save_dxf`/`load_dxf`).

- **M19 — "Alles landet auf Layer 0" GEFIXT (Backend), + Z-Order + Log-Ort.
  Empirisch verifiziert (echter QCAD-Core, Linux-Build).**
  - **Root Cause (endlich gefunden):** `RTransaction` stempelt beim Speichern
    JEDE neue Entity mit `doc->getCurrentLayerId()` und ueberschreibt damit ein
    zuvor per `setLayerId` gesetztes Layer (RTransaction.cpp ~660: "place entity
    on current layer"). Das C-API setzte in `qcad_set_current_layer` nur sein
    eigenes `doc->currentLayer` (QString) + `ensureLayer`, aber NIE den
    Dokument-Current-Layer. Also blieb `getCurrentLayerId()` == "0", und jede
    Entity landete auf "0" — obwohl `qcad_set_current_layer` 1 (Erfolg) lieferte
    und die Layer sogar korrekt angelegt/ins DXF geschrieben wurden.
  - **Fix (1 Zeile):** in `qcad_set_current_layer` zusaetzlich
    `doc->doc->setCurrentLayer(lid)`. Danach: Entities landen in-memory auf
    "Layer 1"/"Layer 2", ueberleben den DXF-Roundtrip, und das DXF zeigt
    `LINE -> Layer 1` / `CIRCLE -> Layer 2`. Reproduktion + Fix mit dem echten
    Core auf Linux gebaut und ausgefuehrt (nicht nur Code-Review).
  - **Smoke-Test erweitert (`tests/smoke.c`):** der Bug konnte nur shippen, weil
    smoke.c NIE Layer testete. Jetzt: current-layer setzen -> Linie -> pruefen,
    dass `qcad_entity_layer` den Layer liefert (nicht "0"), + DXF-Roundtrip. CI
    (Linux-Host UND iOS-Simulator via `simctl`) faellt jetzt bei Regression.
  - **Z-Order (Frontend):** der Viewport-`CustomPaint` war nicht geclippt, also
    malte eine ver­schobene/gezoomte Skizze ueber Ribbon (oben) und Model Browser
    (links) — und weil der Viewport in der Column/Row DANACH gemalt wird, lag die
    Geometrie obenauf. Fix: `ClipRect` um den Painter (viewport.dart).
  - **Log-Datei (Frontend):** `Log.init()` leitet den Pfad aus `$HOME` ab (auf
    iOS teils leer -> Temp-Verzeichnis, das die Files-App NICHT zeigt — daher
    Skizzen sichtbar, aber kein Log). Neu: `Log.retarget(docsDir)` aus
    `AppState.init` schiebt das Log (inkl. Historie) ins ECHTE Documents-Verz.
    neben die Skizzen (`On My iPad > prototype > logs > prototype_log.txt`).
  - **Altbestand:** bereits auf "0" gestrandete Geometrie (Skizzen vom kaputten
    Build) bleibt auf "0", bis sie verschoben wird — dafuer ist M18 "Move N here".
  - **Geaenderte Dateien:** `backend/qcad-core/src/capi/qcad_capi.cpp`,
    `backend/qcad-core/src/capi/tests/smoke.c`, `frontend/lib/widgets/viewport.dart`,
    `frontend/lib/log.dart`, `frontend/lib/app_state.dart`.

- **OFFENER BUG (naechster Schritt):** Beim Ziehen von Punkten eines KREISES oder
  BOGENS verschwindet die ganze Geometrie, bis losgelassen wird. Verdacht:
  `grip.idx` ist bei Kreisen nur fuer `idx < ptCount` (= 1, der Mittelpunkt) ein
  Punktindex — die vier Radius-Grips tragen idx 1..4. Der M15-Build loggt genau
  das (`gripStr`, `moveGrip`-Ein/Ausgabe, Solver-Pfad, NaN-Erkennung); mit dem
  Log vom Geraet ist die Ursache direkt sichtbar. Die M15-Schranken verhindern
  bereits, dass der Viewport dabei ausgeloescht wird.

- **M6–M8 — Grips/Modify/Snap, Constraints, Bemaßung: ERLEDIGT.**
- **M9–M14 — SolveSpace-Solver (libslvs, FFI) + Dart-LM-Fallback,
  Auto-Coincident auf den projizierten CP, Lock, live-korrekter Drag:
  ERLEDIGT.** Architektur: slvs nativ, jede Lösung wird per Residuen-Check
  verifiziert; scheitert oder bailt slvs, übernimmt der Dart-LM-Solver.
- **M15 — Diagnose-Log auf dem Gerät (Files-App): ERLEDIGT.**
- **M16/M17 — Layer-Bindung + Editier-Scope + Auge: ERLEDIGT.**
- **M18–M20 — Layer-System produktionsreif; "alles auf Layer 0"-Backend-Fix;
  Bögen verschwanden beim Drag (slvs-Writeback verlor das
  Richtungs-Flag): ERLEDIGT** (Details in den Commit-Messages 7d8106a,
  37d707d, 0a89d28).
- **M21 — Inventor-komplette Bemaßung: ERLEDIGT** (Abschnitt unten).
- **M22 — Splines produktionsreif: ERLEDIGT** (Abschnitt unten).
- **M23 — Ellipse = 3 Definitionspunkte: ERLEDIGT** (Abschnitt unten).
- **M24 — Ellipsen-Feinschliff + Inline-Bemaßungseingabe: ERLEDIGT.**
- **M25 — Projizierter CP bemaßbar + Mittellinien + Ellipsen-Achsen als
  gebundene Entities: ERLEDIGT** (Abschnitt unten).
- **M26 — Inventor-DOF-Färbung (Träger-Analyse, Kanten-Färbung, Status):
  ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M27 — Bemaßung antippen/doppeltippen -> Wert-Editor (Label-Rect-
  Treffertest): ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M28 — Polylinien-Kanten als Bemaßungs-Teilnehmer (conEdges, 'ang4'):
  ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M29 — Tangente mit Splines (Endpunkt-Tangente, LM-only): ERLEDIGT,
  Geräte-Test offen** (Abschnitt unten).
- **M30 — Tastatur-Shortcuts D/L/C/R/S/Strg+S: ERLEDIGT, Geräte-Test
  offen** (Abschnitt unten).
- **M31 — Tangente mit Polylinien-KANTEN + Klick-Auflösung: ERLEDIGT,
  Geräte-Test offen** (Abschnitt unten).
- **M32 — Project Geometry (Inventor) + Show-Constraints/DOF default aus:
  ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M33 — Project Geometry alle Typen + Hover/Active-Button + Fremd-Layer-
  Selektionssperre: ERLEDIGT, Geräte-Test offen** (Abschnitt unten).
- **M34 — Rechtecke als vier Linien + Kanten-Projektion + Hover/Gelb-Fixes:
  ERLEDIGT, Host-Tests grün (94), Geräte-Test offen** (Abschnitt unten).
- **M35 — Pattern-Panel funktional (Rechteckige/Runde Anordnung, Spiegeln,
  Inventor-Dialoge): ERLEDIGT, Host-Tests grün (114), Geräte-Test offen**
  (Abschnitt unten).
- **M36 — Form-Auto-Constraints (Slots, Tangenten-Kreis/-Bogen), Fillet/
  Chamfer komplett wie Inventor, Trim/Split erhalten Constraints:
  ERLEDIGT, Host-Tests grün (134); im Geräte-Test traten Bugs zutage
  (Slot-Drag, Fillet-Button tot, Chamfer) → in M37 behoben** (Abschnitt unten).
- **M37 — Produktions-Härtung nach Geräte-Test: ERLEDIGT, Host-Tests grün
  (157) + Shim-Host-Gate (12), Geräte-Test offen.** Solver-Sicherheitsnetz
  (nie divergiertes Rendern/Committen, atomare Ops), Slot/Fillet/Chamfer an
  der Wurzel korrekt (redundanzfrei, Ecken-Koinzidenz-Entfernung, x/y-Setback-
  Bemaßung), Fillet-Button startet, Shim v3 (endpunktverankerte Tangenten).
  Voller Audit + Restpunkte im README (Abschnitt unten).
- **M38 — Zweiter Geräte-Test → Ast-Persistenz (`tanBranch`), Drag-Settle,
  Trim/Split-Koinzidenzen (+ Shim v4 Punkt-auf-Kreis), CP-Bindung für
  deterministische Formen, Fillet-Maß je Rundung, Pick-Dedupe: ERLEDIGT,
  Host 161 + Shim-Gate 13 grün, Geräte-Test offen** (Abschnitt unten).

## UI-Design-Spec (Stand = create-panel.html, FINAL abgenommen)
Stil: Autodesk Inventor Sketch-Tab, Dark Theme. Palette:
Panel `#292D33`, Flyout `#212429`, Hover `#31363D`, Text `#DDE0E3`, Dim `#9EA4AA`,
Blau (Grips/Akzent) `#3D9BE9`, Constraint-Rot `#E05A56`/`#D65A56`, Gelb `#E8C63F`,
Viewport `#212830`. Ribbon: `width:100vw`, blaue Linie oben
(`2px rgba(47,123,214,.85)`) und unten (`.45`), vertikale Panel-Trenner `#3a3f45`.
Icons: handgezeichnete Inline-SVGs (16/18/26/32/34 px), Sprache: hellgraue
Geometrie, blaue Quadrat-Grips, rote Constraints mit grauen Cursor-Pfeilen/
Häkchen, gelbe Blitze, KEIN Grün außer dem Plus im Layer-Icon.

**Ribbon-Panels in Reihenfolge (nichts hinzufügen/weglassen):**
1. **Layer** — ein großer Button „Start / New Layer" (Layer-Stapel-Icon in
   gestrichelten Ecken + grünes Plus, kleines ▼ unten rechts). Klick = fügt im
   Model-Browser „Layer N" hinzu (Dummy).
2. **Create** — große Buttons Line/Circle/Arc/Rectangle (je ▼-Flyout), rechts
   Spalte: Fillet ▾ / A Text ▾ / + Point. Flyouts (Einträge exakt):
   - Line: Line·Line, Line·Midpoint Line, Spline·Control Vertex,
     Spline·Interpolation, Equation Curve, Bridge Curve
   - Circle: Center Point, Tangent, Ellipse
   - Arc: Three Point, Tangent, Center Point
   - Rectangle: Two Point, Three Point, Two Point Center, Three Point Center,
     Slot Center to Center, Slot Overall, Slot Center Point, Slot Three Point
     Arc, Slot Center Point Arc, Polygon
   - Fillet: Fillet, Chamfer   /   Text: Text, Geometry Text
   Flyout-Einträge zweizeilig (fett + Untertitel), erster Eintrag hervorgehoben.
   Flyouts öffnen DIREKT unter dem geklickten Element (anchor.bottom).
3. **Project Geometry** — nur der große Button (isometrische blaue Ebenen),
   KEIN Dropdown.
4. **Pattern** — Rectangular (blaues Quadrat-Raster), Circular (blauer
   Punktring), Mirror (Dreieckpaar), Titel „Pattern".
5. **Constrain** — großer „Dimension"-Button (weißes |←→|-Glyph) + 5×3-Grid:
   Reihe1: AutoDim(⚡gelb), Coincident, Collinear, Concentric, Lock(rot);
   Reihe2: Show Constraints(⚡), Parallel, Perpendicular, Horizontal, Vertical;
   Reihe3: Constraint Settings, Tangent, Smooth(G2), Symmetric, Equal.
   Rote Glyphen mit grauen Cursor-Pfeilen/Checks, Hatch-Striche bei H/V.
   Titel „Constrain ▼".
6. **Insert** — Image / Points / ACAD (farbige Icons), Titel „Insert".
7. **Format** — Grid: Driven Dimension (oben, colspan), Kugel + Crosshair
   (Crosshair im AKTIV-Rahmen blau), darunter Zeile „Show Format" (colspan,
   darf nicht überlaufen — Grid-Spalten `auto`). Titel „Format ▼".
8. **Modify** (LETZTER Block) — 3×3: Move/Copy/Rotate | Trim/Extend/Split |
   Scale/Stretch/Offset, blaue Inventor-Icons, Titel „Modify".

**Model-Browser links (300px, Inventor-Stil):**
- Header: Tab „Model ✕", „+", rechts 🔍 und ☰.
- Baum: blauer Würfel „Sketch1" (nicht Part1); KEIN Representations-Ordner;
  „Origin"-Ordner mit +/−-Expander → Kinder: X Axis (rot), Y Axis (blau),
  Center Point (**automatisch projiziert**, blauer Grip, Tooltip);
  danach Container `#layers` (hier landen „Layer 1..N");
  unten „End of Sketch" (roter ✕-Kreis).
- Rechtsklick auf Layer-Zeile → Kontextmenü (Dummy): **Edit** (oberster
  Eintrag), Copy, Duplicate, „Export only this layer", „Toggle visibility".
- Rechts daneben Viewport `#212830`.
- ALLES nur Design-Dummy: „Funktionen" sind Flyouts, Origin-Expander,
  Layer-Hinzufügen, Kontextmenü, Edit-Modus, Home/Tabs (siehe unten).

**Layer-Edit-Modus (im Mock umgesetzt, Verhalten übernehmen):**
- „Start New Layer" legt „Layer N" im Browser an UND startet sofort den
  Edit-Modus für diesen Layer.
- Edit-Modus für BESTEHENDE Layer: Doppelklick auf die Layer-Zeile ODER
  Rechtsklick → „Edit".
- Im Edit-Modus:
  - Die aktive Layer-Zeile wird im Model-Browser hervorgehoben
    (Inventor-Stil: Hintergrund `#3A4149`, 1px-Outline `#5A88B5`, Text weiß).
  - Im Viewport erscheinen X- und Y-Achse als **graue Linien** (`#6b7178`,
    1px) und der Center Point als **grauer Punkt** — alle drei NICHT
    interaktiv (pointer-events:none), reine Referenz-Geometrie.
  - ÜBER dem grauen Center Point liegt ein **gelber projizierter Punkt**
    (`#E8C63F`, Rand `#9a8320`, Tooltip „Projected Center Point").
    Regel: **Projiziertes ist GELB. Interagieren kann man NUR mit
    projizierten oder gezeichneten Elementen**, nie mit der grauen
    Roh-Geometrie.
  - Oben rechts im Ribbon erscheint das **Exit-Panel**: großer grüner Haken
    (`#3FA43C`, dicker Strich), Beschriftung „Finish ▼", Panel-Titel „Exit"
    (exakt wie Inventor-Screenshot). Klick auf Finish beendet den Edit-Modus
    (Highlight, Achsen-Overlay und Exit-Panel verschwinden).

**Untere Tab-Leiste (30px, `#14171B`, wie Inventor):**
- Links „🏠 Home", daneben ein Tab pro geöffneter Skizze mit ✕ zum Schließen;
  aktiver Tab heller (`#262B31`) mit 2px blauer Unterkante (`#2f7bd6`);
  ganz rechts ☰. Schließen des aktiven Tabs wechselt zum letzten offenen
  Tab, sonst zurück zur Home-View.

**Home-View (vereinfachte Inventor-Startseite, App-Start-Zustand):**
- KEIN Model-Browser, KEIN Viewport, im Ribbon werden ALLE Panels versteckt;
  einziges Panel/Tool: großer Button „Create New Sketch" (Rechteck-Skizzen-
  Icon mit blauen Grips + grünes Plus), Panel-Titel „Sketch".
- Inhalt: Überschrift „Recent" + Karten-Grid (190px-Karten `#24282D`,
  Hover-Rand blau): dunkle Vorschaufläche (radialer Gradient) mit
  Sketch-Würfel-Icon, darunter Name (fett) + Datum. 6 Dummy-Beispiel-
  Skizzen ohne Inhalt (Bracket_v2, Flange, Plate_120x80, Gasket,
  Shaft_Profile, Cam_Outline). KEIN Sortieren/Suchen/Pinnen (bewusst
  weggelassen — einfacher als Inventor).
- Klick auf eine Karte öffnet die Skizze (Tab entsteht, Model-Browser-
  Wurzel zeigt den Skizzennamen); „Create New Sketch" erzeugt
  Sketch1, Sketch2, … und öffnet sie direkt.

## Frühere funktionierende Tool-Engine (Referenz, aktuell NICHT im Mock)
In einer früheren Iteration dieses Chats existierte eine Canvas-Engine
(prototype-ribbon.html, überschrieben) mit: Line/Polyline/Circle(CR/2P/3P)/
Arc(3P/Center)/Rectangle/Ellipse/Point; Move/Copy/Rotate/Mirror/Scale/Erase/
Offset; Snapping (Endpunkte, Ursprung, projizierte Achsen); Achsen-Projektion;
**Dimension-Tool wie Inventor** (Shortcut `d`): Linie→Platzieren=Länge,
2 Punkte=Abstand, 2 Linien=Winkel (Bogen, Strahl-Wahl nach Platzierung),
Kreis=Radius (R…), Punkt+Linie=Lotabstand; Live-Preview in Rot, Esc bricht ab.
Diese Logik muss in den finalen Mock bzw. direkt in Flutter neu integriert
werden (Design hat Vorrang, Verhalten wie beschrieben).

## Nächste Schritte — M5: Flutter-App (Vorgabe des Nutzers, NICHTS auslassen)
Der Nutzer hat den nächsten Schritt exakt so definiert:

1. **Das GESAMTE Design genau so für Flutter machen.** 1:1-Port des
   HTML-Mocks (`create-panel.html`) — Design, alle Buttons, Funktionen,
   Flyouts, Model-Browser, Layer-Edit-Modus, Finish-Button, Home-View,
   Tab-Leiste, Farben, Icons: **alles exakt gleich wie in diesem Prototyp.**
   Das ist dem Nutzer sehr wichtig: **1:1 wie im HTML.**
2. **Eingabe-Optimierung fürs Erste: Keyboard + Maus am iPad.**
   Touch-Bedienung (Fingergesten auf dem Screen, Long-Press statt
   Rechtsklick etc.) kommt ERST SPÄTER, nicht in dieser Version.
   AUSNAHME (gehört in die ERSTE Version): **Pan mit 2 Fingern auf dem
   Touchpad und Zoom per Pinch auf dem Touchpad** müssen integriert sein.
3. **Erster Funktionsschritt: einfaches Zeichnen mit dem Backend.**
   Einfache Linien, Kreise, Rechtecke und ein paar weitere Grundformen
   werden REAL über das QCAD-Backend (C-API/FFI) umgesetzt.
   **Alles andere bleibt in der UI integriert/sichtbar, ist aber noch
   nicht umgesetzt** (Buttons vorhanden wie im Mock, ohne Funktion).
4. **Saving und Loading auf dem iPad als erster Schritt einrichten,
   ebenso die Preview-Erstellung** (Vorschaubilder der Skizzen für die
   Recent-Karten der Home-View).
5. **Test-IPA-Build erstellen, den der Nutzer auf dem iPad installieren
   kann** — mit diesen einfachen Funktionen und dem QCAD-Backend.

Der Nutzer stellt im neuen Chat **das HTML (`create-panel.html`) und einen
neuen PAT selbst zur Verfügung.**

### Technische Anknüpfung (aus M4-Planung, weiterhin gültig)
- `frontend/` neu aufsetzen (flutter create, ffi ^2.1.0), Ribbon/Browser/
  Canvas/Home/Tabbar als Widgets, SVG-Icons via CustomPainter oder
  flutter_svg; alten `main.dart` (8e241b3) ersetzen.
- XCFramework linken (CI-Artefakt `prototype-ios-capi`) + Qt-iOS-Static-Libs
  (Liste in `src/capi/CMakeLists.txt`); Achtung Qt-main-Wrapper vs.
  Flutter-main (headless: libqios ggf. weglassen).
- Erster echter Dart-FFI-Lauf (M2-Restschuld): `bindings/dart/qcad_ffi.dart`,
  Logik aus `example/qcad_smoke.dart`, Marker `DART SMOKE: PASS`.
- CI-Job macos-14: `flutter build ios --simulator`, install + launch
  --console-pty, Marker-Urteil, **pipefail AUSSEN vor dem Block**, Timeouts,
  Screenshot-Artefakt (retention-days: 3). Für den Nutzer-Test zusätzlich
  Device-Build/IPA (unsigniert bzw. Sideload-fähig, z. B. via AltStore/
  Sideloadly — mit Nutzer klären).
- C-API um Geometrie-Abfrage erweitern (`qcad_entity_geometry(idx,…)`)
  für echtes Rendering aus dem QCAD-Dokument; Save/Load über vorhandenes
  `load/save_dxf` (Dokumente + Preview-PNGs im App-Documents-Verzeichnis).
- Design-Detailhinweise aus der Mock-Review (nicht blockierend, bei
  Gelegenheit): Touch-Trefferflächen erst relevant, wenn Touch kommt;
  Platz für Maß-Eingabe/Statuszeile beim Canvas-Layout einplanen.

## Backend-Kurzreferenz (unverändert, Details im README)
- Build lokal (Ubuntu): cmake+ninja+qt6-base/declarative/svg;
  `cmake -B build -G Ninja -DBUILD_QT6=ON -DCMAKE_BUILD_TYPE=Release`,
  `cmake --build build -j -- -k 0`. Smoke: `-DQCAD_CAPI_SMOKE=ON` →
  `./release/qcad_capi_smoke` = „SMOKE: PASS".
- C-ABI (`src/capi/qcad_capi.h`): qcad_init/version, document_new/free,
  add_line/circle/arc/polyline, entity_count, bounding_box, load/save_dxf.
- Fallstricke: Property-Init-Liste in qcad_capi.cpp (46 Klassen, RColor/
  RLineweight privat=auslassen); Storage/SpatialIndex heap-allozieren, NUR
  RDocument löschen (Doppel-Free); RSettings via QCoreApplication+Org-Name;
  iOS-Configure braucht `-DCMAKE_BUILD_TYPE=Release`; `set -o pipefail` VOR
  `{…}|tee`-Blöcken (zweimal falsches Grün dadurch!); Qt-iOS-Prebuilt:
  arm64=Device, x86_64=Simulator (Rosetta), kein arm64-Sim-Slice;
  `simctl spawn` hängt → install + `launch --console-pty`; Info.plist im CI
  überschreiben; smoke.c nutzt TMPDIR; Apple-Link ohne --start-group.
- Spline/opennurbs, spatialindex, snap/grid, Hatch/Text: zurückgestellt
  (`R_NO_OPENNURBS` etc.) → im UI ausgegraut.
- CI: `.github/workflows/m1-core-build.yml` (build-core-ios +
  m3-ios-sim-logic). Logs werden in Branches committet:
  `ci-debug-logs/ci-logs/*` (M1/M2), `ci-debug-logs-m3/ci-logs-m3/*` (M3).
  `**.md`-Commits triggern kein CI. Artefakt-Retention 3 Tage.

## Nützliche Pfade
```
backend/qcad-core/src/capi/               C-ABI (qcad_capi.h/.cpp, tests/smoke.c)
backend/qcad-core/bindings/dart/          Dart-FFI (noch nie ausgeführt)
.github/workflows/m1-core-build.yml       CI
frontend/                                 VERALTETER erster UI-Wurf (ersetzen)
create-panel.html                         FINALER UI-Mock inkl. Edit-Modus/Home/
                                          Tabs (vom Nutzer bereitgestellt)
```

---

## M21 — Vollständiges Bemaßungssystem (Inventor-Pick-Matrix)

**Was:** Der Dimension-Tool-Click ist jetzt eine Zustandsmaschine über eine
GEMISCHTE Auswahl (`conPts` + `conEnts` gleichzeitig erlaubt). Jeder Klick
erweitert die Auswahl, wenn die Kombination gültig ist, sonst platziert er.
Die Matrix steht in `AppState._dimensionClick` / `buildDimensionAt`
(app_state.dart) und im README.

**Neue Bemaßungsarten:**
- `pline` — senkrechter Punkt-Linie-Abstand. `pts = [Punkt, LinieA, LinieB]`
  (drei PRefs, KEINE Entity-Referenz — funktioniert dadurch auch für
  Polylinien-Segmente). Nativ: neuer Shim-Code `SH_PT_LINE_DIST` (=20),
  Shim-Version 2. Der Shim baut eine Ad-hoc-Linien-Entity über die zwei
  Punkte (kostet keine Parameter) und setzt `SLVS_C_PT_LINE_DISTANCE`.
- `ang3` — 3-Punkt-Winkel, `pts = [Strahl, SCHEITEL, Strahl]`. Läuft bewusst
  IMMER über den Dart-LM-Solver (Bail in `_trySolveWithSlvs`): der Shim hat
  keinen 3-Punkt-Winkel, und ein stummer Drop wäre schlimmer als LM.

**Fallstricke, die schon eingebaut/umschifft sind:**
1. **Vorzeichen von PT_LINE_DISTANCE.** SolveSpace' Residuum ist
   `proj = (a.y-b.y)(a.x-p.x) - (a.x-b.x)(a.y-p.y)` (constrainteq.cpp,
   PointLineDistance, Workplane-Zweig) — das ist das NEGATIVE des "üblichen"
   cross(b-a, p-a). Der Shim wertet exakt SolveSpace' Ausdruck aus und
   signiert das Ziel passend, sonst spiegelt der Solver den Punkt durch die
   Linie. Host-Tests 9/10 prüfen beide Seiten. Der Dart-LM-Pfad friert die
   Seite analog in `_prepare` ein (`ctx.sign`).
2. **Versions-Gate.** Ein VOR M21 gebautes IPA hat Shim v1 und würde den
   unbekannten Code 20 einfach überspringen → jede Verify schlägt fehl →
   Dauerschleife in den Fallback. Deshalb: `SlvsFfi.version` (aus
   `slvs_shim_version()`), und `_trySolveWithSlvs` bailt bei
   `pline && version < 2` sofort. Frischer Build nötig für den nativen Pfad.
3. **PRef braucht Wert-Gleichheit.** `conPts.contains(pt)` dedupliziert die
   Auswahl; mit Identity-Equality war jeder Re-Klick "neu". `==`/`hashCode`
   sind jetzt auf PRef implementiert (constraints.dart).
4. **Kreis-Kombinationen sind KEINE neuen Arten.** Kreis+Punkt, Kreis+Kreis
   laufen als gewöhnliche `dist`-Bemaßung über den Mittelpunkts-PRef
   (`getPt(circle, 0)` = Zentrum) — Serialisierung, slvs-Packung und Renderer
   existierten schon. Kreis+Linie und parallele Linien laufen als `pline`
   mit dem Zentrum bzw. einem Endpunkt der zweiten Linie als Messpunkt.
5. **Parallel-Erkennung** für Linie+Linie (Abstand statt Winkel) liegt bei
   sin(0.5°) — `_linesParallel`. Inventor bietet bei parallelen Linien den
   Linearabstand an; ein Winkelmaß zwischen (fast) parallelen Linien wäre
   ohnehin degeneriert.

**Rendering (viewport.dart `_paintDimension`):** `pline` zeichnet die
Maßlinie zwischen Punkt und Lot-Fußpunkt (gestrichelte Verlängerung, wenn der
Fußpunkt außerhalb des Segments liegt). `ang`/`ang3` zeichnen jetzt einen
echten Winkelbogen durch die Textposition (Scheitel = Schnittpunkt bzw.
mittlerer Pick), gestrichelte Strahl-Verlängerungen bei `ang3`.

**Tests:** `backend/slvs/tests/shim_test.c` Szenarien 9/10 (CI-Gate "ALL SHIM
TESTS PASS" deckt sie ab). NEU: `frontend/test/dimension_kinds_test.dart` +
`dimension_picks_test.dart` (18 Tests) und ein `flutter test`-Gate im
m5-flutter-ipa-Job. Auf dem Host läuft Engine.create() im Dart-Fallback und
der Solver ohne libslvs im LM-Pfad — genau die Pfade, die getestet werden
sollen.

**Offen / Ideen:** Tangenten-Varianten für Kreis-Abstände (Inventor: Auswahl
Mittelpunkt vs. Tangente beim Platzieren), Bogenlängen-Bemaßung, Winkel über
Quadranten-Umschaltung beim Platzieren.

---

## M22 — Spline-Fixes: Tag-Verlust beim Commit, periodische geschlossene Splines, Klick-auf-Start

**Symptom:** Während des Zeichnens sah der Spline korrekt aus (Kurve +
Kontrollpunkte), nach Enter waren es nur noch gerade Linien ohne
Kontrollpunkte. Außerdem war "Spline auf seinem Startpunkt beenden" buggy.

**Ursache 1 (der Hauptbug):** `SketchModel.refresh()` stellt die Spline-Tags
nach dem Engine-Roundtrip per Index aus dem VORHERIGEN `s.geometry` wieder
her. Beim allerersten Commit existiert der neue Spline im alten Stand aber
noch nicht — sein Index liegt hinter `prev.length`, das Tag fiel weg, und der
Spline wurde als gerade Polyline gerendert. Fix: `refresh({List<Geo>?
tagSource})` — `_rebuildEngine` übergibt die MASSGEBLICHE Liste `gs`, aus der
die Engine gerade gebaut wurde (`_committed(s, tags: gs)`). Zusätzlich
kopiert `refresh` die Engine-Liste jetzt (`List.of`), weil die
Fallback-Engine eine unveränderliche Liste liefert und das Re-Tagging sonst
wirft.

**Ursache 2:** Geschlossene CV-Splines waren mathematisch falsch: geklemmter
Knotenvektor + 3 angehängte CVs lässt die Kurve auf cv[0] STARTEN, aber auf
cvIn[2] ENDEN (geklemmt endet auf dem letzten CV) — sichtbare Lücke/Ecke am
Startpunkt. Fix: geschlossene CV-Splines sind jetzt ein echter PERIODISCHER
kubischer B-Spline (uniforme Knoten, k CVs umgeschlagen, ausgewertet auf
[t_k, t_n]); Start==Ende exakt, C2-glatt am Stoß. Offene bleiben geklemmt
(Kurve beginnt/endet auf erstem/letztem CV, wie Inventor).

**Ursache 3 (UX):** Zum Schließen musste man exakt (1e-6!) auf den Start
klicken UND danach noch Enter drücken. Jetzt: Klick auf den Startpunkt (ab 3
gesetzten Punkten, Toleranz 8/zoom als Fallback wenn Snap aus) schließt und
committet SOFORT — Inventors Geste. Der Snap auf den Startpunkt existierte
schon (extraPoints in computeSnap).

**Sichtbarkeit:** CV-Splines zeigen bei Hover/Selektion jetzt ihr
Kontrollpolygon (gestrichelt) + Punktmarker — ohne das waren die
Off-Curve-Kontrollpunkte unsichtbar und der Spline wirkte uneditierbar.
Fit-Splines brauchen das nicht (Punkte liegen AUF der Kurve).

**Tests:** `frontend/test/spline_test.dart` — Tag überlebt Rebuild,
periodischer Schluss (exakt + kein Knick), Fit-Spline schließt + läuft durch
alle Fit-Punkte, Tool schließt bei Klick auf Start. Der Tag-Test fährt den
echten `refresh(tagSource:)`-Pfad über die Dart-Fallback-Engine.

**Bekannte Grenzen:** Spline-Punkte sind im Solver weiterhin freie
Polyline-Vertices (Constraints/Bemaßungen auf Kontroll-/Fit-Punkte gehen,
Tangenten-Handles wie in Inventor gibt es noch nicht). DXF exportiert
weiterhin die Kontrollpolygon-Polyline (R_NO_OPENNURBS) + Sidecar-Tag.

---

## M23 — Ellipse: 3 Definitionspunkte statt 96-Vertex-Polygon

**Symptom:** Eine Ellipse war eine geschlossene Polyline aus 96 Sample-
Punkten — 96 Grips, 96 Snap-Vertices, 96 freie Solver-Punkte, und "eine
Kurve" war sie nie.

**Fix:** Gleiche Architektur wie Splines (Tag an einer Polyline, Kurve wird
Dart-seitig erzeugt): `Geo.ellipseTag` an einer 3-Punkt-Polyline
`[Zentrum, Hauptscheitel, Nebenscheitel]` — exakt Inventors Ellipsen-Grips.
Alle Tag-Erhaltungspfade (refresh/tagSource, Sidecar, modify.keepTag,
isSpline-Guards für Mittelpunkt-Snap und Bemaßungs-Kantenpick) greifen
automatisch, weil sie auf `spline != straight` prüfen.

- `ellipseCurve` (spline.dart) sampelt die Kurve; der Nebenscheitel trägt nur
  seine Komponente SENKRECHT zur Hauptachse bei — die Ellipse kann also nie
  scheren, egal was Solver oder Drag mit den Rohpunkten machen.
- `normalizedEllipse` wird in `_rebuildEngine` auf jede Ellipse angewandt
  (der eine Trichter für alle Edits): ein abgedrifteter Nebenscheitel wird
  exakt auf die Nebenachse zurückgesetzt, damit der Grip auf der Kurve liegt.
- `moveGrip` (snap.dart) hat Inventor-Semantik: Zentrum-Grip verschiebt die
  ganze Ellipse, Hauptscheitel rotiert/streckt (Nebenscheitel folgt senkrecht,
  b bleibt), Nebenscheitel ändert nur die Nebenausdehnung.
- Snap bietet Zentrum + alle VIER Quadranten an (die zwei gespiegelten werden
  aus den gespeicherten Scheiteln berechnet).

**Kompatibilität:** Früher gezeichnete 96-Punkt-Ellipsen bleiben gewöhnliche
Polylines — sie rendern unverändert, werden aber nicht rückwirkend
konvertiert. DXF exportiert wie bei Splines das Definitions-Polygon +
Sidecar-Tag (die C-API hat kein qcad_add_ellipse; REllipseEntity existiert im
Core, ein natives Ellipsen-Entity im C-API wäre der nächste Schritt für
sauberen DXF-Export).

**Tests:** 6 neue in spline_test.dart (Builder-Tag, Quadranten, Scher-
Immunität, Normalisierung, Zentrum-/Hauptscheitel-Grip). 28 gesamt, alle grün.

---

## M24 — Ellipsen-Feinschliff + Inline-Bemaßungseingabe

1. **Hover-Highlight:** Der Hover-Pfad zeichnete für JEDE Polyline nur die
   eine Kanten-Halo (`haloEdge`) — bei Splines/Ellipsen war das eine schräge
   Gerade statt der Kurve. Getaggte Polylines highlighten jetzt über
   `paintGeo` (zeichnet die Kurve), nur gerade Polylines behalten die
   Kanten-Halo.
2. **Ellipsen-Achsen:** Haupt- und Nebenachse werden immer als gestrichelte
   Mittellinien gezeichnet (paintGeo, ellipseTag-Zweig) — sie tragen die
   Zentrum-/Quadranten-Punkte, auf die man bemaßt und constraint.
3. **Ellipse als Kurve in der Bemaßungs-Matrix:** `isCurve` umfasst jetzt
   ellipseTag (Zentrum = Vertex 0). Vorher fing der Polyline-Zweig in
   `_dimensionClick` die Ellipse ab, bevor sie als Entity gepickt werden
   konnte — Ellipse+Linie/Punkt/Kreis funktionierte gar nicht.
4. **Vertex vor Kante:** Ein Punkt-Pick gewinnt IMMER gegen den Entity-Pick
   (Inventors Prioritität) — vorher gewann beim ersten Klick die Entity,
   wodurch "Endpunkt, Endpunkt" als "Linie, eigener Endpunkt" gelesen wurde.
   Der EIGENE Endpunkt einer gepickten Linie erweitert nicht zu pline=0,
   sondern platziert.
5. **_distKind nach Inventors Regionen:** über/unter der Bounding-Box des
   Punktpaars → horizontal (distx), links/rechts → vertikal (disty),
   diagonal/entlang der Normalen → fluchtend. Vorher entschied nur der
   Normalen-Winkel, was unvorhersehbar wirkte.
6. **Inline-Bemaßungseingabe statt Dialog:** Textfeld direkt AUF der
   Bemaßung (Position via _worldToScreen, im Stack über dem Painter).
   Öffnet nach dem Platzieren einer neuen Bemaßung und beim Tippen auf eine
   bestehende. Enter committet, Esc bricht ab, Klick daneben committet
   (Inventor behält die Bemaßung). Einheiten wie gehabt (mm/cm/m, Winkel in
   Grad). Der Over-Constrained-Dialog (getrieben/abbrechen) bleibt ein
   Dialog — das ist eine Entscheidung, kein Werteintrag. _askValue ist weg.

**Tests:** flow_probe_test.dart fährt die Flows durch AppState.toolClick:
Linie+Ellipsenzentrum → pline, Ellipsenkörper als Kurven-Pick →
Zentrum↔Linie, Platzierungsregionen distx/disty/dist. 31 gesamt.

---

## M25 — Projizierter Center Point bemaßbar + Ellipsen-Achsen als echte Mittellinien

**Teil 1 — Projizierter Center Point (Ursprung):** War als Pick angeboten
(`_nearestPointRef` liefert `PRef(kProjCenter, 0)`), aber die Konsumenten
dereferenzierten roh mit `getPt(gs[ent])` — beim Sentinel −1 flog das bzw.
die Guards (`ent < 0 → return`) warfen die Bemaßung beim Rendern weg. Neuer
Helfer `refPt(gs, ref)` (constraints.dart) löst JEDEN Punkt-Ref auf,
inklusive Ursprung. Umgestellt: `measureDim` (alle Punkt-Arten),
`_distKind`, der komplette Bemaßungs-Painter, die Pick-Halos. Merkregel im
Code: Bemaßungs-Konsumenten benutzen NIE rohes getPt auf PRefs.

**Teil 2 — Mittellinien (Centerline-Stil):** `Geo.style`
(styleNormal/styleCenterline) analog zum Spline-Tag: withStyle/withData/
onLayer erhalten ihn, eigener Sidecar `<name>.styles.json`, UND — der beim
Testen gefundene Kernbug — `refresh()` stellt den Stil jetzt wie den
Spline-Tag wieder her (vorher wurde jede Mittellinie beim ersten Edit wieder
durchgezogen gerendert). Rendering: Linien mit styleCenterline zeichnen
gestrichelt (paintGeo), sind aber VOLLWERTIGE Entities: verschiebbar,
bemaßbar, constraintbar. Ribbon: Format → "Centerline (toggle selected)"
schaltet den Stil der Selektion um (Inventors Format-Toggle).

**Teil 3 — Ellipsen-Achsen sind jetzt ECHTE Mittellinien-Entities:** Beim
Commit einer Ellipse entstehen zwei Achsen-Linien (Quadrant+ → Quadrant−)
im Centerline-Stil, an die Ellipse gebunden über
  coincident(Achsende A, Ellipsen-Scheitel) ×2 und
  midpoint(Ellipsen-ZENTRUM auf Achsenlinie) ×2
= 8 LINEARE Gleichungen für die 8 Linienparameter → weder über- noch
unterbestimmt, Achse ziehen treibt die Ellipse durch den Solver. WICHTIG:
Die erste Formulierung (symmetric um die jeweils andere Achse) koppelte die
Achsen nichtlinear und blieb im LM-Solver reproduzierbar in einem lokalen
Minimum ~0.3 % daneben hängen — deshalb NEUER Constraint-Typ
`CType.midpoint` (Punkt = Mittelpunkt einer Linie), ans ENDE des Enums
angehängt (Sidecar speichert den Enum-INDEX!), LM-Residual linear,
slvs-nativ über den existierenden Shim-Code SH_MIDPOINT (12), Glyph ⫧.
Die dekorative Achsen-Zeichnung aus M24 ist raus — die Achsen sind jetzt
Geometrie. LM-Iterationsbudget 25 → 80 (bricht bei Konvergenz früh ab).

**Tests:** m25_test.dart — Punkt+Ursprung-Bemaßung, Linie+Ursprung (pline),
Ellipsen-Commit erzeugt 2 gebundene Achsen (midpoint×2 + coincident≥2),
Achsen folgen der (gepinnten) Ellipse exakt durch den Solver,
Centerline-Stil überlebt den Engine-Roundtrip. 36 gesamt, alle grün.

---

## M26 — Inventor-DOF-Färbung: Träger-Analyse statt Alle-Punkte-Regel

**Symptom (Nutzer):** Beim Rechteck wurden alle Linien erst weiß, wenn das
GANZE Rechteck bestimmt war. In Inventor wird eine Linie schon weiß, wenn
nur noch ihre Länge frei ist (z. B. Ecke fixiert + H/V-Constraint).

**Recherche (belegt):** Autodesk-Forum "Bug: Line colour updates as fully
constrained when it isn't" — akzeptierte Antwort eines Autodesk-Engineers
nach Rückfrage beim Inventor-Team: Linien mit fixierter Richtung + Lage
werden im Fully-Constrained-Schema gefärbt, obwohl keine Längenbemaßung
existiert; die Endpunkte sind SEPARATE Entities mit eigenem Zustand. Ein
Rechteck ist in Inventor vier einzelne Linien → Kanten färben unabhängig.

**Ursache bei uns:** `entityFull` im Viewport-Painter verlangte, dass JEDER
Punkt der Entity aus `freePoints` verschwunden ist. Eine Linie mit freier
Länge hat einen beweglichen Punkt → blieb violett. Und ein Rechteck ist EINE
Polyline mit EINEM Paint → nichts wurde weiß, bis der letzte Vertex fest war.

**Fix (solver.dart):** `analyzeSketch` extrahiert jetzt die ECHTEN
Nullraum-Basisvektoren aus der RREF (vorher nur movable-Booleans — die
Basis stand schon da und wurde weggeworfen). Pro Basisvektor (= eine noch
mögliche Bewegung erster Ordnung) wird pro Träger geprüft, ob er sich ändert:
- Linie/Kante a→b: lose, wenn ein Endpunkt SENKRECHT zur Kante wandert
  (ändert Richtung/Offset). Bewegung NUR entlang der Kante = freie Länge
  → Träger bleibt fest → weiß. Test: cross(d, δ)/|d| beider Endpunkte.
- Kreis/Bogen: Träger = (cx, cy, r) — die Params o..o+2. Freie
  Bogen-ENDWINKEL (o+3, o+4) zählen nicht (Endpunkte = eigene Entities).
- Getaggte Polylines (Spline/Ellipse): lose, wenn irgendein Param beweglich
  (die Kurve IST ihre Definitionspunkte) — wie bisher, eine Farbe.
- Gewöhnliche Polylines: PRO KANTE (geschlossen n, offen n-1 Segmente).
Ergebnis in `SketchAnalysis.looseCarriers` (Set<(ent, seg)>) +
`carrierFixed(ent, [seg])` + Helper `carrierSegCount(Geo)`. `freePoints`
bleibt UNVERÄNDERT — Grips, Drag-Sperre und DOF-Pfeile hängen weiter daran
(richtig so: der freie Endpunkt einer weißen Linie bleibt ziehbar).
Toleranz: Basisvektor auf max|v| normiert, Schwelle 1e-5 (numerischer
Jacobian mit h=1e-6 rauscht darunter).

**Fix (viewport.dart):** `entityFull` → `segFull(i, seg)` über
`carrierFixed`. Gewöhnliche Polylines werden (wenn nicht selektiert/
Referenz) Kante für Kante mit der Farbe IHRER Kante gemalt statt als ein
Path. Neu außerdem Inventors Status unten rechts im Viewport:
„N dimensions needed" / „Fully Constrained" (aus `analysis.dof`, das es
schon immer gab und das nie angezeigt wurde).

**WICHTIGE ERKENNTNIS aus dem Testen (Erwartung war erst falsch):** Beim
Rechteck mit EINER fixierten Ecke + H/V werden nur die ZWEI Kanten durch
die Ecke weiß. Die gegenüberliegenden Kanten (rechts/oben) bleiben violett
— korrekt, denn ihre Trägergerade VERSCHIEBT sich mit der freien Breite/
Höhe (x=w wandert mit w). Erst die Breiten-Bemaßung macht die rechte Kante
weiß (ihre Länge = Höhe bleibt frei), die Höhen-Bemaßung dann alles. Das
ist exakt Inventors Verhalten und exakt das Szenario des Nutzers („die
Linie, die an der voll bestimmten Ecke hängt").

**Tests:** `frontend/test/m26_test.dart` (9 Tests): Linie fix+H mit freier
Länge → weiß + Endpunkt bleibt freePoint; NUR Längenbemaßung → violett
(Träger transliert/rotiert noch); Rechteck-Progression (Ecke→2 Kanten weiß,
+Breite→3, +Höhe→alles, dof 2→1→0); L-Form über coincident (Kette:
Kante 2 erst weiß, wenn Kante 1 bemaßt ist); Kreis Zentrum fix + freier
Radius → violett, +rad-Bemaßung → weiß; unconstrained → alles lose; voll
bestimmt → looseCarriers leer; carrierSegCount-Konvention. 45 gesamt, alle
grün (flutter test, Host = Dart-Fallback-Engine + LM-Pfad wie in der CI).

**Grenzen:** Erste Ordnung (Nullraum am aktuellen Punkt) — ein Träger, der
nur in höherer Ordnung beweglich wäre, würde weiß gefärbt; praktisch
irrelevant, Inventor arbeitet genauso lokal. Der Status-Text zählt dof als
"dimensions needed" (Inventor zählt genauso Parameter, nicht Bemaßungen).

---

## M27 — Bemaßung antippen/doppeltippen öffnet den Wert-Editor

**Symptom (Nutzer):** Doppeltipp auf eine bestehende Bemaßung sollte sie
editieren — tat es aber nicht (und Einzeltipp meist auch nicht).

**Zwei Ursachen:**
1. Der Treffertest (`dimensionAt`) verglich den Tipp mit `textPos`. Für die
   'dist'-Arten berechnet der Painter die Label-Position aber NEU (Mitte der
   Maßlinie + 10px-Normalenversatz) — der Text liegt gar nicht bei textPos.
   Bemaßungen waren dadurch fast nicht antippbar.
2. Wenn der Editor doch aufging, traf der ZWEITE Tipp eines Doppeltipps den
   „Klick woanders committet"-Zweig und schloss das gerade geöffnete Feld
   sofort wieder.

**Fix:** Der Painter protokolliert jetzt die SCREEN-Rects der wirklich
gezeichneten Labels (`AppState.dimLabelRects`, im Paint gefüllt); Tipps
treffen gegen diese Rects (+8px Finger-Toleranz, oberstes Label gewinnt),
mit dem alten Anker-Test nur noch als Fallback vor dem ersten Paint. Ein
erneuter Tipp auf DASSELBE Label hält den Editor offen (Text neu
selektiert) statt zu committen — Einzel- UND Doppeltipp editieren damit.
Außerdem Inventor-Verhalten ergänzt: Ist das Bemaßungs-Tool aktiv, öffnet
ein Tipp auf ein bestehendes Label dessen Editor statt einen neuen Pick zu
starten. Tests: `frontend/test/m27_test.dart` (5 Widget-Tests, pumpen den
echten Viewport).

---

## M28 — Polylinien-Kanten als Bemaßungs-Teilnehmer ('ang4')

**Symptom (Nutzer):** Punkt→Linie und Linie→Linie funktionierten nicht —
in seinen Skizzen sind die „Linien" meist RECHTECK-Kanten, also Segmente
EINER geschlossenen Polyline ohne eigenen Entity-Index.

**Ursache:** Die Pick-Matrix behandelte einen Kanten-Klick nur als ERSTEN
Pick (→ zwei Eckpunkte). Nach einem Punkt-, Linien- oder Kanten-Pick fiel
der Polyline-Zweig durch (verlangte leeres Pick-Set) → toter Klick oder
falsche Platzierung; `buildDimensionAt` lieferte teils null.

**Fix (app_state.dart):** Neuer Pick-Container `conEdges`
(List<(PRef, PRef)>), überall mit conPts/conEnts zurückgesetzt. Kanten
kombinieren jetzt wie Linien: Punkt+Kante → pline (senkrechter Abstand),
Linie/Kreis/Bogen/Ellipse+Kante → pline (Zentrum bzw. paralleler Spalt)
oder Winkel, Kante+Kante (erste Kante = das gepickte Eckpaar) → paralleler
Spalt oder Winkel. Erste-Pick-Verhalten (Kante = zwei Ecken, Länge,
kombiniert mit Punkt zu ang3) bleibt UNVERÄNDERT — Tests hängen daran.
Eigene Ecke der Kante und dieselbe Kante nochmal platzieren statt zu
erweitern; ein Punkt erweitert nie ein Set, das schon eine Kante enthält.

**Neue Bemaßungsart 'ang4'** (Winkel Linie/Kante ↔ Kante): pts =
[a1,a2,b1,b2], Winkel zwischen den Strahlen a1→a2 und b1→b2 — der
Linie-Linie-Winkel über PUNKTE, weil eine Kante keinen Entity-Ref hat.
Vollständiger Satz nach Checkliste: Residual + Count + Vorzeichen-Prepare
(wie 'ang', hält die Windung), measureDim (auf [0,180] gefaltet wie 'ang'),
Painter (Bogen am Schnittpunkt der Träger via _angleArc), slvs-Bail
automatisch über die Kind-Whitelist (LM-only wie 'ang3', Kommentar
erweitert). Damit ist die alte M14-Lücke „Winkel zwischen zwei
Polyline-Kanten" geschlossen. Viewport: Halo auch für conEdges-Kanten;
Editor-Suffix ° über _isAngleKind.

**Tests:** `frontend/test/m28_test.dart` (7): Punkt→Kante, Linie→Kante
parallel (Spalt) und 45° (ang4), Kante→Kante 90°, Kreis→Kante,
ang4-Treiben durch LM auf 30°, Regressionen pt-pt / Linie+Punkt /
Linie‖Linie. Merker daraus: Ein Felgen-Klick nahe dem Kreiszentrum pickt
das ZENTRUM (Punkt schlägt Entity innerhalb 10/zoom — Inventor-Priorität);
Test nutzt einen größeren Kreis. 57 Tests gesamt, alle grün.

**Grenzen:** Winkel-Quadrantenwahl bei Platzierung fehlt weiterhin (gilt
für 'ang' UND 'ang4'); Kante als ERSTER Pick bleibt bewusst das Eckpaar
(Länge) statt Linien-Semantik — dokumentierte M21-Entscheidung.

---

## M29 — Tangenten-Constraint mit Splines

**Symptom (Nutzer):** In Inventor funktioniert Tangente auch Spline↔Linie
und Spline↔Kreis — bei uns wies die UI Splines mit „Tangent needs at least
one curved entity" ab (round() prüfte nur arc/circle).

**Inventor-Semantik (umgesetzt):** Spline-Tangente wirkt am Spline-
ENDPUNKT. Mathe-Grundlage in unserem Code: Die End-Tangente läuft bei
BEIDEN Spline-Arten exakt entlang der beiden Definitionspunkte am Ende —
fitCurve dupliziert die Endpunkte (Catmull-Rom-Phantome ⇒ Ableitung bei
t=0 ∝ P1−P0) und die offene CV-B-Spline ist GEKLEMMT (Knoten 0×4…1×4 ⇒
Endtangente entlang CV1−CV0). Das Residual nutzt daher direkt diese zwei
Punkte: glatt in den Parametern, identische Formel für beide Arten.

**Umsetzung:**
- UI (`_constraintClick`, cTangent): Splines (splineCv/splineFit, offen)
  sind gültige Teilnehmer. Das beteiligte ENDE wird beim Klick aufgelöst:
  das Ende, das der anderen Entity näher liegt (distToEntity) — gespeichert
  als PRef im Constraint (pts, ein Ref pro Spline). GESCHLOSSENE Splines
  → Toast, kein Constraint (kein Ende). Linie+Linie weiter abgewiesen.
- Residual (1 Gleichung, wie Inventors 1-DOF-Tangente, normiert):
  Spline+Linie cross(EndDir, LinienDir)=0; Spline+Kreis/Bogen
  dot(EndDir, Endpunkt−Zentrum)=0 (Tangente ⊥ Radius); Spline+Spline
  cross der beiden End-Tangenten. residualCount validiert die End-Refs.
- KEINE Berührungs-Gleichung: wie in Inventor liefert Tangente nur die
  Richtung; den Kontakt stellt der Nutzer über Koinzidenz her (sonst gäbe
  es Redundanz-Warnungen bei Koinzidenz+Tangente).
- slvs: expliziter Bail für Tangente mit Polyline-Beteiligung (der Shim
  kennt keine Splines) → verifizierter Dart-LM-Pfad.

**Tests:** `frontend/test/m29_test.dart` (7): Fit-Spline-Ende wird an
horizontale Linie gedreht; CV-Spline-Ende ⊥ Kreisradius; DOF-Analyse zählt
genau 1 Gleichung; UI löst das NÄCHSTE Ende auf; geschlossener Spline
abgewiesen; Linie+Linie abgewiesen; Regression Kreis+Linie-Tangente.

**Grenzen:** Tangente an geschlossene Splines und an beliebiger
Kurvenstelle (nicht Ende) fehlt; Smooth (G2) mit Splines weiter gesperrt;
Ellipse↔Linie-Tangente (andere Mathematik, kein Endpunkt) offen.

---

## M30 — Tastatur-Shortcuts

Im Viewport-Focus-Handler (der schon Esc/Enter behandelt): **D** Bemaßung,
**L** Linie, **C** Kreis (Zentrum), **R** Rechteck (2-Punkt) — über
selectTool, das außerhalb eines Layers weiter blockiert und den Hinweis
toastet. **S** beendet den aktuellen Layer (finishEdit mit Speichern) bzw.
legt außerhalb eines Layers einen neuen an und betritt ihn (startNewLayer).
**Strg+S / Cmd+S** speichert (saveSketch + Toast). Shortcuts feuern NIE,
während der Inline-Bemaßungseditor tippt (_inlineDim-Guard — dessen
Key-Events bubbeln durch den Ancestor-Focus). Kein const-Map mit
LogicalKeyboardKey (Analyzer-Error: überschreibt ==) — if-Kette.
Tests: `frontend/test/m30_test.dart` (4 Widget-Tests; Merker: Toasts
starten Timer, Tests müssen sie mit pump(6s) ablaufen lassen).

---

## M31 — Tangente mit Rechteck-Kanten + Klick-basierte Auflösung

**Symptom (Nutzer, mit Geräte-Log belegt):** Tangente Spline ↔ Rechteck-
Kante ging weiterhin nicht. Log: „REJECTED tangent/ pts=e4.p0 ents=0,4 —
would over-constrain".

**ZWEI Ursachen (beide aus dem Log ablesbar):**
1. Das M29-Residual kannte als Partner nur line/circle/arc. Für die
   gewöhnliche POLYLINE (das Rechteck) lieferte es konstant 0 → Nullzeile
   im Jacobian → Rang wächst nicht → der Redundanz-Check in _addConstraint
   hielt die Gleichung für wirkungslos und LEHNTE AB. (Gleicher latenter
   Bug: Kreis/Bogen ↔ Rechteck-Kante.) MERKER: Ein Constraint, dessen
   Residual für eine Kombination fehlt, wird nicht etwa ignoriert — er wird
   als „would over-constrain" abgelehnt, weil die Nullzeile den Rang nicht
   hebt. Diese Fehlermeldung ist dann IRREFÜHREND.
2. Im Nutzer-Sketch lagen BEIDE Spline-Enden auf Rechteck-Ecken —
   „nächstes Ende zum Partner" war ein Unentschieden und wählte p0 statt
   des angeklickten p8-Endes. Ende (und Kante) müssen aus den KLICKS
   aufgelöst werden.

**Fix:**
- Neues Feld `conEntClicks` (parallel zu conEnts, NUR von _constraintClick
  gefüllt, überall mit conEnts geleert; Längen-Mismatch → Fallback auf die
  alte Heuristik). Spline-Ende = Ende näher am Klick AUF dem Spline;
  Polyline-Kante = polySegmentAt am Klick auf der Polyline.
- cTangent akzeptiert gewöhnliche Polylines als linien-artige Partner.
  Constraint-pts-Layout: [Spline-End-Ref(s)…, Kanten-Eckpaar(e)…].
  Rechteck+Rechteck bleibt abgewiesen (nichts Gekrümmtes).
- Residuals ergänzt: Spline-Ende ∥ Kante (cross, normiert) und
  Kreis/Bogen ↔ Kante (|senkrechter Abstand Zentrum ↔ Kanten-Trägergerade|
  − r, über die zwei Ecken-PRefs — Polyline-Segmente haben keinen
  Entity-Ref, exakt wie bei pline/ang4). residualCount validiert
  nSpl + 2·nPoly Punkt-Refs.
- slvs-Bail griff schon (Tangente mit Polyline-Beteiligung → LM).

**Tests:** `frontend/test/m31_test.dart` (5): 1:1-Nachbau des Nutzer-
Sketches aus dem Log (Spline-Enden auf zwei Rechteck-Ecken, Klick-Reihen-
folge des Logs) → Constraint AKZEPTIERT, korrektes geklicktes Ende p4 und
korrekte linke Kante, +1 Gleichung in der DOF-Analyse; Solver dreht das
End-Chord vertikal an die rechte Kante; Kreis wächst auf Kanten-Träger
(r→15); UI Kreis+Kante baut Kanten-Refs; Rechteck+Rechteck abgewiesen.
73 Tests gesamt, alle grün.

---

## M32 — Project Geometry (Inventor) + Anzeige-Defaults

**Nutzerwunsch:** Show Constraints und die DOF-Anzeige default AUS; und
Projizieren wie in Inventor: Linien ANDERER Layer (plus X-/Y-Achse und der
eh schon projizierte Centerpoint) in den Editier-Layer projizieren — gelb,
laufend quell-aktualisiert, im Ziel-Layer nicht verschiebbar.

**Defaults:** `showConstraints = false`, `showDof = false` (app_state).

**Modell — das Projektions-Tag:** `Geo.proj` (int), exakt dieselbe Mechanik
wie Spline-/Stil-Tag: App-State, DXF round-trippt eine normale Linie, Tag
im Sidecar (`<name>.proj.json`, Index→proj), von `refresh(tagSource:)`
und ALLEN Copy-Methoden (`withData/onLayer/asSpline/withStyle/withProj`)
getragen — der Solver überschreibt jede Entity bei jedem Solve, eine
vergessene Stelle macht aus der Projektion eine normale Linie.
Werte: >=0 Quell-Entity-Index; projAxisX=-2; projAxisY=-3; projBroken=-4
(Quelle gelöscht → Projektion friert ein, wie Inventors kranke Referenz).

**Solver-Integration (solver.dart, zentral statt an jedem Call-Site):**
`solveConstraints` ist jetzt ein Wrapper: (1) `syncProjections(gs)` kopiert
jede Projektion von ihrer Quelle (Achsen = feste lange Linie ±kProjAxisSpan
durch den CP), (2) `_withProjectionPins` hängt implizite fix-Constraints an
beide Endpunkte, (3) innerer Solve, (4) **NOCHMAL syncProjections** — die
Pins halten die Projektion auf der VOR-Solve-Position der Quelle; bewegt
der Solve die Quelle selbst (Bemaßung auf dem Quell-Layer), hinge die
Projektion sonst einen Solve hinterher (Test hat's gefangen).
`analyzeSketch` bekommt dieselben Pins → Projektionen sind voll bestimmt,
ihre Punkte fehlen in freePoints → der bestehende Drag-Block macht sie
unverschiebbar, ohne neuen Code. Bemaßung GEGEN eine Projektion treibt
dadurch die andere Geometrie (Inventor-Referenz-Semantik).

**UI:** Der bisher funktionslose Ribbon-Button „Project Geometry" startet
`Tool.project`. `_projectClick`: eigener Pick über ALLE sichtbaren Layer
(_pickEntity ist absichtlich auf den Editier-Layer beschränkt). Linie auf
anderem Layer → Projektion (engine.addLine auf Editier-Layer + tagSource
mit withProj). Kein Treffer + Klick nahe y=0 → X-Achse, nahe x=0 →
Y-Achse. Abgewiesen mit Toast: Nicht-Linien, gleicher Layer, Duplikate.
Modify-Tools (Trim etc.) weisen Projektionen ab. Painter: gelb (0xFFE8C84A)
vor der DOF-Färbung. Löschen: `remapProjectionsAfterRemove` (constraints.
dart) an allen drei removeAt-Stellen (deleteLayer, trim, split) — Quelle
weg → projBroken, höhere Quell-Indizes rücken nach.

**Grenzen:** Nur Linien + Achsen projizierbar (Kreise/Bögen/Splines wie in
Inventor wären der nächste Schritt: brauchen sync für circle/arc-Daten und
Pins auf cx,cy,r); Projektion einer Projektion durch den Duplikat-Guard
abgedeckt (liegt exakt auf der Quelle); kein „Break Link".

**Tests:** `frontend/test/m32_test.dart` (8): Defaults aus; Projektion
erzeugt getaggte Kopie auf Layer B; Quelle per Bemaßung getrieben →
Projektion folgt im SELBEN Solve; Pinning (freePoints leer, Bemaßung gegen
Projektion bewegt die freie Linie, Projektion ±1e-6 unbewegt); X-Achse per
Klick nahe y=0; Ablehnungen (Kreis/gleicher Layer/Duplikat); Quell-Layer
löschen → projBroken + eingefroren + solve-stabil; Trim verweigert.
81 Tests gesamt, alle grün.

---

## M33 — Project Geometry: alle Typen, Hover, Button-Highlight, Fremd-Layer-Sperre

**Nutzer-Feedback nach Geräte-Test M32:** Linien projizieren funktioniert;
Kreise/Ellipsen (Splines ungetestet) nicht; Project-Button soll bis Escape
leuchten; im Project-Modus soll projizierbares unter dem Finger
hervorgehoben werden; und grau dargestellte Geometrie ANDERER Layer darf im
Edit-Modus überhaupt nicht mehr anfassbar sein (außer im Project-Modus).

**Alle Typen projizierbar:** `_projectClick` kopiert die Quelle jetzt als
GLEICHEN Typ (onLayer+withProj — Spline-/Ellipse-Tag reist automatisch mit)
und legt sie typrichtig in die Engine (addLine/addCircle/addArc mit
reversed/addPolyline mit closed). `syncProjections` kopiert generisch den
Datenvektor bei Typ-Gleichheit. **Pinning generisch:** fix auf JEDEN
ptCount-Punkt deckt alles ab (Bogen: Zentrum+beide Enden bestimmen r und
Winkel; Polyline/Spline/Ellipse: alle Definitionspunkte) — einzige Lücke
ist der Kreis-RADIUS (ptCount=1), der eine zusätzliche rad-Dimension als
Pin bekommt.

**UI:** `_BigWide` hat jetzt `active` (reicht an das vorhandene
`_Hover.activeHighlight` durch) — der Project-Button leuchtet, solange
`app.tool == Tool.project` (Escape → cancelTool → aus). Hover im
Project-Modus: `pickVisibleAny` (aus _projectClick extrahiert, öffentlich)
über ALLE sichtbaren Layer; hervorgehoben wird nur, was projizierbar ist —
fremder Layer UND noch nicht auf den Editier-Layer projiziert
(`_isProjectedOnto`). Der bestehende Halo-Painter übernimmt den Rest.

**Fremd-Layer-Selektionssperre:** `selectAt` und `boxSelectFinish`
überspringen im Edit-Modus alles, was nicht `geoEditable` ist (und
Unsichtbares). Grau = reine Referenz, exakt Inventor. Projektionen LIEGEN
auf dem Editier-Layer und bleiben damit selektierbar (löschbar); außerhalb
des Edit-Modus bleibt alles antippbar. Modify-Tools waren durch _pickEntity
schon immer gescoped, der M32-Projektions-Guard bleibt zusätzlich.

**Tests:** `frontend/test/m33_test.dart` (6): Kreis projiziert + Radius
gepinnt + folgt Zentrum UND Radius der Quelle; Bogen + Rechteck (closed-
Flag) als typgleiche Kopien; Spline MIT Tag + gepinnt; Hover nur auf
unprojizierten Fremd-Entities (nach Projektion aus, außerhalb Project-Modus
Fremd-Layer nie); Selektion: Quelle nicht antippbar, Projektion schon, Box-
Select gescoped; ohne Edit-Modus weiter alles selektierbar. m32-„circle
rejected"-Test an das neue Verhalten angepasst. 87 Tests, alle grün.

**Grenzen:** Achsen-Projektion weiterhin nur X/Y per Klick nahe der Achse;
kein Break-Link; Projektion einer Projektion über Duplikat-Guard gedeckt.

---

## M34 — Rechtecke = vier Linien; Kanten-Projektion; Hover-/Gelb-Fixes

**Geräte-Feedback zu M33:** (1) Klick auf eine Rechteck-Seite projizierte
das GANZE Rechteck statt nur der Linie; (2) Hover-Highlight im Project-
Modus funktionierte auf dem Rechteck nicht (Kreis/Spline ok); (3) die
projizierten Rechteck-Linien waren weiß statt gelb. Und grundsätzlich:
Rechtecke sollen wie in Inventor VIER Linien mit Constraints sein, nie
eine Polyline.

**Rechteck-Modell (die große Änderung):** Alle vier Rect-Tools
(rectTwoPoint/rect3P/rect2PC/rect3PC) liefern aus buildToolGeometry jetzt
`_rectLines` — vier Linien-Entities. `_commitTool` setzt deterministisch
die Constraints (statt Inferenz): 4× coincident an den Ecken; achsparallele
Tools zusätzlich 2× horizontal + 2× vertical (dof 4: x,y,w,h); die
rotierten 3-Punkt-Tools 3× perpendicular (der vierte rechte Winkel wäre
redundant; dof 5 inkl. Rotation). Jede Seite ist einzeln selektier-,
bemaß-, constraint- und projizierbar — die ganzen Polyline-Kanten-
Sonderwege (M26 Per-Edge-Färbung, M28 conEdges, M31 Kanten-Tangente, M34
Kanten-Projektion) bleiben für POLYGONE, SLOTS und BESTANDS-Sketches mit
Polyline-Rechtecken voll in Kraft — alte Dateien funktionieren unverändert.

**Kanten-Projektion:** Neues Geo-Feld `projSeg` (Segment-Index in der
Quell-Polyline, -1 = ganze Entity), von ALLEN Copy-Methoden + refresh
getragen (withProj(src, [seg])). _projectClick löst bei gewöhnlichen
Polylines das geklickte Segment via polySegmentAt auf und erzeugt EINE
Linie mit (proj, projSeg); syncProjections spiegelt die zwei Quell-
Vertices (wrap bei geschlossen); Duplikat-Guard pro (Quelle, Segment) —
weitere Kanten derselben Polyline bleiben projizierbar (auch im Hover:
_isProjectedOnto zählt nur Ganz-Projektionen). Sidecar `.proj.json`
speichert int (alt, M32-kompatibel) ODER [proj, projSeg]; Loader liest
beide Formate.

**Hover-Fix:** Der Halo-Painter zeichnet gewöhnliche Polylines NUR über
hoverEdge — mein M33-Hover setzte hoverEdge=null → Rechteck ohne
Highlight. Jetzt setzt der Project-Hover hoverEdge über polySegmentAt.

**Gelb-Fix:** Der M26-Per-Edge-DOF-Painter lief auch für projizierte
Polylines und übermalte projPaint → Guard `!isProjection`, projizierte
Polylines (ganz, aus M33-Bestand) sind als Ganzes gelb.

**Tests:** `frontend/test/m34_test.dart` (7): 2P-Rect → 4 Linien, 4×
coincident + 2H + 2V, dof 4, Seite einzeln selektierbar; Corner-Drag hält
Rechteck-Form (H/V + Ecken); 3P-Rect → 3× perpendicular, dof 5; Polygon-
Kante projiziert als eine Linie mit projSeg, zweite Kante ok, Duplikat
abgelehnt; Kanten-Projektion folgt der verbreiterten Quelle; Hover setzt
hoverEdge (und bleibt für unprojizierte Kanten aktiv); projSeg übersteht
alle Copy-Methoden. m33-Erwartung (Ganz-Rechteck) auf Kante umgestellt.
94 Tests, alle grün.

**MERKER:** Neue Rechtecke haben KEINE pickedEdge/conEdges-Semantik mehr
nötig (jede Seite ist eine Linie) — beim Testen auf dem Gerät prüfen, dass
Bemaßung/Tangente/Projektion mit den neuen 4-Linien-Rects den normalen
Linien-Pfad nehmen.

---

## M35 — Pattern-Panel: Rechteckige/Runde Anordnung + Spiegeln (Inventor)

Die drei bisher funktionslosen Pattern-Buttons (Ribbon, Panel 4) sind jetzt
echte Werkzeuge mit Inventor-Dialogen. Recherche-Grundlage: die originalen
Inventor-Sketch-Dialoge ("Rechteckige Anordnung", "Runde Anordnung",
"Spiegeln") — Layout, Selektoren, Optionen und Verhalten wurden 1:1
übernommen, in die App-Palette übersetzt und für Touch skaliert.

**Dialog-Architektur (`widgets/pattern_dialog.dart`, neu):** Der Dialog ist
MODELESS — er schwebt oben rechts über dem Viewport (Stack in Viewport2D)
und die Picks laufen weiter über den Canvas. Welcher Eingabe ein Tap
zufließt, bestimmt der AKTIVE Selektor (blauer Rahmen, Inventors Sprache);
`AppState._patternClick` routet: Geometry = Multi-Pick (Tap toggelt),
Direction 1/2 = Linien-Pick, Achse = Punkt-Pick (inkl. projiziertem CP),
Spiegelachse = Linien-Pick (nie Teil der Selektion). Zustand lebt in einer
`PatternSession` (`app_state.dart`); Esc/Cancel verwirft sie als Ganzes,
Enter = OK. Die aktuelle Selektion seedet den Geometry-Pick-Set (Inventor).

**Rechteckige Anordnung:** Direction 1/2 sind beliebige Linien (nicht
notwendig senkrecht), je Flip-Toggle, Anzahl (inkl. Original) und Abstand.
Direction 2 bleibt grau bis Direction 1 gepickt ist — Inventors Flow.
**Runde Anordnung:** Achse (Punkt/Zentrum/projizierter CP), Flip, Anzahl,
Winkel (Default 360°). **Fitted** (im ">>"-Bereich, Default an): der Wert
ist die GESAMT-Spanne, gleichmäßig geteilt (360° teilt durch n statt n-1,
damit erstes und letztes Element nicht zusammenfallen); aus: der Wert ist
der Abstand ZWISCHEN Elementen. Beides getestet.

**Assoziativität (Checkbox, Default an):** Kopien sind über den Solver an
die Quelle gebunden. Neuer Constraint-Typ `CType.pattern` (ans ENDE des
Enums, Sidecar-kompatibel): ents=[Quelle, Kopie], anchors=[kind, …] mit
kind 0 = Translation (dx,dy) bzw. 1 = Rotation (cx,cy,angle). Residuen:
JEDER Parameter der Kopie = transformierter Parameter der Quelle (Punkte
durch die starre Abbildung, Radius gleich, Bogen-Winkel um die Rotation
verschoben, WRAPPED für glatte Gleichungen) — Kopie-Params == Kopie-
Gleichungen, ein Pattern fügt also nie Netto-DOF hinzu und kann für sich
nie überbestimmen (Test). Der slvs-Shim kennt den Typ nicht → expliziter
Bail auf den verifizierten Dart-LM-Pfad (HANDOFF-Regel: nie stillschweigend
droppen). Assoziativität aus = freie Kopien ohne Constraints (Inventor:
Assoziativität entfernen macht aus dem Muster lose Geometrie).

**Spiegeln:** hält die Kopien über den VORHANDENEN symmetric-Constraint —
exakt Inventors Doku ("Symmetric constraints are applied between the
mirrored geometry"): Linie = 2 Punktpaare, Kreis = Zentrum symmetric +
equal-Radius, Bogen = 3 Punktrefs (die redundante Radius-Zeile ist rang-
neutral für LM und DOF-Analyse), Polyline/Spline/Ellipse = je Vertex.
Apply erzeugt und lässt den Dialog offen (Picks geleert), Done schließt,
Cancel verwirft — Inventors Drei-Knopf-Verhalten. **Self Symmetric** (nur
anwählbar bei genau EINEM offenen Spline): endet der Spline auf der
Spiegelachse (Toleranz 8px/zoom), wird er zu EINEM symmetrischen Spline
verlängert — Definitionspunkte gespiegelt angehängt, Paare i↔2n-2-i per
symmetric gebunden, Mittelpunkt per point-on-line auf der Achse gepinnt.

**Preview:** `patternPreview()` zeichnet die anstehenden Kopien hellblau in
den Viewport (wie der Modify-Ghost, gedeckelt bei 600 Entities). Picks
leuchten: Geometry mit dem Pre-Select-Halo, Richtungs-/Achsen-/Spiegel-
Picks blau.

**Bewusste v1-Grenzen (im Dialog sichtbar ausgegraut, wie Inventor vor dem
Pick):** Grenzen/Umgrenzung (Boundary-Fill), Suppress einzelner Instanzen,
Muster entlang Pfad, nachträgliches Edit Pattern (Transformation ist beim
Commit numerisch eingefroren — die Richtung folgt ihrer Linie NICHT nach).
Zentrierlinien-Stil wird auf Kopien übernommen; der Projektions-Tag
bewusst nicht (Projektionen sind nicht patternbar, Toast).

**Tests (`test/m35_test.dart`, 20 neu, gesamt 114):** Dialog-Flow inkl.
Pick-Routing, Fitted an/aus, zwei Richtungen + Flip, Assoziativität unter
Drag (Quelle editieren → Kopie folgt; Achse im Test geerdet, sonst darf
der Solver legitim die Achse drehen), keine Netto-DOF, Validierungs-Toasts,
360°-Rundmuster um den projizierten CP, Bogen-Winkel-Rotation,
Radius-Folge, Flip-Richtung, Spiegel-Symmetric-Set + Drag-Folge,
Spiegelachse nie in der Selektion, Apply-Verhalten, Self-Symmetric
(verlängert + verweigert bei Abstand zur Achse), Sidecar-Roundtrip von
CType.pattern, Remap beim Löschen der Quelle.

---

## M36 — Form-Constraints, Fillet/Chamfer komplett, Trim erhält Constraints

Drei Baustellen aus dem Geräte-Test: (a) Slots (und weitere Formen) kamen
OHNE ihre Inventor-Auto-Constraints an, (b) Fillet/Chamfer waren rudimentär
(nur Linie-Linie, blockierender Radius-Prompt, keinerlei Constraints),
(c) Trim/Split warfen ALLE Constraints/Bemaßungen des getroffenen Elements
weg.

**(a) Auto-Constraints der Formwerkzeuge (deterministisch im Commit, wie
die M34-Rechtecke — nie über Inferenz):**
- Linearer Slot (`slotCC`/`slotOverall`/`slotCP`, Entities [rail1, rail2,
  cap1, cap2]): koinzident + tangent an allen vier Nähten, equal zwischen
  den Kappen, parallel zwischen den Rails (durch die Tangenten impliziert,
  aber für Inventors Glyphen mitgeführt — redundante Zeilen sind
  rang-neutral für LM und DOF-Analyse). Ein Slot hat danach exakt 5 DOF
  (Position, Rotation, Länge, Radius) — getestet, auch unter Drag.
- Bogen-Slot (`slot3A`/`slotCPA`, [outer, inner, capA, capB]): konzentrisch
  zwischen den Rails, koinzident + tangent an den Nähten, equal-Kappen;
  6 DOF (Zentrum, Rail-Radius, Kappen-Radius, zwei Sweeps) — getestet.
  Naht-Zuordnung siehe `_linearSlot`/`_arcSlot` (capA läuft outer.start →
  inner.start usw.).
- Tangenten-Kreis (`circleTangent`): tangent zu allen drei gepickten Linien
  (Picks werden im Commit über `nearestLineIdx` re-attributiert).
- Tangenten-Bogen (`arcTangent`): koinzident auf den Quell-Endpunkt +
  tangent zur Quelle — deterministisch STATT Inferenz (die hätte die
  Koinzidenz vom Endpunkt-Snap dupliziert).
- Polygon bleibt bewusst ohne Regelmäßigkeits-Constraints (eine Polyline
  hat keine Kanten-Entities für equal — bekannte Grenze, unten gelistet).

**(b) Fillet/Chamfer wie Inventor (`filletInventor`/`chamferInventor` in
tools.dart, Session + modeless Dialog):**
- Kein blockierender Prompt mehr: `FilletSession` (app_state) + das kleine
  "2D Fillet"/"2D Chamfer"-Fenster (pattern_dialog.dart) schweben wie in
  Inventor — Werkzeug bleibt scharf, je zwei Picks = eine Ecke, Werte
  zwischen den Ecken editierbar, letzte Werte bleiben über Sessions
  erhalten.
- Fillet zwischen ALLEN Kombinationen aus Linie/Bogen/Kreis: Fillet-Zentrum
  = Schnitt der Offset-Träger (Linie um r zur Pick-Seite, Kreis/Bogen auf
  R+r bzw. |R−r|), Kandidat mit minimaler Summe der Pick-Abstände gewinnt
  (Inventors Ecken-Disambiguierung). Linien und Bögen werden auf die
  Tangentenpunkte getrimmt (Bögen über den Tangenten-WINKEL am näheren
  Ende); VOLLKREISE bleiben ganz (kein Ende zum Trimmen) — die Tangente
  landet trotzdem.
- Constraints: koinzident an beiden Nähten (`FilletResult.seams` liefert
  Entity + getrimmten Punktindex; `jointPt` mappt auf pt1/pt2 des Bogens
  bzw. pt0/pt1 der Fase) + tangent zu beiden Trägern.
- Inventors Ketten-Verhalten: das ERSTE Fillet eines Werts bekommt seine
  Radius-BEMASSUNG (dimKind 'rad'), alle weiteren mit gleichem Wert eine
  equal-Constraint aufs erste; Wert ändern startet eine neue Kette
  (`firstIdx` reset in `filletNotify`).
- Chamfer mit Inventors drei Modi: 0 = gleicher Abstand, 1 = zwei Abstände
  (d1 auf den ERSTEN Pick), 2 = Abstand + Winkel (Winkel von Linie 1 zur
  Fase, Strahl-Schnitt mit Linie 2). Nur Linie-Linie (wie Inventor).
  Gleicher-Abstand-Fasen: erste bekommt Längen-Bemaßung, weitere equal.
- Preview läuft weiter über `buildToolGeometry` (Params werden von der
  Session in `toolParams` gespiegelt).

**(c) Trim/Split erhalten Constraints (`remapAfterReplace` in
constraints.dart):** Statt `remapAfterRemove` (alles weg) werden Constraints
des ersetzten Elements gehalten, wo sie noch Sinn ergeben — exakt Inventors
Verhalten:
- Punkt-Refs wandern positionsbasiert (Toleranz 1e-6) auf das Teilstück,
  das den Punkt noch HAT; Punkte im weggetrimmten Spann verlieren ihre
  Constraint.
- Entity-Refs (tangent, parallel, Bemaßungen, …) wandern auf das Teilstück,
  das den übrigen Beteiligten der Constraint am nächsten liegt (der Träger
  ist unverändert, die Constraint bleibt also geometrisch gültig); ohne
  Kontext (H/V, Radius-Bemaßung) aufs GRÖSSTE Teilstück. Kreis→Bogen ist
  dabei abgedeckt (Radius-Bemaßung, Tangenten etc. funktionieren auf beiden
  Typen).
- Entity-Level-Fix (anchors = alte Gesamtform) und pattern-Mitgliedschaften
  werden fallen gelassen — die gespeicherte Form existiert nicht mehr.
  Kollabiert eine 2-Entity-Constraint auf ein und dasselbe Teilstück, fällt
  sie ebenfalls.
- Split behält damit ALLES (alle Punkte überleben); eine Gesamtlängen-
  Bemaßung über den Schnitt spannt danach über beide Teilstücke — getestet.
- Nebenbefund gefixt: Trim hinterließ ein LÄNGE-0-Reststück, wenn der
  Schnitt genau auf einem Endpunkt lag (`_notDegenerate`-Filter im
  Trim-Pfad). Nach Trim/Split läuft jetzt zusätzlich `solveConstraints`,
  damit erhaltene Bemaßungen sofort wieder erfüllt sind.

**Tests (`test/m36_test.dart`, 20 neu, gesamt 134):** Slot-Constraint-Sets +
DOF (5 bzw. 6) + Drag-Erhalt, Tangenten-Kreis/-Bogen, Fillet Linie-Linie
(Trim, Nähte, Radius-Dim), equal-Kette + Ketten-Reset bei Wertänderung,
Linie-Bogen-Fillet (Tangenten, Bogen-Trim über Winkel), Kreis-Teilnehmer
ungetrimmt, Chamfer alle drei Modi (inkl. d1-auf-ersten-Pick und
Winkel-Geometrie), Parallel-Ablehnung, Trim-Erhalt von perpendicular /
Radius-Dim (Kreis→Bogen) / tangent (Kreis→Bogen), Drop der weggetrimmten
Koinzidenz, Split-Vollerhalt, Drop von Entity-Fix, Gesamtlängen-Dim über
den Schnitt.

> **HINWEIS (M37):** Einige M36-Behauptungen oben waren im Geräte-Test FALSCH
> und wurden in M37 korrigiert: der Slot-`parallel` und der Bogen-Slot-`equal`
> sind NICHT „rang-neutral", sondern rangredundant und destabilisierten den
> Solver; Fillet/Chamfer ließen die alte Ecken-Koinzidenz stehen (kollabierte
> das neue Segment); die Chamfer-Bemaßung war die Diagonale statt der
> Setbacks; der Fillet-Button war auf Touch tot. Details unten.

---

## M37 — Produktions-Härtung nach dem ersten echten Geräte-Test

Grundlage: Geräte-Log (`prototype_log.txt`, 59 563 Zeilen, **1 802 WARN**),
`Sketch1.dxf` + Sidecars, plus statische Tiefenanalyse. Der volle Audit steht
im README (Abschnitt „PRODUKTIONS-AUDIT", P0–P3 + Tests, mit Erledigt-Notizen);
hier die Essenz für die nächste Session.

**Vier Geräte-Symptome → drei tiefe Ursachen + ein Verstärker (alle belegt,
teils numerisch nachgerechnet):**

1. **Slot-Drag „extrem buggy, Linie/Kreise weg, dann wieder da".** Der
   `parallel`-Constraint des Linear-Slots ist rangredundant (mit den echten
   App-Residuen gemessen: 14 Gleichungen inkl. parallel = Rang **13**), der
   `equal` des Bogen-Slots ebenso (15 → Rang 14). Rangdefizit macht `JᵀJ`
   singulär → libslvs meldet `inconsistent`, LM driftet; pro Frame springt die
   Lösung auf den falschen Tangenten-Ast → **finite, aber falsche** Arcs
   (Radius 54→120, Start≈End → Sweep 0). Ein Sweep-0-Arc rendert NICHTS
   (verschwindet), ein 2.2×-Radius malt quer (‚Linie über dem Fillet'). Beide
   sind finite → `allFinite()` griff nicht → der Frame wurde gemalt. Zusätzlich
   hatte der Anzeige-/Drag-Pfad KEIN Residuen-Gate.
2. **Fillet-Button tut nichts.** Der Fillet-`_SmallRow` hatte kein `onTap` —
   nur das 14-px-▼ öffnete das Flyout (im Log kommt `Tool.fillet` KEIN Mal
   vor, `Tool.chamfer` mehrfach).
3. **Chamfer „geht so", Bemaßung diagonal, ‚Linie über dem Fillet'.** Die
   bestehende Ecken-Koinzidenz der zwei gepickten Kanten wurde NICHT entfernt →
   erzwang Länge 0 des neuen Segments gegen die Bemaßung → Gesamt-Sketch-LM
   divergierte (`err=3.54 satisfied=false` direkt nach dem Chamfer im Log; riss
   den zuvor gebauten Slot mit). Und die Bemaßung war die Hypotenuse statt der
   Setbacks (Inventor: aligned dimensions of the setback distance).
4. **Verstärker:** `_lm`-Rückgabe wurde an drei Stellen ignoriert → divergierte
   Geometrie wurde gerendert UND committet.

**Latenter Native-Bug, im Audit gefunden (vom Dart-Verify stumm gefangen):**
Der Shim verankerte Tangenten immer am Arc-START (`other=0`). SolveSpaces
`ARC_LINE_TANGENT`/`CURVE_CURVE_TANGENT` sind endpunktverankert (`other`/
`other2`, `constrainteq.cpp`); für Fillet-Bögen mit Naht am ENDE war die native
Gleichung 90° falsch, bei Slots stimmte sie nur zufällig auf der symmetrischen
Mannigfaltigkeit. Kreise haben keine Endpunkte (`CURVE_CURVE_TANGENT`
ssassert'et darauf). Das war die zweite Quelle des WARN-Spams.

**Fixes (5 Commits `befac53..3cb40d4`, alle Tests grün):**

- **Solver-Sicherheitsnetz (P0-4/5, P2-2/3).** `solveConstraints` liefert jetzt
  `bool` = erfüllt (Residuum ≤ 1e-2) **und** finite **und** nicht degeneriert.
  Neue Helfer in solver.dart: `constraintResidualNorm`, `hasDegenerateGeometry`,
  `debugRank` (Rang/Gleichungen/Params — Ground Truth für Redundanztests).
  `displayGeometry` zeigt nur erfüllte Frames, sonst die letzte gute Drag-
  Geometrie (`_lastGoodDragGeo`), committet beim Loslassen (Inventor-Verhalten).
  ALLE Commit-Aufrufer sind jetzt atomar mit Rollback+Toast: `_solveAndRebuild`,
  `_addConstraint` (Widerspruch), `confirmDimension`, `setDimensionValue`
  (echt atomar), Pattern/SelfSymmetric, Trim/Split, Konstruktions-Commit
  (As-Drawn-Fallback). `paintGeo` malt degenerierte Arcs als sichtbaren Punkt
  statt `drawArc(0)`.
- **Fillet/Chamfer (P0-1/2/6, P1-1).** Body-`onTap` startet Fillet. Die
  Ecken-Koinzidenz der zwei getrimmten Seam-Punkte wird vor dem Verketten
  entfernt. Chamfer bemaßt `distx`+`disty` (Setbacks) statt Diagonale, alle
  drei Modi. Beide bauen auf lokalen Kopien und committen nur nach
  verifiziertem Solve (sonst voller Rollback — der zuvor gebaute Slot bleibt
  bit-identisch, Sequenztest beweist es).
  BEWUSSTE ABWEICHUNG von M36: die Equal-Kette für Folge-Chamfer entfällt
  (jeder Chamfer eigene x/y-Maße); Fillet behält Radius-Dim + equal-Kette.
- **Slot (P0-3).** Linear-Slot ohne `parallel`, Bogen-Slot ohne `equal`.
  Parallelität/Kappen-Gleichheit sind durch die Tangenten/Konzentrik impliziert
  und bleiben funktional erhalten (Test prüft Kreuzprodukt bzw. Radien-
  Gleichheit nach dem Solve).
- **Tangenten (P1-3 + Shim v3).** Linie-Kreis/Bogen-Residuum vorzeichenbehaftet
  (Seite in `_prepare` eingefroren; glatt, ast-stabil), auch die Polygon-
  Kanten-Variante. Shim v3: `slvs_shim_version()==3`, Naht-Enden in `val`
  (Bit 0/1), vom Aufrufer aus der Geometrie bestimmt (`_tangentSeamFlags`).
  Kreis-Tangenten, nahtlose Tangenten und Shim < v3 bailen sauber auf LM.

**Tests (gesamt Host 157, Shim-Gate 12):**
- `construction_rank_test.dart` (8): Rang == Gleichungen (Redundanz 0) +
  Inventor-DOF für Rechteck 2P/3P, beide Slots, Fillet-/Chamfer-Ecken.
- `drag_stability_test.dart` (9): Drags Frame für Frame über den ECHTEN
  Anzeige-Pfad (finite, nicht degeneriert, Residuum ≤ 1e-4, kein Radius-
  Teleport), Folter-Drag in die Degenerationszone, Park-auf-letztem-Gut,
  8-ms-Budget pro Drag-Solve.
- `operation_sequence_test.dart` (6): die Geräte-Session (Rechteck+Slot+Kreis,
  zwei Chamfer) — Slot bleibt bit-identisch; Fillet-Kette treibt beide Radien;
  abgelehnte Ops ändern NICHTS.
- `shim_test.c` +2: [11] Slot löst NATIV (result OKAY; inkrementeller Drag hält
  parallel+equal), [12] Fillet-Tangente am Arc-ENDE exakt.
- `m36_test.dart`: Slot-Tests auf redundanzfreie Sets, Chamfer-Tests auf
  x/y-Setbacks umgestellt.

**Offen aus dem Audit (Prioritäten im README, Abschnitt PRODUKTIONS-AUDIT):**
P1-2 (Fillet-Trim-Robustheit alle Typpaare), P1-4 (Arc-Rundtrip durch die
C-API verlustfrei absichern / während Drag nicht durch die Engine gehen),
P2-1 (EIN gemeinsames Constraint-Add-Gate), P2-4 (eine Arc-Helferbibliothek
statt mehrerer `norm()`-Kopien), P2-6..P2-9 (Perf/Determinismus/Sidecar/
Autosave), P3-1..P3-8 (Inventor-Dialog-Optionen, Trim/Fillet für Splines/
Ellipsen, Bogenlängen-/Winkel-Bemaßung), T-5/T-7 (Invarianten-Wächter +
VERIFY-FAILED-Zähler = 0 als Geräte-Regressionssignal).

**Nächster Geräte-Test — worauf achten:** 0 (statt 1 802) `VERIFY FAILED`
unter normaler Bedienung, stabiler Slot-Drag, Fillet-Button reagiert,
Chamfer zeigt 5/5 statt 7.07.

---

## M38 — Zweiter Geräte-Test: Ast-Persistenz, Settle, Trim-Bindungen, CP-Fix

Log-Bilanz des M37-Builds: **2 863 Zeilen, 3 WARN, 0 VERIFY FAILED** (vorher
59 563 / 1 802). Die Session wurde vollständig auf dem Host reproduziert und
ist als `device_replay_test.dart` permanent. Kernbefunde und Fixes:

1. **Slot-Faltung, zweite Art.** Nicht mehr Frame-Flackern, sondern ein
   KONTINUIERLICHER Ast-Wechsel durch die degenerierte Lage (jeder Frame
   einzeln erfüllt, Residuen ≤ 3.6e-8 in der Host-Wiedergabe). Per-Solve-
   Seitenwahl kann das nicht verhindern. → `Constraint.tanBranch` (Sidecar
   `tb`): Ast einmalig beim ersten Solve erfasst, danach fix; Kurve-Kurve
   analog (innen/außen). Drags parken an der Grenze statt umzuklappen.
2. **Drag-Commit ohne Settle.** endGripDrag übernahm den letzten guten Frame
   mit bis zu 1e-2 Residuum; auf dem Gerät lagen Slot-Nähte danach über der
   1e-6-Naht-Toleranz von `_tangentSeamFlags` → jede Folge-Operation bailte
   auf LM, ein r=5-Fillet an intakter Ecke wurde fälschlich abgelehnt
   (LM err=3.42), r=50 gelang nach Dialogwechsel nativ. → endGripDrag löst
   voll nach (80 It.) und normalisiert Arc-Winkel (`normalizeArcAngles`).
3. **Fillet-Maße:** JEDE Rundung trägt ihr eigenes `rad`-Maß (Label außen an
   der Bogenmitte); Equal-Kette entfernt — Nutzer-Spezifikation, konsistent
   mit den Chamfer-Setbacks.
4. **Trim/Split-Koinzidenz** (`_bindCutPoints`): neue Schnitt-Endpunkte binden
   Punkt-auf-Punkt (Split-Zwilling) oder Punkt-auf-Kurve auf den Cutter.
   Punkt-auf-Kreis/Bogen neu als Residuum + **Shim v4** `SH_POINT_ON_CIRCLE`
   (`SLVS_C_PT_ON_CIRCLE`, Host-Szenario [13]; Versions-Gate im Packer).
5. **CP-/Punkt-Bindung für deterministische Formen** war seit M34/M36 aus
   (Inferenz lief nur im autoConstrain-Zweig). Punkt-Teil ausgekoppelt als
   `inferPointBindings(..., bindOnlyBefore: firstNew)` und für Rechtecke/
   Slots/Tangenten-Formen aktiv; jede Kandidatin durchläuft
   `wouldOverconstrain`. Tests, die Formen unabsichtlich auf (0,0) zeichneten,
   wurden verschoben; die Erdung selbst ist als Regression festgenagelt.
6. **Pick-Duplikat im Koinzidenz-Werkzeug:** zweiter Punkt-Pick schließt den
   ersten aus (`_nearestPointRef(exclude:)`), trifft also auf gestapelten
   Punkten die ANDERE Entität (Geräte-Log: `e17.p1,e17.p1` abgelehnt).

Stand: Host **161** Tests grün, Shim-Gate **13/13**. Erwartung Geräte-Test 3:
Slot bleibt unter beliebigen Drags ein Slot; Trim-Stücke hängen zusammen;
Ecke-auf-CP erdet; jede Rundung zeigt ihr R; weiterhin 0 VERIFY FAILED.

---

## M38.1 — Trim-Bind-Fix: gestapelte Schnittpunkte werden point-on-point

Geräte-Befund (Log der Session vom 17.07.): zwei Rechtecke bzw. zwei gekreuzte
Linien, von beiden je ein Span weggetrimmt — die beiden neuen Endpunkte liegen
exakt aufeinander, blieben aber nur point-on-curve gebunden und konnten
auseinandergezogen werden. Ursache in `_bindCutPoints`: (a) der
„bereits gebunden"-Check nahm JEDE Koinzidenz als Blocker, auch die schwache
on-curve; (b) die on-curve-Bindung des ersten Trims machte den späteren
point-on-point um genau eine Gleichung redundant → `wouldOverconstrain` lehnte
ihn STILL ab (Log zeigte „cut-bind … pts=e6.p1,e9.p0", Zählerstand unverändert).
Fix: der Block greift nur noch bei vorhandenem point-on-point (pts >= 2); ein
gefundener point-on-point ENTFERNT die subsumierte on-curve-Bindung (Upgrade
statt Stapeln, geloggt als „cut-bind upgrades …"); tryAdd-Ablehnungen werden
geloggt. Regressionen: `trim_stacked_points_test.dart` (Rechteck-Session) und
`trim_crossing_lines_test.dart` (4 Varianten: h/v + schräg, beide
Reihenfolgen) — alle fallen auf dem Vor-Fix-Stand, grün danach.

## M39 — Undo/Redo: Snapshot-Journal pro Skizze (Ctrl+Z / Ctrl+Shift+Z)

**Architektur.** Jede `SketchModel` besitzt ihre EIGENEN zwei Stacks
(`_undoStack`/`_redoStack` mit `UndoSnap`-Einträgen) — Isolation zwischen
Skizzen ist damit strukturell, nicht Buchhaltung. Ein `UndoSnap` ist eine
vollständige Tiefkopie des committeten Zustands: Geometrie (Geos mit kopierten
data-Listen, alle Tags: layer/spline/style/proj/projSeg), Constraints über den
bewährten Sidecar-JSON-Codec (round-trippt value, driven, textPos, anchors,
tanBranch), Layer-Liste + Auge/Schloss. Wiederherstellen ist dadurch EXAKT —
kein Replay, keine inversen Operationen, kein Solve, kein Drift; die Historie
enthält nur Zustände, die schon einmal verifiziert committet wurden.

**Ein Choke-Point.** Da die C-API add-only ist, läuft JEDE Mutation der App
durch `_rebuildEngine` — dort sitzt genau EIN `s.checkpoint()` (unterdrückt
via `_restoringHistory`, sonst würde Undo sich selbst journalieren). Identische
Folgezustände werden dedupliziert: eine Operation mit Doppel-Rebuild kostet
trotzdem nur einen Schritt. Die drei Mutationen OHNE Rebuild checkpointen
explizit: Layer-Auge, Layer-Schloss, leeren Layer anlegen. Baseline: der
`SketchModel`-Konstruktor legt Eintrag 0 an; `openSketch` ruft nach dem Laden
`resetHistory()` — Laden ist keine Bearbeitung, Undo geht „bis zum Anfang"
dieser Sitzung und niemals darüber hinaus. Journal bewusst unbegrenzt
(Snapshot einer 100-Entity-Skizze ≈ zweistellige KB).

**Restore-Pfad** (`AppState.undo()/redo()` → `_applyHistory`): bricht alle
laufenden Picks ab (toolPoints, pattern, filletSess, pendingDim, conPts/Ents/
Edges, modEntity, Selektion), verlässt den Editiermodus, falls der Layer im
Zielzustand fehlt/versteckt/gesperrt ist, und stellt über `_rebuildEngine`
wieder her (Journal-Geos werden beim Restore erneut kopiert — nie aliasen).
Während eines Grip-Drags ist Undo gesperrt. Ansonsten Toast „Nothing to
undo/redo.". View-Zustand (Zoom, Tool, DOF-Anzeige) ist absichtlich NICHT Teil
des Journals — wie Inventor.

**Shortcuts** (viewport.dart, M30-Block): Ctrl+Z = Undo, Ctrl+Shift+Z und
Ctrl+Y = Redo (Ctrl schließt Cmd auf dem iPad ein). Immer nur die AKTUELLE
Skizze.

**Tests:** `undo_redo_test.dart` (7): Zeichnen→Undo-auf-leer→Redo exakt;
komplette Session (Linien, Trims, Bemaßungs-Edit) verlustfrei bis zum Anfang
zurück und wieder vor, inkl. Stabilität bei Hin-und-her; neuer Edit nach Undo
tötet den Redo-Zweig; strikte Pro-Skizze-Isolation (Undo in B lässt A und
dessen eigene Historie unberührt); Layer-Ops (anlegen/Auge/Schloss) undoable;
Restore bricht schwebende Picks ab und journaliert sich nicht selbst;
M38-Trim-Upgrade round-trippt durchs Journal. Suite: **173 grün**.

## M40 — Construction-Geometrie (Inventors Format > Construction)

Recherchiert gegen die Inventor-Doku: Linetypes sind Normal / Construction /
Centerline / Reference; Construction dient dem Constrainen normaler Geometrie,
ist voll bemaß-/constrainbar; Workflow = Format-Panel-Toggle (Auswahl +
Klick konvertiert, nochmal Klick zurück). Die Profile-Consumption-Seite ist in
2D bedeutungslos — Construction ist hier ein reiner Linientyp.

**Implementierung.** Neuer Stil `Geo.styleConstruction = 2` im bestehenden
Style-Slot (rides styles.json-Sidecar unverändert generisch, DXF unberührt).
Rendering in `paintGeo`: dünner (0.55× strokeWidth, geklonter Paint — nie den
Caller-Paint mutieren) + fein gestrichelt (5/4) für ALLE Typen; Kreise/Bögen/
Polylines/Splines dashen über `_dashedChain` (Punktkette mit DURCHLAUFENDER
Phase, kein Muster-Neustart pro Sample). Toggle `toggleConstructionSelected()`
teilt sich `_toggleStyleSelected` mit der Centerline (Inventor-Semantik:
gemischte Auswahl → erst alle konvertieren, uniforme → zurück zu Normal).
Ribbon Format-Panel Zeile 2: Construction | Centerline | Center Point (3×21px,
neues 'constr'-Icon). Solver/Snap/Picking/Dimensionen unterscheiden NICHT nach
Stil — Construction verhält sich exakt wie normale Geometrie.

**Slot-Achse.** `_linearSlot` liefert jetzt 5 Entities: [rail1, rail2, cap1,
cap2, ACHSE] — die Achse ist eine Construction-LINIE zwischen den beiden
Cap-Zentren (Inventor). Der Commit bindet ihre Endpunkte koinzident auf die
Zentren: +4 Parameter, +4 Gleichungen → Slot behält seine 5 DOF, Redundanz 0
(rank-gemessen im Test). Bogen-Slots bekommen (noch) keine Auto-Achse: jede
volle Anbindung eines Construction-Bogens (concentric + beide Enden) ist
messbar um genau 1 Gleichung redundant — offen, in Known limits notiert.

**Beifang-Fix:** `_carry` in modify.dart kopierte Layer + Spline-Tag, aber
NICHT den Linienstil — Trim/Move/Rotate/Mirror/Stretch/Offset setzten damit
jede Centerline still auf Normal zurück. Jetzt trägt `_carry` den Stil immer
mit (Trim-Stücke einer Construction-Linie bleiben Construction).

**Tests:** `construction_geometry_test.dart` (6): Toggle hin/zurück, gemischte
Auswahl, Bemaßung TREIBT eine Construction-Linie, Slot-Achse rank-clean mit
5 DOF, Achsen-Drag bewegt den Slot kohärent, Stil überlebt Trim + Undo-Journal.
Slot-Erwartungen in m36/operation_sequence/device_replay auf 5 Entities
angepasst (Achtung: hartkodierte Folge-Indizes!). Suite: **179 grün**.

## M41 — Inventors Parameter-/Ausdrucks-System für Bemaßungen

Recherchiert gegen die Inventor-Doku (Edit box reference, Parameters in
models, Formulas and equations): jede Bemaßung IST ein Modell-Parameter mit
Auto-Namen d0, d1, …; das Edit-Feld parst volle Ausdrücke ("Name = Ausdruck"
benennt um/erstellt, Syntaxfehler werden ROT gezeigt); auf dem Bildschirm
steht nur der BERECHNETE Wert (fx:-Prefix bei gleichungsgetriebenen
Bemaßungen), der rohe Ausdruck erscheint beim erneuten Öffnen wieder; und
während das Feld offen ist, fügt ein Klick auf eine ANDERE angezeigte
Bemaßung deren Parameternamen an der Cursorposition ein ("if the value is
displayed in the graphics window, you can click it to enter its name").

**Implementierung.** Neues `lib/params.dart`: Tokenizer + rekursiver
Abstiegsparser mit Inventors Präzedenz (+ - * / ^ % , ^ rechtsassoziativ),
Klammern, `;` als Mehrfach-Argument-Trenner (Inventor meidet das Komma wegen
des EU-Dezimalkommas — das Komma ALS Dezimaltrenner wird akzeptiert),
Einheiten-Suffixe mm/cm/m bzw. deg/rad + ul, Konstanten PI/E, Funktionen
sin/cos/tan (GRAD wie Inventors Default), asin/acos/atan (liefern Grad),
sqrt/abs/floor/ceil/round/exp/ln/log/sign/min/max/pow. Bewusst KEINE volle
Einheiten-Algebra (kein mm^3-Fehler) — numerische Auswertung in der
Basis-Einheit (mm bzw. Grad). `Constraint` trägt `paramName` ('nm') und
`expr` ('ex') im Sidecar — damit round-trippt auch das Undo-Journal (M39)
beides automatisch.

**Pipeline (app_state.dart):** `ensureParamName(s)` vergibt d0, d1, … bei
Erstellung UND beim Laden alter Sidecars. `setDimensionText` ist der eine
Commit-Pfad (Umbenennen mit Referenz-Nachzug per Wortgrenzen-Regex, Zyklen-/
Selbstreferenz-/Kollisions-Ablehnung, bloße Zahl → expr=null, kein fx);
`dimTextValid` ist die Live-Validierung fürs rote Feld. Nach JEDEM Solve
(`_rebuildEngine`-Tail, hinter `_refreshDriven`) läuft `_chaseExpressions`:
Ausdrücke zum Fixpunkt auswerten (Ketten in einem Pass), dann erneut lösen,
max. 3 Runden, `_inExprChase`-Guard gegen Rekursion; ein unerfüllbarer
Ausdruckswert friert auf den letzten konsistenten Zahlen ein (Rollback wie
M37, nie divergiert committen). Getriebene (Referenz-)Bemaßungen sind
referenzierbar — ihre Nachmessung nach dem Solve zieht die Abhängigen nach;
selbst editierbar sind sie weiterhin nicht. Gelöschte Referenz: der Wert
bleibt EINGEFROREN, der Ausdruck zeigt sich beim nächsten Edit rot (Inventor
hält den letzten guten Wert).

**Viewport:** Edit-Feld zeigt `d3 = ` als Prefix, den ROHEN Ausdruck (falls
vorhanden), färbt live rot, Enter mit rotem Inhalt bleibt offen, Klick-weg
committet Gültiges und behält sonst den gemessenen Wert (neu platzierte
Bemaßung bleibt wie in Inventor in jedem Fall bestehen); Klick auf ein
anderes Bemaßungs-Label fügt dessen Namen ein statt zu committen.
`confirmDimensionText` journaliert ZWEI Schritte (Anlegen mit Messwert,
dann Text anwenden) — Undo schält sie einzeln ab.

**Tests:** `dimension_expressions_test.dart` (9): Engine (Präzedenz,
Einheiten, Komma, Funktionen, Fehlerfälle), Auto-Namen, Ausdruck treibt
Geometrie, Referenz-Kette propagiert durch zwei Stufen, Umbenennen zieht
fremde Ausdrücke nach + Kollisionsschutz, Zyklen/Selbstreferenz/Unbekannte
abgelehnt ohne Seiteneffekt, getriebene Referenz, Sidecar-Round-Trip,
Undo/Redo durchs Journal. Suite: **188 grün**.

## M42 — Hover-Feedback + Sichtbarkeit außerhalb des Editiermodus

**Hover-Highlight auf Bemaßungs-Labels** (Maus/Trackpad): das Label unter dem
Cursor bekommt einen blauen Rahmen + helleren Hintergrund, wann immer ein
Klick darauf etwas TUT — im normalen Layer-Editiermodus (Tap öffnet den
Wert-Editor; aktiv bei Tool none und dimension) und während das M41-
Ausdrucks-Feld offen ist (Klick fügt den Parameternamen ein; das EIGENE
Label wird nie markiert). Implementierung: `_hoverDimLabel` im Viewport-State
(onPointerHover gegen die `dimLabelRects` des letzten Frames), als
`hoverDim` in den Painter gereicht, `_paintDimension(highlight:)` zeichnet
Rahmen/Hintergrund. Touch hat kein Hover — reine Zusatz-Affordanz.

**Sichtbarkeit wie Inventor:** ohne aktiven Editier-Layer (`inEditMode`
false) sind Skizzen-Annotationen unsichtbar — Bemaßungen (ihre Tap-Rects
werden GELEERT, sonst träfen Taps Geister-Labels), Constraint-Glyphen,
DOF-Pfeile UND Construction-Geometrie (`isConstruction`-Skip in der
Entity-Schleife). Die normalen Linien (inkl. Centerlines) bleiben sichtbar.
Beim Betreten des Editiermodus kommt alles zurück.

**Tests:** `m42_visibility_test.dart` (4): Rects leer außerhalb / gefüllt im
Editiermodus / wieder geleert beim Verlassen; Hover-Pfad + Tap öffnet den
Editor; Klick auf ein ANDERES Label während des offenen Ausdrucks-Felds
fügt `d1` ein statt zu committen; Construction-Skip wirft nicht. Harness-
Hinweis: der Test pumpt den Baum nach editingLayer-Wechseln NEU (keine
Listener-Verdrahtung im Test). Suite: **192 grün**.

## M42-Fix — Geräte-Test: Referenz-Klick verlor gegen die Tastatur

Symptom auf dem iPad: das andere Bemaßungs-Label highlightete korrekt, aber
der Klick darauf COMMITTETE das Ausdrucks-Feld statt den Parameternamen
einzufügen; dazu „zufälliges" Springen der Ansicht beim Öffnen/Schließen des
Editors. Ursache (Log 1a856af, Session 01:24): drei Solves mit unveränderten
cons=11 = drei Klick-weg-Commits. Der Tap AUSSERHALB des TextFields
unfokussiert per Flutter-Default schon beim Pointer-DOWN → iOS-Tastatur
faehrt ein/aus → Scaffold resized → map() (verankert bei size/2) verschiebt
JEDES Label zwischen Down und Up → der Up-Hit-Test verfehlte das sichtbar
getroffene Label → „Klick daneben" → Commit. Dasselbe Resize erklaert die
Pan/Zoom-Spruenge.

Drei Fixes: (1) `resizeToAvoidBottomInset: false` am Scaffold — die
CAD-Leinwand reflowt NIE mit der Tastatur (Editor kann in der unteren
Bildhaelfte von der Tastatur verdeckt sein — bekannt, spaeter clampen);
(2) `_downDimHit`: das Label unter dem Finger wird beim Pointer-DOWN
gecaptured und ist fuer den Klick autoritativ (auch fuer Label-Tap im
Dimension-Tool); (3) `onTapOutside: (_) {}` am Editor-TextField — Commit vs.
Referenz-Einfuegen entscheidet ausschliesslich `_handleClick`, der
Default-Unfocus rennt nicht mehr dagegen. Regressionstest: Down auf dem
Label, Label wird VOR dem Up verschoben (simuliertes Tastatur-Relayout), Up
an der alten Position → Editor bleibt offen, `d1` eingefuegt. Suite:
**193 gruen**.

## M43 — Inventors Parameters-Fenster (Manage > fx Parameters)

Neuer Ribbon-Panel „Manage" mit fx-Button (zwischen Format und Modify) —
oeffnet ein MODELESSES, per Titelleiste VERSCHIEBBARES Fenster ueber dem
Viewport (`widgets/parameters_dialog.dart`, Position lebt als `_paramsPos`
im Viewport-State, geclampt). Tabelle wie Inventor: Model Parameters (alle
Bemaßungen: Name-Zelle editierbar mit Referenz-Nachzug, Equation-Zelle mit
der vollen M41-Grammatik + Live-Rot, getriebene Bemaßungen read-only
„(reference)", Value-Spalte) und User Parameters (Add-Button, Auto-Name
User_1…, Loeschen nur unreferenziert — sonst Toast mit dem Nutzer).
Waehrend eine Equation-Zelle fokussiert ist, fuegt ein Tap auf ein
Bemaßungs-Label im Viewport dessen Parameternamen an der Cursorposition ein
(`AppState.paramRefSink`, vom FocusListener der Zelle gesetzt/geraeumt; der
Viewport prueft den Sink VOR der normalen Klick-Behandlung und nutzt den
Down-Zeit-Hit aus dem M42-Fix; Hover-Highlight ist dann ebenfalls aktiv).

**Engine:** `UserParam {name, expr?, value}` in params.dart (+ JSON-Codec),
`SketchModel.userParams`, eigener Sidecar `<name>.params.json`, UndoSnap um
`uparams` erweitert (sameAs, _takeSnap, Restore) — Journal round-trippt.
`paramTable` = Bemaßungen + User-Params; `_depGraph`/`_cycleIfRefs`
verallgemeinern die Zyklen-Pruefung ueber BEIDE Arten (Bemaßung↔User-Param
gemischte Ketten); `_renameRefs` fegt auch User-Ausdruecke;
`_applyExprValues` wertet User-Params im selben Fixpunkt aus (Domaene mm).
APIs: addUserParam, setUserParamText (Grammatik wie Bemaßung inkl.
„Name = …"), renameUserParam, deleteUserParam (Referenz-Guard),
userParamTextValid, renameDimParam (Name-Zelle der Model-Zeile);
User-Param-Aenderungen checkpointen EXPLIZIT (eine reine Wert-Aenderung
ohne abhaengige Geometrie rebuildet die Engine nicht).

**Tests:** `m43_parameters_test.dart` (5): CRUD + Rename-Nachzug beide Wege,
gemischte Kette User→Dim→User→Dim propagiert bis in die Geometrie, Zyklus
ueber Arten hinweg + Delete-Guard, Validierung spiegelt Commit-Regeln,
Codec- und Journal-Round-Trip. Suite: **198 gruen**.

## M44 — Insert: parametrischer Text, Bild-Import, DXF-Import (iOS-Filepicker)

**Parametrischer Text** (Inventors Skizzentext mit eingebetteten Parametern):
Template mit `<Name>`-Platzhaltern, die als AKTUELLER Parameterwert rendern
(Zahl getrimmt) und jeder Wert-Aenderung UND jedem Rename folgen
(`_renameRefs` fegt jetzt auch Templates via `renameInTemplate`). Unbekannte
Namen bleiben woertlich stehen (Inventor zeigt das rohe Token bis der
Parameter existiert). Text-Tool im Sketch-Panel: Tap platziert, Dialog nimmt
Template (mehrzeilig) + Hoehe (mm); Tap auf vorhandenen Text oeffnet den
Edit-Dialog (mit Delete), Drag verschiebt. Text ist ECHTER Inhalt — auch
ausserhalb des Editiermodus sichtbar (im Gegensatz zu M42-Annotationen).

**Bild-Einfuegen** (Insert > Image): iOS-Dokumentpicker (`file_picker`,
FileType.image) → Datei wird NEBEN die Sidecars kopiert (Picker-Temp stirbt
mit der Session), zentriert mit 100 mm Breite platziert, Aspekt aus den
Pixelmassen. Bild ist ein Underlay (unter aller Geometrie gezeichnet).
Antippen selektiert (blauer Rahmen + Resize-Griff unten rechts, Loesch-X oben
rechts); Drag verschiebt, Eck-Griff skaliert aspekterhaltend. Async-Decode
mit `_imgCache` (ui.Image), Broken/Loading zeigt einen Platzhalterrahmen.

**DXF-Import** (Insert > ACAD): iOS-Picker (FileType.custom, .dxf) →
`importDxf` laedt in eine Wegwerf-`SketchModel` mit demselben Backend-Loader,
der Skizzen oeffnet, re-homed die Entities auf den Editier-Layer (oder Default)
und committet sie als EINEN Journal-Schritt durch die normale Solve/Rebuild-
Pipeline. Leerer/kaputter Import wird mit Toast abgelehnt, ohne Seiteneffekt.

**Modell/Persistenz:** `SketchText` und `SketchImage` in `inserts.dart`
(+ JSON-Codecs), `SketchModel.texts`/`.images`, eigene Sidecars
`<name>.texts.json` / `.images.json`, UndoSnap um `texts`+`images` erweitert
(sameAs/_takeSnap/Restore) → Journal round-trippt beide. Test-Hook
`docsDirForTest` (@visibleForTesting), weil Bild-Copy `_sketchDir` braucht
und der Host-Test keinen Path-Provider hat.

**Tests:** `m44_inserts_test.dart` (5): Template-Rendering (Substitution,
Trim, Unbekanntes woertlich, Refs, Rename), Text folgt Wert+Rename +
CRUD/Move-Journal, Text/Bild-Codec-Round-Trip, Bild Insert/Move/Resize
(Aspekt fix + Journal), DXF-Import (nur natives Backend — Merge auf Layer,
EIN Undo-Schritt, Garbage abgelehnt; auf der Dart-Fallback-Engine
uebersprungen wie die bestehende DXF-Abdeckung). Suite: **203 gruen**.

CI-Hinweis: `file_picker` bringt iOS-Pod-Code — integriert automatisch ueber
den bestehenden CocoaPods-Flow (`flutter build ios --config-only` → Podfile).
Basis-Dokument/Bild-Picking nutzt UIDocumentPicker, braucht KEINE
Info.plist-Usage-Strings.

## M45 — Geraete-Test-Fixes (Insert) + Text-Fenster & Bounding-Rect

Aus dem Geraete-Log (build 173239b): Bild-Resize ging nicht, DXF-Import
landete unsichtbar bei ~10000,-2600. Behoben plus die gewuenschten
Text-Erweiterungen.

**Bild-Fixes.** (1) Resize-Griff-Trefferzone war im FALSCHEN Eck: die Griffe
werden an den SCREEN-Ecken gezeichnet (dst.bottomRight/topRight), der
Hit-Test testete aber die WELT-Rect-Ecken — und Screen-unten = -Welt-y, also
lagen sie ueber Kreuz. Beide Hit-Tests (Resize + Loesch-X) rechnen jetzt in
Screen-Koordinaten ueber `_worldToScreen`. (2) Bilder tragen ihren
Editier-Layer (`SketchImage.layer`); ausserhalb dieses Layers werden sie
gedimmt + entsaettigt gezeichnet (ColorFilter-Matrix, ~40% Deckkraft),
Griffe/Selektion nur auf dem eigenen Layer. (3) Insert platziert AM CURSOR
(`app.insertAnchor` = letzte Zeigerposition, im Viewport bei hover/down
gesetzt) mit Breite = 0.5 * aktuelle Ansichtsbreite (`viewWidthWorld`).

**DXF-Fix.** `importDxf` misst die Bounding-Box der eingelesenen Entities
(Kreise/Boegen inkl. Radius) und verschiebt sie so, dass ihr Mittelpunkt auf
dem URSPRUNG liegt — DXF traegt absolute Modellkoordinaten, die sonst weit
ausserhalb der Ansicht liegen. Log nennt jetzt den Versatz.

**Text-Fenster (statt AlertDialog).** Neues verschiebbares, modeless
`TextEditorWindow` im Stil des Parameter-Fensters (`text_editor_window.dart`,
Position `_textWinPos`): mehrzeiliges Template-Feld, **Font-Dropdown**
(Roboto/Helvetica/Courier/Georgia/Menlo) und **Groesse (mm)**, Live-Preview.
Waehrend das Feld fokussiert ist, fuegt ein Tap auf ein Bemassungs-Label
dessen Namen IN ANFUEHRUNGSZEICHEN ein (`"d0"`, vom Nutzer so gewuenscht) —
`AppState.textRefSink`, gleiche Viewport-Routing-Logik wie der Parameter-
`paramRefSink` (Down-Zeit-Hit, Hover-Highlight). Editier-Session-Lifecycle
(`beginTextEdit/endTextEdit`, `editingText`/`editingTextIsNew`): eine
frisch platzierte, leer abgebrochene Text-Instanz wird verworfen und
erzeugt via `placeholder:true` KEINEN Undo-Schritt; Commit checkpointet.

**Bounding-Rect (Construction-Stil, messbar).** `textBoundsWorld` misst den
gerenderten String automatisch (Font + Hoehe, gemeinsamer Top-Level-Measurer
`measureSketchText`) und liefert das Welt-Rect ab der Unten-Links-Anker-
position. Gezeichnet als DUENN GESTRICHELTES Rechteck im Construction-
Linetype-Look, NUR im Layer-Editiermodus und nur fuer Texte auf dem
Editier-Layer. `textSnapPoints` bietet die 4 Ecken + 4 Kantenmitten dem
Snapper an (via `_snapped` → `computeSnap` extraPoints), sodass Bemassungen
UND neue Geometrie an eine Textbox andocken/messen koennen.

WICHTIGE Design-Einschraenkung (fuer die naechste Session dokumentiert): das
Text-Rect ist KEINE echte Solver-Geometrie, sondern ein Painter-Overlay mit
Snap-Punkten. Man kann also Bemassungen/Geometrie AN die Box-Ecken snappen
und so bemaßen, aber die Box-Kanten sind keine eigenstaendig selektierbaren
Entities und nehmen nicht an Constraints teil. Voll-solver-integrierte
Text-Rects (wie projizierte Geometrie gepinnt) waeren ein groesserer,
riskanter Umbau des Rebuild-Pfads — bewusst aufgeschoben.

**Tests:** `m45_inserts_fixes_test.dart` (6): Bild-Layer + View-Breite,
Font/Layer-Round-Trip, Bounding-Rect-Groesse + Ecken-Snap-Punkte,
Snap-Punkte nur auf Editier-Layer, DXF-Rezentrierung (natives Backend),
Editier-Session-Lifecycle. Suite: **209 gruen**.

## M46 — Tastenkuerzel in Editier-Fenstern unterdruecken

Geraete-Feedback: `l` startete das Linien-Werkzeug, obwohl das Text- oder
Parameters-Fenster offen war und getippt wurde. Ursache: die Buchstaben-
Shortcuts im ancestor-`Focus.onKeyEvent` des Viewports feuerten, weil der
Fokus in bestimmten Situationen nicht (mehr) im TextField lag bzw. der
Viewport ihn zurueckholte.

Fix (viewport.dart): VOR jeder Viewport-Tastenbehandlung wird geprueft, ob
gerade getippt wird — `typing = _inlineDim != null || app.editingText != null
|| app.showParams || _editableHasFocus()`. Wenn ja: `KeyEventResult.ignored`,
d.h. der Viewport fasst die Taste nicht an (weder Buchstaben-Shortcuts noch
Escape/Enter — Escape soll die Feld-Bearbeitung abbrechen, Enter sie
bestaetigen; beides ist Sache des TextFields). Die drei App-State-Flags sind
der deterministische Backstop (unabhaengig vom Fokus-Routing);
`_editableHasFocus()` scannt zusaetzlich das primary-focus-Element auf ein
`EditableText`, damit kuenftige Text-Fenster automatisch mitgeschuetzt sind.

**Tests:** `m46_shortcut_suppression_test.dart` (5): Baseline L→Linie; bei
offenem Parameters-Fenster feuern L/C/R/D NICHT; bei offenem Text-Editor
feuert L nicht; nach Schliessen des Fensters geht L wieder; Ctrl+Z ist
ebenfalls unterdrueckt. Suite: **214 gruen**.

## M48 — Natives iOS-Kontextmenue in der Sketch-Galerie

Long-Press auf eine Karte im Home-Tab oeffnet ein ECHTES UIKit-Menue
(`UIContextMenuInteraction` + `UIMenu`): System-Blur, Haptik, Karte hebt ab.
Eintraege: Rename / Duplicate / Export / Share, und **Delete in eigener
Sektion, von UIKit selbst rot gezeichnet** (wir setzen nur `.destructive` —
niemals selbst einfaerben).

**WARUM EIN PLUGIN UND KEIN SWIFT IM RUNNER (die eigentliche Lehre).** Es gibt
kein `frontend/ios/` im Repo — CI baut es bei JEDEM Run neu mit
`flutter create`. Handgeschriebenes Swift im Runner-Target waere also jedes Mal
weg. Ein Plugin als **path-Dependency** umgeht das komplett: CocoaPods zieht
`packages/native_menu` ueber `.flutter-plugins-dependencies` (von
`flutter pub get` erzeugt) im bestehenden `flutter build ios --config-only`.
Exakt der Weg, den `file_picker` (M44) schon geht — der Pfad ist also erprobt.
Eine frühere Session hielt das faelschlich fuer einen harten Blocker.

**Architektur.** Flutter malt in EINE UIView. Eine `UiKitView` pro Karte waere
teuer und der Preview trotzdem leer (die Pixel gehoeren Flutter). Stattdessen
haengt EINE `UIContextMenuInteraction` an der FlutterView, und Dart published
laufend die Trefferrechtecke der Karten. Der Delegate schlaegt den Punkt nach;
ein Treffer liefert ein `UIMenu`, ein Fehlschlag `nil` — dann reicht UIKit den
Touch unveraendert an Flutter durch.

**Sicherheitsnetze (der Sinn des Entwurfs):**
- Die Interaction haengt NUR dran, solange Targets existieren. Home verlassen
  disposed `HomeView`, das published eine leere Liste und ENTFERNT sie — der
  Long-Press/Drag des CAD-Viewports kann nie verdeckt werden.
- Ausserhalb iOS ist jeder `NativeMenu`-Einstieg ein No-Op (`Platform.isIOS`),
  die Host-Suite sieht also nie einen Platform-Channel.
- Rechtecke werden am Scroll-Viewport geclippt: eine weggescrollte Karte im
  Cache-Extent darf keinen Press beanspruchen.
- Der abhebende Preview ist das VORHANDENE 380x240-Preview-PNG des Sketches,
  kein Snapshot der Metal-Ebene (unter Impeller unzuverlaessig).
- **FALLE:** share/export MUESSEN einen Popover-Anker bekommen. Ein Sheet ohne
  `sourceRect` wirft auf dem iPad `NSGenericException` — das ist ein Absturz,
  kein Schoenheitsfehler.
- **FALLE:** Export nutzt `asCopy: true`. Mit `false` VERSCHIEBT der Picker den
  Sketch aus Documents heraus.

**Dateioperationen.** `deleteSketch` / `renameSketch` / `duplicateSketch` /
`sketchExportPath` laufen alle ueber `AppState.sketchFileSuffixes` — EINE Liste
aller zehn Dateien pro Sketch. Neue Sidecars MUESSEN dort eingetragen werden,
sonst verliert ein Rename sie stillschweigend.

**FALLE (die wichtigste):** `deleteSketch` wirft den Sketch aus der SESSION,
BEVOR es Dateien anfasst. `finishEdit`/`goHome`/`closeTab` speichern
automatisch — ein noch offenes Model haette die Dateien nach dem Loeschen
froehlich zurueckgeschrieben. Ein Test pinnt genau das.

`SketchModel.name` ist final, darum wird ein OFFENER Sketch beim Umbenennen
gespeichert, verworfen und aus den umbenannten Dateien neu geoeffnet —
korrekt, zum Preis des Undo-Journals dieses Sketches.

**CI: IPA-Job auf `macos-26`.** Das Menue ist so oder so ein echtes `UIMenu`,
aber das AUSSEHEN einer System-Komponente folgt dem SDK, gegen das gelinkt
wurde, nicht unserem Code. Gegen das iOS-17-SDK (macos-14) rendert es in
Pre-26-Kompatibilitaetsoptik; gegen das iOS-26-SDK uebernehmen
System-Komponenten Liquid Glass automatisch, ohne Codeaenderung. Der Umzug ist
ohnehin erzwungen: macos-14-Images sind seit 2026-07-06 deprecated und ab
2026-11-02 tot.

Bewusst nur `m5-flutter-ipa` umgezogen — `build-core-ios` und
`m3-ios-sim-logic` bleiben auf dem erprobten macos-14, damit der Radius EIN Job
und EINE Zeile ist. Beide Labels sind arm64 (keine Host-Arch-Aenderung).
Deployment-Target bleibt 14.0 (Xcode 26 akzeptiert praktisch >= 12.0, trotz
dokumentierter 15; Qt-iOS braucht >= 14.0). Xcode 27 hebt den Boden auf 15.0.

Erster Job-Schritt ist ein Toolchain-Report mit `sw_vers`,
`xcodebuild -version`, der iOS-SDK-Version und einer expliziten Zeile
`LIQUID GLASS CHECK: PASS|WARN`. Nach der Projektregel „gruener Haken ist kein
Beweis" ist DAS der Marker, den man liest.

**RISIKO / REVERT:** Die echte Unbekannte ist Qt 6.7 + Xcode-26-Toolchain beim
Bauen von qcad-core. Stirbt der Job im Core-Build waehrend die Flutter-Schritte
gesund sind: die eine Zeile `runs-on` zurueck auf `macos-14`. Der Feature-Commit
ist unabhaengig und braucht keine Runner-Aenderung — man behaelt das native
Menue und verliert nur das Glas. Ist Qt der einzige Verlierer, ist der saubere
Fix ein Split: core+slvs auf macos-15 als Artefakte bauen, IPA hier linken
(alte `.a` linken problemlos gegen einen neueren ld).

**Nebenbei (Geraete-Feedback):** Der „CAD"-Titel im Home-Tab ist weg — nur noch
der runde „+" (die Galerie IST die Startseite). Und der Home-Tab in der unteren
Leiste laeuft jetzt buendig bis an den linken Rand in den Bildschirmradius
hinein; `_Tab.leftPad` schiebt nur den INHALT (Icon + Label) um 28 nach innen,
damit ihn die Ecke nicht abschneidet. Hintergrund und blaue Unterstreichung
fuellen die Ecke.

**Tests:** `native_context_menu_test.dart` (14): Menue-Vertrag (IDs,
Reihenfolge, Sektionen, destructive-Flag), das `toMap()`-Wire-Format, das der
Swift-Parser woertlich liest, No-Op ausserhalb iOS, und jede Dateioperation
inkl. der Autosave-Wiederauferstehungs-Sperre. Suite: **245 gruen**.

**Nicht enthalten / offen:** Rename- und Delete-Bestaetigung sind weiterhin
Flutter-`AlertDialog`s (nur das Kontextmenue selbst ist nativ). Die UIKit-Haelfte
ist auf dem Host nicht testbar — Geraete-Test steht aus: Long-Press hebt die
Karte ab, Delete ist rot, Export/Share oeffnen als Popover AN der Karte (kein
Absturz), und im CAD-Viewport darf ein langer Druck NICHTS ausloesen.

## M49 — Split, exakt wie Inventors 2D-Skizzen-Split

Split gab es schon (M5-Ribbon, `splitEntity` in `modify.dart`), aber es war
NICHT Inventors Verhalten: es schnitt am ANGEKLICKTEN PUNKT, zersaegte einen
Kreis in N Boegen (einen pro Schnittpunkt), verweigerte geschlossene Polylinien
komplett und kannte weder Constraint-Vererbung noch Hover-Preview.

**Autodesks Vertrag (recherchiert, Inventor-Hilfe "To Split, Trim, or Extend
Curves"), den M49 jetzt eins zu eins umsetzt:**
- "splits a selected curve to the NEAREST INTERSECTING CURVE" — der Schnitt
  liegt auf einem Schnittpunkt, NIE unter dem Cursor. Der Klick sagt nur,
  WELCHE Kurve und WO ENTLANG man ist.
- "When multiple intersections are possible, Inventor selects the nearest one"
  — naechster Schnittpunkt zum CURSOR, entlang der Kurve gemessen.
- "Both segments of the split inherit the Horizontal, Vertical, Parallel,
  Perpendicular, and Collinear constraints of the original. Equal and
  Symmetric constraints are broken when necessary."
- Bemassungen bleiben erhalten.
- Hover zeigt den Split VORHER an ("pause over a curve to preview the split").
- Rechtsklick wechselt innerhalb der Sitzung zu Trim/Extend, Esc/Done beendet;
  die Sitzung bleibt fuer MEHRERE Splits offen.
- **Split loescht NIE.** Das ist Trims Verhalten ("no physical or virtual
  intersections -> the Trim command deletes the curve"), nicht Splits.

**Umsetzung.**
- `modify.dart`: neuer `SplitPlan {cuts, pieces, hovered}` — EIN Codepfad fuer
  Preview und Ausfuehrung. `planSplit` / `splitEntity` / `splitPoints`.
- OFFENE Traeger (Linie, Bogen, offene Polylinie/Spline) haben schon zwei
  Enden, also EIN Schnitt am naechsten INNEREN Schnittpunkt -> zwei Stuecke.
  Ein Schnittpunkt exakt AUF einem Endpunkt schneidet nichts weg und zaehlt
  deshalb nicht.
- GESCHLOSSENE Traeger (Kreis, geschlossene Polylinie) haben keine Enden, die
  einen einzelnen Schnitt begrenzen koennten. Inventor laeuft darum vom Cursor
  in BEIDE Richtungen bis zum ersten Treffer: die ueberfahrene Spanne plus ihr
  Komplement — immer GENAU zwei Stuecke, nie N.
- Neue Bogenlaengen-Parametrisierung fuer Polylinien (`_polyCumLen`,
  `_polyParam`, `_polyPointAt`, `_polySub`), damit geschlossene Polygone
  korrekt in zwei OFFENE Ketten zerfallen (ein Split-Stueck ist nie wieder
  eine Schleife).
- Layer, Linienstil und Spline-Tag reiten ueber das vorhandene `_carry` mit.
- `constraints.dart`: `remapAfterSplit` + `kSplitInherited` / `kSplitBroken`.
  Das generische `remapAfterReplace` gibt eine Entity-Constraint an GENAU EIN
  Stueck (richtig fuer Trim, wo das andere weg ist) — ein Split behaelt beide,
  also bekommt eine horizontale Linie zwei horizontale Haelften.
- `app_state.dart`: `splitPreview()`, `cycleModifyTool()` (Rechtsklick-Ring
  Split -> Trim -> Extend), Split loggt jetzt sein Constraint-Delta wie Trim.
- `viewport.dart`: Preview malt die ueberfahrene Spanne blau und die
  Schnittpunkte als roten Punkt mit Ring. Rechtsklick (nur Maus) geht in den
  Tool-Ring und zaehlt nie als Tool-Klick.

**FALLE:** `m36_test.dart` pinnte die ALTE Regel ("Horizontal ueberlebt auf
EINEM Stueck"). Das widerspricht Autodesks Doku und wurde auf 2 korrigiert —
mit Kommentar, dass M49 die Erwartung abloest. Wer die Zahl zurueckdreht,
bricht die Inventor-Treue.

**Status:** host-getestet. `flutter test` **269 gruen** (vorher 245, +21 neue
in `test/m49_split_test.dart` + 3 in bestehenden Suites), `flutter analyze`
**12 Issues, alle vorbestehend** (die `unused_local_variable`-Warnung in
`modify.dart:65` steht so auch in HEAD, per `git show` geprueft) — also keine
neuen. Lokal mit Flutter 3.24.5 im Container verifiziert, nicht nur behauptet.
**Geraete-Test steht aus.**

## M50 — Ribbon abgespeckt + totes Chrome entfernt

Zwei VERSCHIEDENE Operationen, die man nicht verwechseln darf:

**(A) VERSCHOBEN, nicht geloescht.** Selten gebrauchte Befehle verlieren ihre
dauerhafte Ribbon-Breite und sitzen jetzt hinter dem ▼ neben dem PANEL-TITEL.
Sie sind alle weiter erreichbar — wer sie beim Aufraeumen wirklich loescht,
macht das Gegenteil des Gewuenschten.
- **Constrain ▾**: Smooth (G2), Constraint Settings, Show Constraints.
  Das Gitter faellt auf 11 Zellen und von 5 auf **4 Spalten** — schmaler UND
  gleich hoch (3 Reihen).
- **Insert ▾** (= Insert + Format + Manage in EINEM Panel): Points, Centerline,
  Center Point, Driven Dimension, Show Format. Auf der Flaeche bleiben nur
  Image, ACAD, Construction, Parameters (2x2, zwei `_SmallRow`-Spalten).
- **Modify ▾**: Extend, Move, Copy, Rotate, Scale, Stretch. Auf der Flaeche
  bleiben Trim, Split, Offset (eine Spalte).

**(B) WIRKLICH ENTFERNT** (totes Chrome, tat nie etwas):
- Model-Browser: `+`, `🔍`, `☰`
- Tab-Leiste: `☰` und das Wort „Home" (das Haus reicht, Icon jetzt 15 px)
- Der immer sichtbare Schloss-TOGGLE in der Layer-Zeile. Neu `_LockedMark`:
  ein Schloss erscheint **nur bei GESPERRTEN** Layern. Sperren/Entsperren
  laeuft ueber das Rechtsklick-/Long-Press-Menue (dort wo auch Rename/Delete
  sitzen), es ist also nichts unerreichbar geworden.
- Die Statuszeile unten LINKS („N degrees of freedom"). Unten RECHTS steht
  dasselbe als „N dimensions needed" / „Fully Constrained" — als Anweisung
  statt als Zahl. Eine Statuszeile reicht.
- Die ▼ an „Start New Layer", an „Create" und an „Finish" (zeigten auf nichts).

**Technik.** Neu `OverItem` / `_OverMenu` / `_OverRow` neben dem vorhandenen
`FlyItem`/`_FlyMenu`: die Overflow-Eintraege tragen einen ROHEN SVG-String
(die Icon-Maps unterscheiden sich je Panel: CN/IN/MD) und einen freien
Callback, damit auch Toggles und Settings hineinpassen — nicht nur Tools.
`_panel()` bekommt `overId` + `over`; Titel plus ▼ werden zusammen zum
Hit-Target. Das Menue oeffnet nach OBEN (`bottom:`), weil die Panel-Titel
unten sitzen. **Dieselbe Endlich-Breiten-Disziplin wie `_FlyMenu`** —
`ConstrainedBox` + `IntrinsicWidth`; siehe die lange Notiz dort: ein
`Positioned`-Kind eines `Stack` bekommt UNBESCHRAENKTE Constraints, und eine
unendliche Breite laesst Impeller im Release-Build die Fuellung weglassen.
`_SmallRow` bekommt optional `iconWidget` (Parameters nutzt Inventors
kursives „fx" — Schrift, keine Grafik). `_FormatGrid` und die toten
`cornerDd`/`cornerDdBelow`-Parameter sind raus.

**FALLE (wichtig fuer die naechste Session):** Der Ribbon laesst sich auf dem
Host NICHT in einem Widget-Test pumpen. `pumpWidget(MaterialApp(Scaffold(
Ribbon(app))))` kehrt nie zurueck — kein Timeout, keine Exception, einfach
haengen (mit einem Minimal-Probe isoliert). Verdacht: `flutter_svg` beim
Rastern der ~40 Icons unter `flutter_tester`. Deshalb pumpt KEIN einziger
Test im Repo den Ribbon — alle Widget-Tests nehmen HomeView, Viewport oder
Dialoge. Eine vorbereitete `m50_ribbon_slimming_test.dart` (17 Tests) musste
darum wieder raus; sie blockierte die ganze Suite. **M50 ist ausschliesslich
GERAETE-getestet, nicht host-getestet.** Wer den Haenger loest, sollte sie
neu schreiben — die Testluecke ist real.

**Status:** `flutter test` **269 gruen** (unveraendert, M50 fuegt keine Tests
hinzu), `flutter analyze` ohne neue Issues. Die drei `prefer_const_*`-Lints,
die CI in `m49_split_test.dart` fand (CI faehrt einen strengeren Lint-Satz als
lokal), sind gefixt. **Geraete-Test von M49 UND M50 steht aus.**

## M51 — Geraete-Test-Fixes: der Ribbon baute UEBERHAUPT nicht

Der erste Geraete-Build von M50 (`e5bb0a9`) war kaputt. Symptome laut Nutzer:
„die Pfeile sind nicht da" und „Pan/Zoom ist ploetzlich total buggy". Das Log
sagt genau warum: **25 ERROR-Zeilen, alle `Stack Overflow` in
`ComponentElement.performRebuild` / `Element.inflateWidget`** — in JEDEM Frame.

**Wurzelursache (mein Fehler in M50, und eine Falle, die jeder trifft):**
```dart
Widget title = Row(...);
title = Builder(builder: (_) => GestureDetector(child: title)); // FALSCH
```
Eine Dart-Closure faengt die **VARIABLE**, nicht deren Wert. Wenn der Builder
laeuft, zeigt `title` laengst auf den Builder SELBST → jeder Build inflatet
`Builder -> GestureDetector -> Builder -> ...` bis der Stack platzt. Deshalb:
- die drei Panel-Titel (Constrain/Insert/Modify) rendern nie → **keine ▼**,
- der Frame-Pipeline verbringt jeden Frame in der Exception-Behandlung →
  **Pan/Zoom fuehlt sich kaputt an**.

Fix: das innere Widget in ein EIGENES `final` (`titleRow`), Ternaerausdruck
statt Reassignment. **Nie eine Widget-Variable auf etwas umschreiben, das sich
selbst einfaengt.**

**LEHRE, die eine ganze Testluecke aufloest:** in der M50-Session „haengte"
`pumpWidget(Ribbon(...))` im Host-Test — ohne Timeout, ohne Exception. Ich habe
das `flutter_svg` zugeschrieben und die Suite geloescht. **Das war falsch.** Es
war exakt DIESE Rekursion: der Test baute einen unendlich tiefen Baum. Nach dem
Fix pumpt der Ribbon in ~1 s. `m50_ribbon_slimming_test.dart` ist wieder da
(14 Tests) — und ihr ERSTER Test ist genau dieser Regressionsschutz: den Ribbon
ueberhaupt zu pumpen faengt den Bug. Wer wieder einen „unerklaerlichen" Haenger
im Widget-Test sieht: **zuerst nach selbstreferenzierenden Closures suchen**,
nicht nach der Rendering-Library.

**Weitere Fixes derselben Runde:**
- **Overflow-Menue oeffnet nach UNTEN** (`top:` statt `bottom:`). Nach oben
  kletterte es ueber den Ribbon bis in die iOS-Statusleiste; nach unten haengt
  es wie jedes andere Flyout ueber der Zeichenflaeche. Ein Test pinnt die
  Richtung (Menue-Eintrag liegt tiefer als der Titel).
- **Statusleisten-Streifen faerbt sich mit.** Der von `SafeArea` reservierte
  Bereich (Uhr/Batterie) wird von dem gemalt, was HINTER der SafeArea liegt —
  vorher die Scaffold-Viewport-Farbe, waehrend direkt darunter der Ribbon in
  `T.panel` sitzt: eine sichtbare Naht quer ueber den Bildschirm. Jetzt
  faerbt eine `ColoredBox` um die SafeArea mit: `T.panel` in der Skizze,
  `T.galleryBg` auf Home.
- **`_OverRow` kann nicht mehr ueberlaufen** (`Flexible` + Ellipsis,
  maxWidth 320). Der Widget-Test zeigte „RenderFlex overflowed by 14 pixels".
- **Pointer-Zaehlung im Viewport wieder symmetrisch.** Der M49-Rechtsklick-
  Zweig kehrte VOR `_pointers++` zurueck, waehrend `onPointerUp` immer
  dekrementiert — die Zaehlung driftet, und der naechste echte Finger sieht
  aus wie der erste (Pan/Zoom statt Zeichnen). Jetzt wird zuerst gezaehlt.

**Status:** `flutter test` **283 gruen** (269 + 14 wiederhergestellte),
`flutter analyze` ohne neue Issues. Geraete-Test von M49/M50/M51 steht aus.

## Gesamtstand & Arbeitsweise (Stand M40, für die nächste Session)

**Was die App kann:** Skizzieren (Linie, Kreis, Bogen, Rechtecke, Polygon,
Slot, Ellipse mit gebundenen Achsen-Mittellinien, CV-/Fit-Splines),
Layer-System mit Editier-Scope/Lock/Auge, Snapping (Vertex, Mittelpunkt,
Zentrum, Quadranten, projizierter CP), Grips mit Inventor-Semantik,
Constraints (coincident, collinear, concentric, fix, parallel,
perpendicular, h/v, tangent, smooth, symmetric, equal, midpoint, pattern) mit
Auto-Inferenz, Inventors komplette Bemaßungs-Pick-Matrix inkl. pline/ang3
und Inline-Werteingabe, getriebene (Referenz-)Bemaßungen, Mittellinien-Stil,
DXF-Speicherung mit Sidecars (Constraints, Spline-Tags, Styles),
Pattern-Panel (Rechteckige/Runde Anordnung, Spiegeln inkl. Self Symmetric,
assoziativ über den Solver), Slots/Tangenten-Werkzeuge mit Inventor-Auto-
Constraints, Fillet/Chamfer komplett (Linie/Bogen/Kreis, 3 Chamfer-Modi,
Radius- bzw. x/y-Setback-Bemaßung), constraint-erhaltendes Trim/Split,
Diagnose-Log in der Files-App, **Undo/Redo pro Skizze (Ctrl+Z / Ctrl+Shift+Z)**, **Construction-Linetype (Format-Toggle, Slot-Achse automatisch)**, **M41: Inventors Parameter-/Ausdrucks-System (d0/d1-Namen, Formeln mit Referenzen im Bemaßungs-Edit-Feld, fx:-Anzeige, Klick-Referenz)**. **M37: Slot/Fillet/Chamfer sind jetzt
solverstabil (redundanzfrei, atomar, kein divergiertes Rendern).**

**Solver-Architektur (unverändert wichtig, M37-Ergänzungen):** libslvs nativ
zuerst, jede Lösung wird gegen die Dart-Residuen VERIFIZIERT; bail/fail →
Dart-LM (iterations=80). **`solveConstraints` liefert seit M37 `bool` (erfüllt
+ finite + nicht degeneriert) — NIE einen unerfüllten Solve rendern oder
committen; alle Commit-Pfade sind atomar mit Rollback.** Zwei eiserne Regeln:
(1) keine Konstruktion darf ein rangdefizites Set erzeugen (mit `debugRank`
prüfen, Redundanz muss 0 sein); (2) neue Constraint-/Bemaßungsarten brauchen
IMMER: Residual + residualCount (Dart), Shim-Packung ODER expliziten Bail,
measureDim (bei Dims), Painter, Tests. Shim-Codes: slvs_shim.h; Versions-Gate
über `slvs_shim_version()` (**aktuell 4** — v3 = endpunktverankerte Tangenten
mit Naht-Flag in `val`, v4 = `SH_POINT_ON_CIRCLE`) für neue Codes. Tangenten müssen einen gemeinsamen
Endpunkt haben und dürfen keinen Kreis enthalten, sonst Bail auf LM.

**Test-/CI-Workflow:** `flutter test` in frontend/ (**214 Tests**) + Shim-Host-
Tests via CMake (SLVS_SMOKE=ON, „ALL SHIM TESTS PASS", **13 Szenarien**).
Beide sind CI-Gates. Auf dem Host läuft die Dart-Fallback-Engine + LM-Pfad —
genau die Pfade, die die Tests absichern sollen; das native Verhalten sichert
zusätzlich das Shim-Host-Gate. IPA: Workflow „Core + C-API Build (iOS)",
Artefakt `prototype-unsigned-ipa`. Lokal reproduzierbar mit
heruntergeladenem Flutter-SDK (stable) + CMake — beide Gates grün.

## M53 — End of Sketch wie Inventors EOP + Apple-Pencil/Touch komplett

**End-of-Sketch-Marker (Inventors End of Part, auf Layer gemappt).** Die
Zeile im Model-Browser ist jetzt der echte Marker: per Drag nach oben/unten
verschiebbar (Escape bricht die Verschiebung ab, wie Inventor), alles
DARUNTER ist zurueckgerollt — gedimmt (45%) im Browser, ohne Auge, nicht
gezeichnet, nicht pickbar, nicht snapbar, nicht editierbar; Bemaßungen und
Constraint-Glyphen der Entities darunter verschwinden mit (constraintVisible
haengt an geoVisible). Neue Layer entstehen OBERHALB des Markers (Inventor:
neue Features landen ueber dem EOP). Rechtsklick/Long-Press auf den Marker:
Move to Top / Move to End / **Delete all layers below** (mit Bestaetigung,
atomar = EIN Undo-Schritt, Constraint-Refs remappt, gestrandete "0"-Entities
werden mit geloescht und die leere "0" gepruned). Jede Layer-Zeile bietet
"Move End of Sketch here" (Inventor 2013: Move EOP Marker). Der Marker
faehrt im Undo-Journal und im Layer-Sidecar (v3, `eos`) mit; alte Sidecars
laden mit Marker am Ende. Solver-Entscheid: zurueckgerollte Geometrie bleibt
im Gleichungssystem (nichts kann sie greifen oder neu referenzieren, sie
wirkt als unbeweglicher Anker) — dadurch ist der Marker-Move in beide
Richtungen sofort und verlustfrei, kein Re-Solve, kein Drift.

**Apple Pencil + Touch, komplett (Trackpad/Maus unveraendert).**
- **Press-Drag-Release-Zeichnen mit dem Pencil:** Pencil 1/2 haben KEIN
  Hover — zwischen Tap 1 und Tap 2 gaebe es kein Gummiband. Darum ankert
  der Aufsetzpunkt den ersten Punkt (gesnappt), der Zug zeigt die Vorschau
  LIVE mit Snapping (und HUD/Dynamic Input aus M52 greift, weil toolClick
  hudApply selbst anwendet), das Abheben setzt den zweiten Punkt. Ein
  blosser Tap bleibt klassisches Klick-Klick. Nur Geometrie-Tools
  (toolMeta); Bemaßung/Modify bleiben reine Picks. Bei Kontakt erscheint
  der Snap-Marker sofort (onPointerDown), waehrend des Zugs folgt er dem
  Stift (onPointerMove) — Hover-faehige Pencils (Pro/M2) hatten das schon
  ueber onPointerHover, exakt wie die Maus.
- **Palm Rejection:** Touches, die landen waehrend der Pencil unten ist,
  werden abgewiesen — gezaehlt (M52-Kontrakt: Count FIRST), aber nie Klick,
  nie Tap, und der Scale-Recognizer verweigert ihnen den Eintritt
  (`_PalmAwareScale.isPointerAllowed`), damit der Handballen einen Strich
  nie in Pan/Zoom kippt.
- **Zwei-Finger-Tipp = Undo, Drei-Finger-Tipp = Redo (Procreate).** Der
  Klassifikator (lib/touch.dart, host-getestet) trennt Tipp von Pan/Pinch
  ueber Bewegung (>18 px) und Dauer (>350 ms) und wird von jeder
  Nicht-Touch-Aktivitaet vergiftet. Haptik bei Ausloesung; unterdrueckt
  waehrend Textfeld/HUD-Eingabe.
- **Ein Finger:** auf Griff/Body/Text/Bild zieht (mit ~1.8x Fangradius,
  touchSlop), auf leerer Flaeche PANNT er — der Pencil behaelt die
  Box-Selektion. Mit aktivem Tool pannt der Finger (Pencil setzt Punkte,
  Finger navigieren). Zwei Finger: Pan + Pinch wie gehabt.
- **Long-Press (Pencil und Finger, 600 ms, still) = Rechtsklick-Rolle:**
  in der Split/Trim/Extend-Familie springt er zum naechsten Werkzeug (M49),
  sonst Quick-Menue am Finger: OK (bei genug Punkten der variablen Tools),
  Cancel (Esc), plus Line/Circle/Rectangle/Dimension im Edit-Mode — damit
  hat reiner Touch endlich Enter UND Esc.
- **Pencil-Hardware (native_menu-Plugin, UIPencilInteraction):**
  **Squeeze** (Pencil Pro) oeffnet das Quick-Menue an der Spitze
  (hoverPose-Anker, Fallback letzte Stiftposition) — Apples eigene
  Squeeze-Semantik. **Doppel-Tipp** = Familie durchschalten, sonst Esc,
  sonst letztes Zeichenwerkzeug wieder scharf (lastDrawTool). Beide
  respektieren die Systemeinstellung (preferredTap/SqueezeAction .ignore
  wird nie weitergereicht).
- **Fat-Finger-Toleranzen ueberall:** Klick-Picks, Bemassungslabels,
  Bild-Loeschkreuz, Center-Point, Snap-Radius skalieren per touchSlop nur
  fuer PointerDeviceKind.touch; Pencil und Maus bleiben praezise.

Tests: `m53_end_of_sketch_test.dart` (Marker-Default/Insert-Above, Rollback
sichtbar+Selektion+enterEdit, Ein-Schritt-Undo, Delete-Below atomar mit
Remap, deleteLayer-Verschiebung, Sidecar-Roundtrip inkl. prae-M53) und
`m53_touch_test.dart` (Tap-Klassifikator: 2/3 Finger, Bewegung, Timeout,
Vergiftung, Cancel, 1/4 Finger; touchSlop).

**M53-Nachtrag (Geraete-Feedback).** (1) Die HUD-Boxen sitzen jetzt NEBEN der
Geometrie statt darauf: der Block wandert 26 px in Strichrichtung UEBER die
Spitze hinaus und waechst von der Geometrie weg — hinter dem Linienende,
radial ausserhalb des Kreisrands, ausserhalb der gezogenen Rechteck-Ecke;
ohne Richtung (erster Klick) wie bisher rechts unten vom Cursor. (2)
Pfeiltasten wechseln die HUD-Felder: Rechts/Runter = hudTab, Links/Hoch =
hudTabBack (neu, gleicher Lock-und-Weiter-Kontrakt rueckwaerts) — auf dem
Rechteck also w <-> h in beide Richtungen. (3) Press-Drag-Release-Zeichnen
funktioniert jetzt auch mit EINEM FINGER (Live-Vorschau, Fat-Finger-Snap
~1.8x; zwei Finger pannen/zoomen weiter, Procreate-Logik); nur bei
Nicht-Geometrie-Tools (Bemassung/Modify) pannt der einzelne Finger weiter.
Test: m53_hud_arrows_test.dart.


**Bekannte Grenzen / nächste Kandidaten:** (M37-Audit-Punkte mit Priorität
stehen ausführlich im README, Abschnitt PRODUKTIONS-AUDIT — hier nur die
fachlichen Grenzen)
- Trim/Extend kennt getaggte Polylines (Splines/Ellipsen) nicht.
- Keine Tangenten-Handles an Fit-Spline-Punkten (Inventors Pfeil-Griffe).
- Kreis-Abstände immer Zentrum-basiert (keine Tangenten-Variante beim
  Platzieren), keine Bogenlängen-Bemaßung, Winkel ohne Quadranten-Wahl.
- DXF exportiert bei Splines/Ellipsen das Definitionspolygon + Sidecar
  (C-API hat kein Spline-/Ellipsen-Entity; REllipseEntity existiert im
  Core — natives qcad_add_ellipse wäre der saubere nächste Schritt).
- Alte 96-Punkt-Ellipsen (vor M23) bleiben gewöhnliche Polylines.
- Pattern v1: kein Boundary-Fill, kein Suppress, kein Edit Pattern (die
  Transformation ist beim Commit eingefroren; Richtung folgt ihrer Linie
  nicht nach), kein Muster entlang Pfad.
- Polygone (eine Polyline) haben keine Regelmäßigkeits-Constraints (keine
  Kanten-Entities für equal — bräuchte einen Segment-Längen-Constraint).
- Fillet trimmt VOLLKREISE nicht (Kreis→Bogen wäre ein Typwechsel); die
  Tangenten-Constraint sitzt trotzdem. Fillet gegen getaggte Polylines
  (Splines/Ellipsen) nicht unterstützt.
- eqCurve erzeugt weiterhin gesampelte Polylines (bewusst: echte Kurve). Bogen-Slots haben noch keine automatische Construction-Achse (jede volle Anbindung eines Construction-Bogens ist um 1 Gleichung redundant — braucht einen 1-Gleichungs-Winkelbind oder eine Sonderbehandlung im Gate).

## M54 — OCCT 3D-Kernel (OpenCASCADE) vendored: C-Shim, Geometrie-Smoke, isolierte CI, iOS-Link

**Ziel & Scope.** Fundament für Inventor-artiges 3D (Skizze extrudieren →
Solid, Boolesche Ops, STEP-Austausch): OpenCASCADE als DRITTER nativer
Kernel neben QCAD (2D/DXF) und libslvs (Constraints). BEWUSST ohne jede
Dart-/Flutter-Änderung — kein `occt_engine.dart`, keine Widgets, kein
`app_state`-Bezug. Ziellinie dieser Session war: IPA baut und exportiert
die Shim-Symbole. Genau das ist erreicht.

**Was liegt wo:**
```
backend/occt/
  upstream/              OCCT als SUBMODULE, gepinnt auf Tag V7_9_3
                         (Commit a016080b; 8.0.0 bewusst NICHT — zu frisch,
                         CMake/Source-Tree umgebaut; siehe VENDOR.md)
  shim/occt_capi.{h,cpp} Flache C-ABI, EXAKT 14 Funktionen: version/
                         shim_version/last_error, make_box, make_cylinder,
                         extrude_polygon, fuse, shape_counts, shape_valid,
                         shape_volume, bbox, export_step, import_step,
                         free_shape. Jeder Entry-Point fängt ALLE
                         OCCT-Exceptions (nichts entkommt später ins FFI).
                         Marker-String: "Prototype OCCT shim" (strings-Check).
  tests/smoke_occt.c     Standalone-C-Smoke mit harten Zahlen (s.u.)
  CMakeLists.txt         Shim-Projekt; konsumiert einen OCCT-Install-Tree
                         via find_package(OpenCASCADE CONFIG)
  VENDOR.md              Pin-Begründung, Lizenz, die EINE Flag-Liste, Traps
.github/workflows/occt-build.yml   isolierter Workflow (paths: backend/occt/**,
                         .gitmodules, er selbst): ubuntu-Host-Smoke +
                         macos-26 iOS-arm64-Static + nm-Symbolcheck
```

**Empirisch verifiziert (Run 29810990247/…286, Marker aus den Logs
gelesen, nicht Häkchen):**
- Host: `OCCT SMOKE: PASS` — Box 6/12/8 Vol 6000.000000; nicht-konvexes
  L-Profil extrudiert 8/18/12 Vol 3000; Zylinder 3 Faces Vol pi*360;
  **Fuse Box∪Zylinder Vol 8785.398163 == analytisch exakt**; STEP-Roundtrip
  Topologie 8/15/10 → 8/15/10, Volumen identisch; Import fehlender Datei
  → NULL ohne Crash. `OCCT HOST + SHIM: PASS`.
- iOS: kompletter OCCT-Cross-Build (5405 Targets) sauber,
  `defined _occt_* symbols in shim archive: 14`, `OCCT IOS STATIC: PASS`.
- m5-IPA: `OCCT MARKER CHECK: PASS` + **`OCCT LINK CHECK: PASS (14 _occt_*
  symbols exported in Runner)`** — via `-force_load libocct_capi.a`, alle
  47 OCCT-Archive auf der Linkzeile (ld64 zieht nur referenzierte Member),
  `_occt_*` in `qcad_symbols.exp`. M5/SLVS/M6-QIOS-Checks weiter PASS,
  M3 PASS, slvs-build per Dispatch grün (strukturell unberührt — paths).
- Diff-Bilanz: NUR neue Dateien + `.gitmodules` (neu, Repo-Wurzel) +
  m1-core-build.yml (m5-Job: 3 neue Steps; nur 2 geänderte Zeilen:
  exp-printf und OTHER_LDFLAGS). 0 Dart-/frontend-Dateien, 0 qcad/slvs.

**OCCT-Build-Konfiguration (die EINE Wahrheit steht in VENDOR.md):**
4 Module ON (FoundationClasses, ModelingData, ModelingAlgorithms,
DataExchange), Rest OFF, alle `USE_*` OFF (`USE_FREETYPE=OFF` ist der
Schlüssel) → NULL Fremdabhängigkeiten. OCCTs CMake zieht benötigte
Toolkits abgeschalteter Module automatisch als Deps
(`EXCTRACT_TOOLKIT_FULL_DEPS`): TKDESTEP→TKXCAF→TKV3d/TKService/TKCAF/…
werden mitgebaut, obwohl Visualization/ApplicationFramework OFF sind.

**Cache-Mechanik (wichtig für Laufzeiten):** iOS-Install-Tree liegt unter
`actions/cache` Key **`occt-ios-arm64-V7_9_3-r1`** — GETEILT zwischen
occt-build.yml und dem m5-Job (identischer Key + Pfad
`backend/occt/install-ios`). Der Key ist gespeichert (occt-ios-Job hat
"Cache saved" geloggt) → künftige m5-Läufe stellen in Sekunden wieder her
statt ~30 min zu bauen. Host analog `occt-host-V7_9_3-r1` (gespeichert).
**Bei Flag-Änderungen den Suffix -r1 in BEIDEN Workflows bumpen** (Cache
ist per Key unveränderlich). Shim wird IMMER frisch gebaut (schnell).

**Lektionen dieser Session (teuer bezahlt, nicht wiederholen):**
1. **iOS-find_package-Falle:** `CMAKE_SYSTEM_NAME=iOS` ⇒ CMake rootet
   JEDES find_package in die iPhoneOS-SDK-Sysroot um
   (`Darwin.cmake: CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY`) —
   `CMAKE_PREFIX_PATH` außerhalb ist unsichtbar, Fehlermeldung sieht aus
   wie "Install kaputt", obwohl der Install perfekt war. Fix (steckt in
   beiden Workflows): `-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH` — der
   Platform-Default ist NOT-DEFINED-geguarded, das Cache-Entry gewinnt.
   OCCT selbst und libslvs rufen kein find_package → nur der Shim traf es.
2. **actions/cache speichert NICHT bei fehlgeschlagenem Job** — zwei
   30-min-OCCT-Builds gingen deshalb verloren, bevor der find_package-Fix
   grün wurde. Wer das je entkoppeln will: actions/cache/restore +
   /save mit `if: always()` direkt nach dem Build-Step.
3. **`shallow = true` in .gitmodules ist eine Falle:** es macht auch den
   FALLBACK `git submodule update --init` shallow (Default-Branch-Spitze,
   die den gepinnten Release-Commit NICHT enthält). Entfernt. Der primäre
   Weg holt explizit `--depth 1` den exakten SHA (GitHub erlaubt
   SHA-Wants; von frischem Clone aus verifiziert).
4. Submodule-Pin ohne Riesen-Clone: `git ls-remote <url> 'TAG^{}'` liefert
   den gepeelten Commit, dann `git update-index --add --cacheinfo
   160000,<sha>,backend/occt/upstream` + .gitmodules von Hand.
5. `ls | head` gehört zur SIGPIPE-Musterklasse (M3/M5) — vermieden.

**Nächste Session (NICHT in dieser erledigt, bewusst):**
- Dart-FFI-Binding `frontend/lib/ffi/occt_engine.dart` gegen die 14
  Funktionen (DynamicLibrary.process(), Muster von qcad/slvs kopieren);
  DART-SMOKE beim App-Start ("backend=occt-ffi …" analog qcad).
- Danach UI: Extrude-Workflow aus der fertigen Skizze (EOP/M53 ist die
  Vorarbeit), 3D-Viewport-Frage klären (OCCT-Visualization ist NICHT
  gebaut — Rendering muss aus Tessellation (TKMesh ist gebaut) + eigenem
  Renderer kommen oder Visualization-Modul nachziehen ⇒ Cache-Key-Bump).
- Shim wachsen lassen, wenn die UI es braucht (Cut/Common, Fillet 3D,
  Transformationen, Tessellation-Export) — Muster: Funktion in
  occt_capi.h/.cpp + Assert im smoke_occt.c + nm-Zahl 14 in BEIDEN
  Workflows und m1-core-build.yml anpassen (drei `-ge 14`-Stellen!).
- IPA-Größe wächst durch OCCT/STEP spürbar (Schema-Code); wenn's stört:
  Linkliste von 47 Archiven auf die tatsächlich gezogenen reduzieren.

## M55 — Dart-FFI-Binding für den OCCT-Kernel + Boot-Smoke

**Ziel & Scope.** Genau die in M54 angekündigte nächste Session:
`frontend/lib/ffi/occt_engine.dart` gegen die 14 Shim-Funktionen, DART-SMOKE
beim App-Start, Host-Tests. BEWUSST keine UI, kein Extrude-Workflow, 0
Änderungen an `backend/**` oder Workflows (occt-Cache-Key
`occt-ios-arm64-V7_9_3-r1` unangetastet — Restore lief in Sekunden).

**Was liegt wo:**
```
frontend/lib/ffi/occt_engine.dart   Binding: alle 14 occt_* via
                                    DynamicLibrary.process(), Probe-once +
                                    Cache (Muster SlvsFfi.instance()).
                                    OcctFfi.instance() == null heißt EHRLICH
                                    "kein 3D-Kernel" — es gibt bewusst
                                    KEINEN Dart-Fallback für B-Rep.
                                    OcctShape: owned Handle, dispose()
                                    idempotent, use-after-dispose wirft
                                    Dart-seitig (der Shim kann's nicht
                                    erkennen). shimVersion exponiert fürs
                                    Feature-Gating künftiger Surface.
                                    occtSmokeLine() liefert die Log-Zeile
                                    (app-import-frei -> host-testbar).
frontend/lib/app_state.dart         init(): occt-Smoke direkt nach dem
                                    qcad-Smoke; loggt PASS/FAIL/SKIP.
frontend/test/m55_occt_ffi_test.dart  Host: Probe-Miss graceful+gecacht,
                                    Smoke-Zeile darf ohne Kernel NIE PASS
                                    sagen (SKIP, backend=occt-none),
                                    OcctCounts-Format.
```

**Smoke-Semantik (Ehrlichkeits-Regel):** make_box(10,20,30), geprüft gegen
die smoke_occt.c-Zahlen: F6/E12/V8, valid, |vol-6000|<1e-6 →
`DART SMOKE: PASS (backend=occt-ffi, shim vN, <marker>, box F6/E12/V8 vol
6000.000000)`. Symbole nicht gelinkt → `SKIP (backend=occt-none)` — nie
Fake-PASS. Kernel da, aber Zahlen falsch → FAIL mit occt_last_error().

**Empirisch verifiziert (Run 29815209111, workflow_dispatch, MARKER AUS DEN
LOGS gelesen, nicht Häkchen):**
- m5-Dart-Tests: `🎉 301 tests passed.` inkl. der 3 m55-Tests namentlich.
- analyze: 234 infos/warnings auf CIs Flutter 3.44.7 (lokal 3.32: 18) —
  ALLE vorbestehend, 0 `error •`, 0 neue durch M55; Job läuft mit
  --no-fatal-infos --no-fatal-warnings.
- `M5 LINK CHECK: PASS`, `SLVS LINK CHECK: PASS`, `OCCT MARKER CHECK:
  PASS`, `OCCT LINK CHECK: PASS (14 _occt_* symbols exported in Runner)`.
- Cache: `Cache restored from key: occt-ios-arm64-V7_9_3-r1` + "not saving
  cache" (Hit auf Primary Key) — Key lebt, Restore in Sekunden.
- M3: `SMOKE: PASS` … `M3 LOGIC TEST: PASS`, launch exit 0.

**OFFENE SCHULD (ehrlich): der Geräte-Beweis fehlt.** Kein CI-Job STARTET
die Flutter-App: M3 ist der headless C++-Logic-Test (druckt sein eigenes
`SMOKE: PASS`, NICHT die Dart-Zeile), m5 baut nur die IPA. Die Pfade, die
eine echte Shape anfassen (makeBox/counts/volume/dispose), liefen daher
noch NIE gegen den gelinkten Kernel — auf Host greift der SKIP-Zweig.
Erster IPA-Start auf Gerät/Simulator muss
`DART SMOKE: PASS (backend=occt-ffi, …)` im Log zeigen (Files > On My iPad
> prototype > logs). Bis dahin gilt: "gelinkt und gegated, Geräte-Smoke
ausstehend" — nicht "fertig bewiesen".

**Lektion dieser Session:** M3s `SMOKE: PASS`-Marker und der Dart
`DART SMOKE:`-Marker sind ZWEI verschiedene Dinge — wer im M3-Log nach der
occt-Zeile sucht, sucht am falschen Ort. Wenn der Geräte-Smoke je in CI
soll: eigener Schritt, der die App im Simulator startet und das Dart-Log
greppt (Muster vom M3-Launcher übernehmbar).

**Nächste Session:**
1. Geräte-Smoke verifizieren (s.o.) — eine Zeile Aufwand, schließt M55 ab.
2. M56: Extrude-Workflow aus der fertigen Skizze (EOP/M53) über
   `OcctFfi.extrudePolygon`; dabei fällt die 3D-Viewport-Entscheidung an:
   Tessellation (TKMesh ist gebaut) + eigener Renderer ODER
   Visualization-Modul nachziehen ⇒ Cache-Key-Bump -r2 in BEIDEN Workflows.
3. Shim-Wachstum (Cut/Common, Fillet 3D, Transformationen,
   Tessellation-Export) nach M54-Muster: drei `-ge 14`-Stellen anpassen!


## M56 — 3D-Teile, Skizze auf einer Ebene, Extrude produktionsreif

**Der Workflow (das Ziel dieser Session), Schritt fuer Schritt:**
1. Gallery **+** -> Menue **New 2D Sketch / New 3D Part** (`home_view.dart`).
2. **New 3D Part** -> Namensprompt (gleiche Validierung wie Sketches, aber
   EIN Namensraum fuer beide Doku-Arten: `docNameExists`) -> Part-Tab.
3. Part-Ribbon (`_partRibbon` in `ribbon.dart`): Sketch / Create / Modify /
   Work Features / Pattern, exakt die Panels des HTML-Dummys. NUR
   **Start 2D Sketch** und **Extrude** sind verdrahtet, der Rest ist
   bewusst inert (wie im Dummy).
4. **Start 2D Sketch** -> die drei Origin-Ebenen werden sichtbar,
   `pickPlane` ist scharf; Tippen auf eine Ebene erzeugt die Kind-Skizze,
   dreht die Kamera frontal darauf und landet in einem frischen Layer 1.
5. Ab hier ist ALLES der bestehende 2D-Sketcher: `app.current` liefert
   `activeChild`, also greifen Ribbon-Edit-Zweig, Model-Browser, Viewport,
   Tools, Solver, Bemassungen, Undo unveraendert.
6. **Finish Sketch** -> zurueck ins 3D-Teil; jedes Feature wird gegen den
   neuen Skizzenstand neu gerechnet.
7. **Extrude** -> das Eigenschaftsfenster; Profile werden IM VIEWPORT
   gepickt (Hover-Highlight, Mehrfachauswahl, Klick nochmal = abwaehlen).
   OK legt das Feature an, **+** legt es an und macht direkt weiter.

**Profil-Erkennung (`profileLoops` in `part_model.dart`).** Inventors
"pickable region" ueber einer fertigen Skizze: geschlossene Einzelkurven
(Kreis, geschlossene Polylinie, Ellipse) sind sofort Loops; offene Kurven
werden ueber ihre Endpunkte (Toleranz 1e-6 mm) zu einem planaren Graphen
verknuepft, Sackgassen weggeschnitten und die beschraenkten Facetten per
Half-Edge-Face-Tracing gefunden. Damit wird aus den VIER Linien eines
M34-Rechtecks ein Loop, und ein Rechteck mit Diagonale liefert zwei
Dreiecke. `regionsFrom` schachtelt Loops (Loch = direktes Kind), `regionAt`
waehlt beim Tippen die KLEINSTE enthaltende Region. Construction- und
Centerline-Geometrie, unsichtbare Layer und alles unterhalb des
End-of-Sketch-Markers nehmen nicht teil.

**Richtungs-Semantik.** Der Shim extrudiert immer +Z; Inventors vier
Richtungen entstehen aus (Hoehe, Startversatz) und dem Platzierungs-
Transform: default (h, 0), flipped (h, -h), symmetric (h, -h/2),
asymmetric (a+b, -b). Kein Spiegeln, keine invertierten Normalen.

**Ehrlichkeits-Regel (wie M55).** `PartKernel` ist die EINZIGE Naht zum
Kernel. Die App verdrahtet `OcctPartKernel`; ohne gelinkte Symbole meldet
der `available == false` und liefert NULL — kein Fake-Solid, kein stiller
Erfolg. Nur die Tests injizieren ein Fake, um die Zustandsmaschine zu
pruefen.

**Persistenz.** `<name>.part.json` neben den Sketches (Kamera, Origin-
Sichtbarkeit, Kind-Skizzen-Liste, Features samt getippter Ausdruecke);
die Kind-Skizzen liegen unter `parts/<name>/sketches/` mit EXAKT denselben
Sidecar-Formaten wie normale Skizzen. Gallery-Karten unterscheiden per
`kind` (Stahl-Wuerfel fuer Parts), Rename/Duplicate/Delete/Export sind
doku-art-bewusst (`renameDocument` etc.); Export eines Parts schreibt
STEP (braucht den Kernel, sonst ehrlicher Toast).

**Zwei Bugs, die die eigenen Tests gefangen haben** (beide gefixt):
`savePart` iterierte `childSketches` ueber ein `await` hinweg (ein
Plane-Pick in dem Fenster = Concurrent Modification), und
`createNamedSketch` pruefte nur Sketch-Namen, liess also einen Sketch mit
dem Namen eines existierenden Parts zu.

**CI-Lektion dieser Session (teuer, nicht wiederholen): ein `nm` auf einem
STATISCHEN ARCHIV beweist gar nichts ueber fehlende Toolkits.** Der erste
M56-Lauf hatte `TKOffset` (BRepOffsetAPI_DraftAngle) NICHT in der
Link-Liste. Der iOS-Job blieb trotzdem gruen — ein `.a` traegt undefinierte
Referenzen kommentarlos mit sich, und `nm -g | grep 'T _occt_'` zaehlt nur
die DEFINIERTEN Symbole. Erst der Host-Job, der wirklich eine ausfuehrbare
Datei linkt, brachte den `undefined reference to BRepOffsetAPI_DraftAngle`.
Fixes: (1) `backend/occt/CMakeLists.txt` listet jetzt JEDES benutzte
Toolkit explizit (TKOffset, TKMesh, TKGeomBase kamen dazu — die letzten
beiden kamen bisher nur zufaellig transitiv mit), (2) der iOS-Job prueft
die Archive dieser Liste im Install-Tree. Merke: der Host-Smoke ist das
einzige Gate, das Link-Vollstaendigkeit beweisen kann.
**Kein Cache-Bump noetig:** TKOffset gehoert zu ModelingAlgorithms (schon
ON), liegt also laengst im gecachten Install-Tree — der IPA-Job (der alle
`libTK*.a` globt) linkte bereits sauber: `OCCT LINK CHECK: PASS (23
_occt_* symbols exported in Runner)`, `occt-ios-arm64-V7_9_3-r1` restored.

**Tests:** `m56_part_test.dart` (30) — Frames rechtshaendig/orthonormal
(sonst weist `occt_transform` sie ab), Span-Semantik aller vier
Richtungen, Profil-Erkennung (4 Linien -> 1 Loop, Kreis-im-Rechteck ->
Loch, Diagonale -> 2 Facetten, Construction/EOS/Sackgasse), Ausdruecke
mit Einheiten, Kernel-Ehrlichkeit auf Host, kompletter Workflow,
Fehlerpfade (ungueltiger Wert, Kernel-Fehler, geloeschtes Profil),
Sketch-Bindung der Session, Persistenz-Roundtrip, Namensraum.

## M56-Nachtrag — Geraete-Test bestanden + offene Punkte (Basis fuer M57)

**Geraete-Test (User, 21.07.2026): der Workflow laeuft.** + > New 3D Part ->
Start 2D Sketch -> Ebene picken -> 2D zeichnen -> Finish Sketch -> Extrude
-> Solid im Viewport. "Most of the stuff worked perfectly." Vom User benannte
Folgepunkte (in M57 abgearbeitet, siehe unten):

1. Das "+"-Menue soll NATIV werden (echtes UIKit statt Flutters `showMenu`).
2. 3D-Parts brauchen Vorschaubilder (Galerie-Karte + Long-Press-Lift zeigen
   sonst nur den Stahl-Wuerfel).
3. Vorschaubilder sollen zuverlaessig aktualisiert werden (App-Close,
   Skizze/Part schliessen, jeder Wechsel aus einem Dokument in die Galerie) —
   fuer 2D UND 3D.

## M57 — Native "+"-Menue, Part-Thumbnails, zuverlaessige Preview-Refreshs

Die drei M56-Nachtrag-Punkte, umgesetzt. **Host: 344 Tests gruen (13 neu),
`flutter analyze` 0 errors.** Verifiziert lokal mit Flutter 3.44.7 (identisch
zur CI-Version) — vor JEDER Aenderung war der Baseline-Lauf 331/0 gruen, damit
jede Differenz zuordenbar ist.

**(1) Galerie-"+" ist ein echtes UIKit-Action-Sheet.**
`native_menu` bekam einen `"menu"`-Fall: `UIAlertController(.actionSheet)`,
praesentiert ueber den BESTEHENDEN `present(_:anchor:)`-Helfer — der setzt den
Popover-Anker (`sourceView`/`sourceRect`), den das iPad ZWINGEND braucht (sonst
NSGenericException, dieselbe Falle wie share/export). `present` gibt jetzt
`@discardableResult Bool` zurueck, damit ein fehlgeschlagenes Praesentieren den
`FlutterResult` nicht leakt; `answered`-Guard feuert das Result GENAU EINMAL
(Muster von prompt/confirm). Dart: `NativeMenu.menu({items, anchor, title,
cancelLabel})` -> gewaehlte id oder null; abseits iOS `isSupported == false`
-> null. `home_view.dart::_showNewMenu` nutzt es auf iOS (Anker = "+"-Button
per GlobalKey) und faellt sonst auf den unveraenderten `showMenu`-Pfad zurueck.
Contract in `newDocMenuItems()` (top-level, ids `2d`/`3d` == die Rueckgabewerte
des Fallbacks), damit beide Pfade in EINE Verzweigung muenden.
Neu getestet: `m57_new_menu_test.dart` (Contract, Host-No-Op, und der bisher
ungetestete "New 3D Part"-Zweig durch den Fallback bis zum Part-Prompt).

**(2) 3D-Parts haben Galerie-Vorschaubilder.**
`Cam3` + ein session-freies `paintPartSolids` sind aus `viewport3d.dart` nach
`lib/part_render.dart` ausgelagert — WICHTIG gegen einen Import-Zyklus:
`part_render` haengt NUR an `part_model` (Vec3/PartCamera/KernelSolid), nie an
`app_state`; darum nimmt `paintPartSolids` die zu zeichnenden Solids +
optionalen Preview-Solid als Parameter statt der `ExtrudeSession`. Der Viewport
zeichnet unveraendert (Feature-in-Bearbeitung ausgeblendet, Live-Preview
transluzent) — dieselbe Funktion. `AppState._writePartPreview` rendert die
Szene mit `paintPartSolids` in einen `ui.PictureRecorder` (380x240, fixe
Iso-Kamera az=pi/4, pol=0.955, auf die Silhouette gezoomt) und legt
`<name>.png` in `_sketchDir`; `savePart` ruft es, `refreshSaved` findet es
(vorher hart `null` fuer Parts). **Ehrlichkeit:** ein Part ohne zeichenbaren
Solid (frisch, alle Features geloescht, ODER kein Kernel gelinkt) bekommt KEIN
PNG und ein altes wird geloescht -> Karte faellt ehrlich auf den Stahl-Wuerfel
zurueck (kein Fake-B-Rep). Das PNG folgt dem Part durch
delete/rename/duplicate (die drei Ops tragen `<name>.png` jetzt mit).

**(3) `flushCurrentDocument()` — zuverlaessige Refreshs.**
Neue Methode, die das OFFENE Dokument (Skizze ODER Part) inkl. Preview
BEDINGUNGSLOS persistiert. Das ist der Fix gegen veraltete Previews: der alte
Weg lief nur ueber `finishEdit`, das frueh aussteigt (`if (editingLayer ==
null && tool == Tool.none) return;`) — also genau, wenn man ein Dokument nur
ANSCHAUT statt editiert; ausserdem hatte ein Part gar kein PNG. Verdrahtet in
`goHome` (VOR dem Nullen von `curTab`) und in einen `paused`/`detached`-
Lifecycle-Observer in `main.dart` (der `_LogFlusher` haelt jetzt die
`AppState`). `closeTab` speichert das benannte Dokument ohnehin schon
(`saveSketch`/`savePart`, beide schreiben jetzt Previews) — daher dort keine
Aenderung noetig. DXF/Part-JSON/Sidecars werden SYNCHRON geschrieben (vor dem
ersten await in save*), landen also selbst bei `detached`; das PNG ist
best-effort.
Neu getestet: `m57_part_preview_test.dart` (10) — PNG-Existenz + Karte,
Leer-Part-Fallback, Stale-Drop, delete/rename/duplicate tragen das PNG, flush
+ goHome schreiben 2D- UND 3D-Preview neu, No-Op ohne offenes Dokument.

**Test-Infrastruktur:** `AppState.docsDirForTest` hat jetzt auch einen Getter
(symmetrisch zum bestehenden Setter, `@visibleForTesting`) — nur damit Tests
auf geschriebene Dateien pruefen koennen; der Setter nimmt jetzt `Directory?`
(Getter/Setter-Typen muessen matchen; Aufrufer uebergeben weiter non-null).

**EHRLICH offen (nicht in dieser Session verifizierbar):**
- **Swift ist auf dem Host NICHT kompilierbar** (kein Xcode/iOS auf Linux). Der
  `"menu"`-Fall und die `present`-Signaturaenderung sind nur durch Lesen
  geprueft; der Dart-Contract, an dem sie haengen, ist getestet. Erster
  Device-/CI-Build ist das Gate — im Runner muss das Action-Sheet erscheinen
  und eine Auswahl New 2D/3D den jeweiligen Prompt oeffnen.
- Die Part-Thumbnails sind auf Host nur ueber das `FakeKernel`-Mesh getestet
  (kein OCCT gelinkt). Auf dem Device rendert `paintPartSolids` das ECHTE
  Tessellations-Mesh — visuell am Geraet gegenpruefen.
- Der M55/M56-**Device-Smoke `backend=occt-ffi`** ist WEITER ausstehend (davon
  unberuehrt).
- `pubspec.lock` bewusst NICHT angefasst: der committete Lock stammt vom
  lokalen 3.32-SDK; CIs `flutter pub get` (3.44.7) loest 9 transitive Deps neu
  auf — exakt wie der lokale Lauf hier. `--enforce-lockfile` schluege deshalb
  fehl; das ist erwartet, nicht neu.

**Naechste Session:** weitere vom Geraet gemeldete Punkte sammelt der User noch.

## M63 — Zahnrad: echte Kurven, Cache, Corner radius (ersetzt Pitch radius)

**Ausgangslage (gemessen, nicht geschaetzt).** Ein Standard-Zahnrad (m=2, z=20)
erzeugte 1300 Punkte; `arcFitLoop` gewann daraus nur 80 Boegen zurueck und
lieferte **920 Kanten, davon 840 Geraden** → 920 Mantelflaechen im extrudierten
Prisma. Ursache war ein verlustbehafteter Rundweg: `gearProfile` KENNT die
exakten Boegen (Kopf, Lueckengrund, Fillets), polygonisiert sie und laesst
`arcFitLoop` sie anschliessend erraten. Die Evolventen-Flanke ist kein Kreis,
also verwarf die `1e-6*r`-Toleranz sie zwangslaeufig.

**(1) Flanke als Bogenkette.** `_greedySpans` sucht per Binaersuche die WENIGSTEN
Kreisboegen, die innerhalb `_flankTolMm` (1 um) an der exakten Evolvente bleiben;
`_arcSamples` emittiert Punkte, die EXAKT auf diesen Boegen liegen (5 pro Bogen =
4 Sehnen, eine mehr als arcFitLoops Mindestlauf). Der Refit ist dadurch
konstruktionsbedingt verlustfrei. Preview-Aufrufer (`flankSamples <= 12`) bekommen
eine lockerere Toleranz statt eines duenneren Polygonzugs.
Ergebnis z=20: 1200 Punkte, **440 Kanten (200 Boegen)**.

**(2) Memo fuer die Outline.** `splineCurveFor()` ist der Trichter fuer jeden
Paint/Hit-Test/Snap und rief `gearCurve` ungecacht. Key = vollstaendige
geometrische Identitaet (`center`, `angle`, `GearParams.signature`), Bound 64,
`clearGearCurveCache()` fuer Tests.

**(3) Corner radius statt Pitch radius.** Der Pitch-Radius war ein redundantes
Eingabefeld (r = m*z/2, vollstaendig aus Modul + Zaehnezahl bestimmt) mit einer
Ruecksynchronisation auf das Modul. Ersetzt durch `Corner radius (mm)`
(`GearParams.cornerRadius`, 0 = auto/klassisch modulrelativ; speist
`rootFilletRadius`/`tipRoundRadius`). Serialisiert als Block-Slot 9 und
JSON-Key `cr`, beides abwaertskompatibel (pre-M63-Blocks mit 9 Slots laden
unveraendert). `Pitch Ø` bleibt als abgeleitete ANZEIGE in der Infozeile.

**(4) Zwei echte Altfehler, die dabei auffielen.**
- `_roundCorner` deckelte den Ruecksprung auf `0.48 * la/lb`, wobei la/lb die
  NACHBAR-SEHNEN der Tessellierung waren (~0.006..0.1 mm). Jedes Fillet war damit
  auf Sehnengroesse zusammengedrueckt — der Corner-Radius aenderte die Outline
  **ueberhaupt nicht** (bit-identisch von 0.2 bis 1.4 mm, `maxTurn` und `minR`
  unveraendert). Das war der Grund, warum das neue Feature wirkungslos blieb.
- Der Wurzel-Fillet am Zahnuebergang war ein No-Op: der Lueckenbogen ENDET exakt
  dort, wo die naechste Flanke BEGINNT, also bekam `_roundCorner` einen
  Schenkel der Laenge 0, brach ab und gab die nackte Ecke zurueck — pro Zahn ein
  **doppelter Punkt, also eine Kante der Laenge 0** (20 Stueck im Standardrad).
  Genau die Degeneration, die einen OCCT-Wire versenkt (M62); bisher nur von
  `dedupeClosedLoop` stillschweigend geheilt.

**Fix:** `_filletChain` baut den Umriss aus FEATURES (Flanke/Kopf/Flanke/Luecke,
4z Stueck) und rundet jeden Uebergang, indem es beide Nachbarn entlang ihrer
BOGENLAENGE auf die Tangentenpunkte trimmt (`_trimPoly`, `_alongFromEnd/Start`).
Weil die Schenkel gekruemmt sind, iteriert die Konstruktion (8 Durchlaeufe) ueber
die Tangentenlinien an den aktuellen Trimmpunkten auf echte Tangentialitaet; der
Radius wird VORHER auf das geklemmt, was 45% der Nachbarlaenge hergibt (ein
nachtraeglich beschnittener Ruecksprung passt nicht mehr zum Radius und
hinterliess einen 95°-Knick). `_roundCorner` ist entfallen.
Gemessen: realisierter Kruemmungsradius == angeforderter auf 1e-3 mm; keine
Kanten der Laenge 0 mehr; `maxTurn` bleibt ueber den gesamten Radiusbereich glatt.

**Tests** (`m63_gear_curves_test.dart`, 14): Kantenbudget je z, Genauigkeit gegen
eine UNABHAENGIGE Evolventen-Referenz (< 1 um), geschlossene/nicht-degenerierte/
positiv gewundene Outline ueber 5 Parametersaetze inkl. `fillet: false`,
Innenverzahnung, Cache-Identitaet + Miss bei Move/Reparametrisierung + Bound,
Corner-Radius-Monotonie und Treffgenauigkeit, Default == klassische Form,
pre-M63-Sidecar-Roundtrip, Pitch-Radius weiterhin als abgeleitete Groesse.

**Verifikation.** Lokal mit Flutter 3.32.0 (= CI-Version) ausgefuehrt:
`flutter analyze` **0 errors**, `flutter test` **438 gruen** (Baseline vor der
Session: 424). **Geraete-Test offen.**

**Ehrliche Restschuld.** Die ~240 verbliebenen Geraden sind je EIN
Uebergangsvertex zwischen zwei Features — arcFitLoops `ratioOk` (Sehnenverhaeltnis
<= 2) bricht dort zwangslaeufig, weil ein 0.04-mm-Fillet neben einer 0.4-mm-
Flankensehne liegt. Sie verschwinden erst, wenn der Extrude-Pfad EXAKTE Segmente
bekommt statt Punktschleifen: `PartKernel.extrude` nimmt heute
`List<List<List<Offset>>>`, die Entity-Herkunft ist an dieser Grenze verloren
(`ProfileLoop.ents` existiert, reicht aber nicht bis zum Kernel). Das theoretische
Optimum liegt bei ~8 Kanten/Zahn (160 bei z=20) mit einem B-Spline-Eintrag im
Shim (v6) — beides bewusst NICHT in dieser Session, weil es C++ plus ein neues
Symbol-Gate braucht und nur in CI verifizierbar waere.

## M64 — Szenenkosten: Frame-Bremse entfernt, Skizzen sichtbar

**Aus dem Geraete-Log (build 5879273) und dem Screenshot.**

**(1) Der teuerste Code im Frame war eine DIAGNOSE.** `logMeshConvention` rief
`meshSelfReport` synchron in `_pushReality`, also auf dem UI-Thread, bei JEDER
Neuvernetzung. Gemessen mit einem synthetischen Mesh in Geraetegroesse:
**6.9 ms bei 4 636 Dreiecken, 49.9 ms bei 34 236** — bei 16.7 ms Frame-Budget
sind das drei verlorene Frames pro Zoomschritt, und das Log zeigt genau diesen
Sprung (`tris=4636` -> `tris=34236` innerhalb einer Sekunde). Der Report machte
pro Dreieck eine 3-Element-`List`-Allokation fuer die Flaechennormale und eine
Liste aus drei Records fuer die Kanten-Hashmap.
Jetzt: `meshDiagnostics` (default **false**) schaltet den vollen Report; sonst
laeuft `meshBrief` — eine Bounding-Box-Passe ohne jede Allokation.
Gemessen **47.1 ms -> 0.37 ms** bei 34 236 Dreiecken (127x). Der volle Report
ist zusaetzlich allokationsfrei gemacht, und `_conventionLogged` (wuchs
unbegrenzt, jede Neuvernetzung ein neues Mesh-Objekt) ist auf 256 begrenzt.

**(2) Tessellierungs-Ratsche.** `meshNeedsRefine` verfeinert bewusst nur, nie
zurueck — ohne Budget waechst die Szene damit bei jedem Zoom und gibt nie etwas
zurueck. Ein einziges z=20-Zahnrad lag bei 34 236 Dreiecken. Neu:
`budgetedLinDeflection` lockert das Bildschirm-Ziel proportional zur
Ueberschreitung von `kSceneTriangleBudget` (120 000). Weil das Ziel dadurch nur
GROEBER werden kann und `meshNeedsRefine` Groeberes ablehnt, pendelt nichts —
die Schleife laeuft einfach aus.

**(3) Skizzen im 3D.** Skizzenkurven wurden mit `edgeRadius * 1.2` gezeichnet
und mit `halfH * 5e-4` von der Flaeche abgehoben — das ist **ein Viertel** von
`highlightEps`, das im selben File als Minimum dokumentiert ist, das die
Tiefenaufloesung ueberlebt. Deshalb lag eine Skizze auf einer Flaeche im
Z-Fighting statt sichtbar darauf. Neu: eigene `sketchRadius` (2.8e-3) und
`sketchEps` (3e-3).

**Verifikation.** `flutter analyze` 0 errors, `flutter test` **443 gruen**
(neu: `m64_scene_cost_test.dart`). Swift-Aenderungen nur von CI kompiliert.
**Geraete-Test offen.**

**OFFEN — die vielen senkrechten Linien (Screenshot).** Ursache gefunden, Fix
bewusst NICHT in diesem Commit: eine bogenapproximierte Flanke (und genauso
eine tessellierte Spline) erreicht den Kernel als KETTE getrennter Flaechen,
und der Renderer zeichnet jede Flaechengrenze. `occt_unify`
(ShapeUpgrade_UnifySameDomain) laeuft bereits — sowohl im Extrude-Pfad
(occt_capi.cpp:445) als auch in `part_model.dart:1530` — kann hier aber nichts
tun, weil benachbarte Flankenboegen ECHT verschiedene Zylinder sind
(andere Mitte, anderer Radius) und darum nicht dieselbe Domaene haben.
Richtiger Fix ist ein Anzeigefilter fuer tangentenstetige Kanten, wie Inventor
ihn hat, und der gehoert in den Shim: `occt_mesh_create` baut bereits
`TopExp::MapShapesAndAncestors(shape, TopAbs_EDGE, TopAbs_FACE, edgeFaces)`
(occt_capi.cpp:995) und filtert dort schon Seam-Kanten heraus. An genau dieser
Stelle, direkt nach dem Seam-Check und vor `BRepAdaptor_Curve curve(edge)`,
gehoert: bei genau zwei Nachbarflaechen die Normalen in der Kantenmitte
vergleichen (`BRep_Tool::CurveOnSurface` -> `BRepLProp_SLProps`, Orientierung
beachten) und die Kante bei kleinem Winkel ueberspringen — analog zum
bestehenden `if (seam) continue;`. Das ist Shim **v9** samt Symbol-Gate und
ausschliesslich in CI verifizierbar; deshalb als eigener, fokussierter Schritt
statt blind zusammen mit drei anderen Aenderungen.

## M65 — Shim v9 Tangentenfilter, Budget nachgemessen, perf-Kanal

Aus dem Geraete-Log build=39555ac.

**(1) Shim v9 — tangentenstetige Kanten werden nicht mehr gezeichnet.**
`edge_is_smooth` vergleicht in `occt_mesh_create` die beiden Flaechennormalen
in der Kantenmitte (`BRep_Tool::CurveOnSurface` -> `BRepLProp_SLProps`,
Orientierung beachtet) und ueberspringt die Kante ab cos(8 deg). Kein neues
Symbol, keine ABI-Aenderung, kein neues Gate — der Filter sitzt intern neben
dem bestehenden Seam-Filter. Bei Unentscheidbarkeit wird die Kante BEHALTEN,
nie faelschlich versteckt.

**(2) Budget war geraten und feuerte nie.** Ein z=20-Zahnrad erreichte im Log
**50 548** Dreiecke, `kSceneTriangleBudget` stand auf 120 000. Jetzt 40 000,
per Test gegen die gemessenen 50 548 abgesichert.

**(3) perf-Kanal.** `Log.i('perf', 'remesh n=.. lin=.. tris=.. in ..ms')` nach
jedem Verfeinerungslauf — im Log war sonst unsichtbar, dass EIN Zahnrad
viermal neu vernetzt wurde (41640 -> 46180 -> 49040 -> 50548).

**OFFEN, mit Belegen.** Der groesste Posten ist NICHT behoben: der
Feature-Baum wird bei jeder Aenderung komplett neu ausgefuehrt.
`recomputeAllFeatures` (part_model.dart:1691) ruft `recomputeFeature` fuer
JEDES Feature bedingungslos. Beleg: um 13:44:13 faellt Extrusion1 von 50 548
auf 4 304 Dreiecke zurueck und verfeinert sich viermal neu, nur weil eine
zweite Extrusion beginnt — 20 Sekunden Kernel-Arbeit weggeworfen, obwohl sich
an Extrusion1 nichts geaendert hat. Fix ist ein Signatur-Cache pro Feature
(eigene Parameter + Quellskizze + akkumulierte Upstream-Signatur); wer
unveraendert ist, behaelt Solid UND verfeinertes Mesh. Bewusst nicht blind
gemacht: der Cache muss `consumedByJoin`, `disposeSolid()` und die
Boolean-Kette exakt richtig behandeln, sonst wird das Modell korrupt.
Ebenfalls offen: Kontextmenue auf Extrusion/Solid, und der 200-ms-Drag
(Solver selbst nur 0.14-0.4 ms, die Zeit geht woanders hin — der perf-Kanal
gehoert als naechstes um den Drag-Handler).

## M66 — Remesh-Stocken, Splines als Boegen, Shim-Version geradegezogen

Aus dem Geraete-Log build=9ef0425. Der v9-Filter wirkt (Zahnrad bestaetigt),
aber der perf-Kanal hat sofort das eigentliche Problem gezeigt.

**(1) Die Neuvernetzung blockiert 0.4-2.6 s auf dem UI-Thread.**
`remesh ... in 696ms / 1133ms / 1251ms / 1634ms / 1812ms / 2130ms / 2580ms`.
Das ist das Stocken beim Zoomen und im Skizzenmodus auf einer Zahnradflaeche —
nicht das Zeichnen, sondern der Kernel.

**(2) Das Budget aus M65 hat versagt.** Es skalierte mit `sceneTris/budget`,
und genau beim Ueberschreiten ist dieses Verhaeltnis ~1.0 — die Lockerung war
also praktisch null und das Geraet lief bis **78 976** Dreiecke weiter. Jetzt
HARTER Stopp: ab Budget wird `double.infinity` zurueckgegeben, `meshNeedsRefine`
lehnt ab, die Ratsche steht. Ab 80% Auslastung wird sanft eingebremst.

**(3) Deflection-Boden war absurd fein.** Das Log erreichte `lin=1.28e-4`, also
0.1 um Sehnenfehler — kein Display loest das auf, es kostete 1 812 ms. Boden
von 1e-4 auf **2e-3** (2 um).

**(4) Splines bekommen dieselbe Behandlung wie die Zahnradflanke.**
Eine tessellierte Spline erreichte den Kernel als Polygonzug, also als Prisma
aus PLANEN Streifen — jede Streifengrenze ist ein echter Knick, den der
v9-Tangentenfilter darum NICHT entfernen kann. Genau deshalb waren beim
Zahnrad die Linien weg, bei der Spline nicht. `arcChainResample` (aus gear.dart
oeffentlich gemacht) legt die Spline auf eine Kette echter Kreisboegen mit
groessenskalierter Toleranz (0.02% der Bounding-Box, 1e-3..5e-2 mm); arcFitLoop
bekommt dadurch exakte Bulges, das Prisma echte Zylinderflaechen, und die
Uebergaenge sind nahezu tangential und fallen unter den v9-Filter.

**(5) `occt_shim_version()` gab noch 8 zurueck**, waehrend der Versionsstring
schon v9 sagte — im Log gut sichtbar als `shim v8, Prototype OCCT shim v9`.
Korrigiert.

**Verifikation.** analyze 0 errors, **444 Tests gruen**. Die Spline-Umstellung
hat keinen bestehenden Test gebrochen. C++ nur CI-verifiziert.

**Weiterhin offen:** Feature-Cache (`recomputeAllFeatures` fuehrt jedes Feature
bedingungslos neu aus), Kontextmenue auf Extrusion/Solid, und die
Neuvernetzung laeuft weiterhin synchron auf dem UI-Thread — das Budget
begrenzt jetzt nur, wie oft und wie teuer sie wird. Richtig waere ein
Hintergrund-Isolate.

## M67 — Feature-Cache + paralleles Vernetzen (Shim v10)

**(1) Feature-Cache — der groesste Posten, endlich weg.**
`recomputeAllFeatures` fuehrte jedes Feature bedingungslos neu aus. Beleg
(build 9ef0425): Extrusion1 fiel von 50 548 auf 4 304 Dreiecke und verfeinerte
sich viermal neu, nur weil eine ZWEITE Extrusion begann — bei 0.4-2.6 s pro
Vernetzung waren das Sekunden voellig unnoetiger Kernel-Arbeit.

Neu: `featureInputSig` erfasst alles, was das Ergebnis bestimmt — eigene
Parameter, gewaehlte Profile, und den vollen Zustand der Quellskizze
(Geometrie, Layer, EOS-Marker, Ebene). Der Schluessel ist eine LAUFENDE
KETTENSIGNATUR: der Schluessel jedes Features enthaelt den des vorherigen
Features desselben Bodies. Damit invalidiert eine Aenderung stromaufwaerts
automatisch alles stromabwaerts, und eine veraltete Faltung kann nie
wiederverwendet werden. `disposeSolid()` loescht `builtSig` mit.
`force: true` fuer Laden/Undo, wo die Kernel-Handles neu sind.

Wichtig fuer die Wirkung: das wiederverwendete Feature behaelt SEIN SOLID,
also auch dessen bereits verfeinertes Mesh — genau das, was vorher verloren
ging.

**(2) Shim v10 — `BRepMesh_IncrementalMesh(..., isInParallel = true)`.**
Stand auf `Standard_False`. Ein Zahnrad-Prisma hat 442-827 Flaechen, die
unabhaengig voneinander tesselliert werden; das ist perfekt parallelisierbar
und war ein einziges Boolean. Auf einem Mehrkern-iPad sollte das die 397-2580
ms deutlich druecken — wieviel genau, sagt erst das Geraet.

**Tests.** `m67_feature_cache_test.dart` (5): unveraendertes Feature wird nicht
neu ausgefuehrt UND behaelt dasselbe Solid-Objekt; Parameteraenderung baut neu;
Skizzenaenderung baut das darauf gebaute Feature neu; `force` baut alles neu;
Signatur ist deterministisch, reversibel und deckt die relevanten Eingaben ab.
analyze 0 errors, **449 Tests gruen**.

**Bewusst NICHT zusammen gemacht:** Float32-Buffer und das
Hintergrund-Isolate. Isolate und `isInParallel` beruehren beide
OCCT-Threading; zusammen eingebaut waere bei einem CI- oder Geraetefehler
nicht zu unterscheiden, welches der beiden schuld ist. Erst v10 auf dem
Geraet bestaetigen, dann das Isolate.

## M68 — Outlines entkoppelt (Shim v11), kein Remesh beim Zeichnen

Geraete-Log nach M67: die Neuvernetzung ist durch v10 von 700-2580 ms auf
**389-586 ms** gefallen, Zoomen ist sauber, 3D allgemein ruhig. Zwei Punkte
blieben, beide mit derselben Wurzel wie zuvor: das Budget spart an der
falschen Stelle.

**(1) Outlines waren an die Flaechen-Deflection gekoppelt.**
`GCPnts_TangentialDeflection(curve, ang_deflection, lin_deflection, 2)` nutzte
exakt die Zahlen der FLAECHEN. Eine Kante ist aber 1D und damit fast gratis,
die Flaechentessellierung ist 2D und bestimmt die Kosten. Sobald das
Dreiecksbudget die Flaechen groeber machte, wurden die schwarzen Umrisse
sichtbar eckig mit — der billigste Teil des Bildes verschlechterte sich, um
den teuersten zu bezahlen. Kanten bekommen jetzt eine eigene feste feine
Deflection (5e-3 mm / 0.05 rad), unabhaengig vom Budget. Shim **v11**.

**(2) Waehrend des Zeichnens wurde neu vernetzt.** Das Log zeigt ~500-ms-
Remeshes genau dann, wenn auf einer Solid-Flaeche skizziert wird — das ist
das Stocken. `_armRefine` bricht jetzt ab, solange `activeChild != null`. Im
Skizzenmodus bewegt sich die 3D-Kamera nicht und niemand schaut hin, es ist
also nichts zu gewinnen; Verfeinerung laeuft nach dem Beenden weiter.

**Tests.** `m68_outline_quality_test.dart`; analyze 0 errors, **452 gruen**.

**Weiterhin offen.** Die Outline-DICKE schwankt noch. Ursache ist strukturell:
Umrisse werden als 3D-Roehren (`TubeBuilder.polyline`) mit weltbezogenem
Radius gezeichnet, und eine Roehre wirkt je nach Blickwinkel unterschiedlich
breit, an Silhouetten duenner. Wirklich konstante Strichstaerke gibt es nur
mit bildschirmbezogenem Linienrendering (Metal-Shader oder Screen-Space-
Quads) — das ist ein Swift/Metal-Umbau und gehoert in einen eigenen Schritt,
nicht neben eine Shim-Aenderung. Ebenfalls offen: Float32-Buffer,
Hintergrund-Isolate, Kontextmenue.

## M70 — Outline-Baender (RibbonBuilder), Stand und naechste Schritte

### Was drin ist

**`RibbonBuilder` in PartScene.swift.** Ein flaches, kamerazugewandtes Band
statt eines gefegten k-Ecks:

| | Dreiecke je Segment | Breitenschwankung |
|---|---|---|
| Sechskant-Prisma (bis M68) | 12 | 15 % |
| 16-Eck-Prisma (M69, `17884ea`) | 32 | < 2 % |
| **Band (M70)** | **2** | **0 %** |

Die Null ist exakt, nicht gerundet: die Kamera ist ORTHOGRAFISCH, also gilt
Weltbreite = Pixel x worldPerPixel ohne Perspektivterm. Das Band wird
senkrecht zur Blickrichtung aufgespannt (`cross(segmentDir, viewDir)`), mit
Sonderfall fuer Segmente, die auf die Kamera zeigen (projizieren zu einem
Punkt, jede Senkrechte taugt).

**Antialiasing.** Das Band ist DREI Quads breit — opaker Kern plus Feder
beidseits — und traegt eine U-Koordinate 0..1 QUER zur Breite. Ueber eine
Alpha-Rampen-Textur auf einem normalen `UnlitMaterial` ergibt das eine weiche
Kante ohne eigenes Metal. Vertex-Farben waeren der naheliegende Weg gewesen,
aber **RealityKits Standardmaterialien lesen keine Vertex-Farben** — deshalb
UV. Das ist der Fallstrick, ueber den man hier stolpert.

### Verdrahtet (M71)

Alle drei Schritte sind eingebaut — aber NUR von CI kompiliert, nie
ausgefuehrt. Was zu pruefen ist, steht unter "Geraete-Test" weiter unten.

1. **Polylinien** mussten gar nicht neu vorgehalten werden: `solidCache` haelt
   die `SolidGeom` bereits, `edgePolylines()` schneidet sie ueber
   `edgeStarts`/`edgePts` auf. Und mit `rebuildEdgesForZoom()` existierte der
   Neuaufbaupfad schon fuer den Zoom.
2. **Neuaufbau bei Kameradrehung**: `rebuildEdgesIfTurned(dir)` haengt in der
   bestehenden Kameraschleife und feuert erst ab cos(3 Grad) = 0.99863.
   Darunter liegt der Breitenfehler unter 0.2 %, ist also unsichtbar, und ein
   Neuaufbau je Frame haette mehr gekostet als die Roehre je gekostet hat.
3. **Alpha-Rampe**: `RampTexture` baut einmalig eine 32x1-Textur (opak
   zwischen u=0.25..0.75, weicher Abfall nach aussen), `Materials.unlitSoft`
   haengt sie als Opacity-Textur an ein normales `UnlitMaterial`. Faellt die
   Textur aus, gibt es eine harte statt einer weichen Kante — nie gar keine
   Linie.

`edgeEntity(viewDir:)` waehlt: mit Blickrichtung das Band, ohne die Roehre.
`TubeBuilder` bleibt damit als Rueckfall erhalten, indem man schlicht
`viewDir: nil` uebergibt.

### Geraete-Test fuer die Baender

- Umrisse beim Orbiten: duerfen weder flackern noch bei der 3-Grad-Schwelle
  sichtbar springen. Springt es, ist die Schwelle zu grob.
- Ruckelt das Orbiten jetzt? Dann ist der Neuaufbau zu teuer und die Schwelle
  muss hoch, oder zurueck auf `viewDir: nil`.
- Sehen die Kanten weich aus? Wenn hart, hat `RampTexture.make()` nil
  geliefert (Fallback greift lautlos).
- Segmente, die genau auf die Kamera zeigen: duerfen nicht aufblitzen.

### Falls es NICHT reicht — urspruengliche Notizen

1. **Polylinien vorhalten.** `edgeEntities` und `sketchEntities` speichern
   heute nur die Entity. Fuer den Neuaufbau braucht es die Quellpunkte, also
   z. B. `[(Entity, [[SIMD3<Float>]], SIMD3<Float>)]` (Entity, Polylinien,
   Ebenennormale bei Skizzen).
2. **Bei Kameradrehung neu aufbauen.** Hook existiert bereits: die Schleife um
   Zeile 266, die `e.position = dir * bias` setzt, laeuft bei jeder
   Kameraaenderung. Dort `RibbonBuilder.mesh(...)` neu erzeugen und per
   `MeshResource.replace` zuweisen — Apple weist ausdruecklich darauf hin,
   dass man NICHT jedes Frame ein neues MeshResource bauen soll.
   **Wichtig: mit Schwelle.** Nur neu aufbauen, wenn sich die Blickrichtung um
   mehr als ca. 3 Grad geaendert hat, sonst kostet das Orbiten mehr als das
   Prisma je gekostet hat. Beim Zoomen genuegt die Breite anzupassen, die
   Ausrichtung bleibt.
3. **Alpha-Rampen-Textur.** 1x16 Pixel, opak in der Mitte, transparent am
   Rand, per `TextureResource.generate` aus einem `CGImage`, Material mit
   `.blending = .transparent`. Ohne sie zeichnet das Band hart und die
   Feder-Quads sind wirkungslos (aber es sieht nicht falsch aus, nur nicht
   weich) — man kann also in dieser Reihenfolge vorgehen und zwischendurch
   testen.

`TubeBuilder` bleibt vorerst stehen: er ist der Rueckfall, falls sich der
Neuaufbau beim Orbiten auf dem Geraet als zu teuer erweist.

### Danach: Float32

Heute reisen Positionen und Normalen als `Float64` von Dart nach Swift. Bei
53 904 Vertices sind das rund 3,4 MB pro Push, und die GPU rechnet ohnehin nur
in `Float32` — es wird also irgendwo konvertiert. Umstellen halbiert den
Upload UND spart die Konvertierung. Betroffen: die Buffer in
`ffi/occt_engine.dart` (`OcctMeshData`), der Payload-Bau in
`reality_scene.dart`, und die Dekodierung in `Payload`/`SolidGeom` auf der
Swift-Seite. Als EIGENER Commit, weil es die ganze Kette beruehrt.

### Danach: Hintergrund-Isolate

Zuletzt und allein. `occt_mesh_create` blockiert trotz M67 (paralleles
Vernetzen, v10) noch 389-586 ms auf dem UI-Thread. Ein Isolate loest das,
fasst aber OCCT-Threading an — genau wie `isInParallel`, das seit v10 aktiv
ist. Deshalb NICHT mit etwas anderem zusammen ausliefern: bei einem CI- oder
Geraetefehler waere sonst nicht zu trennen, welche der beiden Aenderungen
schuld ist. Genau dieser Fall ist bei M67 eingetreten (roter M3-Job, der sich
als Flake herausstellte) und die Trennung war der Grund, warum es in Minuten
geklaert war.

Zu pruefen ist dabei, ob OCCT-Shape-Pointer ueber Isolate-Grenzen hinweg
benutzbar sind — sie gehoeren heute dem Haupt-Isolate. Wahrscheinlich braucht
es `Isolate.run` mit reinen Daten hin und zurueck statt geteilter Handles.

### Ebenfalls weiter offen

- **Kontextmenue** auf Extrusion/Solid (loeschen, umbenennen, sichtbar),
  analog zu den nativen 2D-Menues aus M47. Dreimal angefragt, dreimal nicht
  geliefert.
- **M3-CI-Flake**: der Simulator-Smoke greift die Ausgabe ab, bevor die App
  fertig geschrieben hat — einmal falsches Gruen (Run 29043802347), einmal
  falsches Rot (Run 30270619849). Fix waere, auf den Prozess zu warten bzw.
  mit Timeout auf den Marker zu pollen.
- **200-ms-Drag** aus dem 39555ac-Log: Solver braucht davon 0,4 ms, der Rest
  ist unbekannt. Es fehlt Instrumentierung im Drag-Handler; bis dahin ist
  jede Aussage dazu geraten.

## M72 — Baender abgeschaltet (Rueckfall auf Roehre), Verdachtsliste

Auf dem Geraet (build 8fb292f) zeichneten die Baender **gar keine Umrisse**.
Das ist schlechter als der Zustand davor, deshalb steht
`RealityPartView.useRibbons` jetzt auf `false` und es wird wieder die
16-seitige Roehre aus M69 verwendet (Breitenschwankung unter 2 %, sah auf dem
Geraet gut aus). `RibbonBuilder`, `RampTexture` und der komplette
Neuaufbaupfad bleiben erhalten — das Flag auf `true` reaktiviert alles.

### Verdachtsliste, nach Wahrscheinlichkeit

1. **Backface-Culling.** Das Band ist eine flache Flaeche ohne Dicke. Wenn die
   Dreieckswindung von der Kamera wegzeigt, wird ALLES weggeschnitten — was
   exakt zum Symptom passt (nicht "duenn" oder "fleckig", sondern nichts).
   `side = cross(dir, v)` kehrt sich je nach Segmentrichtung um, die Windung
   ist also nicht konsistent. Fix: `faceCulling = .none` am Material (iOS 15+),
   oder jedes Quad zusaetzlich mit umgekehrter Windung ausgeben.
2. **`opacityThreshold = 0`.** In `Materials.unlitSoft` gesetzt. Alpha-Testing
   mit Schwelle 0 kann je nach Auslegung ALLES verwerfen. Zuerst diese Zeile
   entfernen und ohne sie testen.
3. **Opacity-Textur falsch angebunden.** `.transparent(opacity: .init(scale:
   1, texture: .init(tex)))` — falls RealityKit daraus Alpha 0 liest (z. B.
   weil die Rampe im falschen Kanal landet), ist alles unsichtbar. Gegenprobe:
   `unlitSoft` voruebergehend `unlit(color)` zurueckgeben lassen; kommen die
   Baender dann, liegt es an der Textur, nicht an der Geometrie.
4. **Fehlende Normalen** im MeshDescriptor. Fuer ein Unlit-Material sollte das
   egal sein, ist aber nicht ausgeschlossen.

### Vorgehen beim naechsten Mal

Nicht alles auf einmal. Reihenfolge: erst 2 (eine Zeile), dann 1
(`faceCulling`), dann 3 (Material-Gegenprobe). Nach jedem Schritt aufs Geraet.
Das Flag macht das billig — eine Zeile hin, eine Zeile zurueck.

**Lehre:** Ich haette das Band hinter dem Flag ausliefern sollen, nicht
stattdessen. Eine nie ausgefuehrte Renderaenderung gehoert abschaltbar
eingebaut, sonst kostet ein Fehlschlag einen ganzen Geraetezyklus.

## Float32 — Vorbereitung fuer die naechste Session

Noch NICHT gemacht. Betroffene Kette:

- `frontend/lib/ffi/occt_engine.dart`: `OcctMeshData.positions/normals` sind
  `Float64List`. Die Werte kommen per FFI aus dem Shim, der `double`
  schreibt — entweder dort auf `float` umstellen (ABI-Aenderung, neue
  Shim-Version) ODER in Dart beim Auslesen nach `Float32List` konvertieren
  (kein ABI-Bruch, spart aber nur den Upload, nicht die Konvertierung).
  Empfehlung: erst die Dart-Seite, weil ohne Shim-Aenderung testbar.
- `frontend/lib/reality_scene.dart`: `buildScenePayload` packt die Buffer.
- Swift `Payload`/`SolidGeom`: dekodiert heute `Float64`.

Groessenordnung: bei 53 904 Vertices sind Positionen + Normalen rund 3,4 MB
je Push. Halbiert sich, und die GPU rechnet ohnehin in Float32 — die
Konvertierung passiert also heute schon irgendwo.

## M72 — Baender waren unsichtbar: Winding

**Symptom.** Auf build 8fb292f gar keine Outlines mehr — schlechter als die
Roehre davor.

**Ursache, nachgerechnet statt geraten.** Die Dreiecke waren als
`(a_r, b_r, b_{r+1})` gewickelt. Deren Normale ist `cross(dir, side)`, und mit
`side = cross(dir, v)` ergibt das

    cross(dir, cross(dir, v)) = dir*(dir·v) - v*(dir·dir) = -v

fuer `dir ⊥ v`. Und `v` ist genau die Richtung ZUR Kamera — dieselbe `dir`,
mit der die Kanten per Bias zur Kamera geschoben werden. Jedes Band-Dreieck
zeigte also von der Kamera WEG und wurde vollstaendig rueckseitig gecullt.

**Fix, zweifach abgesichert.**
1. Winding umgedreht: `[i0, j1, i1, i0, j0, j1]`.
2. `m.faceCulling = .none` in `Materials.unlitSoft`. Ein Band hat keine Dicke,
   ist also echt zweiseitig und darf gar nicht davon abhaengen, in welcher
   Reihenfolge es erzeugt wurde. Punkt 1 allein haette gereicht, aber die
   Klasse von Fehler soll nicht wiederkommen.

Ausserdem entfernt: `opacityThreshold = 0`. Das schaltet Alpha-MASKING ein und
arbeitet gegen die weiche Rampe, mit der wir blenden wollen.

**Notausschalter.** `RealityPartView.useRibbons` (jetzt `true`). Auf `false`
faellt alles auf die 16-Eck-Roehre aus M69 zurueck — orientierungsunabhaengig,
unter 2 % Breitenschwankung. Eine Zeile, falls auf dem Geraet noch etwas
klemmt.

**Falls die Outlines immer noch fehlen**, in dieser Reihenfolge pruefen:
1. `useRibbons = false` — kommen die Roehren zurueck? Dann liegt es sicher am
   Band und nicht an der Kanten-Pipeline darueber.
2. Rampe verdaechtigen: in `unlitSoft` den `blending`-Block auskommentieren.
   Erscheint dann eine harte Linie, ist die Opacity-Textur schuld
   (`.init(scale:texture:)`-Signatur oder das Alpha-Format der 32x1-Textur).
3. `halfWidth`: `edgeRadius` war als ROEHRENRADIUS gedacht. Beim Band ist es
   die halbe Breite — optisch also dieselbe Groessenordnung, aber falls die
   Linien extrem duenn wirken, ist hier der Hebel.

### Naechster Schritt: Float32

Positionen und Normalen reisen heute als `Float64` von Dart nach Swift: bei
53 904 Vertices rund 3,4 MB je Push, obwohl die GPU ohnehin nur `Float32`
rechnet, es also irgendwo konvertiert wird. Umstellen halbiert den Upload UND
spart die Konvertierung. Betroffen: `OcctMeshData` in `ffi/occt_engine.dart`,
der Payload-Bau in `reality_scene.dart`, die Dekodierung in `Payload`/
`SolidGeom` auf der Swift-Seite. Als EIGENER Commit — es beruehrt die ganze
Kette, und wenn etwas bricht, soll es eindeutig zuordenbar sein.

## M73 — Skizzenlinien in 3D ebenfalls als Baender

Nachdem die Outlines auf dem Geraet bestaetigt sind, laufen die Skizzenkurven
jetzt durch dieselbe Maschinerie: `RibbonBuilder` statt `TubeBuilder`, also
2 statt 12 Dreiecke je Segment und exakt konstante Bildschirmbreite.

Drei Dinge waren dafuer noetig:
1. **`sketchCache`** haelt das letzte Sketch-Payload. Anders als bei den
   Solids (`solidCache`) gab es das noch nicht, es wird aber gebraucht, weil
   ein Band nur solange stimmt, wie es zur Kamera zeigt.
2. **Neuausrichtung** in `rebuildEdgesIfTurned` auf derselben 3-Grad-Schwelle
   wie die Kanten. Ohne das behielten die Skizzenlinien die Ausrichtung ihrer
   Entstehung und wuerden beim Drehen duenner.
3. **Akzente ueberleben** die Neuausrichtung: `rebuildSketches` loescht
   `sketchAccent`, deshalb merken sich `accentHover`/`accentSelected` die
   letzten Eingaben und `applySketchAccents` wird danach erneut aufgerufen.
   `applySketchAccents` malt ausserdem mit `unlitSoft`, wenn Baender aktiv
   sind — sonst haette eine hervorgehobene Kurve ihre weiche Kante verloren.

Rueckfall unveraendert: `useRibbons = false` schaltet Kanten UND Skizzen
zurueck auf Roehren, weil beide durch `outlineDir` gehen.

**Fehlerklasse, die zweimal zuschlug:** iOS-Verfuegbarkeit. Erst
`TextureResource.generate` (iOS 15+), dann `faceCulling` (**iOS 18+**, nicht
15). Beides nur von CI gefangen. Bei jeder neuen RealityKit-API vorher die
Mindestversion pruefen — lokal ist das hier nicht feststellbar.

## M74 — Float32 ueber den Platform-Channel

Positionen, Normalen, Kantenpunkte und Skizzen-Polylinien reisen jetzt als
`Float32` statt `Float64`. Der Kernel liefert Float64, die GPU nimmt aber nur
Float32 — die Umwandlung passierte also ohnehin, nur an der teuersten Stelle:
Vertex fuer Vertex in `Payload.floats`, bei JEDEM Push. Jetzt einmal pro Mesh
in Dart, und Swift interpretiert die Bytes direkt.

- ~3,4 MB -> ~1,7 MB je Push bei einem Zahnrad mit 54k Vertices
- die Konvertierungsschleife in Swift entfaellt ersatzlos
- `OcctMeshData.positions32/normals32/edgePoints32` sind lazy und gecacht, es
  wird also NICHT pro Push kopiert (per Test festgehalten)

**Die Falle dabei, festgenagelt in `m74_float32_test.dart`:** Swift dekodiert
Solid-Buffer UND Skizzen-Polylinien durch dasselbe `Payload.floats`. Die
Skizzen-Polylinien wurden in `reality_scene.dart` separat als `Float64List`
gebaut — waeren sie so geblieben, haette Swift deren Bytes als Float32 gelesen
und Muell gezeichnet. Wer hier je einen weiteren Float-Buffer ergaenzt: er
MUSS Float32 sein, sonst bricht es still.

Nicht umgestellt: `frame` (9 Doubles je Ebene) und `vec3`-Listen. Die sind
winzig und gehen ueber den normalen Codec, nicht ueber `Payload.floats`.

### Was noch offen ist

1. **Hintergrund-Isolate.** `occt_mesh_create` blockiert trotz v10 noch
   389-586 ms auf dem UI-Thread. Einzeln ausliefern — es fasst wie
   `isInParallel` OCCT-Threading an. Zu klaeren: ob OCCT-Shape-Pointer ueber
   Isolate-Grenzen benutzbar sind; wahrscheinlich `Isolate.run` mit reinen
   Daten hin und zurueck statt geteilter Handles.
2. **Kontextmenue** auf Extrusion/Solid (loeschen, umbenennen, sichtbar),
   analog M47. Fuenfmal angefragt, fuenfmal nicht geliefert — das gehoert als
   Naechstes drangenommen.
3. **M3-CI-Flake**: Ausgabe wird abgegriffen, bevor die App fertig schreibt.
   Einmal falsches Gruen (29043802347), einmal falsches Rot (30270619849).
4. **200-ms-Drag**: unerklaert, Solver braucht davon 0,4 ms. Es fehlt
   Instrumentierung im Drag-Handler.

### Wiederkehrende Fehlerklasse

Dreimal in dieser Session von CI gefangen, nie lokal feststellbar:
iOS-Verfuegbarkeit neuer RealityKit-APIs. `TextureResource.generate` (15+),
`faceCulling` (**18+**, nicht 15). Bei jeder neuen RealityKit-API zuerst die
Mindestversion nachschlagen.

## M75 — Das Stocken im Skizzenmodus war NIE der Kernel

Drei Runden lang (M64/M66/M68) habe ich die 3D-Vernetzung optimiert. Das war
alles fuer sich richtig, aber es hat das gemeldete Problem nicht beruehrt.
Der Beweis steht im Log von build 9852b09: zwischen 20:25:31 (Skizze
angelegt) und 20:25:37 (Kreis fertig) gibt es **keine einzige** `perf:
remesh`-Zeile. Der M68-Guard wirkt, waehrend des Zeichnens vernetzt nichts.

**Die echte Ursache.** M59 zeichnet waehrend des Skizzierens das Modell als
Unterlage in den 2D-Painter (`paintPartUnderlay`). Darunter laeuft
`buildSceneSolid`, und das

- allokiert **ein `SceneTri` pro Dreieck** — 34 236 bei einem Zahnrad
- scannt zusaetzlich alle ~105 000 Positionswerte fuer `maxAbs`

und zwar bei **jedem `paint()`**, also jedem Frame, solange die Skizze offen
ist. Das ist das Stocken. Es waechst linear mit dem Modell — deshalb war
"hunderte Zahnraeder" mit dieser Architektur ausgeschlossen.

**Fix.** Die Unterlage haengt nur von den Solids und der Ansichtstransformation
ab, und beim Zeichnen bewegt sich keins von beidem. `_UnderlayCache`
rasterisiert sie einmal in eine `ui.Picture` und blittet danach nur noch.
Schluessel: Groesse, Pan, Zoom, Skizzenebene und die Mesh-Identitaeten.

**Lehre fuers naechste Mal.** Ich habe dreimal die Ebene optimiert, die ich
schon vermessen hatte, statt die zu messen, ueber die berichtet wurde. Der
`perf`-Kanal deckt bis heute nur den Remesh ab. **Vor der naechsten
Performance-Aenderung: `paint()` und den Drag-Handler instrumentieren**, sonst
wiederholt sich das. Der unerklaerte 200-ms-Drag aus dem 39555ac-Log ist
sehr wahrscheinlich dieselbe Ursache.

**Noch nicht geprueft, aber verdaechtig:** ob `paintPartUnderlay` auch
ausserhalb des Skizzenmodus pro Frame laeuft, und ob der 2D-Painter weitere
O(Geometrie)-Arbeit pro Frame macht (Snap-Suche, Hit-Test-Aufbau). Der
Cache behebt den groessten Posten, nicht zwangslaeufig alle.

## M76 — Project Geometry aus 3D (IMPLEMENTIERT)

Recherche steht, Implementierung NICHT begonnen. Diese Notiz existiert, damit
die naechste Session nicht nochmal recherchieren muss und nicht das Falsche
baut.

### Was Inventor tatsaechlich macht (Autodesk-Doku)

1. **Referenz, kein Abzug.** Projizierte Geometrie bleibt mit der Quelle
   VERKNUEPFT und aktualisiert sich, wenn die Quelle sich aendert. Deshalb
   heisst sie "reference geometry". Ein einmaliger Snapshot waere falsch.
2. **Waehlbar, nicht editierbar.** Sie kann bemasst und als Constraint-Ziel
   benutzt werden, aber nicht gezogen werden. Fuer den Solver also FIX.
3. **Auto-Projektion.** Beim Anlegen einer Skizze auf einer Modellflaeche
   werden ALLE Kanten dieser Flaeche automatisch Referenzgeometrie. Diese
   automatischen sind NICHT loeschbar, manuell projizierte schon. Das ist ein
   echter Unterschied im Datenmodell, kein UI-Detail.
4. **Quellen:** Kanten, Vertices, Loops, Work Features, und Kurven aus
   anderen sichtbaren Skizzen.
5. **Verwaiste Referenz.** Faellt das Quell-Feature weg, verliert die Referenz
   ihre Verknuepfung und wird zu FESTEN Skizzenkurven — Constraints und
   Bemassungen bleiben erhalten. Nicht einfach mitloeschen.
6. **Ausnahme:** projizierte Schnittkanten (cut edges) sind NICHT assoziativ.
7. Optional in Inventor: "Autoproject Edges During Curve Creation".

### Vorgeschlagenes Datenmodell hier

- Neues `Geo`-Flag `reference` (analog zu `construction`), plus eine
  Quellreferenz: `(featureName, edgeIndex)` — die Extrusion und der Index in
  `edgePolylines()`.
- **Solver:** Referenzgeometrie geht als FIXE Punkte in slvs, nie als DOF.
  Sonst zieht der Solver am Modell.
- **Rebuild:** in `recomputeAllFeatures` nach dem Feature-Cache die Referenzen
  neu projizieren, wenn sich die Signatur ihres Quell-Features geaendert hat.
  Der Cache-Schluessel aus M67 liefert das bereits.
- **Verwaist:** Quelle weg -> `reference` bleibt, Quellreferenz auf null,
  Geometrie bleibt stehen. NICHT loeschen.
- **Nicht loeschbar:** bei Auto-Projektion ein zweites Flag `autoRef`.

### Projektion selbst

Kanten kommen als Weltraum-Polylinien aus `SolidGeom.edgePolylines()`
(v9 filtert dort bereits tangentenstetige Kanten heraus — fuer die Projektion
will man aber MEHR als die Silhouette, also ggf. den ungefilterten Satz).
`sketchFrameOf(cs)` liefert die Ebene; `frame.toLocal(worldPt)` projiziert.
Verdeckte Kanten sind dabei kein Sonderfall: es wird orthogonal auf die Ebene
projiziert, Sichtbarkeit spielt geometrisch keine Rolle. Sie sollen nur
ANDERS dargestellt werden (gestrichelt), wie in Inventor.

### UI

- Werkzeug "Project" in der Skizzen-Ribbon, Mehrfachauswahl bis Escape.
- Hover-Highlight beim Ueberfahren einer projizierbaren Kante: es gibt bereits
  `applySketchAccents(hover:selected:)` und `_hoverFace` in viewport3d — den
  gleichen Mechanismus fuer Kanten erweitern statt neu bauen.
- Darstellung: Referenzgeometrie in eigener Farbe (Inventor nimmt eine
  andere als normale Skizzenkurven), verdeckte gestrichelt.

### Reihenfolge

Erst Datenmodell + Solver-Fixierung + Rebuild, dann Rendering, zuletzt
Auto-Projektion der Flaechenkanten. Auto-Projektion zuletzt, weil sie sonst
bei jedem Sketch-auf-Flaeche sofort viele Referenzen erzeugt und Fehler im
Fundament verstaerkt.

**ACHTUNG Performance:** eine Zahnradflaeche hat ~440 Kanten. Auto-Projektion
erzeugt dort also 440 Referenzkurven in der Skizze. Vor diesem Schritt MUSS
die Painter-Instrumentierung aus M75 stehen, sonst ist der naechste
Stotter-Bericht wieder nicht zuzuordnen.


## M76 — Umsetzung: 3D-Kanten in die Skizze projizieren

Gebaut auf dem vorhandenen Projektionsmodell (M32-M34, Layer zu Layer), nicht
daneben. Es gab bereits `Geo.proj` / `projSeg`, `syncProjections()` und
`_withProjectionPins()` — letzteres fixiert JEDE Projektion fuer den Solver
und gilt damit automatisch auch fuer die neuen.

**KEINE Auto-Projektion.** Bewusst gegen Inventors Vorgabe entschieden: nur
der Center Point wird weiter automatisch projiziert, alles andere manuell.
Der Nutzer will kontrollieren, was projiziert wird — und eine Zahnradflaeche
haette sonst ~440 Referenzkurven auf einmal erzeugt.

**Neu:** `Geo.projSolid` (-5). `projSeg` traegt den Index in
`partEdges(part, frame)` — Features in Baumreihenfolge, darin Kantenindex.
Diese Reihenfolge IST die Identitaet, deshalb ist sie deterministisch
definiert und wird nie stillschweigend umgehaengt.

**Warum die Nachfuehrung nicht im Solver liegt:** `syncProjections()` sieht
nur `List<Geo>`, die Quelle einer 3D-Projektion braucht aber PartModel und
Ebene. `syncSolidProjections()` sitzt darum in part_model.dart und wird nach
jedem `recomputeAllFeatures()` aufgerufen; der Solver ueberspringt
`projSolid` explizit.

**Waise:** Quellkante weg -> `projBroken`, Kurve friert an Ort und Stelle ein,
statt zu verschwinden. Genau Inventors Verhalten (Referenz ohne Parent wird zu
festen Kurven, Constraints bleiben). Per Test festgehalten.

**Verdeckte Kanten** sind kein Sonderfall: orthogonal projiziert zaehlt
Sichtbarkeit geometrisch nicht. Sie sind projizierbar wie sichtbare.

**UI:** Bei aktivem Project-Werkzeug werden alle projizierbaren Modellkanten
schwach gezeichnet, die unter dem Cursor hervorgehoben (`hoverSolidEdge`).
Reihenfolge beim Tippen: Skizzengeometrie zuerst, Modellkante nur wenn nichts
in der Skizze naeher liegt — so bleibt Layer-zu-Layer unveraendert. Die
Kantenliste ist ueber Ebene + Feature-Mesh-Identitaeten gecacht, damit die
Hover-Abfrage nicht pro Frame ~440 Kanten neu flacht (die Lektion aus M75).

**Tests** `m76_project_3d_test.dart` (9): Aufzaehlung inkl. unsichtbarer/
konsumierter Features, Line vs. offene Polyline, bewegte Quelle zieht die
Projektion mit, unveraendertes Modell meldet keine Aenderung, Waise friert
ein statt zu verschwinden, normale Geometrie bleibt unangetastet, Picking mit
Toleranz. analyze 0 errors, **465 Tests gruen**.

**Ehrliche Grenzen.**
- Kanten werden als Linie/Polylinie projiziert, nicht als Bogen oder Spline.
  Fuer Referenzgeometrie ist das korrekt genug (sie wird nie editiert), aber
  ein projizierter Kreis ist damit ein feines Polygon statt eines echten
  Kreises — Bemassung darauf misst Sehnen, nicht den Radius. Wer das braucht:
  `edgeCurves` (16 Doubles je Kante, Shim v4) traegt bereits Typ und
  Parameter, damit liesse sich ein echter Bogen rekonstruieren.
- `syncSolidProjections` mutiert die Geometrieliste direkt, wie
  `syncProjections` es tut; die Engine sieht es beim naechsten Solve dieser
  Skizze. Auf dem Geraet pruefen, ob eine geoeffnete Skizze sofort nachzieht,
  wenn man das Elternfeature aendert.
- Nur auf Host-Ebene getestet, **Geraete-Test offen**.

## M77 — Projektionen behalten ihren TYP + Performance-Overlay

**(1) Exakte projizierte Geometrie.** M76 hat jede Kante als Linie/Polylinie
projiziert; ein projizierter Kreis war damit ein feines Polygon und eine
Bemassung darauf mass Sehnen. Jetzt wird der analytische Datensatz des Kernels
benutzt (`edgeCurves`, 16 Doubles je Kante, Shim v4 — war laengst da, nur
ungenutzt).

Die Mathematik, die man hier NICHT ueberspringen darf: orthografische
Projektion erhaelt Linien und Kegelschnitte, aber **nicht den Typ**. Ein Kreis
bleibt nur dann ein Kreis, wenn seine Ebene parallel zur Skizzenebene liegt;
gekippt ist er eine echte Ellipse, hochkant eine Strecke. `analyticProjectedEdge`
unterscheidet alle drei.

Und der Teil, den man leicht falsch macht: projiziert man Mittelpunkt und die
beiden Halbachsenvektoren einzeln, erhaelt man **konjugierte** Halbmesser, NICHT
die Hauptachsen — die Ellipsen-Grips waeren schief. Rytz' Konstruktion dreht
sie auf die Hauptachsen: `tan(2t) = 2(X·Y) / (|X|² − |Y|²)`.

Faelle: Linie -> Linie, paralleler Kreis -> Kreis, Teilkreis in Ebene -> Bogen,
gekippter Kreis -> Ellipse (3 Grips), hochkant -> Strecke, Typ 0 -> Polylinie.
Eine TEIL-Ellipse hat in diesem Skizzenmodell keine Grip-Form und bleibt
bewusst Polylinie, statt stillschweigend zur vollen Ellipse geschlossen zu
werden.

`PartEdge.displayPts` erzeugt Punkte nur fuers Zeichnen und Picken — niemals
fuer die Entity, die baut `geoForPartEdge` exakt.

**(2) Performance-Overlay** (`widgets/perf_overlay.dart`), unten rechts, grau,
50 % Deckkraft, `IgnorePointer`. Zeigt fps, **Durchschnitt/SCHLECHTESTE**
Framezeit im 60-Frame-Fenster, Features/Solids/Dreiecke der Szene sowie
Entities und Projektionen der Skizze. Faerbt sich nur bei Problemen (gelb ab
20 ms, rot ab 33 ms).

Bewusst die SCHLECHTESTE Framezeit, nicht nur der Schnitt: ein Mittel von
16 ms mit einem 200-ms-Aussetzer stottert trotzdem, und genau solche
Aussetzer suchen wir. Das Overlay zeichnet sich selbst nur mit ~5 Hz neu —
ein Messinstrument, das pro Frame rebuildet, misst sich selbst mit.

Es existiert wegen M75: drei Runden Performance-Arbeit gingen in die falsche
Schicht, weil der `perf:`-Logkanal nur den Remesh abdeckt und ein Log keine
Framezeit waehrend eines Drags zeigen kann.

analyze 0 errors, **472 Tests gruen** (16 in m76_project_3d_test.dart).

## M78 (GEPLANT) — Skizzenmodus muss die LEBENDE 3D-Szene behalten

### Zwei Befunde

**(1) Mein M75-Cache deckt das Pannen NICHT ab.** Der Schluessel enthaelt
`pan` und `zoom`, also invalidiert jede Panbewegung ihn und der volle
34 236-Dreieck-Aufbau in Dart laeuft wieder pro Frame. M75 hat das Stocken
beim ZEICHNEN behoben, nicht beim Navigieren. Das war in der Meldung zu weit
gefasst.

**(2) Inventor rastert das Modell gar nicht.** Belegt durch die
Autodesk-Doku zu Slice Graphics: man soll "das Modell drehen, sodass der
wegzuschneidende Teil zur Kamera zeigt", und Modellgeometrie kann die
Skizzenebene VERDECKEN. Beides ist in einer flachen Unterlage unmoeglich —
Verdeckung ist Tiefe, Drehen ist eine lebende Szene. Slice Graphics ist eine
Near-Plane-Clip im 3D-Renderer.

### Konsequenz: die richtige Architektur

Statt `paintPartUnderlay` (CPU, O(Dreiecke) pro Frame) die RealityKit-Szene
im Skizzenmodus STEHEN LASSEN, die Kamera auf die Skizzennormale ausrichten
und den 2D-Skizzen-Canvas transparent darueberlegen. Das Modell wird dann von
der GPU gezeichnet, wie im 3D-Modus auch — Pan und Zoom kosten nichts, weil
sie nur die Kameramatrix aendern.

Vorteile ueber die Performance hinaus: echte Verdeckung, Drehen waehrend der
Skizze moeglich, und Slice Graphics (F7) waere spaeter eine Near-Plane am
Skizzenursprung statt eines Sonderfalls im Painter.

### Umsetzung, skizziert

1. Im Skizzenmodus die `RealityPartView` sichtbar lassen statt sie gegen den
   2D-Painter zu tauschen; Kamera auf `sketchFrameOf(cs).n` ausrichten,
   orthografisch, Pan/Zoom auf die Kamera abbilden statt auf `map()`.
2. Den 2D-Painter transparent darueber (`ColoredBox` entfaellt), er zeichnet
   nur noch Skizzengeometrie, Grips, Bemassung, Snap.
3. `paintPartUnderlay` und `_UnderlayCache` entfallen danach ersatzlos.
4. Der Veil (`T.viewport.withOpacity(0.55)`) wird eine Eigenschaft des
   3D-Materials, damit die Skizze der klare Vordergrund bleibt.

**Haken, ehrlich:** die 2D-Welt-Transformation (`map()`, Pan/Zoom, Snap,
Hit-Test) muss exakt mit der 3D-Kamera uebereinstimmen, sonst laufen Cursor
und Modell auseinander. Das ist der eigentliche Aufwand, nicht das Rendern.
Eine gemeinsame Quelle fuer beide Transformationen ist Voraussetzung.

### Zwischenschritt, falls das zu gross ist

`_UnderlayCache` pan/zoom-invariant machen: das Bild EINMAL mit
Identitaets-Transformation aufzeichnen und beim Blitten
`canvas.translate/scale` anwenden. Eine `ui.Picture` speichert Vektorbefehle,
kein Bitmap, also bleibt die Qualitaet erhalten. Damit faellt Pan und Zoom aus
dem Cache-Schluessel und beides wird sofort fluessig — ohne die
Architekturaenderung. Voraussetzung: `paintPartUnderlay` mit neutralem
Pan/Zoom aufzeichnen und pruefen, dass `map()` wirklich affin in beiden ist
(es zentriert auf `size/2`, das muss beim Aufzeichnen mitgedacht werden).

## M79 — Performance-Logging vollstaendig + Pan-Fix + Befund zur 3D-Skizze

### (1) `performance_logs.txt` — eigene Datei, eigener Zweck

`lib/perf.dart`, verdrahtet in `main.dart` (`Perf.init()`) und
`app_state.dart` (`Perf.retarget()`, neben `Log.retarget`). Getrennt vom
Ereignislog, weil Performance-Daten periodisch und massenhaft anfallen und die
Ereignisse ertraenken wuerden, die einen Bug reproduzierbar machen.
Rotation bei 4 MB nach `performance_logs_prev.txt`, Snapshot alle 5 s.

Pro Eintrag: `n=Aufrufe  letzte / Schnitt / p95 / schlechteste ms`.

**Frames** getrennt nach `frame.build` (Dart, UI-Thread) und
`frame.raster` (GPU-Thread) — welcher hoch ist, sagt dir, ob du Widgets oder
Zeichnen ansehen musst. Dazu fps und `jank(>33ms)` mit Prozentsatz.

**Benannte Spans** (`Perf.span`): `2d.paint`, `2d.underlay`,
`2d.underlay.rebuild`, `3d.push`, `3d.payload`, `kernel.remesh`,
`kernel.feature`, `sketch.solveRebuild`, `sketch.profileLoops`,
`sketch.syncProjections`, `project.partEdges`, `project.syncSolid`.
Zaehler: `2d.underlay.hit`, `project.edgesQuery`.
Gauges: `sceneTris`, `triangles`, `features`, `solids`, `sketchEntities`,
`sketchProjections`, `remeshCount`.

**Ressourcen — was geht und was nicht, ehrlich:**
- RAM: `ProcessInfo.currentRss`, echt und exakt (`rssMB`, `rssPeakMB`,
  `rssMaxMB`).
- GPU: iOS gibt einer Sandbox-App KEINE GPU-Auslastung. Aber
  `FrameTiming.rasterDuration` IST die Zeit des Raster-Threads pro Frame und
  steigt genau dann, wenn die GPU-Arbeit waechst — das ist die brauchbare
  Groesse.
- CPU: ebenfalls kein Prozentwert verfuegbar. `frame.build` plus die
  benannten Spans schluesseln die UI-Thread-Zeit auf konkrete Arbeit auf, was
  "welcher Teil kostet was" beantwortet, ohne einen Prozentsatz zu erfinden.
Nicht Messbares wird WEGGELASSEN statt geschaetzt.

`Perf.span` ist Stopwatch aus einem Pool plus ein Map-Lookup — keine
Allokation je Aufruf, Formatierung erst beim Flush. Per Test auf < 20 us
gedeckelt: ein Messgeraet, das in den eigenen Zahlen auftaucht, ist wertlos.

### (2) Pannen im Skizzenmodus — der M75-Cache war luecken haft

`_UnderlayCache` hatte `pan` im Schluessel, jede Panbewegung invalidierte ihn
also und der 34 236-Dreieck-Aufbau lief wieder pro Frame. Jetzt ist `pan`
NICHT mehr im Schluessel: bei gleichem Zoom ist eine Panbewegung exakt eine
Translation der aufgezeichneten Vektoren, und eine `ui.Picture` speichert
Vektorbefehle statt Pixel — Qualitaet bleibt erhalten.

**Vorzeichenfalle, die mir dabei passiert ist:** aus `Cam3.project` folgt
`d(screen_x)/d(pan.dx) = -zoom`, aber `d(screen_y)/d(pan.dy) = +zoom` — die
Skizzen-Y-Achse zeigt nach oben, die Bildschirm-Y nach unten. Ich hatte erst
zweimal minus, das haette die Unterlage beim Pannen vertikal wegdriften
lassen. Jetzt per Test gegen `map()` festgenagelt.

`_panMarginFrac` (25 % des Viewports) erzwingt einen Neuaufbau, bevor man aus
dem aufgezeichneten Bereich herauspannt — `paintPartSolids` cullt auf den
sichtbaren Bereich, ausserhalb ist im Bild nichts.

### (3) 3D-Szene im Skizzenmodus — Befund, NICHT umgesetzt

Recherche (M78) steht: Inventor haelt die lebende 3D-Szene. Beim Umsetzen bin
ich auf zwei Dinge gestossen, die die naechste Session direkt verwerten kann.

**Gute Nachricht: die Transformationen stimmen bereits ueberein.** Per Test
bewiesen (`m79_perf_test.dart`, "the 3D camera and the 2D map agree"):
`Cam3` mit `halfH = h/(2*zoom)` und `ox/oy = origin·u + pan` liefert EXAKT
dieselben Bildschirmkoordinaten wie `Viewport2D.map()`. Die gemeinsame Quelle,
vor der ich in M78 als Hauptaufwand gewarnt hatte, existiert also schon.

**Der echte Blocker ist der KAMERA-ROLL.** `Cam3.basis` bekommt in
`paintPartUnderlay` die expliziten `frame.u`/`frame.v`. `PartCamera` dagegen
hat nur `az, pol, halfH, ox, oy` und leitet ihre Basis ueber
`_basisS(d) = fwd × (0,1,0)` her — also **kein Rollwinkel**. Auf einer
beliebigen Flaeche weicht `frame.u` davon um einen Roll ab, und das Modell
erschiene in der Skizzenebene verdreht.

**Zu tun, in dieser Reihenfolge:**
1. `PartCamera` um `roll` erweitern; Basis = um `roll` gedrehte
   `_basisS/_basisU`. Fuer bestehende Kameras `roll = 0`, also verhaltensneutral.
2. `roll` in `cameraPayload` mitschicken und in `RealityPartView` auf die
   RealityKit-Kamera anwenden.
3. Beim Oeffnen einer Kindskizze setzen:
   `pol = acos(n.y)`, `az = atan2(n.x, n.z)`,
   `halfH = size.height/(2*zoom)`, `ox = origin·u + pan.dx`,
   `oy = origin·v + pan.dy`, `roll` = Winkel zwischen `_basisS(n)` und
   `frame.u`.
4. In `main.dart` den Skizzenfall nicht mehr auf `Viewport2D` allein
   schalten, sondern `Viewport3D` darunter und `Viewport2D` transparent
   darueber.
5. `paintPartUnderlay` und `_UnderlayCache` entfallen dann ersatzlos.
6. Der Veil (`T.viewport.withOpacity(0.55)`) wird eine Materialeigenschaft.

**Pruefkriterium auf dem Geraet:** Cursor und Modell duerfen beim Pannen,
Zoomen und auf einer GEKIPPTEN Flaeche nicht auseinanderlaufen. Die gekippte
Flaeche ist der Fall, der den Roll aufdeckt — auf xy/xz/yz faellt ein
fehlender Roll nicht auf.

### Weiterhin offen

- Kontextmenue auf Extrusion/Solid (loeschen, umbenennen, sichtbar). Sechsmal
  angefragt, sechsmal nicht geliefert — das gehoert als Naechstes dran.
- Hintergrund-Isolate fuer `occt_mesh_create` (389-586 ms auf dem UI-Thread).
  Einzeln ausliefern, es fasst wie `isInParallel` OCCT-Threading an.
- M3-CI-Flake: Ausgabe wird abgegriffen, bevor die App fertig schreibt.
- Projizierte TEIL-Ellipse bleibt Polylinie (kein Grip-Modell dafuer).

## M80 — Inventor-Verhalten: die LEBENDE 3D-Szene im Skizzenmodus

Umgesetzt. Der CPU-Underlay ist ersatzlos entfallen.

### Was sich geaendert hat

**`main.dart`:** In einem Part wird IMMER `Viewport3D` gerendert. Eine offene
Kindskizze legt `Viewport2D` transparent darueber. Vorher wurde zwischen
beiden umgeschaltet und das Modell im 2D-Painter nachgezeichnet.

**`Viewport2D._paint`:** zeichnet im Part-Skizzenmodus keinen opaken
Hintergrund mehr, nur noch den Veil (`T.viewport` @ 55 %) ueber die echte
3D-Szene. `paintPartUnderlay` und `_UnderlayCache` sind geloescht.

**`PartCamera.roll`** (neu) plus `PartCamera.forSketch(frame, size, pan, zoom)`.
`Cam3` dreht die Basis um den Roll; bei `roll = 0` kommt exakt die alte
abgeleitete Basis heraus, Orbiten ist also unveraendert. Roll geht als
`'roll'` im `cameraPayload` mit und wird in `RealityPartView.placeCamera()`
auf `right`/`up` angewandt.

**`Viewport3D._effectiveCamera`:** waehrend einer offenen Kindskizze besitzt
der 2D-Editor die Navigation, die 3D-Kamera wird aus dessen `pan`/`zoom`
abgeleitet. EINE Quelle — das ist der ganze Grund, warum der Cursor nicht vom
Modell wegdriften kann.

### Warum der Roll noetig war

`az`/`pol` allein koennen nicht jede Orientierung ausdruecken: die Basis
entsteht durch Kreuzen der Blickrichtung mit dem Welt-Up, was den Roll
festnagelt. `paintPartUnderlay` bekam dagegen die expliziten `frame.u`/`v`.
Auf einer GEKIPPTEN Flaeche unterscheiden sich beide um genau diesen Winkel,
und das Modell erschiene in der Skizzenebene verdreht. Auf xy/xz/yz faellt
das NICHT auf — genau so ueberlebt so ein Fehler eine Sichtpruefung.

### Beweis statt Augenschein

`m80_sketch_camera_test.dart` (10) projiziert dieselben Skizzenpunkte einmal
durch `Viewport2D.map()` und einmal durch `Cam3(PartCamera.forSketch(...))`
und verlangt Uebereinstimmung auf **1e-6 Pixel** — bei 0, 15, 42, 90 und 137
Grad Neigung. Dazu: Blickrichtung == Skizzennormale, `halfH` == `h/(2*zoom)`,
Zoom 0 ergibt keine kaputte Kamera, und eine gerollte Basis bleibt
orthonormal.

### Gewinn

Pan und Zoom bewegen jetzt nur noch eine Kamera — die GPU zeichnet das
Modell. Der Posten, der pro Frame ein `SceneTri` je Dreieck allokierte
(34 236 bei einem Zahnrad), existiert nicht mehr. Dazu kommt, was Inventor
auszeichnet und mit einer flachen Unterlage prinzipiell unmoeglich war: echte
VERDECKUNG des Skizzenplans durch Modellgeometrie.

### Geraete-Test — was zu pruefen ist

1. **Gekippte Flaeche.** Skizze auf eine schraege Flaeche, dann pannen und
   zoomen. Modell und Skizze duerfen sich nicht gegeneinander verschieben
   oder verdrehen. Das ist der Roll-Test; auf den Ursprungsebenen sagt er
   nichts aus.
2. **Cursor-Treue.** Ein Snap auf eine Modellkante muss dort greifen, wo die
   Kante GEZEICHNET wird.
3. **Verdeckung.** Skizzengeometrie hinter dem Solid muss verdeckt sein.
4. **Kein Stocken** beim Pannen/Zoomen in der Skizze.

### Bewusst beibehalten

Die Verfeinerung bleibt waehrend einer offenen Skizze gesperrt (M68). Das
Modell behaelt die Aufloesung, die es beim Oeffnen hatte — stark
Hineinzoomen zeigt es also etwas grob, dafuer stockt nichts. Wenn das
stoert, ist die Stelle `_armRefine` in viewport3d.dart; eine einmalige
Verfeinerung beim Betreten der Skizze waere der naechste Kompromiss.

### Rueckfall

Es gibt keinen Schalter mehr — der Underlay-Pfad ist geloescht. Falls das
Verhalten auf dem Geraet nicht stimmt, ist `f6475cd` der letzte Commit mit
dem alten Weg.

## M81 — Skizzenlinien in 3D: Zoom, Konstruktionsgeometrie, Farben

Vier Punkte, alle aus demselben Grund: die 3D-Skizzendarstellung war eine
vereinfachte Kopie der 2D-Regeln statt derselben Regeln.

**(1) Baender aktualisierten nur beim Orbit, nicht beim Zoom.**
`rebuildEdgesIfTurned` (Richtungsaenderung) baute die Skizzen mit neu,
`rebuildEdgesForZoom` aber nur die SOLID-Kanten. Ein Band haengt an beidem —
Ausrichtung an der Blickrichtung, Breite an `halfH`. Beim Zoomen blieben die
Skizzenlinien also auf ihrer alten Breite stehen, waehrend das Modell um sie
herum skalierte. Neu: `rebuildSketchRibbons()`, aufgerufen aus BEIDEN Pfaden;
der Orbit-Pfad ruft jetzt schlicht `rebuildEdgesForZoom()`, das beides macht.

**(2) Konstruktionsgeometrie wurde in 3D immer gezeigt.** 2D hat die Regel
laengst: `if (!app.inEditMode && g.isConstruction) continue`. Der
Sketch-Payload filtert jetzt genauso — sichtbar nur, wenn GENAU diese Skizze
gerade bearbeitet wird.

**(3) Farben.** 2D benutzt vier: weiss (bestimmt, editierbare Ebene),
blau-violett `9A8CF5` (unterbestimmt), gelb `E8C84A` (Projektion), grau
(Referenz). 3D malte alles in einer Farbe. Jetzt traegt der Payload je Kurve
eine ARGB-Farbe, `sketchGeoColor()` entscheidet sie, und Swift baut das
Material damit. DOF-Quelle ist `app.analysis.carrierFixed(gi, 0)` — dieselbe,
aus der Viewport2D malt.

**(4) Ausserhalb der bearbeiteten Skizze: alles weiss.** DOF ist ein
Editier-Signal; auf einer Skizze, die man nicht bearbeitet, waere es Rauschen,
auf das man nicht reagieren kann. 2D macht es so, 3D jetzt auch.

**Falle dabei:** `sketchTones` ist ein Parallel-Array zu `sketchEntities`.
Ohne das haette das Loeschen eines Hover-Highlights die Kurve auf die flache
Standardfarbe zurueckgesetzt — die Constraint-Faerbung waere also
verschwunden, sobald man einmal irgendwo hovert. Beide Arrays werden in
`rebuildSketches` gemeinsam geleert.

Tests: `m81_sketch_style_test.dart` (5). analyze 0 errors, **498 gruen**.

## M88 — Kamera-Schwenk, Farbregel korrigiert, Projektionen aktualisieren

Drei gemeldete Fehler, alle bestaetigt und behoben.

### (1) Projizierte 3D-Geometrie aktualisierte nicht

`_syncSolidProjectionsInner` hat die Tag-Liste mutiert, aber nie
`_rebuildEngine` gerufen — die ENGINE haelt die echte Geometrie, die
Tag-Liste allein reicht nicht. `syncProjections()` kommt damit durch, weil es
INNERHALB von `solveConstraints` laeuft, dessen Ergebnis anschliessend von
`_rebuildEngine` gepusht wird. Mein Sync laeuft dagegen nach einem
Feature-Rebuild und muss selbst pushen. Ohne das blieb jede aus einer
Extrusion projizierte Kurve auf ihrer alten Form stehen, wenn man die
Extrusion aenderte. Genau als Risiko in M76 notiert und dann nicht
nachgezogen.

### (2) Skizzenlinien manchmal weiss statt blau-violett

Meine Regel war GENAU UMGEKEHRT zu 2D. Viewport2D:
`segFull(i,0) => hasAnalysis && analysis.carrierFixed(i,0)` — ohne Analyse
ist das FALSE, die Kurve also violett. M81 hatte den Default auf `true`
(weiss) gesetzt. Sichtbar wurde es vor allem direkt nach einer Aenderung,
bevor `_reanalyze()` gelaufen ist.

Zweiter Punkt derselben Ursache: ich hatte die DOF-Faerbung an
`inEditMode` gekoppelt ("ausserhalb alles weiss"). Das war meine Erfindung —
2D faerbt nach DOF unabhaengig vom Edit-Modus. Jetzt gilt: DOF-Faerbung fuer
die Skizze, die `app.analysis` beschreibt (also `app.current`), sonst weiss,
weil die Indizes fuer eine andere Skizze bedeutungslos waeren. Nur das
Ausblenden von KONSTRUKTIONSGEOMETRIE haengt weiterhin an `inEditMode`, wie
in 2D.

### (3) Kamerawechsel jetzt animiert

`PartCamera.lerp` plus ein 420-ms-`AnimationController` mit
`easeInOutCubic` in Viewport3D. Zwei Details, die sonst falsch aussehen:

- **Winkel nehmen den KURZEN Weg.** `az` kommt aus `atan2`, ein Paar
  beiderseits von +/-pi ist also Alltag; ein simpler Lerp haette das Modell
  fast eine ganze Umdrehung gedreht. Gilt auch fuer `roll`.
- **Zoom interpoliert GEOMETRISCH.** Zoom ist multiplikativ: linear zwischen
  27 und 2700 liegt 1363, was optisch schon fast ganz herausgezoomt ist —
  der echte Mittelpunkt ist 270.

Der Schwenk startet immer bei dem, was gerade auf dem Schirm ist, also
springt es auch dann nicht, wenn man mitten in der Animation wieder
umschaltet.

**Das 2D-Overlay wird erst am Ende eingeblendet** (`app.sketchOverlayFade`,
ab 85 % des Schwenks). Es zeichnet mit FESTER Transformation, waehrend die
Kamera noch faehrt — beides liefe sonst auseinander und die Skizze wuerde
ueber das Modell rutschen. Verloren geht nichts, weil die 3D-Szene
Skizzenkurven ohnehin als Baender rendert. Waehrend der Blende ist das
Overlay `IgnorePointer`, damit kein Tap auf einer noch nicht sichtbaren
Skizze landet.

Tests: `m88_camera_swing_test.dart` (6), `m81_sketch_style_test.dart` neu
geschrieben (4) — die alten kodierten meine falsche Regel.
analyze 0 errors, **558 gruen** (Baseline 553).

## M89 — Der Sprung am Ende des Schwenks, und die verdrehte Skizze

Beide Symptome hatten EINE Ursache: die Kamerabasis wurde aus der
BLICKRICHTUNG abgeleitet, und das geht an den Polen nicht.

### Die Rechnung

Mit `dir = (sin p·sin a, cos p, sin p·cos a)` ist

    fwd × (0,1,0) = (sin p·cos a, 0, −sin p·sin a)

Normalisiert also `(cos a, 0, −sin a)` — fuer JEDES pol, weil sich `sin p`
herauskuerzt. Die Basis haengt gar nicht von pol ab. Zwei Fehler folgten
daraus:

1. **Der Ersatzzweig sprang.** Wurde das Kreuzprodukt kurz, fiel der Code auf
   `fwd × (0,0,1)` zurueck — das zeigt irgendwohin, nicht dorthin, wo die
   Annaeherung hinlief. Eine Skizze auf einer Deck- oder Bodenflaeche landet
   genau dort (`pol = acos(±1) = 0` bzw. `pi`), also jedes Mal.
2. **Grundlegender: an einem Pol ist der Azimut nicht mehr in `dir`.** Bei
   `pol = 0` ist `dir = (0,1,0)`, egal welches az vorher galt. Aus der
   Richtung ist die Basis dort also prinzipiell nicht rekonstruierbar — mein
   erster Reparaturversuch (`atan2(dir.x, dir.z)` im Ersatzzweig) war deshalb
   ebenfalls falsch und fiel im Test durch.

### Der Fix

`PartCamera.rightFor(az) = (cos az, 0, −sin az)` — geschlossene Form im
AZIMUT allein. Kein Kreuzprodukt, kein Sonderfall, stetig ueberall. `Cam3`
und die Swift-`placeCamera()` nutzen jetzt beide diese Form, und `up` folgt
als `right × fwd`.

### Warum die Skizze verdreht erschien

Es gab DREI Kopien dieser Konstruktion: `Cam3._basisS`, `placeCamera()` in
Swift und `_derivedRight` in part_model.dart. Der Roll wird gegen die eine
gemessen und auf die andere angewandt — sobald sie auseinanderlaufen, ist die
Skizze rotiert oder gespiegelt. Genau das passierte an den Polen, wo die
Ersatzzweige unterschiedlich zuschlugen. Jetzt existiert die Formel nur noch
einmal (`rightFor`), die Swift-Seite traegt einen Kommentar, der auf sie
verweist, und `_basisS`/`_basisU` sind geloescht.

**Wichtig fuers Orbiten:** Ein Test prueft, dass die geschlossene Form
ueberall dort mit dem alten Kreuzprodukt uebereinstimmt, wo dieses brauchbar
war — das Orbitverhalten aendert sich also nicht, nur die Polfaelle werden
richtig.

Tests: `m89_basis_continuity_test.dart` (6), darunter Skizzen auf Deck- und
Bodenflaeche sowie eine um 90 Grad gedrehte u-Achse, jeweils mit der
Forderung, dass `+u` nach rechts und `+v` nach oben projiziert — dort taucht
eine gespiegelte oder 180 Grad verdrehte Skizze auf.
analyze 0 errors, **564 gruen**.

## M90 — Trackball-Orbit (Inventors Free Orbit / Blenders Trackball)

### Was vorher war

`_orbit` addierte auf `az`/`pol` und klemmte `pol` auf
`[0.02, pi − 0.02]` — ein TURNTABLE, der nicht einmal den Pol erreichte. Man
konnte also nie genau von oben schauen, geschweige denn darueber hinaus
weiterdrehen.

Die Klemme war eine Umgehung: die Basis wurde aus der Blickrichtung abgeleitet
und degenerierte an den Polen. Seit M89 (`rightFor(az)`) gibt es diese
Degeneration nicht mehr, der Grund fuer die Klemme war also entfallen.

### Recherche

- **Blender** hat zwei Methoden. Turntable haelt den Horizont waagerecht und
  behaelt eine feste Up-Richtung — laut Handbuch bewusst mit dem Nachteil
  verlorener Flexibilitaet. Trackball ist "less restrictive, allowing any
  orientation". Turntable ist der Standard, und Nutzer empfinden Trackball
  vielfach als unintuitiv.
- **Inventor** hat Free Orbit (F4, der aeltere Standard) und Constrained Orbit
  (2009 ergaenzt). Free Orbit dreht um die BILDSCHIRMachsen: links/rechts um
  die vertikale, vor/zurueck um die horizontale, und ein Zug um den Kreis
  herum rollt um die Bildschirmnormale. Constrained Orbit dreht um die
  TOP/BOTTOM-Achse des ViewCube, "als laege das Modell auf einer Drehscheibe".

Umgesetzt ist Free Orbit, weil das die gemeldete Erwartung ist. Constrained
laesst sich spaeter als zweiter Modus ergaenzen — umgekehrt waere es Mehrarbeit.

### Umsetzung

`PartCamera.orbitScreen(yaw, pitch)` rotiert die BASIS um die Bildschirmachsen
(Rodrigues): yaw um das kameraeigene Up, dann pitch um das NEUE Right, damit
sich beides wie eine echte Kugel zusammensetzt. `setBasis(d, r)` schreibt
`az`/`pol`/`roll` zurueck und orthogonalisiert `r` dabei neu — ueber hunderte
Drag-Events summiert sich sonst Drift.

Entscheidend: das braucht DREI Freiheitsgrade. Eine Zwei-Winkel-Kamera kann
einen Trackball prinzipiell nicht darstellen; erst `roll` aus M89 macht es
moeglich. An einem Pol ist `az` beliebig (`atan2(0,0)`), und das ist in Ordnung,
weil der Roll gegen `rightFor(az)` gemessen und vom Renderer aus DEMSELBEN `az`
wieder aufgebaut wird.

**Alle fuenf Klemmen sind weg**, nicht nur die im Drag: die ViewCube-Pfeile
gehen jetzt durch dieselbe Trackball-Rotation (sonst holen sie die
Beschraenkung zurueck), und `orientToDir`/`_snapTo` schnappen exakt auf
Top/Bottom statt eine Tausendstel-Radiante davor haengenzubleiben.

### Tests

`m90_trackball_test.dart` (9). Die wichtigsten pruefen, was vorher unmoeglich
war: ein langer Pitch-Zug muss BEIDE Pole durchlaufen (`dir.y` unter −0.999
und ueber +0.999), eine volle Umdrehung muss exakt zum Ausgangspunkt
zuruecklaufen (Richtung UND Roll, sonst driftet es), und die Basis muss nach
1000 zufaelligen Drags noch orthonormal sein. Dazu: yaw-dann-pitch unterscheidet
sich von pitch-dann-yaw — Rotationen kommutieren nicht, und genau dieser
Unterschied ist es, der einen Trackball frei anfuehlen laesst; ein Turntable
auf zwei Winkeln kann ihn gar nicht zeigen.

Beim Schreiben hatte ich die Pitch-RICHTUNG falsch angenommen und den Test
entsprechend falsch formuliert; ein Trace zeigte `0.56 → −0.99 → +0.99`, also
den vollen Durchlauf. Die Eigenschaft ist jetzt richtungsunabhaengig
formuliert.

analyze 0 errors, **573 gruen**.

### Offen

- **Constrained Orbit** als zweiter Modus samt Umschalter.
- **Roll per Geste:** Inventors Zug um den Kreis herum ist mausgedacht; auf
  dem iPad waere die Zwei-Finger-Drehgeste das idiomatische Gegenstueck.
  `orbitScreen` deckt Roll noch nicht ab — dafuer braeuchte es eine Rotation
  um `dir` selbst, was mit `setBasis` trivial ist.
- Orbiten waehrend einer offenen Skizze aendert `p.camera`, angezeigt wird aber
  `forSketch(...)`. Das ist ungefaehrlich (kein Ueberschreiben der
  Ebenenausrichtung), aber die Eingabe erreicht die 3D-Ebene ohnehin nicht,
  weil das 2D-Overlay darueber liegt.
