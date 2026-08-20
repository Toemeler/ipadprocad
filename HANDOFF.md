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

> **Stand der CI (nachgelesen, nicht am Haken abgezaehlt).**
> Letzter Lauf auf `main`: **32029429683** zu `eb8e035` (M228) — **1931 Tests
> bestanden**, **55 Issues / 0 Errors** (Ausgangszahl seit M220; der M225-Lauf
> stand kurz auf 59 und ist zurueckgeholt). Der Stand zu M220 zum Vergleich:
> Lauf 31970418590, 1805 Tests. Der OCCT-Kernel-Lauf **31820861588** zu `07e3790`
> (M217) ist der letzte, der den Shim wirklich gebaut hat;
> `ci-logs-occt/smoke.log` beginnt mit
> `Prototype OCCT shim v20 (OCCT 7.9.3) (shim ABI v20)` und endet auf
> `OCCT SMOKE: PASS`, mit `[33]` (STEP-Export) und `[34]` (Delete Face /
> Direct Edit) darin. Der Workflow ignoriert `**.md`, ein reiner
> Dokumentations-Push loest also KEINEN Lauf aus.
>
> **WAS JETZT NOCH OFFEN IST** (Stand M231, gegen den Code geprueft — nicht
> aus den Eintraegen unten abgeschrieben, die immer nur ihren eigenen Moment
> beschreiben).
>
> **1. Der Geraete-Test.** Weiterhin der aelteste und groesste Punkt: nichts
> seit M192 lief auf Hardware. Die Reihenfolge fuer M221–M231 steht unten.
>
> **2. Ungebaute Ribbon-Eintraege** (`onTap: null`, gedimmt im Klappmenue —
> die Liste ist aus `ribbon.dart` gezogen, nicht erinnert):
> * **Create ▼** Emboss, Derive, Decal
> * **Modify ▼** Shell, Draft, Thread, Thicken / Offset
> * **Work ▼** UCS (bewusst: ein Koordinaten-SYSTEM, kein dritter Fall von
>   Achse und Punkt)
> * **Skizze, Insert ▼** Points, Center Point, Driven Dimension, Show Format
>
> Shell, Draft und Thicken/Offset brauchen alle drei denselben Shim-Zusatz
> (`BRepOffsetAPI_MakeThickSolid`); das ist C++ plus ein OCCT-Lauf, und der
> Smoke-Test kann sie ueber das VOLUMEN pruefen — die staerkste Verifikation,
> die dieses Projekt hat.
>
> **3. Bewusst verweigert, mit Grund** (nicht vergessen, sondern entschieden):
> * **Direct > Rotate** (M217) — braucht eine `BRepTools_Modification`, deren
>   Fehlerfaelle erst an echten Formen auftreten.
> * **Delete Face ohne Heal** (M217) — es gaebe Flaechenkoerper, die es hier
>   nicht gibt.
> * **Sweep-Twist und Coil-Enden** (M131b) — der Shim lehnt sie ab, statt
>   still etwas Falsches zu bauen.
> * **Split in ZWEI Koerper** (M228) — braucht ein Feature, das einen Koerper
>   gebaeren kann; der Fold bildet eines auf einen Solid ab.
> * **Ein Muster ueber ein Loch oder eine Flaechen-Aenderung** (M226) — der
>   Weg dahin ist benannt: das WERKZEUG wiederholen, wie M213 es fuer Blends
>   tat. Der Umweg, der funktioniert, steht in der Ablehnung: die
>   Skizzenpunkte mustern.
> * **Hole: Linear/Konzentrisch, Gewinde, Spitzenwinkel** (M225/M226) — jedes
>   ein eigener Satz Zahlen bzw. eine Gewindetabelle.
>
> **4. Zwei Meldungen aus M210, weiterhin ohne Befund:** keine. Beide sind
> erledigt — der Profil-Pick in M221, die Dreiecke und die ISO-Schraffur in
> M222.

> **GERAETE-TEST — die Reihenfolge, in der es sich in EINER Sitzung pruefen
> laesst (M221–M231).**
>
> Nichts davon war je auf Hardware; das ist der aelteste offene Punkt und
> reicht in Wahrheit bis M192 zurueck. Diese Liste deckt nur die acht
> Meilensteine dieser Sitzung ab, dafuer in einer Reihenfolge, die aufeinander
> aufbaut: jeder Schritt benutzt, was der vorige gebaut hat.
>
> 1. **Skizze mit zwei konzentrischen Kreisen, Extrude oeffnen (M221).**
>    Erwartet: das Panel geht auf und die Skizze SCHLIESST sich dabei (vorher
>    lag das 2D-Overlay darueber und verschluckte jeden Pick). Dann Ring
>    antippen, danach die Scheibe: **beide** muessen ausgewaehlt sein, und die
>    Fuellung muss die zeigen, die man gerade getippt hat — nicht die andere.
>    Das war die gemeldete Sache.
> 2. **Denselben Ring extrudieren.** Erwartet: ein Ring mit Loch, keine volle
>    Scheibe. (Der Anker lag frueher in der Mitte des Lochs, also konnte die
>    Aufloesung beim Rebuild die falsche Region treffen.)
> 3. **Eine Skizze auf der Deckflaeche oeffnen, Slice Graphics an (M222).**
>    Erwartet: die Schnittflaeche ist schraffiert und zeigt **keine
>    Dreieckskanten** mehr. Mit zwei Koerpern im Schnitt: die Schraffuren
>    muessen sich unterscheiden (45°/135°).
> 4. **Arbeitsebene: Three Points, dann Two Coplanar Edges (M223).** Erwartet:
>    beide bauen; ein dritter Punkt auf einer Linie mit den ersten beiden wird
>    mit einer Meldung abgelehnt, nicht geraten.
> 5. **Tangential zu einem Zylinder durch einen Punkt (M224).** Zylinder auf
>    der Seite antippen, auf der die Ebene liegen soll. Erwartet: die Ebene
>    liegt auf DIESER Seite. Tippt man den Zylinder genau in Richtung des
>    Punktes an, muss der Befehl noch einmal fragen statt zu raten.
> 6. **Hole auf zwei Skizzenpunkten (M225).** Erwartet: Panel oeffnet, Tipp auf
>    einen Punkt setzt eine Bohrung, zweiter Tipp nimmt sie weg; OK bohrt beide
>    nach INNEN (nicht aus dem Teil heraus). Danach den Punkt in der Skizze
>    verschieben: die Bohrung muss mitwandern.
> 7. **Dasselbe Loch auf Counterbore stellen (M226).** Erwartet: ein flacher,
>    weiterer Topf an der Oberflaeche. Dann Countersink, 90°: ein Kegel, der
>    sich nach OBEN oeffnet. **Wenn der Kegel andersherum steht, ist das
>    Taper-Vorzeichen falsch** — das ist die eine Stelle dieser Sitzung, die
>    nur ein Bild klaeren kann.
> 8. **Das Loch im Browser doppelt antippen.** Erwartet: das Panel geht mit den
>    gespeicherten Werten auf (das war bis M226 tot).
> 9. **Zweiten Koerper bauen, Combine > Cut (M227).** Erwartet: erster Tipp
>    waehlt den Koerper, der BLEIBT; danach den anderen; OK laesst einen
>    Koerper uebrig. Mit „Keep tool" bleiben beide.
> 10. **Split mit der XZ-Ebene (M228).** Erwartet: die Haelfte auf einer Seite
>     verschwindet, „Other side" dreht es um, und der Ebenen-Pick startet
>     **keine Skizze**.
> 11. **Arbeitsebene: Angle to Plane around Edge (M229).** Ebene, dann eine
>     Kante darin. Erwartet: die Ebene steht schraeg DURCH die Kante, und das
>     Wertfeld oben steht offen — mit **„deg"** statt „mm". Zahl aendern: die
>     Ebene folgt.
> 12. **Normal to Curve at Point (M231).** Eine Skizzenkurve dort antippen, wo
>     die Ebene sie kreuzen soll. Erwartet: die Ebene steht senkrecht auf der
>     Kurve an genau dieser Stelle.
> 13. **Ein Panel offen lassen und nach Hause gehen (M230).** Erwartet: das
>     Panel ist beim Zurueckkommen WEG. (Vorher kam es wieder — und zeigte auf
>     die Skizze des anderen Teils.)
>
> Was dabei nebenbei mitgeprueft wird, weil es ueberall drinsteckt: dass ein
> 3D-Panel die anderen schliesst, dass Esc Panel UND Pick zusammen wegraeumt,
> und dass OK/Abbrechen in der Schnellwerkzeug-Leiste fuer alle vier neuen
> Panels funktionieren.

> **Nachtrag zur Nummerierung (M214–M216).** Diese drei entstanden auf einem
> eigenen Branch als M212/M213/M214, waehrend `main` M212 und M213 bereits
> fuer die 3D-Muster vergeben hatte. Zwei verschiedene M212 in einer
> Codebasis, deren Kommentare alle an Meilensteinnummern haengen, sind eine
> Falle — also ist die ungemergte Seite gewandert (`43a404c`):
> STEP-Export → **M214**, Work Axis/Point → **M215**, Ribbon-Klappmenues →
> **M216**. Dateien und das Analyse-Dokument wurden mit umbenannt.

> **M225 (1/2) — Hole: das Feature.**
>
> „Hole" steht seit M56 als Beschriftung im Teil-Ribbon und war bis M216 ein
> Knopf in voller Groesse mit leerem `onTap`. Es ist der meistbenutzte Eintrag
> in Inventors Modify-Panel, und der einzige Weg hierher war bisher: einen
> Kreis zeichnen und als Cut extrudieren — hinterher etwas voellig anderes.
> Im Browser steht „Extrusion", der Durchmesser ist eine Skizzenbemassung
> statt einer Lochgroesse, und das Loch zu verschieben heisst, Geometrie zu
> bearbeiten statt einen Punkt.
>
> **Es ist ein koerper-veraenderndes Feature, keine Extrusion mit
> `output: 'cut'`** — obwohl es genau so beim Kernel ankommt. Ein Loch kann
> nie ein Basis-Feature sein (es muss Material geben), sein Browser-Eintrag
> und sein Dialog handeln von einem Loch und nicht von einem Profil, und das
> Profil, mit dem es schneidet, wird aus einem DURCHMESSER abgeleitet statt
> gezeichnet: nichts in der Skizze muss ein Kreis sein, und wer den Punkt
> verschiebt, verschiebt das Loch.
>
> **Platzierung auf Skizzen-PUNKTEN** (Inventors „From Sketch"). Gespeichert
> werden Koordinaten, und bei jedem Rebuild wird der naechste Skizzenpunkt
> gesucht und die Platzierung darauf umgeschrieben — dieselbe Regel wie bei
> `ProfileSel` und aus demselben Grund: ein Index verschiebt sich, sobald
> etwas eingefuegt wird. Landen ZWEI Platzierungen auf demselben Punkt, wird
> abgelehnt statt zweimal dasselbe Loch zu bohren; genau das hinterlaesst ein
> geloeschter Punkt, und es ist die Verwechslung, die M217s `resolveFaces`
> fuer Flaechen schon verweigert.
>
> **Die Bohrrichtung ist nach INNEN.** Die Normale einer Skizze zeigt zum
> Betrachter, das Werkzeug startet also bei −Tiefe und endet auf der
> Skizzenebene. `flip` dreht es um. Bei „Through All" ist das Werkzeug so
> lang wie die Diagonale des Teils plus 20 mm und ragt auf BEIDEN Seiten
> heraus — eine Werkzeugflaeche, die mit einer Koerperflaeche zusammenfaellt,
> ist der klassische Muenzwurf einer Booleschen.
>
> **Bewusst NICHT drin, statt halb:** Senkung, Zylindersenkung und Planansenkung
> (jeweils ein gestuftes oder konisches Profil und ein zweiter Satz Zahlen),
> Gewinde- und Durchgangsloecher (eine Gewindetabelle), der Spitzenwinkel am
> Grund (ein Kegel, also ein Revolve statt einer Extrusion) und die
> Platzierungen Linear/Konzentrisch. To Next / To Face werden ABGELEHNT statt
> als Distanz gebohrt.
>
> Der Kreis geht als 96-Punkt-Polygon zum Kernel — genau wie ein GEZEICHNETER
> Kreis (`sampleEntity(g, arcSamples: 96)`), damit `arcFitLoop` daraus
> dieselben exakten Boegen macht und das Loch eine echte Zylinderflaeche
> bekommt.
>
> **Ehrlicher Stand:** 13 neue Tests (`m225_hole_test.dart`) — was beim Kernel
> ankommt (ein Werkzeug je Platzierung, jeder Punkt exakt auf dem Radius), die
> Lage des Werkzeugs, Flip, Through All, das Mitwandern mit dem Punkt, alle
> Fehlerwege und der JSON-Roundtrip. Die Punkte entstehen im Test durch das
> ECHTE Werkzeug (`Tool.point`), nicht von Hand — ein Loch, das nur
> testgebaute Punkte findet, bewiese nichts. CI-Lauf **32026444774**: **1877
> gruen**, analyze 55 Issues / 0 Errors.

> **M231 — Normal to Curve at Point: die dreizehnte, und die Tangente lag
> schon da.**
>
> M223 hatte sie mit Grund liegen lassen: „braucht einen KURVEN-Beitrag —
> eine Tangente an einem Parameter —, den `WorkRef` nicht fuehrt." Den fuehrt
> er jetzt, und er kostete keine neue Mathematik: der 3D-Kurven-Pick rechnet
> den Trefferpunkt ohnehin aus (er braucht ihn fuer den Tiefentest) und kennt
> das Segment, das er getroffen hat. Auf der seit M219 ADAPTIV abgetasteten
> Kurve IST dieses Segment die Tangente, bis auf die Abtast-Toleranz. Beides
> wurde bisher weggeworfen; `_pickSketchCurveHit` behaelt es, und
> `_pickSketchCurve` ist nur noch dessen Schluessel — alle bisherigen Aufrufer
> bleiben unveraendert.
>
> **Ein Pick, beide Haelften.** `WorkRef.curveAt` traegt den Punkt UND die
> Tangente, und genau deshalb ist die Methode ein einziger Tipp: der Punkt ist,
> wo die Ebene sitzt, die Tangente ist ihre Normale. Was sie von einer geraden
> KANTE unterscheidet, die ebenfalls Punkt und Richtung anbietet, ist nicht die
> Geometrie, sondern die Bedeutung — also die `source`.
>
> **Der Kurven-Pick steht GANZ HINTEN** in `_pickWorkRef`: jeder Solid-Pick
> gewinnt vor ihm, damit nichts, was vor M231 funktioniert hat, jetzt anders
> greift. Eine Kurve antwortet nur, wenn nichts Festes unter dem Finger war —
> und das ist genau der Moment, in dem der Benutzer nur die Kurve gemeint
> haben kann.
>
> **Damit fuehrt jeder der dreizehn Flyout-Eintraege irgendwohin.** Zehn sind
> diese Methoden, drei sind „Plane"/„Offset from Plane" (beide der
> Offset-Fluss) und „Midplane between Two Planes". Die Liste, die seit M56 als
> Attrappe dastand, ist vollstaendig — und keine einzige Zeile davon ist eine
> stille Naeherung: was nicht gebaut werden konnte, wurde jedes Mal mit Grund
> abgelehnt, bis der Grund weggeraeumt war.
>
> **Ehrlicher Stand:** 6 neue Tests im M229-File (Gruppe „M231 — …"): Tangente
> als Normale, Punkt auf der Ebene, Normalisierung eines beliebig langen
> Abtastsegments, die Abgrenzung zur Kante, die Arity, und der Commit ueber
> denselben Weg wie die anderen. **Am Geraet nicht nachgeprueft** — und hier
> heisst das: ob ein Tipp auf eine Kurve dort trifft, wo man zielt. CI-Lauf
> **32047189527**: **1956 gruen**, analyze 55 Issues / 0 Errors.

> **M230 — ein 3D-Panel darf die Modelle nicht ueberleben, auf die es zeigt.**
>
> Beim Nachsehen gefunden, nicht gemeldet — wie schon die beiden aus M226.
> Jede 3D-Sitzung haelt Referenzen IN ein Teil hinein: einen Skizzennamen,
> einen Koerpernamen, einen von einer Flaeche abgenommenen Frame, eine Liste
> von Platzierungen. Vier Stellen in `app_state.dart` sind Momente, in denen
> genau dieses Teil ersetzt oder verlassen wird — nach Hause gehen, Tab
> schliessen, Teil loeschen, Undo-Schnappschuss zurueckspielen — und alle vier
> riefen `cancelExtrude()` **allein**.
>
> Das war richtig, solange die Extrude-Sitzung die einzige war. Seit M136 (das
> Fillet-Panel) ist es still falsch, und diese Sitzung hat vier weitere
> hinzugefuegt (M212 Muster, M225 Hole, M227 Combine, M228 Split). Der Ablauf,
> der es zeigt: in Teil A ein Loch anfangen, nach Hause gehen, Teil B oeffnen —
> das Panel kam wieder und zeigte auf As Skizze.
>
> `cancel3DCommands()` ist die eine Liste, damit der NAECHSTE Befehl per
> Konstruktion mit abgeraeumt wird statt per Erinnerung. Besonders bezeichnend
> ist die vierte Stelle: `_restorePartSnap` traegt seit M182 den Kommentar
> „In-flight 3D sessions hold references into the model that is about to be
> replaced wholesale — cancel them first". Der Kommentar hatte recht; die
> Liste darunter war vier Befehle alt.
>
> **Ehrlicher Stand:** 5 neue Tests
> (`m230_sessions_do_not_outlive_their_part_test.dart`) — je Stelle einer, und
> die Sammelabfrage prueft ALLE neun Sitzungsflags, sodass eine kuenftige
> Sitzung, die jemand hier vergisst, hier auffliegt. **Am Geraet nicht
> nachgeprueft** (aber diese Klasse faellt auf dem Host auf, nicht am Geraet —
> deshalb steht sie hier). CI-Lauf **32046670339**: **1950 gruen**, analyze 55
> Issues / 0 Errors.

> **M229 — Angle to Plane around Edge: die zwoelfte Methode, und sie brauchte
> kein zweites Feld.**
>
> M223 hatte sie mit ihrer Begruendung liegen lassen: „braucht einen Winkel
> zum Eintippen. Das ist der Zwilling des Offset-Feldes (M169), eine
> UI-Aufgabe." Ein Zwilling war dann nicht noetig. Eine Arbeitsebene traegt
> hoechstens EINE editierbare Zahl — Millimeter bei einer Offset-Ebene, Grad
> bei einer gewinkelten —, also fragt das Feld die EBENE, welche es ist
> (`WorkPlane.valueUnit`), und es bleibt bei einem Feld, einem Flag und einem
> Commit-Weg. Eine dritte editierbare Art landet damit an einer Stelle statt
> an dreien.
>
> **Die Geometrie:** die Normale dreht per Rodrigues um die Kante, und der
> Ursprung ist ein Punkt AUF der Kante — das ist die eine Linie, die beide
> Ebenen teilen, und die einzige Wahl, bei der der Winkel sichtbar bleibt.
> `anglePlaneFrame` dreht den GANZEN Frame mit, nicht nur die Normale: sonst
> stuende eine Skizze auf dem Ergebnis verdreht zu der Ebene, aus der sie
> gewinkelt wurde (derselbe Grund, aus dem `offsetPlaneFrame` seine Achsen
> erbt). Eine Kante, die nicht IN der Ebene liegt, wird abgelehnt — die
> Drehung wuerde die Ebene von ihr wegschwenken, und Inventor verlangt sie aus
> demselben Grund.
>
> **Die Ebene behaelt, woraus sie gemacht ist** (Basis, Kante, Winkel) — genau
> das, was M162 fuer den Offset getan hat, und aus demselben Grund: sonst ist
> die eine Zahl, in der der Nutzer denkt, beim Anlegen eingebacken und weg.
> Das Feld geht auf, sobald die Ebene existiert (M169s Reihenfolge: erst
> hinkommen, dann richtig machen), und der naechste Winkel startet bei dem,
> den man zuletzt benutzt hat.
>
> Damit sind **zwoelf von dreizehn** Plane-Eintraegen echt. Offen bleibt nur
> noch Normal to Curve at Point — es braucht einen KURVEN-Beitrag (Tangente an
> einem Parameter), den `WorkRef` nicht fuehrt.
>
> **Ehrlicher Stand:** 14 neue Tests (`m229_angle_plane_test.dart`) — der
> Drehwinkel, dass die Kante in der Ebene BLEIBT, 0 Grad als Identitaet, die
> Ablehnung, der Frame als Ganzes, `setAngle`, dass eine Offset-Ebene weiter
> Millimeter spricht und eine konstruierte gar keine Zahl hat, der Roundtrip
> mit Drehachse, und die Befehlsseite samt „das Feld geht auf". **Am Geraet
> nicht nachgeprueft** — und hier heisst das vor allem: ob das Feld mit „deg"
> an der richtigen Stelle steht. CI-Lauf **32046227338**: **1945 gruen**,
> analyze 55 Issues / 0 Errors.

> **M228 — Split: die Haelfte, die diese Architektur ehrlich tragen kann.**
>
> Inventors Split macht drei Dinge: eine FLAECHE mit einer Kurve teilen, einen
> Koerper in ZWEI Koerper teilen, und einen Koerper an einer Ebene abschneiden
> (Trim Solid). Das mittlere ist keine Fussnote zu den anderen beiden: ein
> Feature, das einen ZWEITEN Koerper erzeugt, hat im Fold keinen Platz — der
> bildet ein Feature auf einen Solid ab und faltet ihn in EINE Kette. Das zu
> bauen hiesse, dem Zeitstrahl beizubringen, dass ein Feature einen Koerper
> gebaeren kann, und das ist ein eigener Meilenstein. Also der Trim — und das
> Panel sagt es, statt es den Nutzer herausfinden zu lassen.
>
> **Das Werkzeug ist der Halbraum-Kasten, den Slice Graphics seit M168 baut.**
> Genau deshalb wird seine Groesse hier nicht neu hergeleitet: er schneidet
> seit M168 in jeder Geraete-Sitzung die nahe Seite weg. Neu ist nur, dass er
> BLEIBT und sich umdrehen laesst. `flip` startet den Kasten eine volle Laenge
> vorher, sodass er exakt AUF der Ebene endet — die beiden Seiten treffen sich
> dort, und keine wird zweimal geschnitten.
>
> **Die Ebene wird gespeichert, nicht ihr Schluessel.** Eine Arbeitsebene kann
> sich bewegen, und ein Ursprungs-Schluessel kann nicht „die Flaeche, die ich
> angetippt habe" sagen; eine Skizze auf einer Flaeche legt ihren Frame aus
> genau diesem Grund ab (M58).
>
> **Der Pick ist der bestehende:** „eine Ebene oder eine planare Flaeche" ist
> dieselbe Frage wie beim Skizzieren und beim Arbeitsebenen-Offset, also
> laeuft der Split durch `planePicked`/`facePicked` — mit einem Zweig neben dem
> von M151, nicht mit einem zweiten Pick-Weg. Die Ursprungsebenen kommen fuer
> die Dauer heraus und verschwinden wieder, wie bei einer Skizze; Esc raeumt
> beides zusammen weg.
>
> **Ehrlicher Stand:** 13 Tests (`m228_split_test.dart`), CI-Lauf
> **32029429683**: **1931 gruen**, analyze 55 Issues / 0 Errors — der Schnitt und wo
> das Werkzeug liegt, beide Seiten (inklusive der Gleichung
> `start + hoehe = Ebene`), die Ablehnungen, Roundtrip mit Frame, der
> Rebuild-Schluessel, und die Befehlsseite: Vorbedingung, Pick, OK, Esc,
> Verdraengung, Browser-Edit. Ausdruecklich mitgeprueft: der Ebenen-Pick darf
> KEINE Skizze anfangen — das ist der andere Fluss auf demselben Tipp.
> **Am Geraet nicht nachgeprueft.**

> **M227 — Combine: eine Boolesche zwischen KOERPERN — und das erste Feature,
> das einen anderen Koerper liest.**
>
> Extrude traegt Join/Cut/Intersect seit M62, aber nur gegen den Koerper, in
> den sein eigenes Profil baut. Sobald zwei Koerper da sind, gab es keinen Weg
> zu sagen „nimm diesen aus jenem heraus" — genau der Fall, fuer den Inventor
> Combine unter Modify fuehrt.
>
> **Die Boolesche selbst ist nichts Neues:** `combineSolids` bedient das
> Extrude-Output seit M62 und nimmt dieselben drei Woerter. Neu ist die
> ABHAENGIGKEIT. Ein Combine liest einen fremden Koerper, und der
> Rebuild-Schluessel konnte das nicht sehen: er besteht aus den eigenen Zahlen
> plus dem Upstream-Hash des EIGENEN Koerpers. Ein bearbeiteter Werkzeugkoerper
> haette also einen Solid stehen lassen, der aus einem Koerper geschnitten ist,
> den es so nicht mehr gibt.
>
> `PartFeature.inputBodies` ist der Haken — leer fuer alles andere, es aendert
> sich also sonst nichts —, und der Fold mischt die Schluessel dieser Koerper
> mit ein. Zwei Tests nageln genau das fest: ein geaenderter Werkzeugkoerper
> laesst die Boolesche neu laufen, ein Leerlauf-Durchgang nichts.
>
> **Aufgeloest wird ueber SEQ, nicht ueber die Listenposition.**
> `bodyFeatureBefore` liefert das lebende Feature dieses Koerpers, wie es
> unmittelbar VOR diesem hier steht. Features des Werkzeugkoerpers, die spaeter
> kommen, halten unter Umstaenden noch einen Solid aus dem vorigen Durchgang —
> einen davon einzufalten hiesse, mit einem Koerper aus der Zukunft zu
> verrechnen. Ein Werkzeug, das an dieser Stelle noch nichts gebaut hat, wird
> beim Namen abgelehnt.
>
> **Keep Toolbody** ist Inventors, und es ist eine Zeile: ohne es wird das
> Werkzeug-Feature `consumedByJoin` gesetzt, und genau das laesst den Koerper
> aus Viewport, Koerperliste und STEP-Export zugleich verschwinden — alle drei
> lesen dieselbe `solid`/`!consumedByJoin`-Regel (M214).
>
> **Bedienung (2/2):** erster Tipp = der Koerper, der BLEIBT (kein Toggle — ihn
> noch einmal anzutippen liesse das Panel ohne Basis), danach die Werkzeuge,
> die sich ein- und ausschalten lassen. Der Befehl oeffnet gar nicht erst,
> wenn es weniger als zwei Koerper gibt. Im Ribbon bleibt Combine im
> Klappmenue, jetzt aber mit echtem Callback: das ▼ ist laut M216 fuer
> Befehle, die verfuegbar sind, aber keine dauerhafte Ribbon-Breite verdienen —
> und Modifys sichtbare Spalte ist voll. Was gebaut von ungebaut trennt, ist
> der Callback, nicht die Liste.
>
> **Ehrlicher Stand:** 20 Tests (`m227_combine_test.dart`) — die drei
> Operationen, mehrere Werkzeuge nacheinander, Keep Toolbody, vier
> Ablehnungen, der Roundtrip, der Rebuild-Schluessel von beiden Seiten, dass
> ein Muster ein Combine wie jedes koerper-veraendernde Feature ablehnt (M226),
> und die Befehlsseite: Basis, Werkzeuge, OK, Esc, Verdraengung, Browser-Edit.
> CI-Lauf **32028790477**: **1918 gruen**, analyze 55 Issues / 0 Errors. Der
> Lauf zu (1/2) hatte genau einen roten — meinen, nicht den des Codes: mit Keep
> Toolbody ueberleben beide Koerper, und `bodyNames` kam als
> `['Solid2','Solid1']` zurueck, weil die Reihenfolge dem Feature folgt, das
> den Koerper traegt (Solid1 haengt jetzt am Combine ganz hinten). Behauptet
> wird die MENGE, nicht die Folge. **Am Geraet nicht nachgeprueft.**

> **M226 — Senkungen: was ein Loch zu einem Schraubenloch macht.**
>
> M225 hat die vier Mundformen ausdruecklich weggelassen und den Grund
> genannt: „jeweils ein gestuftes oder konisches Profil und ein zweiter Satz
> Zahlen". Beides ist jetzt da — ohne eine einzige neue Kernel-Funktion.
>
> **Zylindersenkung und Planansenkung sind derselbe Schnitt** (ein flacher,
> weiterer Topf an der Oberflaeche) und bleiben trotzdem zwei Eintraege: eine
> Zylindersenkung versenkt einen Kopf, eine Planansenkung plant nur eine Nabe,
> damit eine Scheibe eben aufliegt. Inventor zeichnet beide gleich und
> bemasst sie verschieden — das eine still als das andere zu fuehren, ist die
> Sorte kleiner Luege, die bis in die Zeichnung ueberlebt.
>
> **Die Senkung ist ein KEGEL, und dafuer gibt es den Taper schon.** Der Shim
> dokumentiert sein Vorzeichen: „INVENTOR sign: positive tapers outward". Das
> Werkzeug laeuft beim Bohren nach innen vom kleinen Ende zur Flaeche hinauf,
> waechst also — Taper = +Winkel/2. Umgedreht (`flip`) startet es breit an der
> Flaeche und schliesst sich: dasselbe Profil in der anderen Leserichtung,
> Taper = −Winkel/2, und das Profil ist dann der GROSSE Kreis. Die Tiefe folgt
> aus dem eingeschlossenen Winkel: (R − r) / tan(Winkel/2), bei 90° also genau
> die Aufweitung selbst.
>
> **Zwei Schnitte statt eines zusammengesetzten Werkzeugs.** Zwei einfache
> Koerper nacheinander abzuziehen ist das, womit OCCT am wenigsten Muehe hat,
> und es haelt den flachen Boden der Zylindersenkung und den Kegel der Senkung
> vollstaendig aus der Profil-Arithmetik heraus.
>
> **Abgelehnt statt gerechnet:** eine Senkung, die nicht weiter ist als das
> Loch; eine Tiefe von 0; ein Winkel ausserhalb (0, 180). Und zwar zweimal —
> im Panel beim OK und noch einmal im Rebuild, weil ein geladenes Dokument
> nicht durch das Panel gekommen sein muss.
>
> **Ehrlicher Stand:** 6 neue Tests in `m225_hole_test.dart` (Gruppen
> „M226 — …") plus zwei erweiterte: was als ZWEITES beim Kernel ankommt
> (Radius, Hoehe, Taper, Startlage), beide Richtungen, die Ablehnungen, der
> Roundtrip und der Rebuild-Schluessel — ohne den letzten wuerde eine
> geaenderte Senkung den gecachten Solid stehenlassen. Der Panel-Schalter
> traegt vier UNTERSCHIEDLICHE Kurzlabels: „Counterbore" und „Countersink"
> teilen sich sechs Anfangsbuchstaben, und zwei Knoepfe mit demselben Wort
> sind keine Wahl. CI-Lauf **32027556475**: **1896 gruen**, analyze zurueck auf
> **55 Issues / 0 Errors** (der M225-Lauf stand kurzzeitig auf 59 — beide
> Hole-Testdateien importierten `tools.dart show Tool`, und `Tool` kommt aus
> `app_state.dart`; die Tests liefen trotzdem gruen, was genau der Grund ist,
> die Zahl zu lesen). **Am Geraet nicht nachgeprueft** — und beim Kegel heisst
> das ausdruecklich: dass das Taper-Vorzeichen stimmt, sagt der Shim-Kommentar,
> nicht ein Bild.
>
> **Zwei Anschluss-Fehler, beim Nachsehen gefunden statt gemeldet:**
>
> * **Der Browser konnte ein Loch nicht oeffnen.** `editFeature` kannte
>   `HoleFeature` nicht und landete im `else`-Zweig, der nur eine Logzeile
>   schreibt. Ein Feature, das man bauen und nicht mehr aendern kann, ist ein
>   halbes Feature.
> * **Ein Muster haette das Teil aufgefressen.** Die Werkzeug-Einteilung in
>   `_recomputePattern` fragt `src is BodyModifyFeature` — das ist die Klasse
>   mit den KANTEN-Fingerabdruecken (Fillet/Chamfer). Ein Loch ist das nicht,
>   also waere es in den Klon-Pfad gefallen: dort wird das Feature nachgebaut
>   und sein SOLID als Werkzeug kopiert — und der Solid eines Lochs ist der
>   ganze Koerper mit dem Loch drin. Jede Occurrence haette das Teil von sich
>   selbst abgezogen, still. Neu wird jedes Feature mit `modifiesBody`
>   abgelehnt (das trifft auch M217s Flaechen-Edits, die dieselbe Falle
>   hatten), UNTER den beiden spezifischeren Ablehnungen darueber, weil Fillet
>   und Muster ebenfalls `modifiesBody` sind und je einen besseren Satz haben.
>   Der Weg, der wirklich funktioniert, steht in der Meldung: die SKIZZENPUNKTE
>   mustern.

> **M225 (2/2) — Hole: der Befehl.**
>
> `HoleSession`, das Panel, der Pick und der Commit. Bewusst KEINE Variante
> von `ExtrudeSession`: die bedient fuenf Befehle, die alle PROFILE picken und
> sich nur in den Zahlen darunter unterscheiden — ein Loch pickt PUNKTE und
> leitet sein Profil aus einem Durchmesser ab. Es einzufalten hiesse, allen
> fuenfen eine Platzierungsliste anzuhaengen, die sie nie benutzen koennen.
>
> **Das Panel ist klein, weil das Feature klein ist:** Platzierungen,
> Durchmesser, Termination (Distance / Through All), Richtung. Eine leere
> Sektion, die Senkungen oder Gewinde verspraeche, waere genau das tote
> Bedienelement, das M216 abgeraeumt hat. Chrome und Felder kommen aus
> `properties_panel.dart` — der Datei, die es gibt, WEIL drei Panels einmal
> per Kopie gleich aussahen.
>
> **Der Pick:** solange das Panel offen ist, gehoert der Tipp ihm
> (`holePicking3D`, vor allem anderen im `_tap`, wie M212 es fuer die
> Muster-Selektoren eingefuehrt hat — ein Pickfeld, das tot aussieht, ist der
> Fehler, den diese Datei zweimal hatte). Getroffen wird ein Skizzenpunkt ueber
> `_sketchPointAt`, also exakt der Pfad des skizzengesteuerten Musters, und
> `holeCentresFor` liest dieselbe Liste (`sketchPatternPoints`) — zwei
> Definitionen von „ein Punkt in dieser Skizze" waeren zwei Gelegenheiten, sich
> zu widersprechen. Ein zweiter Tipp auf denselben Punkt nimmt ihn wieder weg.
>
> **Und die eine Regel, die dabei ueberall hin musste:** ein 3D-Panel
> schliesst die anderen. Extrude, Fillet, Muster und Hole brechen sich jetzt
> gegenseitig ab, und `openChildSketch` schliesst das Loch-Panel mit — zwei
> Panels, die um denselben Tipp konkurrieren, sind keine Bedienung. Esc
> schliesst Panel und Pick in einem, OK/Cancel der Schnellwerkzeug-Leiste
> bedienen es mit.
>
> **Im Ribbon verlaesst Hole das Klappmenue** und steht neben Chamfer und
> Delete Face — M217s Regel gilt in beide Richtungen: das Klappmenue ist, wo
> ein Befehl auf seinen Bau wartet, nicht wo er danach bleibt.
>
> **Ehrlicher Stand:** 13 weitere Tests (`m225_hole_command_test.dart`):
> Toggle, die Ablehnung ohne Koerper, die Uebernahme des Viewports, Esc, die
> gegenseitige Verdraengung, das Hin und Her beim Punktpicken, der Commit, die
> Ablehnungen und das Bearbeiten an Ort und Stelle. **Am Geraet nicht
> nachgeprueft** — und das Panel ist reine Geraeteseite: dass es sitzt, wo es
> soll, und dass die Tipps ankommen, sagt kein Host-Test.

> **M224 — die drei Tangential-Ebenen: was fehlte, war die SEITE.**
>
> M223 hat sie ausdruecklich nicht gebaut und den Grund notiert: durch einen
> Punkt ausserhalb eines Zylinders gehen ZWEI Tangentialebenen, und Inventor
> entscheidet ueber die Seite, die man angetippt hat. `WorkRef` hielt aber nur
> fest, was ein Pick BEITRAEGT, nicht wo er landete. Genau das ist jetzt
> ergaenzt — und nur das: `radius` und `hitAt` fuer eine Zylinderflaeche, mit
> einem Kommentar, der sagt, warum diese beiden nicht in dieselbe Kategorie
> gehoeren wie der Rest der Klasse. Der Trefferpunkt wurde im Viewport
> ohnehin schon berechnet (fuer den Tiefentest); er wird jetzt bloss nicht
> mehr weggeworfen.
>
> **Eine Ebene, dreimal dieselbe Aufgabe.** Die Normale einer Tangentialebene
> steht IMMER senkrecht auf der Achse, jede ist also durch einen einzigen
> Winkel um sie herum bestimmt: zulaessige Winkel bestimmen, dann mit der
> Tippseite auswaehlen.
>
> * **through Point:** liegt der Punkt AUF dem Zylinder, gibt es genau eine
>   Ebene und gar keine Wahl. Liegt er weiter draussen, sind es zwei, bei
>   ±acos(r/h) um seine eigene Richtung. Liegt er drinnen, gibt es keine — und
>   das wird gesagt, nicht gerechnet.
> * **through Edge:** eine Kante, die AUF dem Zylinder liegt und parallel zur
>   Achse laeuft, bestimmt die Ebene eindeutig. Eine Kante daneben wird mit
>   ihrem Abstand abgelehnt (`... is 4.000 mm off it`) — eine Kante, die nicht
>   auf der Flaeche liegt, ist viel wahrscheinlicher ein Fehlgriff als ein
>   Wunsch.
> * **and Parallel to Plane:** existiert nur, wenn die Normale der Bezugsebene
>   senkrecht zur Achse steht; sonst gibt es gar keine parallele Tangente.
>   Dann sind es +n und −n, und wieder entscheidet die Seite.
>
> **Ein Gleichstand ist keine Antwort.** Tippt man den Zylinder GENAU in
> Richtung des Zielpunkts an, liegen beide Tangenten gleich weit weg, der Pick
> traegt also keine Seite. Statt die erste zu nehmen, fragt der Befehl noch
> einmal („tap the face on the side the plane should go"). Das ist M158s
> Lektion, woertlich: Ranking ist nicht Akzeptanz, ein Muenzwurf gehoert
> verworfen. Aufgefallen ist es beim Nachrechnen der Geometrie in einer
> Simulation VOR dem Push — beide Kandidaten kamen mit demselben Skalarprodukt
> heraus.
>
> Damit sind **elf von dreizehn** Plane-Eintraegen echt. Offen bleiben Angle to
> Plane around Edge (braucht ein Winkelfeld, den Zwilling von M169) und Normal
> to Curve at Point (braucht einen Kurven-Beitrag in `WorkRef`).
>
> **Ehrlicher Stand:** 12 neue Tests im selben File
> (`m223_work_plane_methods_test.dart`, Gruppen „M224 — …"): je Methode die
> Tangentialbedingung (Abstand Achse→Ebene = r) UND die Punktbedingung, beide
> Seiten, die drei Ablehnungen und der Gleichstand. CI-Lauf **32025781360**:
> **1864 gruen**, analyze 55 Issues / 0 Errors. **Am Geraet nicht
> nachgeprueft.**

> **M223 — der Rest von Inventors Work-Plane-Liste, auf der Maschinerie von
> M215.**
>
> Das Plane-Flyout traegt Inventors dreizehn Eintraege seit M56. Drei waren
> echt: „Plane" und „Offset from Plane" (M151/M157, beide der Offset-Fluss)
> und „Midplane between Two Planes". Die anderen zehn taten **nichts** — genau
> die Form, die M216 im Teil-Ribbon gerade abgeraeumt hat, eine Ebene tiefer
> stehengeblieben.
>
> **Fuenf sind jetzt gebaut**, und sie brauchten keine neue Maschinerie:
> `WorkRef` aus M215 modelliert einen Pick nach dem, was er BEITRAEGT, und
> genau das ist es, was diese Methoden lesen. Parallel to Plane through Point,
> Three Points, Two Coplanar Edges, Normal to Axis through Point, Midplane of
> Torus — `solveWorkPlane` ist der Zwilling von `solveWorkAxis`, mit demselben
> `WorkAttempt`-Kontrakt (weiter / abgelehnt / fertig), derselben
> Pick-Schleife in `workFeaturePick` und ohne eine einzige Zeile im Viewport:
> der ruft `pickWorkGeometry` und `workFeaturePick`, beides schon generisch.
>
> **Was die Refusals sagen, ist der Punkt.** Drei kollineare Punkte werden
> abgelehnt, weil eine Unendlichkeit von Ebenen sie enthaelt — das ist keine
> Antwort. Zwei windschiefe Kanten melden, um WIEVIEL sie sich verfehlen
> (`... miss each other by 7.000 mm`), dieselbe Regel wie bei den Achsen. Und
> ein Fehlgriff kostet den Tipp und nicht den Befehl.
>
> **Fuenf sind NICHT gebaut, jede mit Grund** (im Code und im Flyout, das
> jetzt sagt was fehlt, statt stumm zu bleiben — M157):
>
> * **Angle to Plane around Edge** braucht einen Winkel zum Eintippen. Das ist
>   der Zwilling des Offset-Feldes (M169) und eine UI-Aufgabe, keine
>   geometrische.
> * **Normal to Curve at Point** braucht einen KURVEN-Beitrag (Tangente an
>   einem Parameter), den `WorkRef` nicht fuehrt.
> * **Tangent to Surface through Edge / through Point / and Parallel to
>   Plane:** ein Zylinder hat ZWEI Tangentialebenen durch einen aeusseren
>   Punkt bzw. parallel zu einer Ebene, und Inventor entscheidet das ueber die
>   SEITE, die man angeklickt hat. `WorkRef` haelt fest, was ein Pick
>   beitraegt, nicht wo auf der Flaeche er landete — das muesste zuerst dazu.
>   Eine Seite zu raten hiesse, die Ebene in der Haelfte der Faelle auf die
>   falsche Seite des Teils zu legen.
>
> **Nebenbei ein M155-Fehler, an der letzten Stelle, wo er ueberlebt hatte:**
> `_commitWorkPlane` vergab `'Work Plane${p.workPlanes.length + 1}'` — ein
> ZAEHLERSTAND. Loescht man Work Plane2 von dreien und baut eine neue, kommt
> „Work Plane3" ein zweites Mal heraus. Arbeitsachsen und -punkte benutzen
> `_freeWorkName` seit M215, Koerper seit M155; jetzt auch die Ebenen.
>
> Der Offset- und der Midplane-Fluss bleiben, wo sie sind: Offset ist ein ZUG
> mit lebendiger Distanz (M174/M169) und traegt als einzige Ebene eine
> nachtraeglich editierbare Zahl (M162), und beide sammeln `PlaneFrame`s statt
> `WorkRef`s. Ein gemeinsames Feld haette einen der beiden Fluesse dazu
> gebracht, den anderen zu spielen.
>
> **Ehrlicher Stand:** 21 neue Tests (`m223_work_plane_methods_test.dart`),
> CI-Lauf **32025159761**: **1852 gruen**, analyze 55 Issues / 0 Errors —
> je Methode die Geometrie (der Punkt liegt AUF der Ebene, nicht daneben), die
> Refusals, die Pick-Reihenfolge, der Befehl im AppState und der
> Namens-Fehler, der ohne den Fix wieder auftritt. **Am Geraet nicht
> nachgeprueft.**

> **M222 — ein Schnitt hat eine Kontur, ein Netz hat Kanten — und die
> Schraffur unterscheidet die Koerper (ISO 128).**
>
> Die zweite in M210 offen gelassene Meldung: „when i slice graphics there are
> triangles visible ... different parts should have different schraffur, like
> in iso norm." Dort als „ein Render-Fehler und eine echte neue Funktion"
> notiert. Beides steckt an derselben Stelle.
>
> **1. Die Dreiecke.** Der Painter baute EINEN `Path` aus jedem DREIECK des
> Schnittnetzes und zeichnete ihn anschliessend als „die Kontur des Schnitts".
> Eine Dreieckssuppe hat aber keine Kontur: jede geteilte Kante liegt zweimal
> in diesem Pfad und wurde mitgestrichen. Was auf dem Schirm stand, war die
> TESSELIERUNG — und weil die sich bei jedem Remesh aendert, sah es zufaellig
> aus.
>
> `sectionOutlines()` behaelt nur die Kanten, die zu genau EINEM Dreieck
> gehoeren — das ist die Definition eines Randes — und faedelt sie zu
> geschlossenen Schleifen. Die Vertices werden vorher auf ein Raster
> GESCHWEISST (1 µm): zwei Dreiecke einer Flaeche treffen sich an Koordinaten,
> die der Kernel gleich nennt und die nach der Transformation in
> Skizzenkoordinaten im letzten Bit auseinanderliegen koennen — ungeschweisst
> saehe jede Innenkante wie zwei Randkanten aus und die ganze Suppe waere
> zurueck. Die Schleifen behalten die Windung ihrer Dreiecke, aussen und Loch
> laufen also gegenlaeufig, und `evenOdd` fuellt beides richtig.
>
> **2. Die Schraffur.** ISO 128-50 verlangt, dass BENACHBARTE Teile im Schnitt
> unterscheidbar sind — ueber die Richtung, und wo die Richtung wiederkommt,
> ueber den Abstand. Die Einheit, in der der Painter arbeitet, ist damit der
> KOERPER und nicht das Dreieck: `sectionSlices()` gruppiert die Konturen je
> Koerper und gibt jedem einen Stil-Index aus seiner Position in
> `bodyNames`, `kSectionHatch` haelt die vier Varianten (45°/135°, zwei
> Abstaende). Zwei im Browser benachbarte Koerper koennen so nie dieselbe
> Schraffur bekommen. Zwei, die VIER auseinanderliegen, schon — das ist die
> ehrliche Grenze einer Index-Regel: sie weiss, wer in der Liste nebeneinander
> steht, nicht wer sich beruehrt.
>
> Die Schraffurlinien laufen jetzt senkrecht zu ihrer eigenen Richtung im
> Abstand `step` (vorher wurde in x geschritten, womit 45° und 135° sich um
> √2 in der Dichte unterschieden haetten).
>
> **Nebenbei ein Frame-Kosten-Fehler:** `sectionTriangles()` lief bei JEDEM
> Paint durch das komplette Netz jedes Koerpers. Der Schnitt selbst war
> gecacht, seine Auswertung nicht. `sectionSlices()` memoisiert auf demselben
> Schluessel, den `slicedSolid` schon benutzt (Skizzenebene + Identitaet jedes
> geschnittenen Netzes), und wird mit ihm zusammen geleert.
>
> **Ehrlicher Stand:** 10 neue Tests (`m222_section_outlines_test.dart`), die
> Randfaelle vorab in einer Simulation nachgerechnet (Quadrat mit Diagonale →
> EINE Schleife mit vier Punkten; Ring mit Loch → +100 und −4, also
> gegenlaeufig; 1e-9-Versatz → immer noch eine Schleife). Eine bestehende
> M168-Erwartung ist auf den neuen Kontrakt gezogen (`sectionSlices()` statt
> `sectionTriangles()`). CI-Lauf **32024481461**: **1831 gruen**, analyze 55
> Issues / 0 Errors. **Am Geraet nicht nachgeprueft** — und gerade hier heisst
> das etwas: dass die Dreiecke weg sind, sieht man erst auf dem Schirm.

> **M221 — „I cant select the inner circle to also extrude somehow."**
>
> Der eine offene Punkt aus M210, dort ausdruecklich NICHT behoben, weil nur
> eine Vermutung vorlag. Es sind ZWEI Fehler, und keiner davon liegt in der
> Regionen-Zerlegung — die war, wie M210 schon nachgewiesen hatte, richtig.
>
> **1. Der Anker.** Eine Auswahl wird als PUNKT plus Flaeche gespeichert, und
> dieser Punkt war `interiorPointOf(region.outer)` — der Innenpunkt der
> aeusseren SCHLEIFE, die von dem Loch in ihr nichts weiss. Bei einem Ring
> liegt der Schwerpunkt innerhalb der aeusseren Schleife, also ist er die
> Antwort: die Mitte des Lochs. Und exakt dieselbe Antwort gibt die Scheibe,
> die in diesem Loch liegt. Beide Regionen standen damit unter EINEM Anker:
>
> * `toggleSessionProfile` fand den Anker der Scheibe schon in der Liste und
>   tat nichts — das gemeldete Symptom, und zwar in BEIDER Reihenfolge;
> * `hasProfileAt` malte den Ring als ausgewaehlt, wenn die Scheibe gewaehlt
>   war;
> * `resolveProfiles` suchte den naechsten Anker — bei Abstand 0 auf beiden
>   Seiten entschied die Listenreihenfolge, ein Ring konnte also als volle
>   Scheibe neu aufgebaut werden.
>
> Neu ist `regionAnchor(region)`: der Innenpunkt der REGION, also innerhalb
> der aeusseren Schleife und ausserhalb jedes Lochs. Liegt der Schwerpunkt
> frei, bleibt es bei der billigen Antwort; sonst schneidet eine Handvoll
> waagerechter Linien die Region, und von allen Materialmitten auf diesen
> Linien gewinnt die mit dem groessten ABSTAND zu jeder Begrenzung.
>
> **Nicht die breiteste** — das war die erste Fassung, und die CI hat sie
> widerlegt: eine Zeile, die TANGENTIAL an einem Loch entlanglaeuft, kreuzt
> es null Mal, das Loch teilt diese Zeile also gar nicht und die Spanne sieht
> aus wie die ganze Sehne — waehrend ihre Mitte exakt auf dem aeussersten
> Punkt des Lochs sitzt. Der Ring Ø30 um ein Loch Ø10 bekam so den Anker
> `(0, 5)`, also genau auf den Rand seines eigenen Lochs. Ein Punkt auf einer
> Grenze ist der eine Punkt, dessen Innen/Aussen die naechste Tesselierung
> umdrehen kann. Der Abstand sagt, wofuer der Anker da ist.
>
> **Alte Dokumente.** Deren Ring-Auswahl traegt weiter den Mittelpunkt, und
> der ist von der Scheibe null entfernt — nach reiner Naehe wuerde die
> Scheibe die Auswahl beim ersten Rebuild stehlen. `regionForSel` (jetzt der
> eine gemeinsame Zuordner) bevorzugt darum eine Region, deren FLAECHE noch
> zur Auswahl passt, vor einer naeheren, die das nicht tut; die Flaeche ist
> das, was Ring und Scheibe ueber diesen einen Sprung hinweg trennt.
> `resolveProfiles` schreibt danach den neuen Anker zurueck, jedes Dokument
> wandert also beim naechsten Rebuild von selbst mit.
>
> **2. Die Ueberlagerung.** Ist eine Kindskizze offen, liegt Viewport2D ueber
> dem ganzen Viewport (`main.dart`) und reicht keinen Tipp an einen 3D-Pick
> weiter — es IST der Sketcher und kennt weder Profile noch Kanten noch
> Flaechen. Das Panel ging also ueber einer Flaeche auf, die jeden Pick
> verschluckte: gar kein Profil war waehlbar. `openChildSketch` macht die
> Gegenrichtung seit jeher (es bricht ein offenes Extrude ab); nur diese
> Richtung fehlte. Genau das zeigt auch das Log zur Meldung — der Benutzer
> war die ganze Zeit in Sketch7. Neu schliesst ein 3D-Befehl die offene
> Skizze (`_leaveSketchForCommand`, wie Inventor es tut) und Extrude zielt
> danach auf GENAU DIESE Skizze statt auf die neueste; Fillet/Chamfer und die
> Muster-Panels gehen durch dieselbe Stelle, ihre Picks sind dieselben Picks.
>
> **Ehrlicher Stand:** 16 neue Tests (`m221_profile_pick_test.dart`), die
> beide Fehler einzeln festnageln — der Anker-Test haelt ausdruecklich fest,
> dass die ALTE Regel fuer beide Regionen denselben Punkt liefert. CI-Lauf
> **32023838016** zu `b0e8d73`: **1821 gruen** (von 1805), analyze 55 Issues /
> 0 Errors = Ausgangsstand. Der Lauf davor (`32023295745`) hatte genau zwei
> rote, beide meine — siehe den Absatz ueber den Abstand; die Tangenten-Zeile
> haette kein Nachdenken gefunden, nur die CI. **Am Geraet nicht
> nachgeprueft.** Bewusste Abwaegung: die Flaechen-Vorliebe in
> `regionForSel` kann eine stark GEAENDERTE Skizze theoretisch anders
> zuordnen als die reine Naehe (eine andere Region liegt zufaellig naeher an
> der alten Flaeche) — der Preis dafuer, dass keine gespeicherte Ringauswahl
> beim Laden auf die Scheibe kippt.

> **M220 — eine Schrift IST Geometrie: im DXF, und extrudierbar.**
>
> „schriften sollen tatsächlich linien sein wie in dxf üblich … und jede
> schrift kann extrudiert werden". Sie konnte es nicht: eine Schrift war ein
> ETIKETT — ein `TextPainter` malte Pixel und gab nur eine Groesse zurueck.
> In keiner Datei, in keinem Profil, in keinem Koerper.
>
> Das System danach zu fragen geht nicht: `dart:ui` hat keine
> Glyph-Umriss-API, CoreText gibt es nur auf dem Geraet — auf dem Host, also
> in JEDEM Test, waere eine Schrift ein Etikett geblieben. Die Umrisse werden
> darum EINMAL vorab extrahiert (`tool/make_vector_font.py`) und als Daten
> ausgeliefert: jede Glyphe als move/line/quadratic in 1/1000 em, y nach
> oben, Ursprung auf der Grundlinie. Drei Familien (CAD Sans / CAD Mono /
> CAD Serif), ASCII plus Latin-1 — Umlaute und Eszett sind hier nicht
> optional —, dazu Ø, °, µ und die typografischen Striche. Aus den
> DejaVu-Fonts abgeleitet und umbenannt, wie deren Lizenz es verlangt.
>
> Die Kette: `vector_font.dart` flacht die Quadratiken adaptiv ab (0,002 em
> Sehnentoleranz, 16 µm bei 8 mm Schrifthoehe) und setzt eine Zeile;
> `text_geometry.dart` macht daraus Skizzengeometrie — eine GESCHLOSSENE
> Polylinie je Kontur, auf der Ebene der Schrift. Die Punze eines „O" ist
> eine eigene Kontur, `regionsFrom` verschachtelt sie also als Loch und der
> Kernel bekommt Aussen + Loch statt einer vollen Platte.
>
> **Bewusst NICHT in `SketchModel.geometry`:** eine Schrift ist EIN Objekt
> mit EINEM Anker (Inventors auch), ihr Umriss dagegen hunderte Punkte —
> jeder davon waere eine Solver-Unbekannte, ein Griff unter dem Finger und
> ein Eintrag in jedem Undo-Schnappschuss. Die Schrift bleibt parametrisch im
> Sidecar, die Kurven werden abgeleitet und je Text gecacht. Aus demselben
> Grund laufen Textschleifen nicht durch die planare Anordnung: eine
> Glyphenkontur ist bereits geschlossen, und die Anordnung ist quadratisch in
> der Segmentzahl (eine Textzeile hat einige tausend).
>
> **Ehrlich:** die Speicher-DXF der Skizze enthaelt weiterhin keinen Text (er
> lebt parametrisch im Sidecar — nur der EXPORT bekommt die Kurven), ein
> importiertes DXF mit TEXT-Entitaeten wird weiterhin kein Text, und eine
> alte „Georgia"-Schrift behaelt ihre Groesse, ist aber jetzt CAD Serif.
> 29 neue Tests, **1805 gruen** (CI-Lauf 31970418590). **Geraete-Test offen.**

> **M219 — ein Trim an einer Spline schneidet die KURVE, und Splines sind
> nicht mehr grobaufgeloest.**
>
> Zwei Geraete-Meldungen, zwei getrennte Ursachen.
>
> **1. „I can't trim splines. It's really fucked up."** Eine Spline ist hier
> eine POLYLINIE aus Kontroll-/Stuetzpunkten plus einem Dart-seitigen Tag —
> der vendorierte QCAD-Kern ist ohne OpenNURBS gebaut, es gibt also gar keine
> Spline-Entitaet zu schneiden. Trim und Split fielen darum in den
> Polylinien-Zweig und schnitten das KONTROLLPOLYGON: bei einer CV-Spline
> beruehrt das gewaehlte Segment die Kurve nicht einmal. Zurueck kamen gerade
> Stuecke, neu als Spline getaggt — eine andere Kurve, an einer anderen
> Stelle, ohne die Form. Eine Ellipse traf es schlimmer: ihre drei Vertices
> sind Mitte/Haupt-/Nebenachse, das „angeklickte Segment" war also ein
> Radius.
>
> Jede Kurve, die diese App auf einer Polylinie traegt, ist stueckweise
> KUBISCH — eine Kette kubischer Bezier-Segmente stellt sie also EXAKT dar,
> und eine Bezierkette schneidet exakt, weil de Casteljau an jedem Parameter
> ohne Naeherung teilt. `bezier.dart` rechnet um: geklemmte B-Spline per
> Boehm-Knoteneinfuegung, periodische ueber den uniformen Basiswechsel,
> Catmull-Rom in geschlossener Form, Ellipse als 16 Bogensegmente — alle vier
> in den Tests gegen die bestehenden Sampler auf 1e-9 geprueft. Das Stueck
> wird als `Geo.splineBez` zurueckgelegt: eine Polylinie, deren Vertices die
> Kontrollpunkte der Kette SIND, also ohne neue Entitaet, ohne Knotenvektor
> und mit unveraendertem Round-Trip durch DXF, Solver, Undo und
> `.splines.json`. Ein Zahnrad hat keine kubische Form (Evolventen-Generator)
> — es wird beim Schneiden GEBACKEN, denn ein halbes Zahnrad darf kein Tag
> behalten, das „lies meine Punkte als Parameterblock" bedeutet.
>
> Zwei Folgefehler aus derselben Ecke: `_carry` reicht den Spline-Tag nur bei
> gleicher Vertex-ZAHL weiter (das trennt „dieselbe Entitaet, neue Zahlen"
> von „eine neue, daraus abgeleitete"), und `_transformGeoRaw` verlor den
> Parameterblock eines Zahnrads — Move/Rotate/Mirror loeschten dessen Zaehne
> still.
>
> **2. „Also splines are low resolution sometimes."** `splineCurveFor` gab
> die Kurve auf echte Boegen dezimiert zurueck, mit fuenf Punkten je Bogen.
> Diese Kette gehoert in den 3D-Pfad (dort macht `arcFitLoop` daraus wieder
> exakte Bulges, damit eine extrudierte Spline zylindrische Flaechen bekommt)
> — als ANZEIGE-Kurve ist sie schlecht, denn die eingehaltene Toleranz ist
> die des BOGENS, nicht die der fuenf Sehnen darin: gemessen 25 Punkte und
> 10-mm-Sehnen auf einer sanften 200-mm-S-Spline, 0,17 mm neben der Kurve.
> Anzeige, Picking, Snap und Verschneidung bekommen jetzt die echte Kurve,
> adaptiv unterteilt; der Painter reicht eine aus dem ZOOM abgeleitete
> Toleranz durch (ein Fuenftel Pixel, auf Zweierpotenzen gerundet, damit eine
> Pinch-Geste den Memo nicht zerreibt). Nur die Profilkette zum Kernel bleibt
> auf Boegen — mit groesserem Budget, denn bei 64 war es vor dem Ende einer
> langen Spline aufgebraucht und `_greedySpans` deckte den Rest mit EINEM
> Bogen ab.
>
> Dichteres Abtasten kostet, also wurde derselbe Pfad billiger: `intersections()`
> baut die Segmentkette der zweiten Entitaet nicht mehr je Segment der ersten
> neu und verwirft nicht ueberlappende Paare per Bounding Box; die abgetastete
> Kurve wird auf einem Hash der Zahlen memoisiert.
>
> 31 neue Tests, lokal **1774 gruen**. **Geraete-Test offen.**

> **M218 — eine Skizze in 3D lange druecken und GENAU DIESE als DXF
> exportieren.**
>
> „I also want to be able to long press a sketch in 3d mode and export as dxf
> only this sketch from the context menu." Ein Teil verlaesst die App als
> STEP, ganz. Was eine Maschine schneidet, ist EIN Profil — und das kam bis
> hierher nur heraus, indem man es als eigenes 2D-Dokument neu zeichnete.
>
> **Der Export.** `childSketchExportPath(part, sketch)` ist der teil-seitige
> Zwilling von `sketchExportPath` und ausdruecklich keine zweite
> Implementierung davon: die M112-Regel — Konstruktions- und
> Mittelliniengeometrie geht auf den nicht plottenden Layer „Defpoints",
> weil der Stil-Tag in einem Sidecar reist, den das DXF nicht tragen kann —
> ist jetzt `_writeExportDxf`, und beide Aufrufer gehen hindurch. Die Datei
> haelt die EIGENEN 2D-Koordinaten der Skizze, nicht ihre Lage im Teil; sie
> heisst „<Teil> - <Skizze>.dxf", weil eine Kindskizze nur durch beides
> identifiziert ist. Ein offenes Teil wird vorher geschrieben, ein
> geschlossenes kopflos geladen und wieder verworfen (M214: Exportieren ist
> keine Navigation und darf keinen Tab aufmachen).
>
> **Das Menue.** `sketch3dMenuItems()` — Edit Sketch, Hide, Export DXF…,
> Share DXF…. Kein „Show" (nur eine SICHTBARE Skizze kann unter dem Finger
> liegen) und vor allem kein Delete: das steht im Browser, wo die Zeile
> eindeutig ist; ein langer Druck im Viewport kann auf einer Kurve landen,
> die man nicht gemeint hat, und das darf nie eine Skizze kosten.
>
> **Die Geste.** Ein Timer im rohen Listener, NICHT `onLongPress` — ein
> Long-Press-Recognizer gewinnt in der Arena durch Stillhalten und nimmt den
> Ein-Finger-Orbit mit; jede langsame Beruehrung auf leerer Flaeche haette
> die Geste gekostet. Scharf geschaltet wird er nur, wenn der Druck AUF einer
> Skizzenkurve beginnt. 600 ms und 8 px Abbruch, dieselben Zahlen wie im
> 2D-Viewport seit M53. Der Druck verzehrt seinen Kontakt, der Tipp danach
> laeuft also nicht zusaetzlich als Pick und der Finger orbitet das Modell
> nicht hinter dem Menue weg.
>
> 17 neue Tests, **1745 gruen**, analyze 52 Issues / 0 Errors. **Ehrlich:**
> die UIKit-Haelfte (Action Sheet, Files-Exporter, Share Sheet) laeuft auf
> dem Host nicht und ist nur ueber ihren Kontrakt festgenagelt.
> **Geraete-Test offen.**

> **M217 — Delete Face und Direct Edit, Kernel bis Ribbon (Shim v20).**
>
> **Kernel (`b3d1f15`).** Delete Face bildet 1:1 auf
> `BRepAlgoAPI_Defeaturing` ab — OCCTs eigene Beschreibung ist „removal of
> features from a shape", und wie es die Wunde schliesst, IST Inventors Heal:
> die Nachbarn werden verlaengert, bis sie sich schneiden. `heal = 0` wird
> ABGELEHNT statt genaehert: Inventors ungeheilte Variante macht aus dem Teil
> einen FLAECHEN-Koerper und sagt das im Browser, und diese App hat keine
> Flaechenkoerper — jeder `KernelSolid` ist ein Volumen mit Booleschen und
> einem STEP-Produkt. Nein ist die ehrliche Antwort, solange das so ist.
>
> Direct > Move/Size zieht jede gewaehlte Flaeche entlang des Deltas auf und
> fuegt das aufgezogene Volumen hinzu oder schneidet es weg — je Flaeche
> entschieden, am Vorzeichen gegen ihre eigene Aussennormale. Der Lehrbuchweg
> (eine `BRepTools_Modification`, die die Flaeche verschiebt und die Nachbarn
> nachtrimmt) zeigt seine Fehlerfaelle erst an echten Formen, und das
> ungeprueft auszuliefern waere genau die tot-lebendige Bedienung, die dieser
> Zweig gerade abgeraeumt hat. Der Prismenweg ist EXAKT, wo die angrenzenden
> Waende parallel zur Bewegung stehen — also an jedem prismatischen Teil, und
> fuer die greift man zu Direct Edit; an einem konischen Nachbarn weichen
> beide ab, und dann wird es dem Aufrufer GESAGT statt still genaehert.
> Direct > Scale bekommt einen eigenen Einstieg, weil `occt_transform`
> nicht-starre Matrizen mit Absicht ablehnt (v2): eine Platzierung darf nie
> skalieren, Skalieren ist ein Befehl fuer sich.
>
> `occt_mesh_face_ids` ist der Ermoeglicher und loest fuer Flaechen genau
> das, was `occt_mesh_edge_ids` fuer Kanten geloest hat: `occt_mesh_create`
> UEBERSPRINGT eine Flaeche, die es nicht triangulieren kann — Mesh-Index und
> topologischer Index laufen also auseinander, sobald eine einzige ausfaellt.
> Gepickt wird der Mesh-Index, gebraucht der topologische; ein Pick, der auf
> -1 abbildet, wird abgewiesen statt an ein Loeschen mit falschem Index
> weitergereicht. **v20 und nicht v18+1:** zwei Zweige hatten beide v17
> beansprucht (main fuer `occt_mirror`, dieser fuer
> `occt_export_step_named`), dieser hatte darauf schon v18 gebaut, der Merge
> nahm v19.
>
> **Feature-Ebene (`c0ec375`).** `FacePick` ist der Flaechen-Zwilling von
> `EdgeSel`, aus demselben Grund: ein topologischer Index ist ueber einen
> Rebuild hinweg bedeutungslos. Der Anker ist der Mesh-SCHWERPUNKT der
> Flaeche, nicht die `Location` ihrer Flaeche — zwei koplanare Flaechen eines
> Koerpers teilen sich eine Location und waeren ununterscheidbar, ihre
> Schwerpunkte liegen Meter auseinander. Er ist FLAECHENGEWICHTET, damit eine
> in ein grosses Dreieck und zwanzig Splitter zerlegte Flaeche ihren Mittelpunkt
> dort hat, wo das Material ist. Ein Typwechsel oder eine gekippte Normale
> disqualifiziert, genau wie eine Linie, die ein Bogen wurde, es fuer
> `EdgeSel` tut.
>
> Eine Flaechen-Aenderung wird ein echtes ZEITSTRAHL-Feature, kein Griff in
> den Solid: alles in dieser App baut sich aus dem Zeitstrahl neu auf, eine
> Aenderung daneben wuerde der naechste Rebuild verwerfen — das Modell sieht
> richtig aus, bis es das nicht mehr tut. Eine Ablehnung entfernt das Feature
> wieder, ein abgelehnter Edit laesst den Zeitstrahl also so, wie der
> Benutzer ihn vorgefunden hat. Direct > Scale skaliert um die Mitte der
> Bounding Box, nicht um den Weltursprung, sonst schleudert es ein
> ausserhalb modelliertes Teil durch die Szene.
>
> **Nachtrag (`07e3790`).** Die CI fand drei echte Fehler: `FaceSel` gab es
> schon (mains M213 fuer Skizze-auf-Flaeche und „To Face"), meine zweite
> Klasse gleichen Namens heisst jetzt `FacePick` — der bessere Name, denn sie
> ist, was ein PICK erzeugt hat. `viewport3d.dart` importiert die FFI-Ebene
> mit Absicht nicht und braucht sie auch nicht. Und die vier Kernel-Fakes
> ohne `noSuchMethod` brauchen jede neue Schnittstellen-Methode.
>
> **Im Ribbon** verlassen Delete Face und Direct das Klappmenue — die Regel
> aus M216 gilt in beide Richtungen. Das Direct-Flyout traegt Inventors fuenf
> Eintraege; **Rotate ist gelistet und inert**, weil das Drehen einer Flaeche
> dieselbe `BRepTools_Modification` braucht.
>
> Tests: `m217_face_edit_test.dart` plus Smoke `[34]` gegen echte Geometrie —
> ein 20-mm-Klotz mit 5-mm-Bohrung, Delete Face auf der Zylinderflaeche muss
> das Volumen des vollen Klotzes exakt wiederherstellen (Log: `8000.0000`),
> ein ungeheiltes Loeschen muss abgelehnt werden, eine Deckflaechen-
> Verschiebung addiert genau die aufgezogene Platte abzueglich der Bohrung
> darin (`8036.5046`), und x2 skaliert ist 8x Volumen (`51433.6294`).
> **Am Geraet nicht nachgeprueft.**

> **M216 — der 3D-Ribbon zeigt, was gebaut ist; der Rest ist einen Tipp
> tiefer.**
>
> Zwei Drittel des Teil-Ribbons taten nichts: neun von zwoelf Modify-
> Eintraegen, drei von sechs Create-Eintraegen und UCS waren Beschriftungen
> mit `null`-Callback — und Hole war ein Knopf in voller Groesse, dessen
> `onTap` `() {}` war, genau die leere Closure, die M157 am Plane-Knopf
> angeprangert hat. Ein sichtbares Bedienelement muss etwas tun; Schweigen
> liest sich als kaputt, und ein grosser, fertig aussehender Knopf ist die
> teuerste Fassung dieser Luege.
>
> Sie stehen jetzt hinter dem ▼ des Panel-Titels, so wie es der SKIZZEN-
> Ribbon seit M50 macht. Geloescht wird nichts: ein ungebautes `OverItem`
> reicht `null` durch, `_OverRow` zeichnet es gedimmt und untippbar — die
> Roadmap bleibt sichtbar und ehrlich, statt dass der Ribbon so tut, als
> waeren diese Befehle nie geplant gewesen.
>
> **Die Regel ist jetzt ein TYP und keine Konvention mehr:** der Callback von
> `col()` ist nicht mehr nullable und das `?? () {}` ist weg — ein ungebauter
> Befehl kann gar nicht mehr in einer sichtbaren Spalte stehen, er MUSS in
> die `over`-Liste. Genau dieses Fallback ist es, hinter dem hier neun tote
> Knoepfe fertig aussahen.
>
> Stand nach dem Merge mit mains Muster-Befehlen — ungebaut und damit im
> Klappmenue sind noch: **Create ▼** Emboss, Derive, Decal; **Modify ▼**
> Hole, Shell, Draft, Thread, Combine, Thicken/Offset, Split; **Work ▼** UCS.
> (Der Skizzen-Ribbon fuehrt dieselbe Liste fuer Points, Center Point,
> Driven Dimension und Show Format.)

> **M215 — Work Axis und Work Point, jede Inventor-Methode, aus dem Pick
> erschlossen.**
>
> Das Work-Features-Panel hat Plane seit M151; Axis, Point und UCS waren
> Symbol und Beschriftung mit `onTap: null`. Gebaut sind jetzt Axis und
> Point — zuerst gegen die Autodesk-Hilfe recherchiert: Inventor dokumentiert
> acht Achsen- und neun Punkt-Methoden, und die beiden wichtigsten sind die
> ALTEN Eintraege „Axis" und „Point", die gar nicht fragen, welche Methode
> gemeint ist, sondern es aus dem Angetippten erschliessen. Genau diese Form
> hat das hier.
>
> `WorkRef` modelliert einen Pick danach, was er BEITRAEGT, nicht danach, was
> er ist: eine kreisrunde Kante ist gleichzeitig ein Punkt (Mittelpunkt),
> eine Achse und eine Ebene, und was davon zaehlt, entscheidet der jeweils
> andere Pick. Nach Typ braeuchte es einen Fall je PAAR von Typen, nach
> Beitrag einen Fall je Inventor-Methode — also genau die dokumentierte
> Liste. Die Geometrie steht in `work_features.dart`: kein Flutter, kein
> Kernel, kein AppState, also auf dem Host testbar.
>
> **Bedienung, mit Absicht so:** ein Pick, der die Antwort ALLEIN festlegt,
> committet sofort (Kante antippen, Achse da); nur was nicht allein stehen
> kann, wartet auf einen zweiten. Die Folge deckt sich mit Inventor — der
> generische Befehl kann „Through Two Points" nicht aus zwei kreisrunden
> Kanten bauen, weil die erste schon geantwortet hat, und genau darum gibt es
> die benannten Methoden im Menue. Ein Pick, der nicht funktionieren kann,
> wird VERWORFEN und der Befehl bleibt scharf: ein Fehlgriff kostet diesen
> Tipp und sonst nichts. Ein Danebentippen auf leere Flaeche wiederholt die
> Aufforderung, statt abzubrechen. Und eine Ablehnung traegt das Mass mit
> sich: zwei windschiefe Kanten melden, um wieviel sie sich verfehlen.
>
> **Shim v18:** die Flaechen-Datensaetze fuer Kegel, Kugel und Torus sind
> gefuellt. Sie trugen bisher nur ihren TYP, die Slots 1..10 blieben null —
> „Through Revolved Face", „Center of Sphere" und „Center of Torus" haetten
> also still ein Feature im WELTURSPRUNG erzeugt, ohne Fehler. Rein additiv.
>
> **Gezeichnet wird in BEIDEN Painters**, und das ist der Punkt: auf iOS ist
> die Szene RealityKit, `_ScenePainter` laeuft dort nie — eine nur dort
> gezeichnete Achse waere auf dem Host sichtbar und auf dem Geraet unsichtbar
> gewesen. Im Bildschirmraum, also ohne Swift: eine Achse sind zwei
> projizierte Punkte, ein Punkt ein kleines Kreuz. (Eine Arbeits-EBENE
> braucht Tiefe und geht darum durch die Szenen-Payload.)
>
> **UCS bleibt bewusst inert.** Es ist ein Koordinaten-SYSTEM mit eigenem
> Triad und eigenen Platzierungsgesten, keine dritte Variante dieser beiden —
> und ein halb funktionierender Knopf ist schlimmer als einer, der sagt, dass
> er nicht gebaut ist (M157).

> **M214 — ein exportiertes Loch ist ein Loch, eine Verrundung eine
> Verrundung, und Teilen ist kein Oeffnen.** (Ausfuehrliche Analyse:
> `M214_STEP_EXPORT_ANALYSIS.md`.)
>
> Zwei gemeldete Fehler, beide in Dart, bevor der Kernel ueberhaupt erreicht
> wird.
>
> **1. Loecher und Verrundungen fehlten in der STEP-Datei**, obwohl sie auf
> dem Schirm zu sehen waren. Der Export sammelte `f.solid` von JEDEM Feature.
> Jedes Feature haelt aber die laufende Anhaeufung an seiner eigenen Stelle —
> ein Teil aus Klotz → Bohrung → Verrundung reichte dem Kernel also drei
> Solids, und der VEREINIGTE sie. Vereinigung ist exakt die Umkehrung dessen,
> was die spaeteren Features taten: `Klotz ∪ (Klotz − Bohrung)` ist der
> Klotz. Der Export machte die Modellierung rueckgaengig. Additive Features
> ueberlebten, weshalb es meistens zu funktionieren schien.
> `partExportBodies()` ist jetzt die eine benannte Definition von „das Modell
> als Liste von Koerpern", mit derselben Regel
> (`solid` / `!consumedByJoin` / `!rolledBack`), die Viewport, RealityKit-
> Szene und Galerie-Thumbnail laengst benutzen.
>
> **2. Ein Teil aus der Galerie zu teilen OEFFNETE es.** `partExportStep`
> lief durch `openPart`, das einen Tab anlegt, das Teil aktuell macht, das
> Werkzeug loescht und den Viewport neu baut; die lokale Variable `wasLoaded`,
> die das rueckgaengig machen sollte, wurde berechnet und nie gelesen.
> `openPart` ist jetzt geteilt: `_loadPartModel()` liest und faltet ein Teil
> und fasst keinen UI-Zustand an, `openPart` ist das plus die Tab-Buchhaltung.
> Der Export nimmt den kopflosen Weg und entsorgt die Kopie danach (sie
> besitzt ein B-Rep je Koerper und eine Solver-Engine je Kindskizze).
>
> **Produktionshaertung der geschriebenen Datei (Shim-ABI → v17):**
> `occt_export_step_named()` schreibt N Koerper als N BENANNTE Produkte —
> kein Verschmelzen mehr (der alte Weg vereinigte den ersten Solid mit sich
> selbst als „billige Kopie", verlor die Koerper-Identitaet und liess bei
> einer fehlschlagenden Booleschen den ganzen Export scheitern). Einheiten
> auf MM festgenagelt und ZURUECKGELESEN — der Export wird verweigert statt
> geschrieben, wenn es nicht griff, denn `Interface_Static` ist
> prozessglobal und die App liest STEP im selben Prozess: die Verliererseite
> dieser Wette ist ein um 25,4 falsch gefraestes Teil. Schema auf AP214IS
> (was der Header immer behauptet hat), Assembly aus, `surfacecurve` auf 1,
> damit getrimmte Zylinderflaechen — also jedes Loch dieser App — Leser
> ueberleben, die aus PCurves rekonstruieren. `FILE_NAME` traegt den
> Dokumentnamen, ein Transferfehler NENNT den Koerper, veraltete Exporte
> werden vorher geloescht, eine Null-Byte-Datei wird gemeldet statt geteilt.
>
> Tests: es gab **keinerlei** Abdeckung des Export-Pfads — so ist das
> ausgeliefert worden. `m214_step_export_test.dart` nagelt die Koerpermenge
> fest (Bohrung, Verrundung, beides, zwei Koerper, End of Part, versteckte
> Koerper), was beim Kernel ankommt, den Veralteten- und den Leerdatei-Pfad
> und dass Exportieren keine Navigation ist. Smoke `[33]` gegen echtes OCCT:
> zwei getrennte Kaesten muessen als zwei Solids mit zusammen 1125 mm³
> zurueckkommen, mit beiden Namen, dem Dokumentnamen und Millimetern in der
> Datei (Log: `[33] total volume 1125.0000 (want 1125)`).

> **M213 — die fuenf Dinge, die M212 ausdruecklich NICHT konnte. Jetzt
> koennen sie es: Flaechen-Herkunft, gemusterte Verrundungen, Muster entlang
> einer KURVE (mit Curve Length und Start), unregelmaessige Abstaende und
> Winkel, und die Variable Orientierung.**
>
> **1. Flaechen-Herkunft — „welches Feature hat diese Flaeche gemacht?"**
> In Inventor waehlt man ein Feature durch Anklicken einer seiner Flaechen.
> Hier ging das nicht: nach dem Fold steht EIN Koerper pro Body, und dessen
> Flaechen wissen nichts mehr von der Extrusion, aus der sie kamen. OCCTs
> eigene Boolean-History (`Modified`/`Generated`) exportiert der Shim nicht,
> und sie durch jede Operation zu faedeln waere eine neue ABI pro Feature-Art.
>
> Also wird die Herkunft GEOMETRISCH zurueckgewonnen, aus etwas, das der Fold
> ohnehin in der Hand hat: dem eigenen Solid jedes Features, in dem einen
> Moment, bevor die Boolesche es wegfaltet. Eine Boolesche BESCHNEIDET
> Flaechen, aber sie VERSCHIEBT sie nicht — die Flaeche eines Ergebnisses
> liegt weiter auf einer Flaeche, die einer der Operanden mitgebracht hat.
> Verglichen wird darum die FLAECHE im Sinne der unendlichen Ebene bzw. des
> ganzen Zylinders, nicht das beschnittene Stueck; und die Orientierung wird
> bewusst ignoriert, denn ein Loch hat die Wand des Werkzeugs mit umgedrehter
> Normale — genau deshalb ist ein Schnitt ueberhaupt zuordenbar. Ein
> koerper-veraenderndes Feature beansprucht nur, was es HINZUGEFUEGT hat
> (Ergebnis minus Basis), sonst wuerde eine Verrundung jede Flaeche des
> Koerpers fuer sich reklamieren. Und eine Flaeche, die niemand erklaert,
> bleibt UNBEKANNT statt geraten zu werden.
>
> **2. Verrundungen und Fasen lassen sich mustern.** Eine Verrundung ist
> keine Form, sondern die Aenderung einer — es gibt kein Volumen zu kopieren.
> Wiederholt wird darum die OPERATION: die Kanten-Fingerabdruecke werden an
> die Occurrence VERSCHOBEN (Laenge, Kurventyp und Radius aendert eine starre
> Bewegung nicht — genau darum ist ein Fingerabdruck an der Kopie
> wiederfindbar), gegen die Kanten des laufenden Ergebnisses aufgeloest und
> derselbe Blend erneut ausgefuehrt. Die Werkzeuge werden dafuer in
> BAUMREIHENFOLGE sortiert, nicht in Pickreihenfolge: eine Verrundung muss
> nach der Extrusion laufen, die sie rundet, sonst sucht sie Kanten, die es
> an dieser Stelle noch nicht gibt. Eine Verrundung ALLEIN wird abgelehnt
> („waehle auch das Feature, das sie formt"), und ein Muster eines Musters
> ebenfalls.
>
> **3. Reihen entlang einer KURVE.** Inventor laesst Zeilen und Spalten
> „lines, arcs, splines, or trimmed ellipses" sein. Der Richtungs-Pick nimmt
> jetzt jede Skizzenkurve: eine Gerade bleibt eine Richtung, alles andere
> wird ein PFAD, und die Occurrences werden nach BOGENLAENGE darauf verteilt.
> Damit gibt es endlich auch die dritte Distribution — **Curve Length**, die
> auf die Kurve passt, die wirklich da ist — und den **Start** (Inventors
> Extents-Abschnitt, der jetzt echten Inhalt hat: wo auf der Kurve das
> Original sitzt, per Tipp gewaehlt). Die Orientierungsmethode gehoert
> ebenfalls hierher: „Identical" behaelt die Lage des Originals, „Direction A"
> dreht jede Kopie in die Tangente. Ueber das Kurvenende hinaus wird das
> letzte Segment VERLAENGERT statt geklemmt — ein Muster, das zu lang ist,
> laeuft sichtbar hinaus, statt alle restlichen Kopien still aufeinander zu
> stapeln.
>
> **4. Irregular Distance / Irregular Angle** (Inventor 2026). Ein Eintrag
> pro Schritt ersetzt dessen gleichmaessigen Versatz — also genau dieselbe
> Groesse, die die Verteilung sonst ausrechnet, weshalb nichts weiter unten
> wissen muss, welche Occurrence unregelmaessig ist. Neu angelegte Eintraege
> starten auf dem gleichmaessigen Wert, aendern also erst dann etwas, wenn man
> sie aendert. Die Eintraege stehen SORTIERT im Rebuild-Schluessel: die
> Iterationsreihenfolge einer Map ist die Einfuegereihenfolge, und zwei
> gleiche Muster, in anderer Reihenfolge eingegeben, duerfen nicht zwei
> Schluessel ergeben.
>
> **5. Variable Orientierung (Follow Face)** beim skizzengesteuerten Muster:
> mit gewaehlter Flaeche wird jede Kopie von der Normalen am ORIGINAL auf die
> Normale dort gedreht, wo sie landet (aus dem Anzeige-Mesh abgetastet) — ein
> Noppenmuster auf einer gewoelbten Schale steht damit aus der Schale heraus,
> statt mit dem Original mitzukippen. Ein Punkt, der die Flaeche verfehlt,
> behaelt die Original-Normale, statt auf irgendetwas zu kippen.
>
> **Ehrlicher Stand:** 26 weitere Tests im selben File (`m212_pattern_3d_test`,
> Gruppen „M213 — …"), Suite **1643 gruen**, analyze 50 Issues / 0 Errors =
> Ausgangsstand. **Am Geraet nicht nachgeprueft.** Die Flaechen-Herkunft ist
> eine HEURISTIK und sagt das auch: sie ist auf Ebenen und Zylinder exakt
> (analytische Flaechensaetze des Shims), bei Kegel/Kugel/Torus/Spline liefert
> der Shim keine Parameter, dort entscheidet die Lage — und wenn nichts passt,
> lautet die Antwort „unbekannt, waehle im Browser".

> **M212 — die vier MUSTER im Teil: Rechteckig, Kreisfoermig,
> Skizzengesteuert, Spiegeln. „Integrate all pattern tools in 3d mode",
> recherchiert und gebaut wie in Inventor.**
>
> Bis hierher war die Pattern-Gruppe der Teil-Ribbon eine Attrappe: vier
> Knoepfe mit `null` dahinter. Jetzt sind es vier echte Befehle mit EINEM
> modelosen Eigenschaften-Panel, 1:1 nach den Inventor-Screenshots
> (Input Geometry / Direction A+B bzw. Orientation bzw. Placement bzw. Mirror
> Plane / Output Geometry, plus die senkrechte Leiste daneben, die zwischen
> den Befehlen und zwischen „Features" und „Solid" umschaltet).
>
> **1. Der Kernel konnte nicht spiegeln — mit Absicht.** `occt_transform`
> lehnt jede Matrix ab, deren 3x3-Teil nicht Determinante +1 hat („scale,
> shear and mirror are refused"), und das ist richtig: eine nicht-starre
> Matrix an einer PLATZIERUNG ist viel wahrscheinlicher ein Fehler des
> Aufrufers als eine gewollte Spiegelung. Eine Spiegelung, die beim NAMEN
> gerufen wird, kann dieser Fehler nicht sein — also Shim **v17**:
> `occt_mirror(shape, {p, n})` ueber `gp_Trsf::SetMirror(gp_Ax2)`. Dazu die
> Orientierungspruefung: eine Reflexion dreht einen Koerper von innen nach
> aussen, und OCCTs Boolesche lesen die Orientierung — ein unkorrigiertes
> Spiegelbild SCHNEIDET also, wo es fuegen soll. Der Shim misst das Volumen
> und dreht die Form um, wenn es negativ zurueckkommt. Smoke `[13b]` prueft
> Lage, Volumen, Gueltigkeit UND dass sich das Spiegelbild mit dem Original
> vereinigen laesst.
>
> **2. Ein Feature, vier Platzierungsregeln.** `PatternFeature` ist ein
> koerper-veraenderndes Feature wie Verrundung und Fase: es verzehrt den
> Koerper, der es erreicht, und gibt das Ergebnis weiter. Das ORIGINAL ist
> nie eine seiner Occurrences — es steckt schon im Koerper, weiter oben, und
> genau deshalb zaehlt Inventor das Original als „Occurrence 1".
>
> Die Platzierungs-Arithmetik (`patternOccurrences`) ist rein und
> host-testbar, denn genau dort sitzen die Ecken, die in einem Muster
> traditionell falsch sind: der 360°-Umlauf teilt durch die ANZAHL (sonst
> liegen die erste und die letzte Bohrung uebereinander), eine „fitted"
> Teilstrecke durch die LUECKEN, Midplane zentriert die Spanne auf das
> Original — und die Occurrence, die dabei auf dem Original landet, faellt
> weg, sonst wuerde ein Koerper mit sich selbst verschmolzen.
>
> **Identical vs. Adjust** ist Inventors Creation Method, und beide tun hier
> wirklich etwas Verschiedenes: Identical baut das Werkzeug EINMAL und
> platziert es n-mal; Adjust baut jede Occurrence dort neu, wo sie landet —
> `placedFrame` schiebt die Skizzenebene mit, also loest „To Next" /
> „Through All" gegen den Koerper UNTER dieser Occurrence auf. Fuer die
> gespiegelte Occurrence braucht es dazu `mirroredFrame`: eine Reflexion
> macht aus einem rechtshaendigen Rahmen einen linkshaendigen, und den nimmt
> kein Kernel an — also wird v negiert UND das Profil in v gespiegelt
> gelesen. Die beiden gehoeren untrennbar zusammen; nur den Rahmen zu
> spiegeln baut die ORIGINALFORM am gespiegelten Platz: richtige Stelle,
> falsches Teil.
>
> **3. Was ehrlich verweigert wird.** Eine Verrundung ist keine Form, sondern
> die Aenderung einer Form — es gibt kein Werkzeugvolumen zu kopieren, also
> sagt das Feature das (`"... cannot be patterned — pattern the feature it
> shapes"`) statt die Auswahl still fallenzulassen. Ebenso: eine Quelle
> UNTERHALB des Musters (das waere ein Zyklus), eine Quelle auf einem ANDEREN
> Koerper (der Rebuild-Schluessel ist die Kettenhash DIESES Koerpers — eine
> fremde Quelle koennte sich aendern, ohne dass das Muster es merkt), ein
> importierter Koerper, ein Kernel ohne Spiegelung. Und: sind ALLE
> Occurrences unterdrueckt, wird der Koerper KOPIERT statt weitergereicht —
> zwei Features mit einem Solid sind ein doppeltes Free auf dem Geraet.
>
> **4. Bedienung.** Features werden im MODELLBROWSER gewaehlt (im
> Grafikfenster steht ein gefalteter Koerper, dessen Flaechen keinem Feature
> mehr gehoeren) — beide Browser, mit Markierung; Richtung/Achse per Tipp auf
> eine gerade oder RUNDE Kante (bei einer runden ist die Achse die nuetzliche
> Antwort, nicht die Sehne — gelesen aus den analytischen Kurvensaetzen des
> Meshes, nicht aus der Tesselierung), auf eine Skizzenlinie oder eine
> Ursprungsachse; Spiegelebene per Flaeche, Arbeitsebene oder Ursprungsebene
> (plus die drei Knoepfe im Panel); die Punkte eines skizzengesteuerten
> Musters per Tipp auf einen Skizzenpunkt oder auf die Skizzenzeile im
> Browser. Einzelne Occurrences lassen sich im Browser unterdruecken, wie in
> Inventor. Esc/Cancel steigen erst aus dem PICK aus, dann aus dem Panel.
>
> **Ehrlicher Stand:** 58 neue Tests (`m212_pattern_3d_test.dart`). Suite
> **1617 gruen**, analyze 50 Issues / 0 Errors = Ausgangsstand. **Am Geraet
> nicht nachgeprueft.**
>
> **Der Shim ist inzwischen gebaut und GELAUFEN** — nachgelesen im Log, nicht
> am Haken: CI-Lauf `31383036783`, Zweig `ci-debug-logs-occt`, Datei
> `ci-logs-occt/smoke.log`:
>
> ```
> Prototype OCCT shim v17 (OCCT 7.9.3) (shim ABI v17)
> [13b] mirrored bbox x[-10.000,0.000]
> OCCT SMOKE: PASS
> ```
>
> Der Kasten bei x=[0,10], an x=0 gespiegelt, liegt exakt bei x=[-10,0]; PASS
> heisst zugleich, dass die uebrigen `[13b]`-Pruefungen durchgingen — Volumen
> erhalten, Form gueltig, Original + Spiegelbild lassen sich VEREINIGEN (also
> ist die Orientierung korrigiert), Spiegelung an einer versetzten Ebene, und
> die beiden Zurueckweisungen. Der iOS-Job (`occt-ios-static`) ist ebenfalls
> gruen: der Shim uebersetzt fuer arm64 und `nm` findet die Symbole.
>
> **Bewusst NICHT enthalten** (und darum hier genannt statt versteckt): ein
> Feature durch Antippen seiner FLAECHE waehlen (dafuer fehlt die
> Flaechen-Herkunft — der Koerper ist gefaltet), Verrundung/Fase als
> Musterquelle, Inventors „Curve Length"-Distribution und der Start-Punkt
> pro Richtung (beides braucht Muster entlang einer KURVE), die Irregular
> Distance/Angle aus Inventor 2026, und die variable Orientierung
> (Follow Face) beim skizzengesteuerten Muster.

> **M211 — eine Meldung zu Build `1a0bb61`, zwei Fehler, eine Frage: von
> welcher SEITE der Ebene schauen wir?**
>
> „i cant project the shape of the slot on the right. its on the wrong side.
> there is no geometry. also the sketch shows the wrong side of the selected
> face" (`bug20260805T230205`, zweimal hochgeladen, identische Bundles).
>
> Die Skizze lag auf der UNTERSEITE des Teils. Aus `state.txt`:
>
> ```
> --- Sketch4  plane=face  visible=yes
>     face frame: origin=(-0.0000,-0.0000,-0.0000) n=(-0.0000,-1.0000,-0.0000)
> ```
>
> **1. Der projizierte Bogen lag spiegelverkehrt.** Ein Bogen ist ein Paar
> Winkel PLUS eine Richtung, und die Richtung steckt im 3D-Parameter `t`, der
> gegen den Uhrzeigersinn um die EIGENE Achse der Kante laeuft. Projiziert man
> ihn auf eine Ebene, die diese Achse von hinten sieht, dreht sich der Umlauf
> um: `t` wachsend laeuft in Skizzenkoordinaten jetzt IM Uhrzeigersinn. Sowohl
> `ProjKind.arc` als auch `Geo.arc` heissen aber „gegen den Uhrzeigersinn von
> a0 nach a1" — dieselben zwei Endpunkte in derselben Reihenfolge gelesen
> ergaben also das KOMPLEMENT, den anderen Bogen desselben Kreises.
>
> Der Beweis steht im Log. Der Tipp auf die Langloch-Kappe findet nichts:
>
> ```
> click: toolClick tool=Tool.project sketch=Sketch4 w=(18.07,6.84) picks=0
> ui: notice: Tap geometry on another layer, or the X/Y axis.
> ```
>
> Die echte Kappe geht durch (23.20, 0); die gezeichnete ging durch (8.99, 0).
> Und was der Benutzer als naechstes tut, sagt es selbst: ein Kreis um
> (16.10, 0.00) mit dem Rand auf **(8.99, 0.00)** — er hat auf das gezielt, was
> da stand. Der Fix vertauscht die Endpunkte, wenn die projizierten konjugierten
> Halbmesser negativ orientiert sind (`ax × by < 0`). Gleiche zwei Punkte,
> andere Lesart, und das ist der Bogen, der wirklich da ist. Vollkreis und
> Ellipse bleiben unberuehrt.
>
> **2. Die Ansicht drehte sich beim Oeffnen der Skizze.** `orientToDir` nimmt
> eine RICHTUNG entgegen, kann die Kamera also nur ausrichten und sagt nichts
> ueber den Roll — der bleibt, wo der Orbit ihn gelassen hat. Die Skizzenkamera
> hat diese Freiheit nicht: `PartCamera.forSketch` legt Bildschirm-x auf das
> `u` des Frames. Aus dem Log, im Moment des Flaechen-Picks:
>
> ```
> part: face view: n=(-0.00,-1.00,-0.00) camDir=(-0.42,-0.76,-0.50) dot=0.76
>       chose=(-0.00,-1.00,-0.00) -> pol=3.14 az=-3.14
> ```
>
> Die SEITE war nie falsch (`pol` landet auf der Seite, auf der die Kamera schon
> war). Der ROLL war es: Rechtsvektor der Teil-Kamera ≈ (-0.77, 0, 0.64) gegen
> `u = (1, 0, 0)` des Frames — fast eine halbe Drehung, die der M88-Schwenk
> dann ausgefuehrt hat. Das Modell stand verdreht da, und das Langloch, das
> rechts gepickt wurde, lag links. Neu: `PartCamera.orientToFrame` richtet auf
> den FRAME aus statt auf die Normale, `orientToSurface` bekommt den Frame
> statt `frame.n`, und der Einstieg in die Skizze ist ein reiner Zoom.
>
> Dabei mitgenommen, gleiche Fehlerklasse, beides ohne eigene Meldung:
>
> * `openChildSketch` rief fuer eine Flaechen-/Arbeitsebenen-Skizze
>   `orientToPlane('face')`, und das beantwortet jeden unbekannten Schluessel
>   mit dem XY-Ziel. Aus dem Browser geoeffnet zielte die Teil-Kamera also auf
>   die Vorderansicht; sichtbar wurde das erst bei „Finish Sketch".
> * Der Cache-Schluessel von `projectableEdges()` enthielt `fr.key` und
>   `fr.origin`, aber nicht die ACHSEN. Jede Flaechenskizze hat den Schluessel
>   `face`, und der Ursprung einer Flaeche ist der ebenennaechste Punkt zum
>   Weltursprung — die zwei Seiten einer Platte bei z=0 stimmen also in beidem
>   ueberein. Der Wechsel zwischen ihnen benutzte die abgeflachten Kanten der
>   ersten weiter, und die sind fuer die zweite gespiegelt.
>
> **Ehrlicher Stand:** 9 neue Tests (`m211_projected_arc_side_test`). Suite
> **1559 gruen**, analyze 50 Issues / 0 Errors = Ausgangsstand. **Am Geraet
> nicht nachgeprueft.**
>
> Weiterhin offen (aus M210, unveraendert): der Pick des inneren Kreises als
> Profil, und Slice-Graphics-Dreiecke + ISO-Schraffur pro Koerper.

> **M210 — fuenf Meldungen zu Build `1a0bb61`, alle im PART. Drei sind
> behoben, zwei ausdruecklich NICHT — siehe unten.**
>
> **1. „When i select extrude the solid is invisible suddenly."** Beim
> Bearbeiten eines Features wird DIESES Feature ausgeblendet, und bei einem
> Boolean der ganze Koerper, in den hinein gejoint/geschnitten wird — weil die
> VORSCHAU das kombinierte Ergebnis zeigt und beides zu zeichnen die Form
> verdoppelt. Richtig, solange es eine Vorschau GIBT. Aus dem Log:
>
> ```
> feature: FAIL Extrusion5 ... err=the termination face is not reachable
> reality: setScene #98: 0 solid(s) —
> ```
>
> Die Flaechenreferenz des „bis Flaeche"-Extents hat das Wieder-Oeffnen nicht
> ueberlebt, die Vorschau war null — und der Koerper, fuer den sie einstehen
> sollte, blieb trotzdem versteckt. Es wurde gar nichts mehr gezeichnet. Die
> Regel stand drei Zeilen tiefer schon da (Slice Graphics: „a failed slice must
> never make the part vanish"), sie war nur nicht auf die zwei Vorschauen
> angewandt. **Nichts zum Einstehen heisst nichts zum Verstecken.**
>
> **2. „The cross and the cancel button in the dialog dont work."**
> `cancelExtrude()` hat als einzige der Cancel-Methoden nicht
> `notifyListeners()` gerufen. Esc funktionierte, weil `escape3D` selbst
> benachrichtigt; die beiden Knoepfe im Panel aenderten den Zustand und liessen
> das Panel stehen.
>
> **3. „When a tool is in use the cancel button in the toolbar should be
> there."** Das OK/Cancel-Paar der Schnellwerkzeug-Leiste erschien nur, wenn
> eine SKIZZE offen ist („ein Knopf, der nie leuchten kann, luegt ueber die
> Leiste" — richtig fuer ein leeres Part, falsch fuer eines mit offenem
> Extrude-Panel). Jetzt auch bei laufendem 3D-Befehl, und Cancel ist dort Esc
> (`escape3D`, das die Reihenfolge schon kennt: ein Pick steigt aus dem Pick
> aus, nicht aus dem Panel).
>
> **4. „When a tool is selected like extrude, when i click again on the tool it
> should be deselected."** Die Part-Ribbon-Knoepfe oeffneten nur. Jetzt
> schalten sie um — derselbe Befehl zweimal schliesst ihn. Ein ANDERER Befehl
> wechselt (Extrude → Revolve), und ein „Feature bearbeiten" aus dem Browser
> ist nie ein Umschalten. Der Extrude-Knopf leuchtet dazu nur noch fuer
> `kind == 'extrude'`, sonst haette er beim Revolve das Falsche ausgeschaltet.
>
> **NICHT behoben, mit Begruendung:**
>
> * **„I cant select the inner circle to also extrude somehow."** Die
>   Regionen-Zerlegung ist nachweislich richtig: zwei verschachtelte Kreise
>   ergeben ZWEI waehlbare Regionen (Ring und Scheibe), `regionAt` liefert an
>   (0,0) die Scheibe, und `resolveProfiles` macht daraus zwei Gruppen, die
>   OCCT verschmilzt. Der Fehler liegt also im Weg vom Tipp zur Region — und
>   den habe ich nicht eingegrenzt. Das Log zeigt, dass der Benutzer zu dem
>   Zeitpunkt in Sketch7 (2D-Overlay ueber dem Part) war; dort faengt
>   Viewport2D die Tipps ab und weiss nichts von Profil-Picks. Das ist eine
>   VERMUTUNG, kein Befund, und deshalb ist hier nichts geaendert.
> * **„When i slice graphics there are triangles visible ... different parts
>   should have different schraffur, like in iso norm."** Zwei Dinge: ein
>   Render-Fehler in der Schnittdarstellung und eine echte neue Funktion
>   (ISO-Schraffuren pro Koerper). Beides braucht mehr als eine gezielte
>   Korrektur.
>
> **Ehrlicher Stand:** 10 neue Tests (`m210_part_commands` 9, plus einer in
> `reality_scene_test` fuer die neue Sichtbarkeitsregel; ein bestehender dort
> wurde auf den neuen Kontrakt gezogen). Suite **1550 gruen**, analyze 50
> Issues / 0 Errors = Ausgangsstand. **Am Geraet nicht nachgeprueft.**

> **M209 — drei Meldungen zu Build `96c3761`. Die Pick-Reihenfolge von Bogen
> und Langloch ist bereits erledigt und steht hier nicht.**
>
> **1. „The point tool is placing a circle not a point."** Es war einer. Der
> QCAD-Kern kennt nur Linie/Kreis/Bogen/Polylinie, also baute das Werkzeug
> einen Kreis mit Radius 0,35 mm — bei jedem Arbeits-Zoom ein sichtbarer Ring
> mit vier Quadranten-Griffen, einem Rand, auf den Dinge snappen, und einem
> Durchmesser, den man bemassen kann. Der TRAEGER bleibt ein Kreis (nichts
> anderes ueberlebt den Round-Trip), aber er traegt jetzt ein Tag
> (`Geo.pointTag`, dieselbe Mechanik wie Ellipse und Zahnrad), und alles, was
> ihn wie einen Kreis behandelt hat, fragt das Tag: gezeichnet wird ein
> SCHIRM-Marker (X, zoomunabhaengig), es gibt genau EINEN Griff, der Rand ist
> keine Kurve mehr (kein Snap, kein `pointLandsOn`, keine Quadranten-Referenz),
> `sampleEntity` liefert einen einzigen Punkt, und ein Durchmesser-Mass wird
> abgelehnt. **Die Falle dabei:** `sampleEntity` mit EINEM Punkt laesst die
> Segment-Schleife in `distToEntity` null Mal laufen — der Punkt waere
> unselektierbar und unloeschbar geworden; und das Tag musste in die
> Engine-Refresh-Erhaltung, die bis dahin nur Polylinien kannte, sonst ist es
> nach dem ersten Rebuild wieder ein Ring.
>
> **2. „On the freehand spline when i click finish it sets a last spline
> point."** Die modelosen Fenster schweben INNERHALB des Stacks, den der rohe
> Pointer-Listener des Viewports umschliesst, und Flutter stellt einen Pointer
> jedem Ziel auf seinem Hit-Pfad zu. Der Listener sah das Up ueber „Finish"
> also genauso wie der Knopf — und mit scharfem Werkzeug ist ein Up ein
> Tool-Klick. M61 hatte genau das schon einmal (Gear-Dialog) und es so
> geloest, wie man etwas einmal loest: ein handgerechnetes Rechteck fuer
> diesen einen Dialog. Sechs Fenster spaeter war es immer noch der einzige
> geschuetzte. Jetzt sagen die Fenster, wo sie sind ([ViewportWindow]) — beim
> DOWN geprueft, nicht erst beim Klick, damit ein Druck, der zum Ziehen wird
> (ein Slider), auch nicht zeichnet.
>
> **3. „Angle dimensions ... look very weird ... its possible to move the
> dimension so its not clear that the chosen angle is meant, also no arrows."**
> Der Bogen war um die Richtung des LABELS zentriert und ueberstrich von dort
> den gemessenen Wert: ein Bogen der richtigen GROESSE an beliebiger Peilung.
> Zieht man den Text um den Scheitel, dreht der Bogen mit, und das Bild sagt
> nicht mehr, welcher der vier Winkel gemeint ist. Inventor zeichnet ihn
> ZWISCHEN DEN SCHENKELN; der Text waehlt nur den Radius und die Seite.
> `angleArcSpan` (in `pick_math.dart`, rein und getestet) probiert alle vier
> Schenkel-Richtungspaare: der gemessene Wert entscheidet zuerst, unter den
> passenden gewinnt das Paar, in dem das Label liegt. Dazu Pfeilspitzen an
> beiden Bogenenden (tangential) und gestrichelte Hilfslinien dort, wo ein
> Schenkel vor dem Bogen endet. Der 3-Punkt-Winkel (`ang3`) hat immer schon
> zwischen den echten Strahlen ueberstrichen — ihm fehlten nur die Pfeile.
>
> **Ehrlicher Stand:** 19 neue Tests (`m209_point_and_windows` 10,
> `m209_angle_dimension` 9). Zusammen mit dem parallel entstandenen M208
> (Slots) Suite **1540 gruen** (von 1498), analyze 50 Issues / 0 Errors =
> Ausgangsstand. Die beiden Meilensteine liefen getrennt und trugen beide die
> Nummer 208; dieser hier ist auf M209 gezogen, weil M208 zuerst auf main war. **Am Geraet nicht nachgeprueft.** Der Punkt ist
> die Aenderung mit der groessten Reichweite: er beruehrt Snap, Griffe,
> Auswahl, Constraint-Inferenz, Bemassung und Persistenz. Alte Skizzen behalten
> ihre alten Punkt-Kreise (kein Tag, keine Migration) — sie bleiben Kreise, bis
> sie neu gesetzt werden.
> **M208 — vier Meldungen zu Build `96c3761`, alle vier ueber Slots. DREI
> davon sind EIN Fehler, und der steckt in einer Schutzmassnahme aus M196.**
>
> **1. Die Kappe, die als Verrundung galt.** Ein Slot-Kappenbogen ist tangent
> zu BEIDEN Schienen, und `cornerFilletArcs` zaehlte nur, zu wie vielen Linien
> ein Bogen tangent ist — also war jede Slot-Kappe eine „corner fillet" und
> ging an die Verzweigungs-Sperre. Eine Kappe ist aber eine HALBE DREHUNG, per
> Konstruktion, und die Sperre fragt „vorher unter π, nachher ueber π", mit
> einer Toleranz von 1e-6 rad. Aus den Bundles selbst nachgerechnet liegen die
> Kappen bei **π ± 7,3e-6** — die Toleranz war eine Groessenordnung feiner als
> der Abstand, den die echte Form von der Grenze hat. Also entschied die letzte
> Stelle des Solvers, ob ein Frame ein „Umklappen" ist. Das Log sagt, was es
> gekostet hat:
>
> ```
> 565 BRANCH FLIP ... REJECTED, keeping last good   (60 Frames angenommen)
> lm: err=9.81e-10 satisfied=true
> WARN solve: BRANCH FLIP via lm on arc(s) 3 ... REJECTED
> INFO constraint: REJECTED concentric/ ents=7,3 — cannot be satisfied
> ```
>
> Damit sind zwei Meldungen erklaert. „I couldnt properly drag the point
> around. it jumps around or doesnt move at all" — 90 % der Frames wurden
> verworfen, ein verworfener Frame bewegt sich nicht, und der eine angenommene
> nach einer Serie davon kommt auf einmal. Und „it says this constraint is not
> possible but it should definitely be possible (concentric of the 2 slot
> circles)" — die Concentric WAR geloest, auf 9,8e-10 genau, und wurde von
> einer Sperre weggeworfen, die auf diese Form gar nicht zutreffen kann: ein
> Bogen tangent zu zwei PARALLELEN Linien hat seinen Mittelpunkt auf deren
> Mittellinie und die Beruehrpunkte diametral gegenueber. Beide „Zweige" sind
> dieselbe halbe Drehung. Es gibt nichts umzuklappen.
>
> Zwei Aenderungen, beide klein: `cornerFilletArcs` verlangt jetzt, dass sich
> zwei der tangenten Linien tatsaechlich in einem WINKEL treffen (`> 0,57°`) —
> das ist der ganze Unterschied zwischen einer Verrundung und einer Slot-Kappe
> —, und die Sperre braucht ein deutliches Vorher/Nachher (`kHalfTurnSlack`,
> 0,05 rad ≈ 2,9°) statt 1e-6. M196 bleibt scharf: dort ging eine 90°-Ecke auf
> 270°, eine Vierteldrehung weit jenseits des Bandes.
>
> **2. Der Slot, der eine Linie wurde.** „A slot shouldnt be able to become a
> line like this." Der committete Zustand im Bundle:
>
> ```
> [0] line data=[-15.0305, 3.1698, 11.9094, -5.0201]
> [1] line data=[11.9094, -5.0201, -15.0305, 3.1698]   DIESELBE Linie
> [2] arc  data=[-15.0305, 3.1698, 0.0000, ...]        Radius null
> ```
>
> Zwei Luecken, und die Diagnose stand die ganze Zeit im Log (`collapsed by
> this solve: 2,3`). Erstens vergleicht `newlyDegenerate` mit dem Frame DAVOR —
> mit dem M207-Warmstart heisst das: sobald eine Kappe einmal bei Radius null
> stand, verglich jeder spaetere Frame gegen eine bereits kollabierte
> Konfiguration, fand nichts neu kaputt und sagte ja. Der Zusammenbruch war
> klebrig. Zweitens lief der Settle-Solve in `endGripDrag` nur wegen seiner
> Nebenwirkung, sein Rueckgabewert wurde weggeworfen — genau so kam die Form
> ins Dokument, nachdem jeder einzelne Drag-Frame sie korrekt abgelehnt hatte.
>
> Neu ist `collapsedSince(start, now)`: gemessen gegen die Skizze, die der
> Benutzer beim Aufsetzen des Fingers vor sich hatte, nicht gegen den letzten
> Frame. Die Schranke ist RELATIV und gilt pro Geste (1e-3 der Ausgangsgroesse)
> — sie verbietet nie eine Groesse, nur das Zerstoeren einer Form in einem Zug.
> M203 bleibt gewahrt, und zwar aus demselben Grund: dieser Schnappschuss IST
> die committete Skizze, also wird etwas, das schon vorher kollabiert war,
> nicht dem Drag angelastet und das Dokument bleibt bearbeitbar. Der Settle
> wird jetzt geprueft; faellt er durch, wird der zuletzt GEZEIGTE Frame
> committet — was man gesehen hat, ist was man bekommt.
>
> **3. Erst Anfang, dann Ende, zuletzt die Mitte.** „also slots should behave
> like in inventor. so set the start then the end point and at last the
> midpoint so i have an exact preview while drawing. the same with a 3 point
> arc. start then end then middle." Betrifft die beiden Drei-Punkt-Werkzeuge:
> `arcThreePoint` und den Drei-Punkt-Bogen-Slot `slot3A`. Beide lasen bisher
> Anfang, MITTE, Ende. Dieselbe Kurve, aber nur eine der beiden Reihenfolgen
> laesst sich zeichnen: steht die Mitte als zweites fest, ist das ferne Ende
> noch offen, die Form auf dem Schirm schwenkt beim Ziehen umher, und man zielt
> auf eine Kurve, die nicht dort liegt, wo der Bogen landen wird. Die letzten
> drei Picks der Sitzung zeigen es: `(-76.62, 31.76)`, `(26.28, -45.37)`,
> `(-3.05, 32.09)` — der zweite Klick zielte auf das ENDE des Slots und wurde
> als Durchgangspunkt gelesen, weshalb der Slot 91 mm breit herauskam.
>
> **Ehrlicher Stand:** 23 neue Tests in `m208_slots_test.dart`, Suite **1521
> gruen** (von 1498), analyze 50 Issues / 0 Errors = Ausgangsstand. Jede der
> drei Aenderungen wurde EINZELN zurueckgedreht, um zu pruefen, dass die Tests
> sie auch wirklich halten (Flip-Sperre 3 Tests, Kollaps 1, Reihenfolge 3); der
> Kollaps-Test faellt ohne den Fix mit Kappenradius 0,000001 — der Slot IST
> dann die Linie aus der Meldung. Die Zahlen in den Tests stammen aus den
> Bundles, nicht aus der Vorstellung. **Am Geraet nicht nachgeprueft.**
> Reichweite ueber Slots hinaus: `collapsedSince` gilt fuer JEDEN Griff-Drag
> (die bestehenden Drag-Suiten T-1, M47, M94, M182, M207 laufen gruen), und die
> geaenderte Pick-Reihenfolge ist eine Bedienungsaenderung — wer den
> Drei-Punkt-Bogen gewohnt ist, klickt ihn ab jetzt anders.

> **M207 — vier Meldungen zu Build `081a39d`. Eine ist ein Solver-Verhalten,
> drei sind Bedienung.**
>
> **1. Der Zug, der springt.** „The dragging around of those 2 slots is really
> jumping and buggy." Die beiden Slots sind aneinander auto-constraint — und
> **das ist gewollt, das war nicht der Fehler** (ausdrueckliche Ansage: „the
> slots were automatically constrained. this was good. just the dragging around
> was buggy"). Der Fehler steckt darin, WIE ein Drag-Frame gerechnet wurde:
> jeder Frame kopierte die COMMITTETE Geometrie, setzte den Griff auf den
> Cursor und loeste von dort. Bei einer freien Linie ist das dieselbe Antwort.
> Bei einem gekoppelten System nicht: zu einer Cursorposition gehoeren MEHRERE
> Loesungen, und wer jeden Frame von derselben festen Konfiguration neu
> startet, laesst den Solver bei einem Pixel Bewegung auf einen anderen Ast
> springen. Genau das sieht man als Zucken — und genau deshalb trat es erst
> auf, als zwei Formen aneinander haengen.
>
> Der Frame startet jetzt beim ZULETZT GELOESTEN Frame (`_lastGoodDragGeo`, das
> es schon gab, bisher nur als Fallback). Damit ist jeder Schritt ein kleiner
> Schritt von einem Punkt, der bereits auf der Mannigfaltigkeit liegt, und der
> Zug bleibt auf dem Ast, den der Benutzer anschaut. **Nicht** fuer den
> Body-Drag: der verschiebt um (Cursor − Griffpunkt), einen ABSOLUTEN Anker,
> und wuerde sich pro Frame verdoppeln — die drei m47-Tests haben genau das
> sofort gemeldet. Der Test dazu ist scharf: ohne den Warmstart springt ein
> Punkt 43 mm bei 1,7 mm Cursorweg, mit ihm keiner mehr als 25.
>
> **2. Der Pencil, der ausser Reichweite geraet.** „When i hover and the hover
> is interrupted ... the preview should stay exactly like it was ... right now
> the preview goes somewhere in the top left corner for a moment, which results
> in a weird long line over the screen." Die Ecke ist der Beweis: ein Hover auf
> dem FENSTER-URSPRUNG ist keine Stelle, auf die gezeigt wurde, sondern das
> synthetische (0,0), das beim Abbau des Zeigers kommt — dieselbe Signatur wie
> die Cancel-Welle aus M205. Durch `_toWorld` ist das die linke obere Ecke des
> Viewports, und das Gummiband zieht einen Frame lang quer ueber den Schirm.
> Solche Events werden verworfen; die Vorschau haelt ihre letzte echte Position,
> bis die Spitze zurueck ist.
>
> **3. Die fertige Freihandkurve.** „Even when the spline is finished and the
> freehand spline dialog comes, on hover with pencil it still goes on." Die
> Vorschau zeichnet `toolPoints` PLUS den Hover-Punkt; nach dem Strich ist das
> Werkzeug noch `splineFree`, also hing die fertige Kurve weiter am Stift.
> Solange das Fit-Fenster steht, gehoert die Kurve ihm allein. Dazu, wie
> gewuenscht: „close if ends meet" und „snap ends to points" sind keine Schalter
> mehr, sondern Konstanten — beide standen ohnehin auf an, und das Fenster ist
> zwei Zeilen kuerzer.
>
> **4. Das Polygonfeld.** „In the polygon input field the small number input
> field doesnt work. it just closes directly ... this polygon input field needs
> to be redone, it should be similar to the radius input field. also on the
> radius input field the cross at top left isnt needed." Erster und zweiter
> Satz haben dieselbe Antwort: die Seitenzahl lag in einem `AlertDialog` —
> modal, mit einer Barriere unter allem, was die App darueber legt, und
> blockierend, das Werkzeug war bis zur Antwort nicht scharf. Der 2D-Fillet-
> Radius hat nie so funktioniert. Das Polygon bekommt dasselbe modelose
> Fenster, dieselbe Zahlenzeile (jetzt EINE, `toolNumberRow`, statt zwei
> Schreibweisen), denselben Scrub, dasselbe Pad; das ✕ ist bei beiden weg.
>
> **Nachtrag zum Pad (M206):** sein Anker wurde einmal beim Einblenden
> abgelesen. Fuer ein Fenster, das noch einblendet oder das man verschiebt, ist
> das die falsche Stelle. Jetzt haengt es an einem `LayerLink` — die Position
> kommt beim Compositing, ohne einen einzigen Rebuild pro Frame (der erste
> Versuch mit `markNeedsBuild` je Frame liess `pumpAndSettle` nie zur Ruhe
> kommen, was auf dem Geraet eine Dauerlast gewesen waere).
>
> **5. Der Triad.** „When the model browser retracts, the triad should also go
> to the left." M146 hatte ihn absichtlich auf die AUSGEKLAPPTE Breite genagelt;
> das Geraet widerspricht, und es hat recht: einzuklappen ist eine Handlung, um
> die Ecke zurueckzubekommen.
>
> **Ehrlicher Stand:** 16 neue Tests in drei Dateien
> (`m207_drag_continuity` 5, `m207_hover_and_freehand` 6,
> `m207_polygon_window` 5). Suite **1498 gruen** (von 1482), analyze 50 Issues
> / 0 Errors = Ausgangsstand. **Am Geraet nicht nachgeprueft.** Der
> Warmstart ist die eine Aenderung mit Reichweite ueber die Meldung hinaus — er
> betrifft JEDEN Griff-Drag; die bestehenden Drag-Suiten (T-1, M47, M94, M182)
> laufen gruen, aber das ist Host, nicht Hand.

> **M206 — fuenf weitere Meldungen derselben Sitzung. Eine ist ein echter
> Defekt mit zwei Ursachen, vier sind Oberflaeche.**
>
> **1. Ein Tipp, zwei Punkte.** „When I draw a circle and end the hover, when I
> go back into hover the preview won't work and I can't finish drawing the arc
> properly." Der Hover ist eine Fehlspur; das Log sagt es elf Mal:
>
> ```
> 14:26:59.050361  toolClick tool=Tool.arcThreePoint w=(-8.71,20.00) picks=0
> 14:26:59.050432  toolClick tool=Tool.arcThreePoint w=(-8.71,20.00) picks=1
> 14:26:59.712185  toolClick tool=Tool.arcThreePoint w=( 1.48,20.00) picks=2
> layer: tool Tool.arcThreePoint built no geometry from 3 point(s)
> ```
>
> Zwei Platzierungen 71 MIKROSEKUNDEN auseinander, auf demselben Punkt. Das ist
> EIN Pencil-Tipp: das Press-Drag-Draw aus M53 scharf ab 8 px Weg, ein
> gewoehnlicher Tipp wackelt ungefaehr so weit, und das Update, das die
> Schwelle reisst, und das Release danach werden aus DEMSELBEN Pointer-Event
> zugestellt. Anker gesetzt, „Zieh"-Punkt obendrauf. Ein Drei-Punkt-Bogen mit
> zwei identischen Punkten baut nichts, ein Kreis bekommt seinen Rand auf den
> eigenen Mittelpunkt. Die Schwelle ist jetzt kind-abhaengig (18 px, Finger
> 1.8x — gemessen an den Spuren im Bundle: Tipps wackeln bis ~8 px, echte
> Striche laufen 25 bis 70), und das Release setzt den zweiten Punkt nur, wenn
> es AUCH so weit vom Anker entfernt endet. Sonst faellt die Geste in den
> Klick-Klick-Ablauf zurueck, der ohnehin der Normalfall ist.
>
> **2. Und 91 Sekunden, in denen der Viewport gar nichts beantwortet hat.**
> Dieselbe Meldung, zweite Haelfte: nach `14:27:41` kein einziger `toolClick`
> mehr im Log, bei laufenden Pencil- und Zwei-Finger-Tipps in der Gestenspur.
> Was es beendet hat, steht auch im Log, und es ist nichts, was der Benutzer an
> der Skizze getan haette:
>
> ```
> 14:29:17  lifecycle: paused
> 14:29:53  lifecycle: resumed
> 14:29:54  click: toolClick tool=Tool.arcThreePoint ... picks=0
> ```
>
> Eine Sekunde nach der Rueckkehr ging es wieder. Das ist die Signatur des
> M205-Falls: ein Kontakt, den die App noch fuer gedrueckt haelt, macht jeden
> Tipp zum „zweiten Finger" — und damit stirbt BEIDES, der Klick-Pfad
> (`_live.count > 1`) und der Zeichen-Pfad (`soleKind == null`), waehrend die
> native Chrome weiterarbeitet. Der M205-Watchdog kuerzt das von 91 Sekunden
> auf gut zwei; der Resume raeumt jetzt zusaetzlich hart auf, weil das der eine
> Moment ist, in dem Veraltung nicht geschlossen, sondern GEWUSST ist.
>
> **3./4. Wo ein Dialog aufgeht.** „The gear dialog should spawn at the right
> like the extrude panel ... now it spawns under the Modell browser" und „other
> Dialogs spawn under the fast toolbar on the right but they should spawn a bit
> more to the left right next to the toolbar." Zusammen ist das die ganze
> Regel, und sie stand nirgends: Pattern und Fillet waren gegen die
> Schnellwerkzeug-Leiste eingerueckt (M192), Extrude und Edge rechneten
> `width - w - 18` und lagen darunter, Gear/Parameters/Freehand/Text oeffneten
> auf `Offset(60, 60)` — also unter dem Modell-Browser. Alle fragen jetzt
> `DialogDock`. **Warum das so lange durchging:** die Leiste ist eine
> Platform-View, im Flutter-Screenshot ist diese Ecke LEER — ein Dialog
> darunter sieht auf jedem angehaengten Bild richtig platziert aus.
>
> **5. Die Zahlentastatur.** „A really small number input field is used instead
> of the whole keyboard ... but in every dimension input field the whole
> keyboard comes ... can you change this so this small number input field is
> used everywhere", und „the arrow of it should be right under the number
> field." Der Unterschied war ein Flag: iOS bildet einen SIGNED Number-Type auf
> `UIKeyboardTypeNumbersAndPunctuation` ab — die volle Tastatur — und
> `kValueKeyboard` bat um signed, weil ein Offset negativ sein darf. M171 hat
> also genau das bestellt, was M171 verhindern wollte.
>
> Das Flag umzulegen loest den ersten Satz und macht den zweiten unmoeglich:
> die Position der System-Tastatur ist Apples, sie kommt aus dem Caret-Rechteck,
> und Flutter meldet Caret-Rechtecke nur mit Scribble — das M179 fuer
> Zahlenfelder bewusst ABGESCHALTET hat, weil Scribble den Pencil-Strich klaut,
> den der Scrub (M172) braucht. Also gehoert das Pad uns: es geht unter dem
> Feld auf, das es bearbeitet, mit der Spitze darauf, es bringt sein eigenes
> Minus (als VORZEICHEN, nicht als Zeichen an der Cursorposition) mit, und
> `kValueKeyboard` ist `TextInputType.none` — das Feld behaelt Caret, Auswahl
> und jede Hardware-Taste, das System hebt nur nichts mehr. Eingehaengt in
> `ScrubField`, weil seit M180 ohnehin JEDES Zahlenfeld dort durchlaeuft; die
> Equation-Zelle der Parameter steigt per `pad: false` aus, aus demselben
> Grund, aus dem M171 sie schon von der Zifferntastatur ausgenommen hat.
>
> **Ehrlicher Stand:** 39 neue Tests in drei Dateien (`m206_press_drag_draw` 7,
> `m206_dialog_dock` 8, `m206_value_pad` 24), dazu `m171_numeric_keyboard` auf
> den neuen Kontrakt gezogen und die Zahlenfeld-Sonde in
> `m180_every_number_scrubs` nachgefuehrt. Suite **1482 gruen** (von 1442),
> analyze 50 Issues / 0 Errors = Ausgangsstand. Die
> Ribbon-Breite ist unveraendert. **Am Geraet nicht nachgeprueft.** Zwei Dinge
> sind ausdruecklich Umbau und nicht nur Reparatur: die Tastatur eines jeden
> Wertfeldes (Punkt 5) und die Startposition von vier Fenstern (Punkt 3/4) —
> wenn davon etwas nicht gefaellt, ist es an einer Stelle zurueckzudrehen.

> **M205 — fuenf Meldungen der Sitzung vom 2026-08-05, Build `19fcae4`.
> Vier davon sind Eingabe, und drei von denen haben EINE Ursache.**
>
> **1. Der Zeiger, der nie hochkam.** „I couldn't place anything and the
> viewport is jumping around anytime i click anywhere", „i cant drag around any
> point. it seems stuck somehow and buggy", und dann, drei Minuten spaeter,
> „in a new sketch the movement was again working idk what happend".
> `bug20260805T141441/gestures.txt` sagt es woertlich:
>
> ```
> 51623ms  DOWN   p38 mouse at(181.2,171.3)
> 52476ms  DOWN   p39 mouse at(609.4,296.8)
> ...  45 Sekunden Benutzung, keiner der beiden je wieder gehoert  ...
> 97390ms  CANCEL p39 touch at(0.0,0.0)
> 97390ms  CANCEL p38 touch at(0.0,0.0)
> ```
>
> Zwei Kontakte gingen runter und kamen nie hoch. Der Viewport zaehlte Zeiger
> in einem blanken `int` und behandelt „mehr als einer" als Pan/Zoom — ab
> 51,6 s war also JEDER Tipp der dritte Finger: kein Picken, kein Ziehen, kein
> Platzieren, und eine Ansicht, die sich bei jeder Beruehrung bewegt. Befreit
> wurde das Paar erst von der CANCEL-Welle, die die Platform-View schickt, wenn
> sie eine Geste uebernimmt — deshalb ging es „von selbst" wieder: das
> Bug-Melden selbst hat es entstoert.
>
> Ersatz ist `LivePointers` (`lib/touch.dart`), mit zwei Regeln. **Ein Geraet,
> ein Kontakt**: die Pointer-Id ist pro Druck, die DEVICE-Id ist das physische
> Ding, und das kann nicht zweimal gleichzeitig gedrueckt sein — ein neues
> Down auf einem gehaltenen Geraet BEWEIST, dass das gehaltene weg ist. Das
> ist keine Heuristik. **Stille ist Tod**: ein lebender Kontakt meldet jeden
> Frame eine Bewegung, auch wenn er sich nicht bewegt (p36, p77, p84 in
> derselben Spur sind bewegungslose Druecke mit einem Move pro Vsync); wer 2 s
> schweigt, ist verloren. Die zweite Regel ist eine Ermessensfrage, also ist
> sie nicht sicher gemacht, sondern UNGEFAEHRLICH: ein Move fuer einen
> verworfenen Zeiger NIMMT IHN WIEDER AUF. Falsch zu liegen kostet ein Event;
> dem Zaehler zu glauben kostet die App. Ein Watchdog (500 ms, laeuft nur
> solange etwas unten ist) raeumt auch ohne naechste Beruehrung auf, und jede
> Raeumung schreibt eine Zeile in die Gesten-Spur — die naechste Meldung eines
> springenden Viewports muss das sehen koennen.
>
> **2. Der native Klick, der nicht zaehlt.** „The buttons seem to get bigger
> when i click but somehow it doesnt count as a click" — das ist UIKit, exakt
> beschrieben. Ein Control leuchtet bei `touchesBegan` und feuert bei
> `touchesEnded`; was dazwischen aufleuchtet und dann still verlischt, hat
> `touchesCancelled` bekommen. Eine `UiKitView` haelt jede Beruehrung zurueck,
> bis die FLUTTER-Seite entschieden hat, ob sie die Geste will; nimmt dort
> irgendwer sie zuerst, bekommt UIKit statt der Beruehrung ein Cancel.
> **Zwei unabhaengige Sicherungen**, weil „a double proof fix" genau das heisst:
> die Platform-Views der Leisten beanspruchen ihre Geste jetzt SOFORT
> (`eagerNativeTouches`, `native_touches.dart`) — die Arena ist entschieden,
> bevor ein Konkurrent ueberhaupt eintreten kann; und `GlassButton`
> (`GlassButton.swift`) zaehlt einen abgebrochenen Druck trotzdem als Klick,
> wenn er sich nie bewegt hat, innerhalb des Knopfes endete und keine
> Scroll-View darueber gerade zieht. Ein Druck feuert hoechstens einmal.
>
> **3. „When a context menu is open and i click anywhere else this should
> count as a cancel."** Die Sperre hinter den Ribbon-Flyouts war ein
> `GestureDetector.onTap` — und ein Tap muss die Gesten-Arena GEWINNEN. Ein
> Trackpad-Klick, der zwei Pixel zittert, ein Pencil, der rollt, ein Druck, der
> zum Ziehen wird: alles legitim kein Tap, und das Menue blieb stehen. Sperren
> hoeren jetzt auf das rohe Pointer-DOWN. Dazu ein Register (`lib/menus.dart`)
> fuer den Klick, den keine Flutter-Sperre sehen KANN: die Schnellwerkzeug-
> Leiste, die Tab-Leiste und der Modell-Browser sind UIKit, ihr Tipp kommt ueber
> einen Method-Channel zurueck, ohne Pointer-Event zum Schliessen.
>
> **4. „The arrow to expand the list on rectangle or circle is really small and
> difficult to hit ... maybe a swift button or something i can actually see is
> a button."** Es war ein 7,5-Pixel-▼ in einer unsichtbaren 40x14-Box. Jetzt
> ein gezeichneter Chip: Fuellung, Rand, Radius, echtes Dreieck, Press-Zustand
> — 46x26 als Ziel, mehr als das Doppelte der Flaeche. **Die kleinen Zeilen
> (Fillet, Text) sind absichtlich NICHT breiter geworden**: diese Spalte ist
> Ribbon-BREITE, 16 pt mal sechs Spalten, und das Ribbon ist mit 1681 pt schon
> breiter als der Schirm — die 96 pt kaemen rechts ab, und rechts steht Finish
> Sketch. Sie bekommen die Optik und die volle Zeilenhoehe, bei exakt ihrer
> alten Breite.
>
> **Ehrlicher Stand:** 19 neue Tests (`m205_lost_contacts_test.dart`,
> `m205_flyout_button_test.dart`), Suite **1442 gruen**, analyze 50 Issues /
> 0 Errors = Ausgangsstand. Der Ribbon-Inhalt ist auf 1681 pt gemessen —
> unveraendert zum Stand davor, das ist getestet und nicht geschaetzt.
> **Am Geraet nicht nachgeprueft**, und die Swift-Seite ist auf diesem Host
> ueberhaupt nicht kompiliert worden: `GlassButton` und die Eager-Geste
> brauchen einen echten iOS-Build, bevor irgendjemand sie „gruen" nennt. Die
> fuenfte Meldung („clicks on native swift elements ... i also had this problem
> in other apps") ist mit 2. beantwortet, soweit sie von uns aus beantwortbar
> ist.

> **M197 — die vierte Meldung: der Radius frisst die Ecke.**
>
> „Wenn ich einen Radius auf einem Mittelpunkt-Rechteck mache, laufen die
> Konstruktionslinien nicht mehr in die Ecken, und die Ecken sollten als
> Konstruktion stehenbleiben wie beim Trimmen."
>
> **Eine Ursache, zwei Saetze.** Die Diagonalen eines Mittelpunkt-Rechtecks
> haengen per Koinzidenz an den ECKPUNKTEN der Seiten (M92). Der Fillet zieht
> genau diese Punkte auf die Tangentenpunkte zurueck — also wandert die
> Diagonale mit und endet am Verrundungsanfang. Im Bundle
> `bug20260805T003600`: `[4] line data=[-29.2119, 16.9019, ...]`, die Ecke
> liegt bei `-34.2119`.
>
> **Die Loesung ist die von M191, an neuer Stelle:** was weggeschnitten wird,
> bleibt als KONSTRUKTION stehen — hier zwei Stummel, einer pro getrimmter
> Kante. Damit ist die virtuelle Ecke wieder ein echter PUNKT (das gemeinsame
> ferne Ende der beiden Stummel), alles was vorher auf den Eckpunkt zeigte —
> Diagonalen wie Masse — wird per `Constraint.withPts` darauf umgehaengt, und
> die Ecke ist sichtbar noch da.
>
> **Die Buchhaltung, weil genau sie hier zweimal teuer war (M37, M188):** vier
> Gleichungen pro Stummel auf vier Parameter, die Freiheitsgrade bleiben also
> gleich. Nahes Ende koinzident mit dem gekuerzten Linienende (2), fernes Ende
> AUF derselben Linie (1 — Punkt-auf-Kurve; zusammen mit dem nahen Ende ist das
> Kollinearitaet, aber OHNE die abhaengige Zeile, die ein `collinear` mitbraechte
> — `collinear` zaehlt 2 Gleichungen, und eine davon ist bereits erfuellt),
> beide fernen Enden koinzident (2). Das legt die Ecke exakt auf den
> Schnittpunkt der beiden Traeger. Jede dieser Zeilen laeuft trotzdem durch
> `wouldOverconstrain`, und der Fillet als Ganzes bleibt atomar: geht der Solve
> nicht auf, wird alles zurueckgerollt.
>
> **Nur bei einer ECHTEN Ecke.** Beide Picks muessen Linien sein, beide
> getrimmt, und ihre bewegten Endpunkte muessen vorher aufeinander gelegen
> haben. Zwei Linien, die nur bis zum Schnittpunkt verlaengert wurden, haben
> keine Ecke zu bewahren; zwei PARALLELE haben gar keinen Schnittpunkt, und ein
> dort erzwungenes gemeinsames fernes Ende waere unloesbar und wuerde den
> ganzen Fillet mitreissen. Konstruktionsgeometrie wird uebersprungen, aus
> demselben Grund wie beim Trim.
>
> **Ehrlicher Stand:** 8 neue Tests (`m197_fillet_keeps_the_corner_test.dart`).
> Der tragende ist der RANG-Test — `eqs - rank == 0` und `dof == 4` vor wie
> nach dem Fillet. Sechs bestehende Fillet-Erwartungen in vier Dateien wurden
> auf den neuen Kontrakt gezogen (ein Fillet fuegt jetzt Bogen + zwei Stummel
> hinzu); wo die Zahl nur „der Fillet ist gelandet" bedeutete, zaehlen sie
> jetzt die NICHT-Konstruktions-Entities, was gegen kuenftige Scaffolding-
> Aenderungen robust ist.
>
> **Der erste Push war ROT — 7 Faelle in zwei weiteren Dateien**
> (`m36_test`, `operation_sequence_test`), die mein `grep` nach `Tool.fillet`
> nicht gefunden hatte. Alle sieben waren Zaehl- oder INDEX-Erwartungen:
> `s.geometry.last` ist jetzt ein Stummel statt des Bogens, und der zweite
> Fillet-Bogen liegt bei Index 7 statt 5. **Keine einzige Rang- oder
> DOF-Verletzung** — `construction_rank_test` (eqs == rank, dof == 4) und der
> Rang-Test aus M197 waren im selben Lauf gruen, was die Gleichungsbilanz oben
> bestaetigt. Wo eine Zahl nur „der Fillet ist gelandet" hiess, zaehlt sie
> jetzt die Seams am Bogen bzw. die Nicht-Konstruktions-Entities.
>
> **Stand: CI gruen** (Lauf `30959180608`) — **1364 Tests**, davon 8 aus M197
> und die 17 aus M196, analyze 50 Issues / 0 Errors = Ausgangsstand.
> Geraete-Test offen: alle vier Meldungen der Sitzung vom 2026-08-05 sind
> damit beantwortet, keine davon am Geraet nachgeprueft.

> **M196 — drei von vier Geraete-Meldungen (Sitzung 2026-08-05, Build
> `a2d3107`).**
>
> **(1) „Ein Mittelpunkt-Rechteck sollte einen Punkt in der Mitte haben."**
> M92 gab diesen Rechtecken zwei Konstruktions-Diagonalen, damit die Mitte
> sichtbar und fangbar ist. Fangbar war sie (Mittelpunkt-Snap auf jeder
> Diagonale) — gezeichnet war dort nichts. Der Punkt wird jetzt gemalt, und
> zwar **abgeleitet, nicht gespeichert**. Der Grund ist wichtig: eine echte
> Entity waere ein Kreis (die Skizzen-Punkte dieses Projekts SIND kleine
> Kreise, das Backend hat keinen Punkt-Typ), ein Kreisradius ist ein freier
> Parameter, und damit haette jedes Mittelpunkt-Rechteck dauerhaft einen
> Freiheitsgrad zu viel — der fehlende Punkt waere gegen eine Skizze getauscht,
> die nie „vollbestimmt" werden kann. Die Erkennung ist geometrisch: zwei
> KONSTRUKTIONS-Linien, die sich einen Mittelpunkt teilen und nicht parallel
> sind, sind die Diagonalen eines Rechtecks (in jedem Parallelogramm halbieren
> sich die Diagonalen). Kein Tag, also gilt es auch fuer alles schon
> Gespeicherte, und ein Zug kann den Punkt nicht zuruecklassen.
>
> **(2) Ein Ribbon-Knopf schaltet UM.** Nochmal auf das aktive Werkzeug tippen
> legt es weg. Vorher armierte der zweite Tipp dasselbe Werkzeug erneut und
> warf dabei die schon gesetzten Punkte weg — das sieht aus, als passiere
> nichts. Umgesetzt als zwei `cancelTool()` (erst die Picks, dann das
> Werkzeug), das zweite NUR solange das Werkzeug noch steht: `cancelTool()`
> ohne Werkzeug loescht die AUSWAHL, und ein Werkzeug wegzulegen darf nicht die
> Selektion kosten. Nur das exakt gleiche Werkzeug schaltet ab — eine andere
> Variante aus demselben Flyout ist ein Wechsel.
>
> **(3) „Eine Form, die es nicht geben duerfte."** Ein Zug auf einem
> verrundeten Rechteck machte aus zwei R5-Ecken 270°-Keulen. **Der Solver war
> nicht verwirrt:** im Bundle steht `verify ok residual=2.51e-15` — jede
> Koinzidenz, jede Tangente und beide Radienmasse hielten exakt. Es war die
> ANDERE Loesung: liegt der Beruehrpunkt auf der Gegenseite des Kreises,
> beschreiben dieselben Gleichungen den langen Weg herum. Das ist die
> M188-Lehre an neuer Stelle — ein Residuum kann Zweige nicht unterscheiden,
> weil beide exakt sind. Trennen kann sie nur die STETIGKEIT.
> `flippedCornerFillets` vergleicht deshalb mit dem Zustand VOR dem Solve: war
> ein Bogen, der tangential in einer Ecke sitzt (>= 2 Tangenten auf Linien),
> eben noch kleiner als ein Halbkreis und ist jetzt groesser, wird das Ergebnis
> verworfen wie ein nicht-endliches — die Geometrie bleibt auf dem letzten
> guten Stand, der Zug bleibt an der Grenze stehen. Bewusst nur diese
> Richtung: ein bereits grosser Bogen bleibt bearbeitbar, und die Reparatur
> (gross -> klein) wird nie blockiert. **Das repariert die kaputte Datei aus
> dem Bundle nicht**, es verhindert nur, dass so etwas neu entsteht.
>
> **NICHT behoben — die vierte Meldung** („wenn ich einen Radius auf einem
> Mittelpunkt-Rechteck mache, laufen die Konstruktionslinien nicht mehr in die
> Ecken, und die Ecken sollten als Konstruktion stehenbleiben wie beim
> Trimmen"). Diagnose steht, aus `bug20260805T003600`: die Diagonalen haengen
> per Koinzidenz an den ECKPUNKTEN der Rechteckseiten (`d0.p0` auf
> `line0.p0`), und `filletInventor` kuerzt genau diese Endpunkte — die
> Diagonale wandert also mit und endet am Verrundungsanfang statt in der Ecke
> (im Bundle: `[4] line data=[-29.2119, 16.9019, ...]` statt `-34.2119`).
> Der Entwurf, der beide Haelften der Meldung auf einmal loest: die
> weggeschnittenen Ecken als KONSTRUKTIONS-Stummel behalten (genau wie M187/
> M191 es fuer Trim tun), dann existiert die virtuelle Ecke wieder als echter
> Punkt — und die Diagonale wird auf DIESEN Punkt umgehaengt statt auf das
> gekuerzte Linienende. Nicht gebaut, weil die Constraint-Buchhaltung von
> `filletInventor` genau die Stelle ist, an der dieses Projekt schon zweimal
> (M37, M188) an Redundanz haengengeblieben ist; das gehoert sauber gemacht,
> nicht schnell.
>
> **Stand:** CI gruen zu `ab62145` — **1356 Tests** (17 neu,
> `m196_device_session_test.dart`, gebaut auf den Zahlen der Bundles), analyze
> 50 Issues / 0 Errors = Ausgangsstand. Die vierte Meldung ist in **M197**
> behoben.

> **M195 — automatischer Versand der Bug-Bundles: gebaut, dann ZURUECKGENOMMEN.**
>
> Der Upload (GitHub Contents API direkt, plus ein Relay-Modus auf eine selbst
> betriebene https-URL) war fertig und mit 31 Tests belegt. Er ist wieder
> RAUS — vollstaendig, nicht nur abgeschaltet.
>
> **Der Grund ist keine Implementierungsfrage, sondern eine harte Tatsache:**
> in ein GitHub-Repo schreibt niemand anonym. Anonyme Gists sind seit 2018
> weg, API, Push und Releases authentifizieren alle. Ein Repo-Token auf dem
> iPad war nicht gewollt (zu Recht: eine Klartextdatei auf einem Tablet), ein
> Relay verschiebt das Geheimnis nur auf einen Host, den es hier nicht gibt.
>
> **Stand ist wieder der von M194:** der Bericht wird lokal geschrieben
> (`Files > On My iPad > prototype > bugreports`) und von Hand verschickt.
>
> **Falls es doch einmal automatisch werden soll**, sind das die realistischen
> Wege — hier notiert, damit die Sackgasse nicht ein zweites Mal gebaut wird:
> (1) ein Git-Client, der seinen Zugang selbst im Keychain haelt (Working Copy
> + Shortcuts-Aktion), unsere App schreibt nur die Datei; (2) anonymer Upload
> zu einem oeffentlichen Host, die URL wird weitergereicht — kein Geheimnis
> irgendwo, dafuer ist das Bundle per Link lesbar; (3) gar kein Versand,
> sondern ein Ein-Tipp-Share-Sheet nach jedem Bericht. Was NICHT geht:
> anonymer Upload plus geplanter Action, die ihn einsammelt — der Host gibt
> eine ZUFAELLIGE URL zurueck, die nur das iPad kennt, und einen
> deterministischen anonymen Kanal gibt es aus demselben Grund nicht wie
> anonyme Schreibzugriffe.

> **M194 — der Bug-Report-Knopf in die Leiste.**
>
> Er war ein roter Kreis, der ueber der Zeichenflaeche schwebte, ziehbar, weil
> ein Fehlermelder, der den Fehler verdeckt, nutzlos ist. In der M192-Leiste
> verdeckt er nichts — sie ist Chrom, kein Werkzeug —, also entfaellt das
> Ziehen und ein Element weniger schwebt ueber dem Modell.
>
> **Platz:** ganz unten, durch eine Trennlinie abgesetzt. Er ist der eine
> Knopf, der beim Greifen nach einem Werkzeug niemals getroffen werden darf,
> und der Fuss der Leiste ist von jedem Werkzeug am weitesten weg. Rot bleibt
> er: er ist die Kruecke der Prototyp-Phase und soll temporaer aussehen.
>
> **In JEDER Ansicht**, auch auf der Home-Galerie, wo die Leiste sonst leer
> waere — ein Fehler in der Galerie ist auch ein Fehler, und der alte Kreis war
> dort erreichbar. Beim Schreiben der Tests fiel auf, dass genau das erst NICHT
> stimmte: `buildQuickTools` verlaesst sich zweimal ueber ein fruehes `return`
> (Home, ausserhalb des Editiermodus), und an einem davon fiel der Knopf still
> heraus. Deshalb prueft der Test alle vier Kontexte einzeln.
>
> **Code:** das Widget `BugButton` faellt weg, `BugReport.open(context, app)`
> bleibt — dieselben zwei Dialoge, dieselbe 120-ms-Pause vor dem Screenshot
> (die Melde-UI darf nicht auf dem Bild landen, das ist der ganze Grund fuer
> die Pause). **Kein Spinner mehr**: er wuerde genau in den Screenshot geraten,
> und die zwei Dialoge klammern die Wartezeit ohnehin ein.
> `BugReport.enabled = false` nimmt den Knopf mit, ohne den Rest der Leiste
> anzufassen.
>
> **Stand:** CI-Lauf `30940445242` gruen — **1339 Tests** (Basis 1307 + 16
> M192 + 9 M193 + 7 M194, alle 32 einzeln im Log geprueft), analyze 50 Issues /
> 0 Errors = Ausgangsstand. Der iOS-Job desselben Laufs ist ebenfalls
> durchgelaufen: **`GlassToolBar.swift` ist damit erstmals wirklich
> kompiliert**, die IPA gebaut und veroeffentlicht. Geraete-Test offen.

> **M193 — einzelne Objekte loeschen.**
>
> **Das Problem.** Das Kleinste, was eine Skizze verlieren konnte, war ein
> ganzer LAYER (`deleteLayer`). Ein Loeschen pro Objekt gab es nirgends — nicht
> auf einer Taste, nicht im Menue, nicht auf einem Knopf. Eine falsche Linie
> hiess: alles danach mit zurueckdrehen.
>
> **Drei Wege, ein Befehl.** `deleteSelection()` haengt an (1) dem Papierkorb
> in der M192-Leiste, der mit einer Auswahl ERSCHEINT — als LETZTER Eintrag,
> damit nichts darueber unter dem Daumen wegrutscht; er ist der einzige Knopf,
> der ohne Auswahl gar keine Bedeutung hat, also graut er nicht aus, er ist
> weg; (2) dem Long-Press, der jetzt VORHER auswaehlt, was unter dem Finger
> liegt (eine bestehende Auswahl bleibt unangetastet — sonst kollabierte ein
> Rahmen-Select auf das eine Objekt unter dem Finger) und im Menue rot
> „Delete" anbietet; (3) Entf/Backspace, bewusst UNTER dem HUD-Block, damit
> Backspace waehrend einer Werteingabe weiter die Zahl korrigiert statt
> Geometrie zu loeschen.
>
> **Die Falle ist die Index-Arithmetik.** Geometrie wird ueber INDIZES
> adressiert, und Constraints, Bemassungen und Projektions-Tags halten genau
> diese Indizes. Geloescht wird darum **hoechster Index zuerst** — sonst
> verschieben sich die Indizes unter den noch nicht abgearbeiteten Opfern —,
> `remapAfterRemove` wirft weg, was AUF das geloeschte Objekt zeigte, und
> `remapProjectionsAfterRemove` zieht die Projektions-Tags nach. Dieselbe
> Arithmetik wie `deleteLayer`, aus demselben Grund. Ein `_rebuildEngine` am
> Ende macht alles zu EINEM Undo-Schritt, auch wenn zehn Objekte fallen.
>
> **Reichweite.** Nur `geoEditable`: der Layer im Editiermodus. Ausserhalb des
> Editiermodus ist gar nichts loeschbar — der Layer IST der Bearbeitungsbereich
> (M17), und ein Loeschen ueber Layergrenzen hinweg waere die eine Operation,
> die das ignoriert.
>
> **Ehrlicher Stand:** 9 Tests (`m193_delete_selection_test.dart`). **Der
> erste Push war ROT** — `kDefaultLayer` liegt in `ffi/qcad_engine.dart`, nicht
> in `app_state.dart`; `flutter analyze` brach mit `undefined_identifier` ab
> und der Test-Schritt lief dadurch nie (CI-Lauf `30939902554`, Log auf
> `ci-debug-logs-dart`). Import nachgezogen, Ergebnis steht aus. Ohne
> Flutter-SDK im Sitzungs-Image faengt genau das niemand vor dem Push ab.
> Geraete-Test offen.

> **M192 — die Schnellwerkzeuge bekommen eine Flaeche.**
>
> **Das Problem.** Das Quick-Menue aus M53 haelt die zwei Befehle, ohne die
> kein laufendes Werkzeug auskommt: OK (Enter) und Abbrechen (Esc). Am Mac
> sind das Tasten. Auf dem iPad waren sie NUR ueber einen 600-ms-Long-Press
> oder die Pencil-Pro-Quetschung erreichbar — eine unauffindbare Geste vor dem
> einen Knopf, den jede halb gezeichnete Linie braucht. Undo/Redo lagen genauso
> versteckt (Zwei-/Drei-Finger-Tipp, Procreate-Sprache, ebenfalls M53).
>
> **Die Loesung.** Eine **vertikale Liquid-Glass-Leiste am rechten Rand**,
> dauerhaft sichtbar, **nur Icons** (Labels wuerden sie fuer Woerter doppelt so
> breit machen, die ein CAD-Nutzer kein zweites Mal liest). UIKit, derselbe
> `UIGlassEffect` wie Ribbon/Browser/Tab-Leiste, derselbe dunkle
> Trait-Override — ohne den kommt Glas in Flutters hellem Trait milchig heraus
> (M146). Knopfgroesse 44 pt, Apples HIG-Untergrenze, genau der Punkt der
> Uebung.
>
> **Inhalt, drei Stufen.** Undo/Redo ueberall — ein Fehlgriff ist ueberall
> moeglich. OK und Abbrechen (rot) ueberall dort, wo der SKETCHER lebt (Skizzen-
> Tab oder Kindskizze ueber einem Teil), ob im Editiermodus oder nicht; im Teil
> OHNE offene Skizze bleiben sie weg, statt dauerhaft dunkel dazustehen — ein
> Knopf, der nie leuchten kann, luegt ueber die Leiste. Innerhalb einer Stufe
> wandert nichts: die Knoepfe graut es aus, sie verschwinden nicht, denn ein
> Ziel, das unter dem Daumen wegrutscht, trifft man nicht ohne hinzusehen. Im
> Layer-Editiermodus zusaetzlich Linie, Kreis, Rechteck, Bemassung und
> Trimmen; Trimmen steigt in die Modify-Familie ein und schaltet drinnen
> Split -> Trim -> Extend weiter (die Rechtsklick-Rolle aus M49). OK ist
> bewusst NUR fuer Werkzeuge mit variabler Punktzahl (Splines) und das
> Freihand-Fenster aktiv — Werkzeuge mit fester Punktzahl committen sich
> selbst, und ein OK, das nichts tut, ist schlimmer als ein dunkles.
> Undo/Redo folgen dem Journal, das gerade gilt: Skizze in der Skizze, Teil im
> Teil.
>
> **Platz.** Vertikal zentriert zwischen Ribbon und Tab-Leiste — oben rechts
> sitzt der ViewCube, unten rechts die Constraint-Anzeige, beide waren zuerst
> da. Die zwei modeless Fenster (Pattern, Fillet/Chamfer) weichen um die
> Leistenbreite nach links aus.
>
> **Nichts wurde entfernt**: Long-Press, Quetschung und alle Tasten laufen
> unveraendert weiter. Die Leiste ist dieselbe Befehlsmenge mit einer Flaeche.
>
> **Aufteilung.** `buildQuickTools` / `runQuickTool` sind PUR (Dart, host-
> testbar): welcher Knopf existiert, welcher lebt, was ein Tipp aufruft. UIKit
> besitzt die Pixel (`GlassToolBar.swift`). Dieselbe Grenze wie Tab-Leiste und
> Browser, aus demselben Grund.
>
> **Stand:** CI-Lauf `30938913544`, Job „Dart analyze + host tests": **1323
> Tests gruen** (16 neu, `m192_quick_tools_test.dart`), analyze 0 Errors. Beide
> Schritte laufen unter `set -o pipefail`, der gruene Haken ist also
> aussagekraeftig. Analyze meldete 51 statt 50 Issues — ein
> `unnecessary_import` im neuen Test, in M193 entfernt. Das Sitzungs-Image
> selbst hat kein Flutter-SDK, hier lief nichts. **Swift ist damit NICHT
> geprueft**: `GlassToolBar.swift` kompiliert erst im iOS-Job. Geraete-Test
> offen.

> **M191 — der Trim behaelt nur die WEGGESCHNITTENE Spanne, und getippte Masse
> entstehen wirklich.** Drei Meldungen zu Build `83dc216`.
>
> **(1) „es sollte nur eine Konstruktionslinie fuer den Teil geben, der
> tatsaechlich weggeschnitten wurde."** M187 hatte das ganze getrimmte OBJEKT
> als Konstruktionsgeometrie behalten — also lag unter jedem sichtbaren Stueck
> eine gestrichelte Vollkopie (im Bundle doppelt zu sehen:
> `line [23.98,19.50 -0.99,19.50]` zweimal). Jetzt bleibt genau die Spanne, die
> der Schnitt entfernt hat: `trimCutAway` ist das exakte Komplement von
> `trimEntity` — beide kommen aus derselben Klammerarithmetik, weil getrennt
> gerechnet genau das auseinanderlaeuft. Behaltene Spanne + weggeschnittene
> Spanne deckt das Original einmal, ohne Ueberlappung.
>
> **(2) „der zweite Kreis laesst sich nicht ziehen … die Linien sind alle
> weiss."** Dieselbe Ursache: die Bindungen, die jedes sichtbare Stueck auf
> seine Traegerkopie hefteten, zogen die Skizze auf `dof=0 freePoints={}` —
> daher auch die Vollbestimmt-Farbe. Mit der Kopie faellt der ganze
> Traeger-Apparat weg (`_trimKeepingCarrier`, `_bindPiecesToCarrier`, 107
> Zeilen), die Stuecke laufen wieder ueber `remapAfterReplace` und behalten
> ihre Freiheiten. Was die weggeschnittene Spanne bringt: eine Bemassung, die
> vorher mit dem Schnitt starb, findet jetzt Geometrie — im Test messen die
> beiden Enden weiter die vollen 40 mm, eines auf dem Stueck, eines auf dem
> Geist.
>
> **Die eine Feinheit dabei:** der Geist braucht EINE Gleichung, um auf seiner
> Herkunft zu bleiben — `equal` beim Radius, ein Punkt-auf-Linie beim geraden
> Stueck. `concentric` bzw. `collinear` waeren zwei Gleichungen fuer denselben
> einen Freiheitsgrad, und das Overconstrain-Tor lehnt sie zu Recht ab.
> Gemessen ohne diese Bindung: nach einem Zug lagen die Geist-Boegen 2.5 und
> 3.7 Einheiten neben den Mittelpunkten ihrer Partner, Radius bis 3.6 daneben.
> Mit ihr: 3e-14.
>
> **(3) Getippte Masse entstanden nicht.** `_hudBuildDims` verlangte fuer die
> Rechtecke `placedCount == 4`; die mittenbasierten Rechtecke committen aber
> SECHS Objekte (vier Seiten + zwei Konstruktionsdiagonalen), also lief der
> Zweig nie — die Groesse stimmte (die Locks formen die Geometrie), das Mass
> fehlte. Jetzt `>= 4`, `rect3PC` mit dazu, und die Beschriftung sitzt 8 mm
> NEBEN der gemessenen Seite, nach AUSSEN vom Formmittelpunkt weg (blind nach
> unten/rechts versetzt landet sie beim mittenbasierten Rechteck im Inneren).
>
> 1307 Tests gruen (7 neu in `m191_trim_leftover_and_hud_dims_test.dart`; die
> Trim-Kontrakte aus M36/M187/M188 und die zwei Bind-Regressionen auf das neue
> Modell gezogen — sie pruefen jetzt wieder die sichtbare Geometrie, weil jeder
> Schnittpunkt einen gestrichelten Zwilling hat), analyze 50 Issues / 0 errors.
> Das getippte Mass geht durch denselben `hudInput`/`hudTab`-Pfad wie am Geraet.

> **M190 — jeder gruene Build wird ein Release, und das iPad meldet sich.**
>
> Bisher endete M5 mit einem Artefakt, dessen Download einen GitHub-Login
> braucht — SideStore hat keinen. Neu: `ci/publish_release.sh` legt nach jedem
> gruenen M5 das Release `build-<Run-Nummer>` an, mit der IPA, einer
> `source.json` (SideStore-Source, die letzten 10 Builds) und einer
> `latest.json` fuer den Shortcut. Einstieg ueber GitHubs
> `/releases/latest/download/<asset>`-Redirect, also feste URLs ohne
> Extra-Branch. Danach `ci/notify_build.sh` (Pushover oder ntfy, ohne Secrets
> ein No-op). Geraeteseite: `AUTOINSTALL.md`.
>
> **Der Weg ist der selbst ausgeloeste Shortcut**, nicht die Automation: ein
> Shortcut im Kontrollzentrum schlaegt bei jedem Auslosen `latest.json` nach,
> hebt den VPN und ruft den Deep Link. Er braucht keinen Dienst und kein
> Secret. Push ist nur noch das Signal „es liegt was bereit" und ausdruecklich
> optional; eine Mail-Automation als Ausloeser ist raus (vom Nutzer
> abgelehnt).
>
> **Die Bundle-Version ist jetzt die Run-Nummer** (`--build-name=0.1.<run>
> --build-number=<run>`), und zwar in BEIDEN `flutter build ios`-Aufrufen. Nur
> im zweiten reicht nicht: der `--config-only`-Lauf schreibt die
> `Generated.xcconfig`, der Release-Lauf schreibt sie mit anderer Version neu,
> und der Pod-Schritt war umsonst. Vorher trug jede IPA `0.1.0 (1)` aus der
> pubspec — man sah am Geraet nicht, welcher Build laeuft.
>
> **Was NICHT geht, im SideStore-Quelltext nachgesehen statt in der Doku
> geglaubt:** ein Install ohne Tipp. `sidestore://install?url=…` geht ueber
> `URLHandler.swift` und `MyAppsViewController.importApp` immer in
> `InstallAppDialog.present` — ein Alert mit Install/Cancel; der Weg ueber eine
> `.ipa`-Datei muendet im selben Dialog. Die einzigen App-Intents sind
> `RefreshAllAppsIntent` (+ Widget), also kein Install im Hintergrund, und ein
> Auto-Update aus einer Source existiert nirgends (`autoUpdate`,
> `automaticallyUpdate`, `installUpdates`: null Treffer). Null Tipser gaebe es
> nur mit SideStore-Fork, TestFlight (99 $/Jahr) oder AltServer auf einem
> Dauerlaeufer im WLAN. Gewaehlt wurde bewusst der Zwei-Tipp-Weg.
>
> Der Notification-Link zeigt auf `shortcuts://run-shortcut?name=Install%20…`
> und nicht auf `sidestore://`, damit der Shortcut den VPN einschalten kann,
> BEVOR SideStore uebernimmt — ohne Tunnel scheitert SideStore erst beim
> Signieren, also nach dem Download.
>
> **Am Geraet noch nicht gesehen:** die ganze Geraeteseite. Verifiziert sind
> nur die CI-Haelfte (Trockenlauf mit gestubbtem `gh`: Manifeste, Reihenfolge
> neueste-zuerst, Kappung bei 10, Fallback bei kaputter Vorgaenger-Source) und
> das Schema gegen SideStores CodingKeys. Ob Shortcut, Push und Deep Link in
> dieser Kette wirklich durchlaufen, zeigt erst der erste Build danach.

> **M189 — App-Icon.**
>
> Artwork vom Nutzer geliefert (isometrischer Wuerfel, orange `#FF592D`, „P" mit
> quadratischer Punze, gestrichelte Rueckkanten), gewuenscht auf cremeweissem
> Grund. Gewaehlt: **`#FAF6EC`**, Glyphenhoehe **65 %** der Kachel.
>
> **Die eine Stelle, an der man sich hier vertut:** zentriert wird auf den
> **soliden** Bildrand (279,244)-(746,800), NICHT auf den Alpha-Rand
> (260,142)-(749,935). Der Unterschied ist der weiche Schatten; auf den
> Alpha-Rand zentriert sitzt das Motiv sichtbar zu hoch. Beide Zahlen stehen im
> Generator, damit das beim naechsten Artwork nicht neu erraten wird.
>
> **Warum der Satz nicht im iOS-Baum liegt:** den gibt es nicht. `flutter
> create` erzeugt `ios/` in JEDEM CI-Lauf neu — und schreibt dabei Flutters
> blaues Standard-Icon. Der Satz liegt also in `frontend/branding/` und der
> Workflow kopiert ihn unmittelbar nach dem Scaffolding darueber. Davor steht
> ein `test -f`: ohne das waere ein verschobener Pfad ein GRUENER Build mit
> Platzhalter-Icon — genau die Sorte Fehler, die ein Haken verdeckt.
>
> **Alle 15 Groessen sind opakes RGB.** Ein Alphakanal ist bei Apple fuer das
> 1024er-Marketing-Icon ein Ablehnungsgrund und rendert am Geraet schwarz; der
> cremefarbene Grund wird deshalb hier einkomponiert und nicht der Plattform
> ueberlassen.
>
> Quelle (`app_icon_source.png`, 1024 RGBA) und Generator (`make_app_icon.py`,
> braucht Pillow, laeuft NICHT in der CI) liegen daneben — der Satz ist
> reproduzierbar, statt aus dem groessten PNG rueckgerechnet werden zu muessen.
>
> 1300 Tests gruen (4 neu in `m189_app_icon_test.dart` — Contents.json gegen die
> tatsaechlichen IHDR-Groessen, Alphakanal-Verbot, Vollstaendigkeit des
> iPad-Satzes), analyze 50 Issues / 0 errors. **Am Geraet noch nicht gesehen:**
> ob das Icon auf dem Home-Screen so wirkt wie in der Vorschau.

> **M188 — fuenf Meldungen zu Build `d6df102`, zwei Ursachen. Die erste war
> meine eigene aus M187.**
>
> **(1) Die M187-Bindung eines RUNDEN Stuecks war unsound.** Ich hatte
> `equal` + „beide Endpunkte liegen auf dem Rand" gewaehlt und im Kommentar
> ausdruecklich begruendet, warum NICHT `concentric` — die redundante Zeile.
> Der Rangzaehler stimmte, die Geometrie nicht: drei Gleichungen, die den
> Mittelpunkt nur **diskret** festlegen. Der an der Sehne gespiegelte
> Mittelpunkt erfuellt jede davon. Das Geraet fand ihn:
> `arc data=[-1.5312, -0.0920, 8.4957 …]` auf einem Traeger im Ursprung.
>
> Dieselbe Schlupfrichtung machte den Rest: ein Zug am zweiten Kreis lief den
> Traegerradius auf **null** (`circle data=[0, 0, 0.0000]`, „i moved the second
> circle and the first circle collapsed"), danach trug die Skizze dauerhaft
> 3.6e-6 Residuum (`satisfied=false` in JEDEM Solve des Logs), und jede spaetere
> Operation startete aus einer entarteten Lage.
>
> **Lehre, teuer bezahlt:** *zwei diskrete Loesungen sind keine Bedingung.* Ich
> hatte nur DOF gezaehlt. Ein Rangargument sagt nichts darueber, ob die zweite
> Wurzel erreichbar ist — und der LM findet sie. Jetzt `concentric` + `equal`.
> Die befuerchtete Redundanz an den Endpunkten faellt sauber durchs Tor, genau
> wie sie soll.
>
> **(2) `filletInventor` trimmt das falsche Linienende** — ein aelterer,
> eigenstaendiger Fehler, den erst der zweite Radius sichtbar macht. Der Code
> bewegte den Endpunkt, der dem TANGENTENPUNKT naeher liegt; der Kommentar
> darueber sagt seit jeher, was richtig waere („the endpoint inside the corner
> moves"). Solange die Kante lang ist, ist das dasselbe. Nach dem ersten Radius
> nicht mehr: eine von 15 auf 9.01 verkuerzte Kante hat ihren zweiten
> Tangentenpunkt **4.01 vom falschen** und **5.0 vom richtigen** Ende entfernt.
> Also zog der zweite Radius das Ende, das der erste schon an seinen Bogen
> geklebt hatte — beide Boegen hingen am selben Punkt, die Kante fiel auf Laenge
> 0 zusammen, der Solve scheiterte, die Operation wurde zurueckgerollt
> („somehow I couldn't make a radius on the second corner of the rect",
> „the horizontal line of the rect was lost when making a radius"). Die alte
> Ecken-Koinzidenz blieb aus demselben Grund stehen: der Aufrufer sucht sie
> ueber genau diese Punktindizes. Gewaehlt wird jetzt ueber die Projektion auf
> den Tangentenpunkt der ANDEREN Auswahl — das ist die Eckseite, unabhaengig
> von den Laengen der beiden Stuecke.
>
> **(3) „when dragging the rect around it behaved really buggy"** war kein
> dritter Fehler. Der Zug loest die GANZE Skizze, und in derselben Skizze lag
> der entartete Guertel aus (1): das Log zeigt `err=6.77e+0 satisfied=false`,
> Rueckfall auf `lm-relaxed`, `maxAbs` springt 27→33→35. Auf einer gesunden
> Skizze bleibt das Rechteck beim Ziehen exakt rechteckig (H/V-Abweichung 0.0,
> Residuum ~1e-10) — als Test festgehalten. **Am Geraet nachpruefen**, das ist
> die eine der fuenf Meldungen, die nur indirekt belegt ist.
>
> **Neu im Log:** eine abgelehnte Fillet/Chamfer-Operation schreibt jetzt den
> Satz, den sie nicht loesen konnte (`sketchDump`). Ohne den war aus dem
> Geraete-Log nur ablesbar DASS der Solve aufgab; mit ihm sieht man in einer
> Zeile, dass beide Boegen am selben Endpunkt hingen.
>
> 1296 Tests gruen (9 neu in `m188_trim_carrier_soundness_test.dart`, die
> Geraete-Skizze auf die Ziffer nachgebaut), analyze 50 Issues / 0 errors.

> **M187 — die ersten drei Meldungen, die durch den M184-Bug-Knopf kamen.**
>
> Drei Bundles aus derselben Geraete-Sitzung (Build `ef22833`):
> `bug20260804T112452`, `T112835`, `T112936`. Alle drei sind aus dem LOG
> hergeleitet, nicht aus dem Code erraten — genau das, wofuer M184/M185/M186
> gebaut wurden, und es hat beim ersten Einsatz funktioniert: in allen drei
> Faellen stand die Ursache in `log.txt` und im Sketch-JSON.
>
> **(1) „Trimme eine Seite des Kreises mit 2 Linien dran → der GANZE Kreis war
> weg."** Der Log zeigt den Trim auf `e2` (Kreis r8.2223) und danach
> `arc data=[…, 4.9872242902, 4.9872410503]` — ein Bogen von **1.7e-5 rad**.
> Also keine Loeschung, ein Null-Bogen. Beide Linien sind TANGENTEN und enden
> auf dem Rand. Mit den echten Zahlen nachgerechnet:
> * Linie 1: Wurzeln bei `t = 1.0000009` und `1.0000053` — beide ausserhalb des
>   festen `[-1e-9, 1+1e-9]`-Fensters in `_segCircle`, also **verworfen**. Der
>   Beruehrpunkt sitzt 9.1e-5 Weltmass HINTER dem Linienende, obwohl der
>   Endpunkt radial nur 2.6e-10 danebenliegt: an einer Tangente wird ein
>   radialer Fehler eps zu einer Verschiebung von ~sqrt(2·r·eps) ENTLANG der
>   Linie. Ein Parameter-Epsilon kann das nie treffen.
> * Linie 2: dieselbe Tangente, aber die Wurzeln fielen knapp ins Fenster —
>   **zwei** Schnittpunkte 1e-4 auseinander. Getrimmt wurde die Spanne dazwischen.
>
> Beides in `_segCircle`: die Diskriminante IST `4aa(r²-dPerp²)`; alles
> innerhalb `2·r·1e-6` ist eine Tangente und liefert **genau einen** Punkt. Die
> Segmentgrenze wird nicht mehr parametrisch, sondern **radial** geprueft
> (Wurzel auf [0,1] klemmen, fragen „liegt der Punkt noch auf dem Rand"). Dazu
> `_distinct` (Punkte naeher als 1e-6 sind EIN Punkt) und ein laengenskaliertes
> Endfenster in `_segSeg`.
>
> **(2) „Endpunkt landete auf einem Kreis, kein Punkt-auf-Kreis — beim
> Startpunkt hat es geklappt."** Der Log entscheidet: die Linie wurde ZUERST
> gezeichnet (Startpunkt auf Kreis 0 → Bindung entstand), der zweite Kreis
> DANACH, mit seinem Rand-Klick exakt auf dem Linienende. Die Inferenz fragte
> immer nur „landet ein Punkt des NEUEN Objekts auf etwas Aelterem" — die
> Bindung hing damit an der Zeichenreihenfolge. `inferPointBindings` bindet
> jetzt auch rueckwaerts (bestehender Punkt auf die neue Kurve); diese
> Rueckwaerts-Bindung geht durch dasselbe Overconstrain-Tor wie eine manuelle
> Bedingung (`isReverseBind`), weil sie als einzige inferierte Relation eine
> bereits voll bestimmte Skizze treffen kann.
>
> **(3) „Beim Trimmen soll die Originallinie immer als Konstruktionslinie
> stehenbleiben, damit Masse/Bedingungen nicht zerstoert werden."** Umgesetzt
> wie gefordert: der Traeger bleibt an SEINEM Index liegen, nur umgestylt —
> also wird **kein einziges Constraint umgehaengt** (`remapAfterReplace` laeuft
> auf diesem Pfad gar nicht mehr) und keines faellt weg. Die Stuecke haengen
> per Punkt-auf-Punkt (geerbter Endpunkt) bzw. Punkt-auf-Kurve (Schnittpunkt)
> am Traeger, runde Stuecke zusaetzlich per `equal`; die MITTE wird bewusst
> nicht gepaart, weil concentric+equal beide Endbindungen impliziert und genau
> diese redundante Zeile den Solver „inkonsistent" sagen laesst (dieselbe Falle
> wie beim Slot-parallel, M114).
>
> **Folge, die man kennen muss:** ein Schnittpunkt ist jetzt durch
> Traeger ∩ Schneider VOLL bestimmt. Das alte explizite Punkt-auf-Punkt
> gestapelter Schnittecken (der Fix aus der 07-17-Sitzung) ist dadurch redundant
> und wird vom Tor abgelehnt — richtig so, aber `_bindCutPoints` musste lernen,
> danach auf die Kurvenbindung ZURUECKZUFALLEN, sonst blieb das Schnittende
> lose. Die beiden Regressionstests haben ihren Kontrakt getauscht: nicht mehr
> „ein Punkt-auf-Punkt existiert", sondern „beide Enden sind gepinnt und kommen
> nach einem Stoss wieder auf EINEN Punkt zusammen". Ausserdem bevorzugt
> `_pickEntity` bei Gleichstand normale Geometrie — das Stueck liegt exakt auf
> dem Ghost, und der Ghost hat den kleineren Index.
>
> **Nicht gemacht, bewusst:** eine Bindung, die beim ZIEHEN eines Punktes auf
> eine Kurve entsteht. Der Log zeigt, dass Meldung (2) vom Zeichnen kam;
> Inventor inferiert beim Ziehen bestehender Geometrie ebenfalls nicht.
>
> **Offene Produktfrage aus (3):** ein Trim, der NICHTS schneidet, laesst jetzt
> einen Konstruktions-Ghost stehen (mit Toast) statt die Geometrie zu loeschen.
> Das folgt dem „immer" der Meldung, ist aber der eine Fall, in dem Loeschen
> richtiger sein koennte — am Geraet entscheiden.
>
> 1287 Tests gruen (13 neu in `m187_trim_and_binds_test.dart`, 9 alte
> Trim-Erwartungen auf den neuen Kontrakt gezogen), analyze 50 Issues /
> 0 errors = Ausgangsstand dieses Branches.

> **M186 — die drei Lücken aus dem M185-Audit geschlossen.**
>
> * **Screenshot.** `RepaintBoundary` um den ganzen Body, PNG ins Bundle.
>   **Wichtig:** auf iOS ist der 3D-Körper eine RealityKit-PLATFORM-VIEW, vom
>   OS ausserhalb von Flutters Layer-Tree komponiert — er ist im Bild NICHT
>   drin, egal wie man aufnimmt. 2D-Skizzen (CustomPainter) sind vollständig
>   drauf. `report.md` schreibt das ausdrücklich dazu, damit ein leerer
>   Viewport im Bild nie als „Körper fehlt" gelesen wird.
> * **Roher Pointer-Stream** (`gesture_trace.dart`). Ringpuffer, 800 Events,
>   `Listener` ganz aussen, also VOR der Gesture-Arena. Moves werden pro
>   Pointer auf ~25 ms ausgedünnt, damit ein Flick nicht die Vorgeschichte
>   verdrängt. Nicht ins Log (120 Hz pro Kontakt), nur ins Bundle.
> * **Native Grenze** (`RealityPush` in `reality_scene.dart`). Was Dart
>   zuletzt hinübergereicht hat: Szenen-Signatur, Solids mit Tri/Vert/Revision,
>   Kamera, Zähler und Zeitstempel. Sagt genau, auf welcher Seite der Grenze
>   der Fehler liegt: steht dort ein Körper mit 4 148 Dreiecken und der Schirm
>   ist leer, liegt es hinter der Linie — steht nichts da, davor.
>
> **Der Fund dabei:** der erste Screenshot-Widget-Test hing zehn Minuten.
> `toImage` gibt die Arbeit an den Rasterizer und wartet; headless (und damit
> auch: App im Hintergrund, keine Surface) antwortet niemand und der Future
> bleibt für immer pending. Ohne Deadline hätte der Bug-Button die App
> aufgehängt — beim Melden eines Aufhängers. `captureScreenshot` hat jetzt
> ein Timeout, der Rest des Bundles ist davon unberührt.
>
> `m184_bug_report_test.dart` (31, inkl. M186-Gruppen) +
> `m186_screenshot_test.dart` (2). analyze 0 errors, **1267 grün**.
>
> **Offen:** kein Share-Sheet; die native Seite loggt weiterhin nur, was Dart
> ihr gibt, nicht was RealityKit daraus macht.

> **M184 — Bug-Button, Bundle und Logging, das die Frage schon beantwortet.**
> Ziel: EIN Zip, das alles sagt, ohne dass der Melder etwas dazuschreiben muss.
>
> * **Der Button** (`widgets/bug_button.dart`, TEMPORÄR — `BugButton.enabled`
>   ist der eine Schalter). Schwebt über allem, ist ZIEHBAR (ein Reporter, der
>   den Bug verdeckt, ist nutzlos), Tap öffnet ein Textfeld, danach steht der
>   Pfad zum Kopieren da. Leerer Text ist erlaubt: der State-Dump ist die
>   wertvolle Hälfte und der ist so oder so vollständig.
> * **Das Bundle** — `bug_report.dart` rein und host-testbar, `bug_capture.dart`
>   für AppState/FFI/Disk. Inhalt: `report.md` (Triage ZUERST: SICK / SILENT /
>   NOT FINITE / BODY GONE), `state.txt` (jedes Feature mit Parametern via
>   eigenem toJson, Solid oder Fehler, JEDER Edge-Fingerprint samt `tol`, jede
>   Skizze mit Geometrie und Constraints), `part.json`, `sketches/`,
>   `mesh.txt` (voller Watertight-Report, `meshDiagnostics` erzwungen),
>   `log.txt`, `log_prev.txt`, `env.txt`.
> * **Zip ohne Paket** (`zip_writer.dart`): `ZLibCodec(raw: true)` ist genau der
>   DEFLATE-Stream, den Methode 8 will, der Rest sind vierzig Byte Header. Ein
>   Reporter, der von einem geglückten `pub get` abhängt, fehlt genau dann,
>   wenn der Build in Schwierigkeiten ist. Der Test entpackt mit dem echten
>   `unzip`, nicht mit dem Writer, der die Bytes erzeugt hat.
> * **2D:** ein gescheiterter Solve nannte nur die Skizze — unbrauchbar. Jetzt
>   `constraintResidualsPer` + `solveFailureDump`: WELCHE Constraints nicht
>   halten, schlechteste zuerst, mit den Entities, auf die sie zeigen. Halten
>   alle, sagt der Dump ausdrücklich DEGENERATE GEOMETRY, statt eine leere
>   Liste zu zeigen, die neben einem Fehlschlag wie „alles in Ordnung" aussieht.
> * **3D:** `meshAnomalies` meldet leere Tessellation, Normals/Positions-
>   Mismatch und nicht-endliche Vertices als WARN — plus den teuren
>   Self-Report, ohne dass jemand vorher ein Flag kennen musste.
>
> **Bewusst NICHT gemeldet:** hohe Dreiecke-pro-Fläche. Das sah nach der
> Signatur eines selbstschneidenden Blends aus (63 101 Dreiecke auf 21
> Flächen), ist es aber nicht: dasselbe Solid hatte kurz davor 20 822, und
> geändert hat sich nur die Deflection. Eine Warnung, die bei normalem Zoomen
> feuert, ist schlechter als keine — sie bringt dem Leser bei, das Tag zu
> überspringen.
>
> `m184_bug_report_test.dart` (21). analyze 0 errors, **1255 grün**.
>
> **Offen:** kein Share-Sheet (Pfad wird angezeigt/kopiert, Datei über Files
> holen), kein Screenshot im Bundle.

> **M183 — Fillet und Chamfer, die nicht kaputtgehen.** Basis: Geräte-Log auf
> Kopf `0ad6cc3` plus der Nutzerbericht „2 mm Fillet auf 2 mm Wand → Fehler,
> 1.999 geht". Drei belegte Wurzelursachen, alle auf dem Weg zwischen „Nutzer
> hat diese Kante gepickt" und „Kernel rundet sie":
>
> * **F1 — Ein verschobener Körper galt als gelöscht.** Extrusion1 von 5 auf
>   7 mm erhöht → der Boss darüber wandert 2 mm, beide Chamfer-Kanten mit ihm.
>   2 mm ist mehr als die 0.66 mm, die ein 1.64-mm-Rim driften darf, also
>   meldete das Log `sel[0] LOST`, `sel[1] LOST` und das Feature starb mit
>   „none of the selected edges exist any more" — bei einem Edit, das keine
>   der beiden Kanten entfernt hat. `resolveEdges` löst jetzt in zwei Phasen:
>   erst wie bisher, dann darf eine verlorene Auswahl an einer VERSCHIEBUNG
>   wiedergefunden werden — aber nur an einer, die das Feature aus eigener
>   Evidenz belegen kann (ein Geschwister hat sie eigenständig aufgelöst, oder
>   sie erklärt unabhängig zwei verlorene Auswahlen). Eine frei erfundene
>   Verschiebung erklärt jede Kante und wäre genau das Weglaufen, gegen das
>   M158 geschrieben wurde.
> * **F2 — Eine deutlich andere Kante wurde akzeptiert.** Log: `sel[0] ->
>   edge 8 ... l=17.964 ... got l=12.802`. Länge war ein 0.05-Gewicht, also
>   kostete ein 29-%-Sprung ein Viertel der Toleranz. Jetzt 0.5 — aber auf
>   einem Kreis sind Radius und Umfang DIESELBE Tatsache, doppelt berechnet
>   würde ein schrumpfender Rim mit 2π bestraft. Also: Radius misst die Grösse,
>   der überstrichene WINKEL misst die Ausdehnung. Gleicher Radius, zwei
>   Drittel der Länge heisst Bogen statt Vollkreis, und das ist eine andere
>   Kante.
> * **F3 — OCCT kann keinen Blend bauen, der exakt auf einer Tangente landet.**
>   Offen seit 2010 (GitHub-Issue #172). Genau der Nutzerbefund: 2.0 scheitert,
>   1.999 geht. Der Shim (v16) versucht jetzt eine Leiter: exakt, dann 1e-6,
>   1e-5, 1e-4, 1e-3 relativ darunter. Auf 2 mm sind das höchstens 2 µm — unter
>   jeder Fertigungstoleranz, tausendfach über `Precision::Confusion` — und der
>   Aufrufer ERFÄHRT, welche Sprosse benutzt wurde (`BlendReport`, in ppm).
>
> Dazu zwei Dinge, die der Shim vorher gar nicht konnte: das Ergebnis geht
> durch `BRepCheck_Analyzer` (`IsDone()` ist NICHT hinreichend — daher der
> Mesher, der 10.7 s mahlte und 63 k Dreiecke für 21 Faces ausspuckte), und
> eine unmögliche Kante killt nicht mehr das ganze Set: erst alle zusammen,
> dann jede einzeln geprüft, dann die Überlebenden greedy aufgebaut. Fehler
> werden aus `StripeStatus`/`NbFaultyContours` benannt statt pauschal „radius
> too large?" zu raten.
>
> Tests: `m183_blend_robustness_test.dart` (20 host tests) pinnt F1/F2 und den
> Report; `smoke_occt.c` [21c]/[21d] pinnen F3 und das Teil-Ergebnis im Kernel
> (nur dort läuft C++ überhaupt). analyze 0 errors, **1234 grün**.
>
> **Offen:** Der Report läuft ins Log, nicht in den Browser — eine Sprosse
> unter Nennmass oder eine übersprungene Kante sollte am Feature sichtbar
> sein. Und mit nur ZWEI gepickten Kanten, von denen eine gelöscht wird und
> der Körper sich gleichzeitig verschiebt, fehlt die Korroboration: beide
> gehen verloren. Drei Kanten reichen.

> **M182 — „A system that cannot break": der Part-Recompute ist jetzt ein
> Sicherheitsnetz.** Basis: Geräte-Bericht auf Kopf `29c203a` (Log +
> Session-Verlauf): Fillet1 auf vier Zylinderkanten brach die zweite Extrusion,
> Revolution1/2 fielen mit „no closed profile in Sketch5/6", Chamfer1 verlor
> sein Base, und ein unsichtbar geschalteter Extrusionskörper zerstörte Solid1.
> Vier Wurzelursachen (alle aus dem Log belegt, Details in `M182_ANALYSIS.md`):
> (1) **Sichtbarkeit war Geometrie** — der Fold rückte nur mit
> `if (f.visible)` vor, ein verstecktes Feature verschwand aus dem Körper und
> liess den nächsten Modify ohne Base. (2) **Ein Fehler erzeugte ein Phantom** —
> nach Chamfer1-Fail materialisierte Extrusion4 als freistehender „cut" ohne
> base. (3) **Projektionen folgten dem kaputten Körper** — SyncSolidProjections
> schrieb die verrutschten Segmente in Sketch5/6, die geschlossenen Profile
> öffneten sich, die Revolutions fielen. (4) **Der kaputte Zustand wurde
> persistiert** — mutierender Recompute + Save nach jeder Aktion; und Löschen
> (Body/Feature/Sketch/unterhalb EOP) war irreversibel.
>
> **Was drin ist (alles in `M182_ANALYSIS.md` + `m182_cannot_break_test.dart`):**
> * **F1** Sichtbarkeit ist Display, nie Geometrie: der Fold läuft durch jedes
>   Feature, `visible` steuert nur das Zeichnen.
> * **F2** Ehrlicher, eingedämmter Fehlschlag: ein fehlgeschlagener Recompute
>   lässt das Feature SICK zurück (kein Solid + Fehlertext; bestehender
>   m56-Vertrag „deleting the profile marks the feature sick, honestly") —
>   der Schutz liegt in der Eindämmung (keine Kaskade, kein Phantom, kein
>   Persistieren des kaputten Zustands), nicht in stehengebliebener Geometrie.
> * **F3** Keine Phantome: scheitert ein Feature, werden alle späteren
>   Features DESSELBEN Körpers mit „feature X on this body failed" markiert
>   statt mit null-Base zu rechnen; ein nicht-'new'-Feature ohne erreichbares
>   Base meldet „no solid before this feature".
> * **F4** Atomarer Durchgang: Face-Settle und Projektions-Sync laufen nur
>   nach erfolgreichem Recompute.
> * **F5** Projektions-Closure-Guard (`freezeProjectionUpdatesThatBreakLoops`,
>   pur und host-getestet): ein Update, das eine geschlossene Schleife eines
>   verbrauchten Sketches öffnen würde, wird verweigert — die bewegten Segmente
>   frieren als `projBroken` auf ihrer alten Kurve. Dazu `_projTol` von 25 % auf
>   5 % (kein Sprung auf eine fremde Kante derselben Art).
> * **F6** Nativer Browser: der Expander-Key ist jetzt die Zeilen-ID
>   (`ft:Name` statt `Name`) — Extrusionen/Revolutionen lassen sich endlich
>   aufklappen und zeigen ihre Skizze.
> * **F7** Part-Undo für destruktive Operationen (Feature/Body/Sketch/Below-EOP
>   löschen): Snapshot-Journal pro Part (PartModel-JSON + alle Kind-Sketchen als
>   UndoSnaps), Ctrl/Cmd+Z / Ctrl+Shift+Z / Ctrl+Y im 3D-Viewport,
>   Bestätigungsdialog für das native „Delete all features below EOP".
> * **F8** Ehrliches Logging (Feature-Löschungen, Restores, Sick-Zustände).
>
> **Verifikationsstand — ehrlich:** geschrieben auf Branch
> `m182-cannot-break` (Basis `session/m130-m145-kernel-features`, Kopf
> `29c203a`), **8 neue Host-Tests** (`m182_cannot_break_test.dart`), aber
> NICHT lokal ausgeführt — keine Flutter/Dart-Toolchain in der Session. Gate:
> die drei per workflow_dispatch angestossenen Workflows (m1-core-build mit
> dart-checks/m3/m5-IPA, occt-build, slvs-build) + Geräte-Test. Der
> Geräte-Bericht dieser Sitzung ist die Regression-Fixture: die Kaskade darf
> sich nicht reproduzieren lassen.
>
> > ## ⇢ STAND FUER DIE NAECHSTE SITZUNG (Kopf `7ab7ee5`, M154–M161)
>
> **Alles aus einem einzigen Geraete-Bericht** (Build `684d35e`, Log +
> Screenshot + vier `.part.json`). **956 Host-Tests gruen**, `flutter analyze`
> 50 Issues / 0 errors = Ausgangsstand, lokal mit Flutter 3.32.0. Der Lauf auf
> `285a176` (M154–M160) ist in ALLEN VIER Jobs gruen, IPA inklusive —
> Schritt fuer Schritt im Log geprueft, nicht am Haken.
>
> **Sechs der acht sind durch Tests festgenagelt, die OHNE den Fix rot laufen.**
> Zwei nicht, und beide sagen es im eigenen Commit: M157 (Knopf-Verdrahtung)
> und M161 (die Refine-Schleife liegt im `State` des Viewports, den die
> Host-Suite nicht fahren kann).
>
> * **M154** EOP wurde auf eine ZEILENZAHL geparkt statt auf den Sentinel — die
>   Skizze der zweiten Extrusion entstand unter der Marke.
> * **M155** `nextSolidName()` gab nach dem Neuladen einen SCHON VERGEBENEN
>   Koerpernamen aus (Datei: Solid1..Solid3, gespeichert `solidN: 1`); und die
>   zweite Skizze war nie anwaehlbar, weil der Viewport im ersten Durchgang
>   `break`te. Das war der Loft/Sweep-Blocker.
> * **M156** Projektion + darueber gezeichneter Kreis = zwei Schleifen, deren
>   Zwischenraum 10 um breit ist. Genau der Ring im Screenshot.
> * **M157** Der Plane-Knopf war `onDefault: () {}`.
> * **M158** Der Chamfer wurde bei Gleichstand per Muenzwurf gesetzt UND das
>   Ergebnis via `reanchor` festgeschrieben — ein Fehlgriff war permanent.
> * **M159** Ein Remesh-Schritt ging 7 536 -> 1 002 412 Dreiecke, bis 56 s.
> * **M160** **Regression, die ich selbst in M154 eingebaut hatte.**
> * **M161** Die Vorschau wurde verfeinert und danach weggeworfen.
>
> **OFFEN — nach Wichtigkeit:**
> 1. **Geraete-Test von M154–M161.** NICHTS davon war je auf Hardware. M158
>    aendert, WANN ein Chamfer faellt, M156 aendert, welche Profile angeboten
>    werden — beides braucht Augen an echten Teilen.
> 2. **Work Planes: der Offset ist nicht eingebbar.** `workPlaneOffset = 10`
>    wird NIRGENDS zugewiesen — jede Offset-Ebene ist exakt 10 mm (belegt in
>    `Part4.part.json`: `"Offset 10.00 mm from face"`). Das ist der naechste
>    konkrete Schritt und kleiner als er klingt.
> 3. **Work Planes: 9 von 12 Methoden fehlen** (Drei Punkte, Parallel durch
>    Punkt, Winkel um Kante, Tangential, Normal zu Achse/Kurve, Zwei koplanare
>    Kanten, Torus-Mittelebene). Inventors generische Plane ist ausserdem
>    KONTEXTSENSITIV und kennt das Ziehen fuer den Offset.
> 4. **Der echte Anker einer Kreiskante ist ihr MITTELPUNKT**, nicht der
>    Bogenmittelpunkt, der mit dem Radius wandert. `OcctEdgeInfo` fuehrt ihn
>    nicht; herleiten braucht die Kreisebene -> **Shim v16**, also C++ und ein
>    eigener Meilenstein. Das ist die Wurzel unter dem wandernden Chamfer;
>    M158 macht ihn nur ehrlich statt richtig.
> 5. **Vorhersagende Tessellierung.** M159 begrenzt die KOSTEN der Entdeckung,
>    sagt die Dreieckszahl nicht voraus. Der Wachstumsexponent ist pro
>    Flaechentyp verschieden (~1/sqrt(d) Zylinder, ~1/d^2 Helix) und laesst
>    sich pro Solid aus aufeinanderfolgenden Durchgaengen MESSEN.
>
> **Fehlermuster dieser Sitzung — das lohnt sich zu lesen:**
> * **Dreimal war der richtige Code schon da und wurde still ueberschrieben.**
>   `commitExtrude` rief `appendFeature(f)` (parkt die Marke korrekt) und
>   ueberschrieb das Ergebnis in der NAECHSTEN Zeile. `toggleSessionProfile`
>   hatte die richtige Regel fuer den Skizzenwechsel — ein `break` im Viewport
>   sorgte dafuer, dass sie nie erreicht wurde. Beim Suchen nach einem Fehler
>   also erst pruefen, ob die Loesung schon existiert und nur verliert.
> * **Ein Zaehlerstand, der „gerade jetzt" stimmt, ist kein Zustand.** Waechst
>   die Liste, muss „am Ende" ALS SOLCHES gespeichert werden (M154), und ein
>   Namenszaehler muss vergebene Namen UEBERSPRINGEN statt hochzuzaehlen (M155).
> * **Reihenfolge beim Laden.** `openPart` haengt die Skizzen NACH `loadJson`
>   an. Alles, was in `loadJson` den Zeitstrahl befragt, sieht ihn unvollstaendig
>   (M160). Neue Entscheidungen gehoeren in `finishLoad`.
> * **Ranking ist nicht Akzeptanz.** M152 gewichtete den Radius schwerer, damit
>   der RICHTIGE Kandidat gewinnt; die Frage, ob der Gewinner UNTERSCHEIDBAR
>   war, stellte niemand (M158). Ein Muenzwurf gehoert verworfen, nicht benutzt.
> * **Ein reaktives Budget kann einen Schritt nicht bremsen**, nur die Folge
>   danach (M159). Und was gleich weggeworfen wird, verfeinert man nicht (M161).

> **M131b — Sweep, Loft und Coil vollstaendig: Shim v15 (44 Symbole), Modell,
> Session, Panel, Picking. 853/853 Tests.**
>
> **Shim, analytisch geprueft — nicht per Augenmass:**
> - `occt_sweep_profile` (MakePipeShell). Smoke [30]: ein 10x10-Quadrat 40 mm
>   geradeaus gesweept ist ein Prisma, V = 4000.000000 exakt, 6 Flaechen. Ein
>   L-Pfad muss MEHR Material ergeben. Scharfe Pfadecken scheiterten zunaechst
>   komplett; `SetTransitionMode(RightCorner)` behebt das (und ist auch das,
>   wie ein gesweepter Stab an einer Ecke wirklich aussieht).
> - `occt_loft_sections` (ThruSections). Smoke [31]: zwei gleiche Quadrate 25 mm
>   auseinander = 2500.000000 exakt; ein 10->20-Kegelstumpf =
>   h/3*(A1+A2+sqrt(A1*A2)) = 5833.333333, gemessen 5833.333333.
> - `occt_coil_profile`. Der Helix ist eine GERADE im (u,v)-Raum eines
>   `Geom_CylindricalSurface` — u windet, v steigt. Smoke [32]: 5 Windungen,
>   50 mm Hub, Radius 20, Querschnitt 4 mm^2 → Schaetzung ueber die
>   Helixlaenge 2521.2193, gemessen 2521.2203. Uebereinstimmung auf 4e-7.
>
> **Ehrlich verweigert statt still ignoriert:** Twist beim Sweep und die
> Coil-Enden (Close Start/End) sind NICHT implementiert; ein Wert ungleich
> null wird abgelehnt. Ein Sweep, der still nicht verdreht, ist ein falsches
> Teil, und man sieht es dem Ergebnis nicht an.
>
> **Ein Panel, fuenf Arten.** `ExtrudeSession.kind` traegt jetzt extrude,
> revolve, sweep, loft, coil. Von den Feldern sind Profile, Sketch-Bindung,
> Output, Koerper, Vorschau und Auto-Pick allen gemeinsam; nur die Zahlen
> darunter unterscheiden sich. Drei eigene Panels waeren drei Kopien der
> Kanten- und Vorschaubehandlung gewesen.
>
> **Coil-Methoden:** alle vier Inventor-Varianten (Revolution and Height,
> Pitch and Revolution, Pitch and Height, Spiral) rechnen im MODELL auf ein
> (Umdrehungen, Hoehe)-Paar um (`CoilFeature.resolved`), sodass der Shim eine
> Form kennt und das Panel trotzdem alle vier anbietet.
>
> **`CurveSel` fuer den Sweep-Pfad:** wie `EdgeSel` per Geometrie gespeichert
> (Endpunkte + Laenge), nicht per Index — ein Index verschiebt sich, sobald
> etwas in der Skizze eingefuegt wird, und der Sweep zeigte dann still auf
> eine andere Linie.
>
> **Cache-Fehler dabei gefunden und behoben:** `featureInputSig` hashte nur
> EINE Skizze. Ein Sweep haengt aber auch an der Skizze seines PFADES und ein
> Loft an einer je Sektion — deren Bearbeitung liess den gecachten Solid
> stehen und nichts bewegte sich. Neu `PartFeature.sketchNames`, und die
> Signatur hasht alle.
>
> **Und ein Parser-Fehler:** `parseValueExpr` entfernte `mm|deg|°`, aber nicht
> `ul` — Inventors einheitenloses Suffix fuer Zaehlwerte. „5 ul" ergab damit
> null, und jede Coil-Methode, die Umdrehungen liest, verweigerte still den
> Dienst.
>
> **22 neue Tests** (was wirklich beim Kernel ankommt, alle vier
> Coil-Umrechnungen, Pfad in WELT-Koordinaten, Sektionen in Pick-Reihenfolge,
> Mehrfach-Skizzen-Abhaengigkeit, JSON-Roundtrip).
>
> **NOCH OFFEN:** die Arbeitselemente (Plane/Axis/Point/UCS). Der Ribbon
> traegt Inventors vollstaendige 13er-Plane-Liste bereits als ATTRAPPEN
> (`'plane'`-Flyout in ribbon.dart), es gibt aber kein Modell dafuer — kein
> `WorkFeature`, keine Konstruktionsmethoden, und Arbeitsebenen sind nicht als
> Skizzenebene waehlbar. Das ist ein eigener Meilenstein, nicht ein Anhaengsel.

> **M130a — Ursache der wilden Highlight-Linien: falsches Drahtformat.
> Merge M123/M124. 831/831 Tests.**
>
> (Umbenannt von M129: eine Parallel-Sitzung auf demselben Branch hat M129
> fuer das Feature-Tree-Aussehen des nativen Browsers benutzt.)
>
> **Der Build-Bruch (#307):** `Cannot convert value of type 'SIMD3<Float>' to
> expected argument type 'Float'`, dreimal auf einer Zeile.
> `Payload.floats(_:)` gibt `[SIMD3<Float>]` zurueck — die Punkte sind SCHON
> gruppiert. Mein M127-Code hat sie ein zweites Mal gruppiert und dabei jeden
> Punkt als Skalar behandelt. Ich hatte die Signatur des Helfers ANGENOMMEN
> statt sie nachzulesen; genau der Fehler, den ich in dieser Sitzung schon
> einmal gemacht habe.
>
> **Und die eigentliche Ursache der Linien „ueberall, nicht am Teil, manche
> irrsinnig lang":** `Payload.floats` bindet den Puffer an `Float`, also 32
> Bit. Mein Dart schickte `Float64List`-Ausschnitte, also 64 Bit. Dieselben
> Bytes als 32-bit-Floats gelesen ergeben keine „leicht verschobenen" Punkte,
> sondern beliebige Zahlen — riesige Koordinaten weit ausserhalb des Teils,
> genau das gemeldete Bild. Jetzt wird `edgePoints32` geschnitten
> (`Float32List.sublistView`), also dasselbe Format, das jede andere
> Punkt-Nutzlast schon benutzt (`solidPayload` schickt `edgePoints32`).
>
> **Warum kein Test das gefangen hat und jetzt einer da ist:** die
> Nutzlast-Tests prueften die WERTE (`[0,1,0,1,1,0]`), und die stimmten — ein
> `Float64List` mit denselben Zahlen ist inhaltlich identisch und faellt erst
> auf der anderen Seite der Grenze auf. Neu prueft ein Test explizit, dass
> JEDE ausgegebene Linie ein `Float32List` ist.
>
> **Vor dem Push diesmal jeder Typ NACHGESEHEN statt angenommen:** `cam.dir`
> und `outlineDir` sind `SIMD3<Float>`, `highlightEps` und `edgeRadius` sind
> `Float`, `RibbonBuilder.mesh` nimmt `([[SIMD3<Float>]], halfWidth: Float,
> viewDir: SIMD3<Float>)` — identisch zu den beiden bestehenden Aufrufstellen,
> `Materials.unlitSoft` nimmt `UIColor`, `Colors.highlight` ist einer.
>
> **Nicht das Problem, geprueft:** der Anzeige-Index wird beim Verfeinern des
> Meshes NICHT ungueltig. Refinement aendert die Tesselierungsdichte, nicht
> die Anzahl gezeichneter Kanten, und `poly()` liest `edgeStarts` und Punkte
> aus DEMSELBEN Mesh — Index und Puffer bleiben also konsistent.
>
> **Merge M123/M124 von `main`** (Punkt bindet an Kreis/Bogen/Spline/Polygon;
> radiales Spaltmass zwischen zwei Kreisen; getriebener Kreis-Offset) —
> konfliktfrei ausser HANDOFF.

> **M128 — End of Part neu gebaut: die Invariante wird jetzt ERZWUNGEN statt
> erinnert. 809/809 Tests, 17 davon neu und ausschliesslich fuer EOP.**
>
> **Warum das siebenmal schiefging.** `eopAfter` (eine Zeilenposition) und
> `rolledBack` (ein Flag je Knoten) sind ZWEI Darstellungen EINER Tatsache.
> Dass sie uebereinstimmen, wurde per Konvention gepflegt: sechs Aufrufstellen
> von `applyEndOfPart`, fuenf UI-Stellen die `setEndOfPart` rufen, und nichts,
> das es durchsetzt. Jeder EOP-Bug in der Historie (M91, M100, M102, M113,
> M121, M122) war dieselbe Form — die beiden liefen auseinander. Arithmetik zu
> reparieren hat deshalb nie geholfen.
>
> **Die eigentliche Ursache, bisher unentdeckt: `recomputeAllFeatures` hat
> `rolledBack` NIE beachtet.** Ein zurueckgerolltes Fillet wurde weiterhin
> gerechnet, nahm weiterhin die Extrusion darunter als Basis und markierte sie
> als `consumedByJoin` — womit BEIDE unsichtbar waren: eines unterdrueckt, das
> andere „aufgegangen" in etwas, das nicht gezeichnet wird. Das ist M122s
> verschwindender Koerper, und es ist auch das, was im Screenshot zu sehen war
> (Fillet1 unter der Marke, Koerper trotzdem verrundet).
>
> **Drei Aenderungen, die die Fehlerklasse unmoeglich machen:**
>
> 1. **Der Fold LEITET die Flags selbst ab, als erstes, bedingungslos.**
>    `recomputeAllFeatures` ruft `applyEndOfPart` an seinem Kopf. Der Fold ist
>    der einzige Trichter, durch den jede Geometrie laeuft — damit ist ein
>    veraltetes `rolledBack` nicht mehr darstellbar, statt bloss unerwuenscht.
>    Kostet O(Zeilen) einmal pro Rebuild.
> 2. **Ein unterdrucktes Feature ist wirklich abwesend:** wird nicht gerechnet,
>    beruehrt die Kette nicht, und sein Solid wird FREIGEGEBEN. Damit kann
>    keine veraltete Geometrie in die Szene sickern und kein Vorgaenger mehr
>    faelschlich als verbraucht gelten.
> 3. **`kEopAtEnd` als Sentinel statt einer Zahl.** Die Marke auf die letzte
>    Zeile zu ziehen speicherte bisher DIE ZEILENZAHL. Danach war sie nicht
>    mehr „am Ende": jedes neu erzeugte Feature landete UNTER ihr und kam
>    unterdrueckt zur Welt — unsichtbar, ohne Hinweis warum. Das duerfte ein
>    guter Teil des „really buggy"-Eindrucks gewesen sein.
>
> **Dazu `PartModel.appendFeature`:** Inventor baut, was man gerade gemacht hat
> — bei Marke mitten in der Liste rueckt sie hinter das neue Feature. Die Regel
> liegt jetzt im Modell (eine Stelle) statt an drei Anhaenge-Stellen, die sie
> vergessen koennen.
>
> **Ausserdem:** die toten `rolled`-Menge in `applyEndOfPart` entfernt
> (berechnet, nie gelesen — in einer fehleranfaelligen Funktion eine
> Belastung).
>
> **Die 17 Tests pruefen INVARIANTEN, nicht Arithmetik:** die Flags folgen der
> Marke auch wenn niemand appliziert hat; Loeschen laesst kein Flag zurueck;
> ein Bereich ausserhalb wird geklammert statt geglaubt; ein unterdrucktes
> Feature haelt kein Solid und verbraucht seinen Vorgaenger nicht; der Koerper
> bleibt bei Marke mitten in der Liste sichtbar; Zurueckrollen stellt ihn
> wieder her; „am Ende" ueberlebt das Anlegen eines Features; ein neu
> erzeugtes Feature wird nie unterdrueckt geboren; und der Fillet-Fall aus dem
> Screenshot explizit.
>
> **NICHT behoben, weil nur am Geraet beurteilbar:** wie sich das ZIEHEN
> anfuehlt. Die Zeilenarithmetik ist seit M113 in beiden Browsern trivial
> (`start + dy/32`, geklammert) und die Marke wird erst beim Loslassen
> committet, es wird also nicht pro Schritt gespeichert. Ob es sich fluessig
> anfuehlt, sagt nur ein Geraetetest.

> **M127 — Zwei Geraetebefunde: Hover-Highlight in der Vorschau, und die
> fehlenden Kanten am Anfang/Ende jedes Radius. 792/792, Shim v14.**
>
> **BEFUND 1: Fillet-Uebergaenge wurden gar nicht gezeichnet.** Die
> v9-Unterdrueckung tangentenstetiger Kanten greift bei cos(8 deg) — und ein
> Fillet ist seinen Nachbarflaechen BAUARTBEDINGT tangential. Genau die Linie,
> wo der Radius auf die Flaeche laeuft, fiel damit unter dieselbe Regel wie ein
> Bogenketten-Artefakt: der verrundete Wuerfel erschien als ein glatter Klumpen
> ohne Umriss (Screenshot vom Geraet).
>
> Behoben: unterdrueckt wird nur noch, wenn BEIDE Nachbarflaechen denselben
> Flaechentyp haben. Bogenketten sind Zylinder-zu-Zylinder, bleiben also
> unterdrueckt; Ebene-zu-Zylinder und Zylinder-zu-Torus kommen zurueck.
> Bekannte Grenze und dokumentiert: ein Fillet, das tangential in ein ANDERES
> Fillet gleichen Typs laeuft, bleibt unterdrueckt — das vom Bogenketten-Fall
> zu trennen braucht mehr als den Flaechentyp. Smoke [29] prueft es (skippt
> unter 7.6 wie [28], laeuft auf CI).
>
> **BEFUND 2: das Hover-Highlight verschwand, sobald die Vorschau stand.** Und
> zwar nicht durch einen Verdrahtungsfehler, sondern weil das DESIGN falsch
> war. Der Akzent reiste als „Anzeige-Kante N von Solid X". Sobald die
> Fillet-Vorschau den Koerper ERSETZT, ist dieser Koerper nicht mehr in der
> Szene — der Renderer hat also keine Geometrie, an die er das Ribbon haengen
> koennte, und `solidCache` kennt die Vorschau nicht (`rebuildPreview` baut ein
> lokales `SolidGeom`). Das Highlight fiel genau dann aus, wenn man es braucht:
> beim Weiterpicken auf einem Koerper, der gerade durch die Vorschau seiner
> eigenen Verrundung ersetzt ist.
>
> Behoben, indem der Akzent jetzt als ROHE WELT-POLYLINIEN reist
> (`{'lines': [[x,y,z,...], ...]}`). Damit ist er unabhaengig davon, ob sein
> Koerper gezeichnet wird — und die ganze Anzeige-Index-Buchhaltung auf der
> Swift-Seite entfaellt: eine Entity statt eines Dictionaries pro Solid, ein
> Cache-Key statt einer Index-Menge, kein Aufraeumen bei entfernten Solids
> (es gibt keinen Bezug mehr). `edgeHighlightEntity` in `PartScene.swift` ist
> damit verwaist und entfernt.
>
> **Nebenbei gelernt:** Swift setzt in `rebuildPreview` fest
> `Materials.preview()`. Die in M126 getroffene Dart-Wahl „normaler Stahl
> statt kMatPreview" wurde also ohnehin ignoriert — die Vorschau ist
> durchscheinend, egal was das Payload sagt. Nicht geaendert, aber notiert:
> falls die Vorschau am Geraet schwer zu beurteilen ist, liegt der Schalter
> dort, nicht in Dart.
>
> **Aufgefallen im Screenshot, NICHT gemeldet und nicht angefasst:** im Browser
> steht `Fillet1` UNTERHALB von `End of Part`, waere also zurueckgerollt — der
> Koerper ist im Bild aber verrundet. Entweder stimmt die EOP-Zeichnung nicht
> oder ein zurueckgerolltes Fillet wirkt trotzdem. Sollte geprueft werden.
>
> **6 Tests** fuer die neue Payload-Form, darunter explizit „funktioniert auch
> wenn der Koerper durch eine Vorschau VERSTECKT ist" — der gemeldete Fall.

> **M126 — Geraetebefunde behoben: Fillet/Chamfer haben jetzt eine LIVE-
> Vorschau, und der OK-Knopf bleibt nicht mehr grau. 793/793 Tests.**
>
> **Zwei Symptome, EINE Ursache.** `_openEdgeFeature` berechnet die Vorschau
> genau EINMAL — beim Oeffnen, mit null Kanten — und setzte damit
> `previewError = "Select at least one edge."`. `toggleEdgePick` rief
> `_updateEdgeFeaturePreview()` NIE auf. Folge: das Kantenfeld zeigte brav
> „3 Edges", waehrend die Fehlermeldung und der graue OK-Knopf am
> eingefrorenen Zustand von vor dem ersten Tipp hingen — und weil die Vorschau
> nie gerechnet wurde, gab es auch keine zu zeichnen. Ein Aufruf behebt beides.
>
> **Zweite, unabhaengige Ursache: die Vorschau wurde nie GEZEICHNET.**
> `edgeSession` kam im ganzen Renderpfad nicht vor. Ergaenzt:
> - `EdgeFeatureSession.previewReplacesBody` — ein Fillet fuegt kein Material
>   hinzu, es MODIFIZIERT einen Koerper, also muss das Original waehrend der
>   Vorschau verschwinden, sonst scheinen die unverrundeten Kanten hindurch.
>   `visibleSolids` beruecksichtigt das jetzt fuer BEIDE Sessions.
> - `buildScenePayload` gibt die Kanten-Vorschau aus, wenn keine
>   Extrude-Vorschau ansteht — in NORMALEM Stahl, nicht `kMatPreview`: dieses
>   Bild steht fuer den ganzen Koerper, und an einem durchscheinenden Koerper
>   laesst sich eine Verrundung schlecht beurteilen. Das offene Panel ist das
>   Signal, dass noch nichts committet ist.
> - `sceneSignature` traegt `eprev`/`eprevrepl`, sonst wird das neue Mesh gar
>   nicht gepusht.
>
> **Dritter Befund, beim Testen aufgefallen (noch nicht am Geraet gesehen):**
> die Ein-Koerper-Regel in `toggleEdgePick` verglich Koerper ueber die
> OBJEKTIDENTITAET. Ein Recompute ersetzt die `KernelSolid`-Instanz, also
> haette der naechste Tipp „anderer Koerper" gelesen und die gesamte Auswahl
> STILL verworfen. Erster Versuch, ueber `_bodyNameOfSolid` zu vergleichen,
> half nicht — die Funktion matcht selbst per Identitaet und kann die ALTE
> Instanz hinterher nicht mehr benennen. Jetzt wird der Koerpername BEIM
> PICKEN festgehalten (`pickedEdgeBodyName`); nur er ueberlebt einen Rebuild.
> Test deckt beide Richtungen ab: neue Instanz desselben benannten Koerpers
> behaelt die Auswahl, ein echt anderer Koerper beginnt eine neue.
>
> **Chamfer ausdruecklich mitgeprueft**, weil „gemeinsame Maschinerie" bis zum
> Beweis eine Behauptung ist: 6 Tests mit einem aufzeichnenden Kernel — die
> CHAMFER-Kernelstrecke wird wirklich benutzt, Distanz aendern baut die
> Vorschau neu, Modus 1 sendet d1/d2 und Flip tauscht sie, Modus 2 sendet den
> Winkel und Flip nimmt den Komplementwinkel, letzte Kante abwaehlen loescht
> die Vorschau wieder.
>
> **11 neue Tests** (5 Fillet-Vorschau/Regression, 6 Chamfer).

> **M125 — Voller CI-Durchlauf gruen: IPA gebaut, Swift uebersetzt, 41
> Symbole im Runner. Damit ist ALLES in M130-M145 maschinell geprueft.**
>
> `m1-core-build` Lauf #303 auf `session/m130-m145-kernel-features` — alle
> VIER Jobs erfolgreich:
> - **Dart analyze + host tests (fast):** unabhaengige Bestaetigung von 0
>   Analyzer-Fehlern und 780 Tests auf der CI-SDK.
> - **build-core-ios** und **M3 headless logic (iOS Simulator):** erfolgreich.
> - **M5 Flutter iOS build + unsigned IPA:** erfolgreich, `Runner.app` 67.3 MB,
>   IPA als Artefakt hochgeladen.
>
> **Alle Gates einzeln bestaetigt (nicht nur der gruene Haken):**
> `LIQUID GLASS CHECK: PASS (iOS SDK 26)` ·
> `M6 QIOS CHECK: PASS` · `M5 LINK CHECK: PASS` · `SLVS LINK CHECK: PASS` ·
> `OCCT MARKER CHECK: PASS` ·
> **`OCCT LINK CHECK: PASS (41 _occt_* symbols exported in Runner)`** ·
> `REALITYKIT LINK CHECK: PASS` · `THUMB CHANNEL CHECK: PASS`.
>
> **Die Swift-Seite ist damit uebersetzt.** Sie war die letzte ungeprueffte
> Flaeche dieser Reihe: `edgeHighlightEntity` in `PartScene.swift` und
> `rebuildEdgeAccents` in `RealityPartView.swift` (M135) waren blind
> geschrieben und nie kompiliert. Beweis ist nicht der gruene Job allein,
> sondern `THUMB CHANNEL CHECK` — der greppt
> `$APP/Frameworks/reality_view.framework/reality_view` nach seinem
> Kanal-String, also MUSS das Framework, in dem diese beiden Dateien liegen,
> uebersetzt und im Bundle sein. Swift-Diagnosen im ganzen Log: NULL.
>
> **Was jetzt maschinell bewiesen ist:** Shim uebersetzt fuer iOS arm64 gegen
> OCCT 7.9.3 und exportiert 41 Symbole bis in das ausgelieferte Binary;
> Geometrie analytisch korrekt (SMOKE PASS, [20]-[28]); 780 Dart-Tests; 0
> Analyzer-Fehler; Swift uebersetzt; IPA paketiert.
>
> **Was maschinell NICHT beweisbar ist und offen bleibt:** ob der
> Kanten-Akzent am Geraet SICHTBAR ist (2.2x Breite gegen Z-Fighting war eine
> Ueberlegung, keine Beobachtung); ob 14 px die richtige Fingertoleranz sind;
> ob das Fillet-Panel mit drei Kantensaetzen in 300 px passt. Das braucht
> einen Geraetetest, kein weiteres Kompilat.

> **M124 — CI-Verifikation auf echtem OCCT 7.9.3: Shim gruen, Geometrie
> analytisch korrekt, und die vier lokalen „Baseline"-Fehler waren
> tatsaechlich reine 7.6-Artefakte.**
>
> Branch `session/m130-m145-kernel-features`, `occt-build` Lauf #30 —
> BEIDE Jobs erfolgreich.
>
> **`occt-ios-static`:** der Shim uebersetzt gegen echtes OCCT 7.9.3 fuer
> iOS arm64, und `defined _occt_* symbols in shim archive: 41` — das Gate
> (>= 41) haelt. Alle zehn neuen Funktionen dieser Reihe sind damit auf der
> Zielplattform bewiesen, nicht nur auf dem lokalen 7.6.3 mit gestubbtem
> `BRepLib_ToolTriangulatedShape`.
>
> **`occt-host-smoke`: OCCT SMOKE: PASS.** Die Zahlen sind IDENTISCH mit dem
> lokalen 7.6-Lauf: [20] 706.858347 (=225*pi) bei 4 Flaechen, [21] 12 Kanten
> und 7892.699082, [22] 7840.000000, [23] Treffer bei 10 und 30, [24] 22
> konvex / 2 konkav, [25] 19.4712 und 340.5288, [26] variabel 7924.1899
> zwischen const2 7982.8319 und const6 7845.4867 (Mittel 7914.1593, also
> nachweislich variiert statt gemittelt), [27] genau ein Flaechentreffer bei
> 340.5288.
>
> **[28] lief hier zum ersten Mal ueberhaupt** — lokal skippt er, weil 7.6
> nicht meshen kann. Ergebnis: `cylinder: 2 display edges, 3 topological`,
> `map is a REMAP`. Damit ist die Fehlerklasse, um deren Willen
> `occt_mesh_edge_ids` existiert, an echter Geometrie belegt: ein Zylinder hat
> DREI topologische Kanten, aber nur ZWEI gezeichnete, ein Fillet auf dem
> Anzeige-Index haette also wirklich die falsche Kante getroffen.
>
> **Die lokal getragene „Fehlerparitaet 4 = 4" ist aufgeloest:** [11], [12],
> [15] und [16] scheitern unter 7.9.3 NICHT. Sie waren ausschliesslich Folge
> des 7.6-Stubs fuer `ComputeNormals` — die Kontrollmessung gegen HEAD hatte
> das richtig vermutet, jetzt ist es bewiesen. Unter 7.9.3: null Fehler.
>
> **`m1-core-build` Lauf #303, Teilergebnisse:** `Dart analyze + host tests`
> erfolgreich (unabhaengige Bestaetigung der 780 Tests auf der CI-SDK),
> `build-core-ios` erfolgreich. `M5 Flutter iOS build + unsigned IPA` laeuft —
> das ist der EINZIGE Job, der die Swift-Seite (`edgeHighlightEntity`,
> `rebuildEdgeAccents` aus M135) uebersetzt und damit die letzte ungeprueffte
> Flaeche dieser Reihe.

> **M123 — Merge M120-M122, eine falsche Behauptung korrigiert, und M122s
> Dialog-Fix auf das Fillet-Panel uebertragen. 780/780, 0 Fehler.**
>
> **Eigene Falschaussage richtiggestellt.** Ein frueherer Eintrag dieser
> Sitzung behauptete, `m1-core-build.yml` baue den OCCT-Shim nicht neu (weil
> gecacht) und so sei M109s kaputte Translation Unit durchgerutscht.
> Nachgesehen: gecacht wird `backend/occt/install-ios`, also die OCCT-
> BIBLIOTHEK; der Shim wird dort aus der Quelle gebaut (`libocct_capi.a`,
> Zeile 726) und der ccache-Key haengt an `backend/**/*.cpp`. Die Behauptung
> war falsch und steht jetzt korrigiert im Merge-Eintrag. Die echte Luecke ist
> schmaler: `occt-build.yml` — die isolierte Pruefung mit Symbolzahl und
> Undefined-Symbol-Check — ist seit M68 nicht mehr gruen.
>
> **M122s Fix galt auch fuer mein Panel.** M122 hat den Extrude-Dialog von
> (12, 12) weggeholt, weil er dort unter der schwebenden Browser-Karte
> aufging. `EdgeFeatureDialog` (Fillet/Chamfer) stand auf genau demselben
> hartkodierten (12, 12) und hatte damit denselben Fehler — nur eben in einem
> Panel, das M122 nicht kannte. Jetzt ebenfalls rechts, vertikal zentriert,
> und die Kopfzeile ist ziehbar wie beim Extrude-Dialog.
>
> **Uebernommen ohne Konflikt:** M122s `recomputeAllFeatures` beim
> EOP-Rollen (die Join-Kette wurde nie neu gebaut, weshalb der Koerper
> verschwand) passt sauber zu M131s Fold; M120/M121 (Browser-Griff,
> zurueckgezogene Karte, EOP-Pan) beruehren nichts aus dieser Reihe.

> **M145 — Audit der eigenen Arbeit. Zwei echte Befunde behoben, drei
> Invarianten festgenagelt. 780/780 Tests, 0 Analyzer-Fehler, 41 Symbole.**
>
> **BEFUND 1 (behoben): die Radien-Zuordnung war fragil.** `resolveEdges`
> ANKERT die Fingerabdruecke neu und erzwingt ueber `taken`, dass jede lebende
> Kante nur EINE Auswahl bedient. Die Radien-Zuordnung danach rief `bestMatch`
> aber ein ZWEITES Mal auf, ohne dieses `taken` — waren zwei Picks auf
> denselben Ueberlebenden gedriftet, konnten Radien und Kanten
> auseinanderlaufen. `resolveEdges` liefert jetzt zusaetzlich den QUELLINDEX
> jeder ueberlebenden Auswahl, und die Zuordnung ist ein schlichter Lookup —
> kein zweiter Matching-Durchlauf, also keine Driftmoeglichkeit. Neuer Test:
> gehen bei drei Kanten mit Radien [2,3,4] die mittlere verloren, muss beim
> Kernel [2,4] ankommen — nicht [2,3] (positionsweise) und nicht [2,2] (Drift).
>
> **BEFUND 2 (behoben): `occt_mesh_edge_ids` hatte NULL Testabdeckung.** Genau
> die Funktion, deren Fehlen die stille Fehlerklasse verursacht haette
> (Anzeige-Index != topologischer Index, also Fillet auf der FALSCHEN Kante).
> Neu Smoke [28] an einem Zylinder — dessen Naht laesst die Anzeigeliste
> fallen, also KANN die Abbildung nicht die Identitaet sein: geprueft werden
> Laenge, Wertebereich, Eindeutigkeit, und explizit dass es ein REMAP ist.
> Ehrlich: der Test braucht `occt_mesh_create`, das unter 7.6 aus
> shim-fremden Gruenden scheitert ([11]/[12]), also SKIPPT er dort LAUT und
> laeuft erst auf der 7.9-CI wirklich.
>
> **Festgenagelt, weil stillschweigend tragend:**
> - `DisplayEdge.of()` liefert GENAU einen Eintrag pro Anzeige-Kante, auf
>   jedem Zweig. Der Kanten-Akzent des CPU-Painters indiziert darauf; wuerde
>   ein spaeterer Zweig ohne `out.add` `continue`n, landete der Akzent still
>   auf der falschen Kante. Jetzt getestet, auch fuer Meshes ohne analytische
>   Records.
> - Beide `_strokeRuns`-Aufrufe in `_paintSolidEdges` nehmen `edgeColor`, nicht
>   den Parameter — der Akzent ist also wirklich sichtbar und nicht toter Code.
> - 41 exportierte `occt_*`-Symbole (per `nm` gezaehlt) == 41 Deklarationen ==
>   alle VIER CI-Gates. Vorher nur behauptet, jetzt gemessen.
>
> **Ebenfalls geprueft, ohne Befund:** kein Shim-Header wird transitiv
> vorausgesetzt (alle 10 neu benutzten Typen explizit inkludiert — wichtig,
> weil 7.9 andere Transitivitaeten hat); keine der eingefuehrten Hilfen ist
> toter Code; keine TODO/FIXME-Reste; der doppelte
> `_syncSolidProjections`-Aufruf ist nicht zurueckgekehrt.
>
> **Merge M113fix-M119** dabei mitgenommen. In `model_browser.dart` wurde
> origin/mains M113-Fix genommen: er entfernt die doppelten
> EOP-Deklarationen SAMT ihres veralteten Doc-Blocks, waehrend meine
> fruehere Aufloesung den Kommentar verwaist zurueckgelassen hatte.

> **M144 — Die letzten drei offenen Punkte in einem Zug: variabler
> Fillet-Radius, Revolve „To <Flaeche>", Kanten-Akzent im CPU-Painter.
> Shim 41 Symbole, 771/771 Tests, 0 Analyzer-Fehler.**
>
> **1) Variabler Radius.** `occt_fillet_edges` nimmt jetzt ein optionales
> zweites Radius-Array; wo `radii2[i] > 0` ist, benutzt der Shim
> `BRepFilletAPI_MakeFillet::Add(r1, r2, edge)` und der Radius laeuft LINEAR
> von einem Kantenende zum anderen (Inventors variabler Radius mit zwei
> Kontrollpunkten). Null oder NULL heisst konstant, also aendert sich fuer ein
> gewoehnliches Fillet nichts und alte Dateien laden unveraendert. Im Panel
> gibt es je Satz ein optionales Feld „to"; leer = konstant. Ein nicht leerer,
> aber unbrauchbarer Wert ist ein FEHLER, nicht ein stiller Rueckfall auf
> konstant.
>
> **Smoke [26] behauptet ABSICHTLICH keine Formel.** Das Integral der
> konstanten Querschnittsflaeche ueber die Kante,
> `(1-pi/4)*L*(r1^2+r1*r2+r2^2)/3`, sagt 7925.605 voraus, gemessen wird
> 7924.190 — die Naeherung ist um 1.8e-4 falsch, weil sie annimmt, die
> Fillet-Flaeche bleibe senkrecht zur Kante, und ein wandernder Radius kippt
> sie. Statt eine Toleranz aufzuweichen, bis eine falsche Formel durchgeht,
> prueft der Test, was EXAKT gilt: mehr Material weg als bei konstant 2 mm,
> weniger als bei konstant 6 mm, und NICHT der Mittelwert der beiden — was
> genau das waere, was Radien-Mitteln statt Variieren liefern wuerde.
> (7924.19 gegen 7982.83 / 7845.49, Mittel 7914.16.)
>
> **2) Revolve „To <Flaeche>".** In M143 blieb das aus, weil
> `occt_revolve_hits` das ERSTE Material meldet, nicht die GEWAEHLTE Flaeche —
> ein Profil kann auf dem Weg dorthin durch andere Flaechen laufen. Neu:
> `occt_revolve_hits_face`, das den Kreis nur gegen EINE Flaeche schneidet
> (die dem gepickten Punkt naechste; `BRepIntCurveSurface_Inter` nimmt jede
> `TopoDS_Shape`, also auch ein einzelnes Face). Kreisaufbau und
> Winkel-Extraktion sind jetzt gemeinsame Helfer, damit der Winkelnullpunkt
> nur an EINER Stelle definiert ist. Smoke [27]: dieselbe Box und Bahn wie
> [25], aber nur nach der y=-5-Flaeche gefragt — genau ein Treffer bei
> 340.5288, der bei 19.4712 taucht korrekt NICHT auf. Ein Test nagelt zudem
> fest, dass `resolveRevolveSweep` wirklich `revolveHitsFace` benutzt und
> nicht die Ganzkoerper-Variante.
>
> **3) Kanten-Akzent im CPU-Painter.** `paintPartSolids` bekommt
> `accentSolid`/`accentEdges`/`accentColor` — genau parallel zum bestehenden
> `highlightSolid`/`highlightFace`. Damit zeigen Nicht-iOS-Builds und
> Galerie-Thumbnails dieselbe Auswahl wie das RealityKit-Overlay, in derselben
> Farbe, mit Hover und Auswahl in EINER Menge wie auf dem Geraet.
> Nebenbei entdeckt: `projectSolidEdges` in `part_render.dart` hat KEINE
> Aufrufer mehr — toter Code seit die M59-Pipeline uebernahm. Nicht angefasst,
> aber hier vermerkt.
>
> **12 neue Tests** (6 variabler Radius inkl. „konstant schickt gar keine
> Endradien", 2 Revolve-To-Face, 4 uebrige).
>
> **Stand:** `flutter analyze` 0 Fehler, `flutter test` 771/771, Shim
> uebersetzt gegen echtes OCCT mit 41 Symbolen, Smoke-Fehlerparitaet zu HEAD
> unveraendert 4 = 4. CI-Gates auf 41.
>
> **Damit ist die Liste offener Punkte dieser Sitzung leer — bis auf das
> Eine, das hier nicht zu schliessen ist: SWIFT wurde nie uebersetzt (kein
> Xcode). Die Kanten-Akzent-Overlays aus M135 in `PartScene.swift` und
> `RealityPartView.swift` sind der groesste ungepruefte Teil und brauchen
> einen Geraetebuild.**

> **M143 — Revolve-Extents richtig: `occt_revolve_hits` (Shim 40 Symbole).
> 764/764 Tests, 0 Analyzer-Fehler.**
>
> **Warum ein Ray-Cast hier nicht reicht.** In M139 wurden die Extents-Knoepfe
> fuer Revolve wieder ENTFERNT, weil `resolveExtrudeSpan` nur den linearen
> Fall loest und ein Revolve still auf den Winkel zurueckgefallen waere. Ein
> revolviertes Profil reist aber auf einem KREIS — die Frage ist nicht „nach
> welcher Strecke", sondern „nach welchem WINKEL" es zuerst auf Material
> trifft. Kein Strahl kann das beantworten.
>
> **Neu im Shim:** `occt_revolve_hits(shape, achse, punkt, out, max)` gibt die
> sortierten, entdoppelten WINKEL in Grad (0, 360), gemessen ab dem Punkt
> selbst, an denen dessen Kreisbahn eine Flaeche schneidet. Moeglich, weil
> `BRepIntCurveSurface_Inter::Init` neben `gp_Lin` auch einen
> `GeomAdaptor_Curve` nimmt — also einen `Geom_Circle`. Der Winkelnullpunkt
> liegt AUF dem Punkt (`gp_Ax2` mit der Radialrichtung als X-Achse), damit der
> Aufrufer schlicht den kleinsten positiven Treffer als „To Next" nehmen kann.
> Ein Punkt auf der Achse hat keine Bahn und liefert 0.
>
> **Smoke [25]** analytisch: Box x in [10,20], y in [-5,5], Punkt (15,0,0) um
> die Z-Achse. Die Bahn verlaesst die Box, wo 15*cos = sqrt(200), also bei
> atan2(5, sqrt(200)) = 19.4712 Grad und symmetrisch bei 340.5288.
> Gemessen: genau diese Werte. Achse-Punkt und degenerierte Achse ebenfalls
> geprueft. Fehlerparitaet zu HEAD weiterhin 4 = 4.
>
> **`resolveRevolveSweep`** ist das rotatorische Gegenstueck zu
> `resolveExtrudeSpan`: kleinster positiver Winkel ueber alle Profil-Anker,
> Flipped liest 360 minus dem Treffer, Symmetric/Asymmetric legen den
> aufgeloesten Winkel beidseitig an. Through All ist einfach eine ganze
> Umdrehung. Basis-Features werden abgelehnt wie beim Extrude.
>
> **„To <Flaeche>" bleibt bewusst extrude-only.** Eine Drehung auf einer
> GEPICKTEN Flaeche zu beenden braucht den Winkel, bei dem der Sweep genau
> DIESE Flaeche erreicht; `occt_revolve_hits` unterscheidet die Flaechen nicht.
> Der Knopf ist fuer Revolve ausgeblendet UND das Modell weist es mit
> Begruendung ab, statt es still wie To Next zu behandeln.
>
> **Wieder in die Falle getappt und wieder vom Compiler gefangen:**
> `revolveHits` als konkrete Default-Methode auf `PartKernel` hilft den Fakes
> nicht, weil sie `implements` benutzen — dasselbe wie in M131. Vier Fakes
> ergaenzt.
>
> **Eigene falsche Testannahme:** „Through All ist eine ganze Umdrehung"
> scheiterte, weil das Rechteck im Test das ERSTE Feature ist und es damit
> keinen Koerper gibt, durch den man gehen koennte. Die Ablehnung ist richtig
> (Inventor graut es aus); der Test erwartet sie jetzt.
>
> **NOCH OFFEN:** variabler Radius entlang EINER Kante; „To <Flaeche>" fuer
> Revolve; CPU-Painter zeichnet den Kanten-Akzent nicht; die gesamte
> Swift-Seite ungeprueft (kein Xcode) — das ist inzwischen die groesste
> ungetestete Flaeche dieser Sitzung.

> **M142 — Shim v13: Kanten-KONVEXITAET, und damit Inventors „All Fillets" /
> „All Rounds". 759/759 Tests, 0 Analyzer-Fehler.**
>
> **Warum das ein eigener Meilenstein war.** `allFillets`/`allRounds` lagen
> seit M136 im Modell, aber unbedienbar: Verrundung (INNENkante) von Abrundung
> (AUSSENkante) zu unterscheiden braucht die Konvexitaet, und
> `occt_shape_edge_info` lieferte sie nicht. Ohne sie haetten beide Schalter
> dieselbe Menge ausgewaehlt.
>
> **Shim:** `occt_shape_edge_info` gibt jetzt ZWOELF statt zehn Doubles;
> [10] = Flaechenwinkel in Grad (0 = tangentenstetig, 90 = rechter Winkel),
> [11] = +1 konvex / -1 konkav / 0 unbekannt. Version v13, Symbolzahl
> unveraendert 39 (keine neue Funktion).
>
> **Der erste Versuch war falsch und der Test hat es gezeigt.** Vorzeichen
> ueber den Mittelwert der beiden AUSSENnormalen zu bestimmen und dann
> einwaerts zu schreiten liefert „innen" fuer JEDE Kante — bei einer
> Innenkante liegt der Schritt genauso im Material wie bei einer Aussenkante.
> Ergebnis im Smoke: 24 konvex, 0 konkav. Richtig ist die Winkelhalbierende
> der beiden IN-DIE-FLAECHE-Richtungen (`nOut x T`, mit dem Tangenten-
> Vorzeichen aus der Orientierung der Kante IN der jeweiligen Flaeche): bei
> einer Aussenkante zeigt sie ins Material, bei einer Innenkante in den
> Hohlraum, auf den die Ecke sich oeffnet. Danach 22 konvex, 2 konkav.
>
> **Smoke [24]** prueft es an echter Geometrie: ein Balken aus der Oberseite
> eines Blocks geschnitten ergibt einen Kanal, dessen zwei Bodenkanten
> INNENkanten sind, waehrend die 22 uebrigen Blockkanten aussen bleiben.
> Zusaetzlich in [21]: jede Kante eines schlichten Wuerfels ist konvex bei
> exakt 90 Grad. Fehlerparitaet zu HEAD weiterhin 4 = 4.
>
> **UI:** „All Fillets" / „All Rounds" fuellen den AKTIVEN Kantensatz mit
> allen konkaven bzw. konvexen Kanten des Koerpers. Verlangt einen Pick
> vorher, damit der Koerper bekannt ist — „alle Kanten" ohne Koerper ist
> sinnlos, also wird es abgelehnt statt geraten. Automatisch hinzugefuegte
> Kanten bekommen Display-Index -1: sie wurden nicht im Viewport getippt, sind
> also nicht hervorhebbar, und `_edgeAccentPayload` ueberspringt sie.
>
> **6 neue Tests** (All Rounds nimmt nur konvexe, All Fillets nur konkave,
> nie doppelt, landen im aktiven Satz, ohne Koerper Verweigerung,
> `isConvex`/`isConcave` gegen den Shim-Vertrag).
>
> **NOCH OFFEN:** variabler Radius entlang EINER Kante; Revolve-Extents
> (Winkel, bei dem der rotierende Sweep zuerst Material trifft);
> CPU-Painter zeichnet den Kanten-Akzent nicht; die gesamte Swift-Seite
> ungeprueft (kein Xcode).

> **M141 — Fillet-Kantensaetze: Radius JE SATZ, wie in Inventor.
> 753/753 Tests, 0 Analyzer-Fehler.**
>
> **Was fehlte.** Das Modell trug Radius je Kante schon immer (`radii` ist
> parallel zu `edges`), aber das Panel setzte EINEN Radius fuer alles. Damit
> war Inventors Kernverhalten nicht erreichbar: „alle Verrundungen, die in
> einem Vorgang entstehen, werden EIN Feature", und in diesem Feature traegt
> jeder Kantensatz seinen eigenen Radius.
>
> **Wie es jetzt geht.** `pickedEdgeSet` liegt parallel zu `pickedEdges` und
> haelt fest, in welchen Satz jede Kante gehoert; neue Picks landen in
> `activeEdgeSet`. Das Panel zeigt eine Zeile pro Satz — links „N edges" als
> Auswahlknopf, rechts das Radiusfeld — plus „+ Add edge set". Ablauf: Satz 1
> tippen, „+", weiter tippen. Ein Tipp auf eine Satz-Zeile macht sie wieder
> aktiv.
>
> **Fehler werden dem Satz zugeordnet.** Ein unbrauchbarer Radius in Satz 2
> meldet „Radius of set 2 must be > 0." statt still Satz 1s Wert einzusetzen —
> ein Feature mit einer Zahl, die das Modell nicht traegt, waere schlimmer als
> eine Fehlermeldung.
>
> **Wiederoeffnen rekonstruiert die Saetze** aus den DISTINKTEN Radien des
> gespeicherten Features (Reihenfolge des ersten Auftretens), sodass ein
> mehrsaetziges Fillet so zurueckkommt, wie es gebaut wurde.
>
> **Beweis, nicht Behauptung:** ein aufzeichnender Fake-Kernel prueft, dass bei
> zwei Saetzen (2 mm / 4 mm) und drei Kanten tatsaechlich
> `radii == [2.0, 2.0, 4.0]` in Kantenreihenfolge beim Kernel ankommt — das
> ist die Zusage, auf die `occt_fillet_edges` gebaut ist. Dazu 7 Tests fuer
> die Satz-Buchhaltung (Entfernen haelt `pickedEdgeSet` synchron, `newEdgeSet`
> waechst die Radiusliste mit, auf einem Chamfer tut es nichts).
>
> **NOCH OFFEN:** `allFillets`/`allRounds` (Inventors Auswahlmodi) brauchen
> die KONVEXITAET einer Kante, um Verrundung von Abrundung zu unterscheiden;
> `occt_shape_edge_info` liefert die nicht — waere ein Shim-Feld
> (Winkel zwischen den Nachbarflaechen) und damit ein eigener Meilenstein.
> Variabler Radius entlang EINER Kante fehlt ebenfalls. Revolve-Extents,
> CPU-Painter-Akzent und die gesamte Swift-Seite unveraendert offen.

> **M140 — Offene Punkte abgearbeitet, jetzt mit laufender Toolchain.
> 745/745 Tests, 0 Analyzer-Fehler.**
>
> **Alle SIEBEN Kopien der Punkt-Segment-Mathematik sind jetzt EINE.** In M134
> wurden vier zusammengelegt und drei bewusst liegen gelassen
> (`part_model._segDist`, der Inline-Fall in `constraints.dart`,
> `modify._lineParam`), weil sie mit Degeneriert-Schwelle 1e-18 statt 1e-12
> arbeiten und ohne laufende Tests niemand haette pruefen koennen, ob das
> Angleichen den Constraint-Solver veraendert. Loesung: `segDistSq` bekommt
> einen `eps`-Parameter, jeder Aufrufer behaelt seine eigene Schwelle — eine
> Implementierung, unveraendertes Verhalten. Die Solver-Tests bestaetigen es.
>
> **Doppelter `_syncSolidProjections(p)` entfernt.** Stand seit laengerem als
> versehentlich duplizierte Zeile mit kaputter Einrueckung in `app_state.dart`
> und projizierte bei jedem Oeffnen eines Teils mit importiertem Koerper alle
> Solid-Kanten zweimal.
>
> **Revolve um eine URSPRUNGSACHSE (X/Y/Z).** Vorher war eine gezeichnete
> Konstruktionslinie Pflicht — fuer die haeufigste Drehung ueberhaupt (um Y)
> reine Reibung. Inventors Koplanaritaets-Regel gilt weiter und wird BEIDES
> geprueft: liegt der Weltursprung in der Skizzenebene, und hat die Achse
> keine Komponente entlang der Ebenennormalen. Eine nicht-koplanare Achse (Z
> auf einer XY-Skizze) wird mit Begruendung ABGELEHNT statt still projiziert —
> eine projizierte Achse waere eine Drehachse, die der Benutzer nie gewaehlt
> hat. Im Tap-Pfad schlaegt die Ursprungsachse eine Skizzenlinie, weil sie
> duenner gezeichnet und leichter zu verfehlen ist.
>
> **4 neue Tests** in `m137_revolve_test.dart` (Y-Achse wird korrekt in
> Skizzenkoordinaten uebersetzt, Z wird abgelehnt, unbekannter Schluessel
> wird abgelehnt, die Achse erreicht den Kernel), damit 21 in der Datei und
> 745 im Ganzen.
>
> **NOCH OFFEN:** Fillet-Panel setzt EINEN Radius fuer alle Kanten, obwohl das
> Modell Radius je Kante traegt (`radii` ist eine Liste) — Inventors
> „mehrere Kantensaetze in einem Feature" ist damit noch nicht bedienbar,
> ebenso `allFillets`/`allRounds`. Revolve-Extents (To Next/To/Through All)
> brauchen den Winkel, bei dem der rotierende Sweep zuerst auf Material
> trifft — echte Arbeit. Der CPU-Painter zeichnet den Kanten-Akzent nicht.
> Und alles Swift bleibt ungeprueft (kein Xcode).

> **MERGE — `origin/main` (M101-M111) in die Sitzungsarbeit (M130-M139)
> integriert. 0 Analyzer-Fehler, 739/739 Tests, Shim uebersetzt mit 39
> Symbolen.**
>
> **Zwei unabhaengige M101-Reihen.** Diese Sitzung baute offline M130-M139
> (Shim v12, Feature-Polymorphie, Extents, Kanten-Pick, Fillet/Chamfer,
> Revolve). Auf `main` entstanden parallel M101-M111 (Preview/Hover-Fixes,
> nativer Browser auf Liquid Glass, STEP-Export/Import). Gleiche Nummern,
> voellig andere Inhalte. Umnummerierung steht aus — Vorschlag: diese Reihe
> auf M112ff, weil `main` die veroeffentlichte ist.
>
> **Konflikte (7) und wie sie aufgeloest wurden:**
> - `PartKernel`: upstreams ABSTRAKTES `importStepSolids` neben den vier
>   konkreten dieser Sitzung; alle FUENF Fakes tragen jetzt beides.
> - `ExtrudeFeature`: upstreams `imported`/`importPath` durch die
>   M102-Umschreibung hindurchgerettet, inkl. Serialisierung.
> - **Beinahe-Datenverlust:** der `if (f.imported)`-Waechter in
>   `recomputeAllFeatures` haette den M102-Umbau nicht ueberlebt. Ohne ihn
>   wirft der erste Rebuild nach einem STEP-Import die importierte Geometrie
>   weg. Wiederhergestellt und typgeprueft (`f is ExtrudeFeature && ...`,
>   denn `features` ist jetzt `List<PartFeature>`).
> - `native_browser`/`_host`: auf `PartFeature` verbreitert und von
>   `openExtrude` auf `editFeature` umgestellt — der native Browser
>   bearbeitet damit auch Fillet, Chamfer und Revolve.
> - Shim: 39 Symbole (v12 + upstreams `occt_split_solids`), CI-Gates in
>   BEIDEN Workflows von 38 auf 39.
>
> **CI-BEFUND (KORRIGIERT):** `occt-build.yml` ist seit **M68 (27.07.)** nicht
> mehr erfolgreich durchgelaufen — Lauf #28 (M109) wurde abgebrochen. Die
> isolierte, strengere Pruefung (Symbolzahl + Undefined-Symbol-Check) fehlt
> also seit M68.
>
> **Was in einer fruehern Fassung dieses Eintrags FALSCH stand:** dort hiess
> es, `m1-core-build.yml` baue den Shim ueberhaupt nicht neu, weil ein
> gecachtes OCCT verwendet werde, und so sei M109s kaputte Translation Unit
> nach `main` gelangt. Nachgesehen: der Cache ist `backend/occt/install-ios`,
> also die OCCT-BIBLIOTHEK — die zu cachen ist richtig. Der Shim selbst wird
> in diesem Workflow SEHR WOHL aus der Quelle gebaut (`libocct_capi.a`,
> Zeile 726), und der ccache-Key haengt an `backend/**/*.cpp`. Ein kaputter
> Shim faellt dort also auf. Die Luecke ist damit deutlich kleiner als
> behauptet: es fehlt nur die isolierte Zweitpruefung, nicht jede Pruefung.
>
> **Lokal nachgeholt:** der ZUSAMMENGEFUEHRTE Shim uebersetzt sauber gegen
> echtes OCCT (7.6.3), inklusive upstreams `occt_split_solids`, und die
> Smoke-Fehlerparitaet zu HEAD bleibt 4 = 4 (7.6-Normalen-Artefakt).

> **PARALLELE REIHE M130-M139 (dieser Branch, noch nicht gemergt).**
> Diese Sitzung baute zunaechst als M101-M107 und kollidierte damit voll mit
> der auf `main` unabhaengig entstandenen Reihe M101-M113 (Preview/Hover,
> nativer Browser, Liquid Glass, STEP, DXF). Gleiche Nummern, voellig andere
> Inhalte. Umnummeriert auf **M130-M139**, mit Abstand statt auf die naechste
> freie Nummer: `main` legte waehrend dieser Sitzung etwa einen Meilenstein
> pro zehn Minuten nach, jede angrenzende Nummer waere beim naechsten Push
> wieder kollidiert. Code-Kommentare, Testdateinamen und die Eintraege unten
> tragen jetzt durchgaengig die neuen Nummern.
>
> Zuordnung: M130 Shim v12 · M131 Feature-Polymorphie · M132 Extents ·
> M133 Pick-Schicht · M134 Dedup · M135 Kanten-Hervorhebung ·
> M136 Fillet/Chamfer-Dialog · M137 Revolve · M138 Verifikation ·
> M139 M137-Tests + Revolve-Extents entfernt.

> **M139 — M137 nachgetestet (die Luecke aus dem letzten Meilenstein) und
> dabei einen echten Bug gefunden. 739/739 Tests gruen.**
>
> **Der Bug, den erst der Test zeigte.** Die Achsen-Pruefung in
> `_revolveSessionFeature` lautete
> `if (!s.axisPicked && !(s.axDx != 0 || s.axDy != 0))`. Die Vorgabeachse ist
> (0, 1) — also NICHT degeneriert — womit die zweite Klausel falsch wird und
> die ganze Bedingung nie greift. Folge: ein Revolve liess sich committen,
> ohne dass je eine Achse gewaehlt wurde, gedreht um eine Y-Achse, die der
> Benutzer nie angefasst hat. Jetzt ist `axisPicked` das EINZIGE Tor, die
> Richtung wird getrennt auf Nulllaenge geprueft.
>
> **17 neue Tests** in `test/m106_revolve_test.dart`, end-to-end durch
> `AppState` mit einem AUFZEICHNENDEN Fake-Kernel — geprueft wird also, was
> tatsaechlich beim Kernel ankommt, nicht was ankommen sollte: Full sendet
> exakt 360; Full ueberstimmt einen getippten Winkel; Symmetric sweept
> Angle A und liefert die Startdrehung als `mat34Rotated(...,-45)` im
> Placement (bei Full ist es das schlichte `mat34(0)`); Asymmetric summiert
> A+B und startet bei -B; Achse als Punkt+Richtung in Skizzenkoordinaten;
> unbekannte Skizze und Index ausserhalb werden abgelehnt; A+B > 360 wird
> abgelehnt; Bearbeiten ERSETZT das Feature (Name und seq bleiben) statt ein
> zweites anzulegen.
>
> **Revolve-Extents: bewusst entfernt statt kaputt gelassen.** Die drei
> Knoepfe erschienen im Revolve-Panel, weil das Panel geteilt ist, aber
> `resolveExtrudeSpan` loest nur den linearen Fall — ein Revolve waere still
> auf den Winkel zurueckgefallen. Die Knoepfe sind jetzt fuer Revolve
> ausgeblendet UND das Modell weist einen Nicht-Distance-Extent auf einem
> Revolve mit einer Meldung ab (fuer den Fall, dass eine Datei aus einem
> spaeteren Build so etwas mitbringt). Ein Bedienelement anzubieten, das
> nichts tut, ist schlechter als keins.
>
> **Stand nach diesem Meilenstein:** `flutter analyze` 0 Fehler,
> `flutter test` 739/739, Shim uebersetzt gegen echtes OCCT und die
> Smoke-Checks [20]-[23] liefern weiter exakt die analytischen Werte.
> Fehlerparitaet zu HEAD im Smoke unveraendert 4 = 4 (das 7.6-Normalen-
> Artefakt im bestehenden Mesh-Pfad).
>
> **OFFEN:** Revolve-Extents richtig implementieren hiesse, den Winkel zu
> finden, bei dem der rotierende Sweep zuerst auf Material trifft — das ist
> echte Arbeit, kein Nachziehen. Ausserdem unveraendert ungeprueft: alles
> Swift (kein Xcode), also die Kanten-Akzente aus M135, das Aussehen der
> Panels, und OCCT 7.9.3 selbst.

> **M138 — ECHTE Verifikation. Flutter-SDK und OCCT lokal installiert; alles
> von M101-M106 wurde zum ersten Mal wirklich uebersetzt und ausgefuehrt.
> Ergebnis: 18 Analyzer-Fehler gefunden und behoben, 722/722 Tests gruen,
> Shim kompiliert und rechnet analytisch korrekt.**
>
> **Setup:** Flutter 3.44.8 / Dart 3.12.2 (Tarball), OCCT 7.6.3 (Ubuntu
> `libocct-*-dev`). Die Produktion nutzt 7.9.3; fuer 7.6 fehlt
> `BRepLib_ToolTriangulatedShape` (kam erst in 7.7), dafuer ein Stub auf
> `Poly_Triangulation::AddNormals()`.
>
> **`flutter analyze`: 18 Fehler → 0.** Was ein Klammer-Zaehler NIE gefunden
> haette:
> - **`hoverEdge` war schon vergeben.** `app_state.dart:849` hat ein
>   `(int, int)? hoverEdge` fuer den Polyliniensegment-Hover des 2D-Sketchers;
>   mein `(KernelSolid, int)? hoverEdge` kollidierte damit. EIN Fehler, VIER
>   Folgefehler (zwei falsche Zuweisungen in `_projectHover`, eine in
>   `viewport.dart`). Umbenannt in `hoverEdge3d` / `setHoverEdge3d`.
> - **`edgeFingerprint` war verschwunden.** Beim Herausschneiden der lokalen
>   `segDistSq`/`PickBest`-Kopien in M134 hat mein Skript die dazwischen
>   liegende Funktion mitgenommen. `part_pick.dart` rief sie weiter auf.
> - **`ExtrudeSession` fehlte der Import** in `m103_extents_test.dart`.
> - **10 Fehler in den ALTEN Tests** (`m56_part_test`, `m67_feature_cache_test`)
>   — genau die in M131 vorhergesagte Folge der Polymorphie: `features` ist
>   `List<PartFeature>`, `distanceA`/`taperDeg`/`direction`/`exprA` brauchen
>   den konkreten Typ. Casts ergaenzt.
>
> **`flutter test`: 722/722 gruen**, davon 115 in den sechs neuen/erweiterten
> Dateien. Der QCAD-FFI faellt auf Linux erwartungsgemaess auf die
> Dart-Engine zurueck; das aendert nichts am Ergebnis.
>
> **Shim gegen echtes OCCT: 0 Compilerfehler.** Und die Smoke-Tests
> [20]-[23] rechnen EXAKT die analytischen Werte:
> - Revolve-Rohr `706.858347` = 225*pi, 4 Flaechen
> - 12 topologische Wuerfelkanten
> - Fillet r=5: `7892.699082` = 8000 - 25*(1-pi/4)*20
> - Chamfer d=4: `7840.000000`
> - Ray durch den Wuerfel: Treffer bei 10 und 30, je EINMAL
>
> Damit sind Revolve, Kanten-Identitaet, Fillet, Chamfer und Ray-Cast nicht
> mehr „blind geschrieben", sondern gerechnet.
>
> **Eigene falsche Testannahme korrigiert:** `[21]` erwartete, dass ein
> Fillet mit r=15 auf einer 20-mm-Kante scheitert. Tut es nicht — 15 < 20,
> das ist ein voellig legaler Radius. Auf r=25 geaendert (groesser als die
> Flaeche, auf der er liegen muss).
>
> **Kontrollexperiment gegen HEAD.** Vier Smoke-Checks ([11], [12], [15],
> [16], alle `mesh_create`) scheitern unter 7.6 mit
> `gp_Dir() - input vector has zero norm`. HEADs UNVERAENDERTER Shim,
> identisch gebaut, scheitert an GENAU denselben vier. Also ein
> 7.6-gegen-7.9-Artefakt des Normalen-Stubs im bestehenden Mesh-Pfad, keine
> Regression: Fehlerparitaet 4 = 4.
>
> **Was weiterhin NICHT geprueft ist:** alles Swift (kein Xcode) — also die
> Kanten-Akzent-Overlays aus M135 komplett; das AUSSEHEN der Panels; alles
> Zeigerbezogene (ob 14 px die richtige Tippgroesse ist); und OCCT 7.9.3
> selbst, denn lokal lief 7.6.3.
>
> **Hinweis fuer CI:** die 48 verbleibenden Analyzer-Meldungen sind Warnungen
> und Infos, ueberwiegend Alt-Bestand (ungenutzte Importe in aelteren Tests,
> `withOpacity` deprecated). Keine davon ist neu genug, um sie hier still
> mitzuaendern.

> **M137 — Revolve-Dialog samt Achsen-Pick. Damit sind alle vier
> Feature-Typen aus M102 bedienbar.**
>
> **Vorher nachgesehen, wieder drei Sachen gespart.** (1) Der Ribbon-Knopf
> „Revolve" existiert samt Icon, nur `onTap: () {}`. (2) Der Sketcher kennt
> `Geo.styleCenterline` und `Geo.styleConstruction` bereits — genau das, was
> Inventor als Revolve-Achse akzeptiert; nichts Neues noetig. (3)
> `_pickSketchCurve` liefert schon einen `sketchName#index`-Schluessel, also
> IST der Achsen-Pick ein Sketch-Kurven-Pick, kein neuer Mechanismus.
>
> **EINE Session und EIN Panel fuer Extrude und Revolve.** Von den 13 Feldern
> der `ExtrudeSession` sind nur `exprTaper`/`iMate`/`matchShape`
> extrude-eigen; Profile, Sketch-Bindung, Richtung, Output, Koerper, Extents,
> Vorschau und Auto-Pick sind identisch. Eine `RevolveSession` haette das
> alles verdoppelt. Stattdessen additiv: `kind`, dazu Achse + `full`. Das
> Panel verzweigt — Angle statt Distance (Einheit deg), Achsen-Zeile ueber
> dem Winkel, Full-Schalter (dimmt den Winkel), Taper ausgeblendet (ein
> Revolve hat keine Formschraege).
>
> Der KLASSENNAME bleibt `ExtrudeSession`, obwohl er jetzt beides traegt: er
> steht in main, ribbon, viewport3d, part_render und zwei Testdateien, und
> Umbenennen waere blind reines Risiko fuer Kosmetik. `kind` ist, was
> tatsaechlich schaltet. Bewusste Schuld, hier vermerkt.
>
> **`editing` wurde auf `PartFeature?` verbreitert.** Die Extrude-Bearbeitung
> mutiert das Feature IN PLACE; Revolve ersetzt es stattdessen im Timeline-
> Slot (derselbe Zug wie `applyEdgeFeature`), weil eine In-Place-Variante eine
> zweite Kopie jeder Feldzuweisung bedeutet haette, ohne Gewinn.
>
> **Achse als GEOMETRIE gespeichert**, nicht als Referenz auf die Linie:
> Punkt + Richtung in Skizzenkoordinaten. Die Linie darf spaeter geloescht
> oder neu gezeichnet werden — woran das Feature haengt, ist die Achse, die
> sie definiert hat. Genau der Vertrag, den `RevolveFeature` seit M102 hat.
> Nicht-Linien und Nulllaengen-Linien werden mit einer Meldung abgelehnt.
>
> **Validierung:** Winkel A in (0, 360], A+B <= 360 bei Asymmetric, Achse
> zwingend. `sweepDeg`/`startOffsetDeg` (M102, host-getestet) rechnen
> Flipped/Symmetric/Asymmetric aus; die Startdrehung reitet im Placement
> (`mat34Rotated`), der Shim sweept immer positiv.
>
> **Neu/berührt:** `app_state.dart` (`kind`+Achsenfelder in ExtrudeSession,
> `openRevolve`, `_revolveSessionFeature`, Achsen-Pick, `setExtrude(full:)`,
> `applyExtrude`-Zweig, `editFeature`), `widgets/extrude_dialog.dart`
> (Verzweigungen), `widgets/viewport3d.dart` (Achsen-Zweig im Tap-Pfad),
> `widgets/ribbon.dart`.
>
> **Verifikationsstand — ehrlich:** kein `flutter analyze`, keine Host-Tests.
> Die Winkel- und Placement-Mathematik ist seit M102 host-getestet und
> numerisch geprueft; NEU und ungetestet sind die Session-Verzweigung, der
> Achsen-Pick und die Panel-Verzweigungen — dafuer wurden in dieser Sitzung
> keine Tests geschrieben (Budget), was die groesste Luecke dieses
> Meilensteins ist. `applyExtrude` traegt jetzt zwei Pfade in einer Funktion;
> das ist die Stelle, die beim ersten CI-Lauf am ehesten bricht.
>
> **OFFEN:** keine Tests fuer M106; Revolve-Extents (To Next/To/Through All)
> sind im Modell und im Panel sichtbar, aber `resolveExtrudeSpan` gilt nur
> fuer Extrude — ein Revolve mit „Through All" nimmt derzeit still den
> Winkel-Pfad. Ausserdem weiterhin: Ursprungsachsen (X/Y/Z) sind als
> Revolve-Achse nicht waehlbar, nur Skizzenlinien.

> **M136 — Fillet- und Chamfer-Dialog. Kernel, Feature-Modell, Kanten-Pick
> und Hervorhebung lagen; das hier ist die Bedienoberflaeche.**
>
> **Vorher nachgesehen, drei Sachen gespart.** (1) Die Ribbon-Knoepfe fuer
> Fillet und Chamfer EXISTIEREN samt Icons (`MO['fillet']`, `MO['chamfer']`),
> sie hatten nur `onTap: () {}` — es war nur zu verdrahten, nichts zu bauen.
> (2) Ein 2D-Sketch-Fillet gibt es NICHT (die Treffer in `gear.dart` sind
> Zahnfuss-Rundungen, eine reine 2D-Konstruktion). (3) Eine gemeinsame
> Dialog-Huelle gab es nicht — Kopfzeile, Abschnitt, Beschriftungszeile,
> Wert- und Pick-Feld lagen alle PRIVAT in `ExtrudeDialog`.
>
> **Also zuerst extrahiert, dann gebaut.** Neu `widgets/properties_panel.dart`
> mit `panelSection` / `panelRow` / `panelPickField` / `panelValueField` /
> `panelDimWhen`. Die Rumpfe sind die Originale aus dem Extrude-Dialog,
> VERSCHOBEN statt neu geschrieben, damit sich am bestehenden Panel optisch
> nichts aendert; `ExtrudeDialog` hat seine privaten Kopien verloren und ruft
> jetzt dieselben Funktionen. Ohne diesen Schritt haetten drei Panels drei
> Kopien derselben Felder gehabt — genau das Muster, das schon einmal
> passiert ist.
>
> **EIN Dialog fuer beide Befehle.** `EdgeFeatureDialog` + `EdgeFeatureSession`
> mit `kind` = fillet|chamfer. Inventor zeigt zwei Befehle, aber die Panels
> unterscheiden sich nur in den Zahlen unter der Kantenliste — Kanten-Picker,
> Vorschau, OK/Abbrechen und die gesamte Huelle sind identisch. Zwei Sessions
> waeren zwei Orte, an denen die Kantenbehandlung synchron bleiben muesste.
>
> **Chamfer-Methoden** wie in Inventor: Distance / Two Distances / Distance
> and Angle, plus Flip (nur sichtbar wenn die beiden Seiten ueberhaupt
> unterschiedlich sind — bei gleicher Distanz bedeutet Flip nichts).
> `kernelParams` rechnet Flip weg, bevor irgendetwas den Shim erreicht.
>
> **Beim Wiederoeffnen** eines bestehenden Features wandern dessen Kanten
> zurueck in den Picker, damit 3D zeigt, worauf das Feature wirkt, statt einer
> leeren Auswahl.
>
> **Esc schliesst beides:** der Kanten-Pick gehoert ZUM Panel, nur den Pick
> abzubrechen liesse ein Panel zurueck, dem man keine Kanten mehr geben kann.
> `_openEdgeFeature` schliesst ausserdem eine offene Extrude-Session — zwei
> Property-Panels in derselben Ecke wuerden beide die 3D-Taps beanspruchen.
>
> **`editFeature` fertig verdrahtet:** Doppeltipp auf eine Fillet- oder
> Chamfer-Zeile im Browser oeffnet jetzt das richtige Panel. Revolve faellt
> weiterhin bewusst durch (kein Panel), statt ersatzweise das Extrude-Panel zu
> oeffnen.
>
> **Nebenbei gefunden, NICHT von mir:** `app_state.dart:1898-1899` ruft
> `_syncSolidProjections(p)` ZWEIMAL hintereinander, mit kaputter Einrueckung.
> Steht schon so in HEAD. Nicht angefasst, aber vermutlich ein Versehen.
>
> **Neu/berührt:** neu `widgets/properties_panel.dart`,
> `widgets/edge_feature_dialog.dart`, `test/m105_edge_feature_test.dart`
> (12 Tests); `app_state.dart` (Session, open/set/apply/cancel, Vorschau,
> `editFeature`, Esc), `widgets/extrude_dialog.dart` (delegiert jetzt),
> `widgets/ribbon.dart`, `main.dart`.
>
> **Verifikationsstand — ehrlich:** kein `flutter analyze`, keine Host-Tests,
> kein Xcode. Getestet ist die Session-Logik, die Validierung, die
> Chamfer-Parameterabbildung inkl. Flip, die getrennte Nummerierung und der
> JSON-Roundtrip. NICHT testbar: Vorschau und Commit, beide brauchen einen
> gelinkten Kernel — die Tests nageln nur fest, dass ohne Kernel ehrlich
> gescheitert statt ein Solid erfunden wird. Das Layout selbst hat niemand
> gesehen; dass der Dialog gut AUSSIEHT, ist unbelegt.
>
> **OFFEN:** Revolve-Dialog samt Achsen-Pick (M106) — das Modell, der Shim und
> `RevolveFeature` liegen seit M130/M131 vollstaendig, es fehlt nur das Panel.
> Ausserdem: Inventors „All Fillets / All Rounds"-Auswahlmodi und variabler
> Radius sind im Modell vorgesehen (`allFillets`/`allRounds`, Radius je Kante)
> aber im Panel nicht bedienbar — es setzt einen Radius fuer alle Kanten.

> **M135 — Kanten-Hervorhebung in 3D: Hover + Auswahl sichtbar. Die
> Fillet-/Chamfer-Dialoge koennen jetzt darauf aufsetzen.**
>
> **Der Plan aus M134 war falsch — Nachschauen hat ihn ersetzt.** Dort stand,
> das Basis-Kanten-Mesh muesse in zwei Meshes zerlegt werden. Muss es nicht:
> `rebuildHighlight` macht fuer FLAECHEN laengst genau das Richtige, naemlich
> eine SEPARATE Overlay-Entity aus einer Teilmenge bauen, gecached darauf was
> zuletzt gebaut wurde, und das Basis-Mesh nie anfassen. Fuer Kanten gilt
> dasselbe Muster eins zu eins. `edgeEntity()` bleibt voellig unberuehrt.
>
> **Neu Swift-seitig:** `SolidGeom.edgeHighlightEntity(edges:halfWidth:
> viewDir:lift:eps:color:)` — Spiegelbild von `faceHighlightEntity`, baut ein
> Ribbon nur ueber die akzentuierten DISPLAY-Kanten. Dazu
> `RealityPartView.rebuildEdgeAccents(from:)` mit `builtEdgeAccent`-Cache
> (gleicher Waechter wie `builtHighlight`: dieselbe Kante hovern baut nicht
> jeden Frame neu), aufgerufen aus `setScene` UND `setOverlays`.
>
> **Warum breiter statt nur naeher:** Akzent und Basis-Kante sind
> konstruktionsbedingt KOPLANAR. Ein Tiefen-Nudge allein laesst sie weiter
> z-fighten und der Akzent liest sich als Sprenkel; ein deutlich breiteres
> Ribbon (2.2x) zeigt beidseitig einen Saum, egal wie der Tiefentest ausgeht.
> Nudge ist trotzdem drin, aus demselben Grund wie beim Flaechen-Highlight.
>
> **DISPLAY-Indizes reisen, nicht topologische.** Swift indiziert
> `edgeStarts`; die Anzeige-Liste ueberspringt degenerierte, Naht- und
> tangentenstetige Kanten. Nur Dart muss wissen, dass die beiden Raeume
> auseinanderlaufen — deshalb schickt `solidPayload` auch weiterhin KEINE
> `edgeIds`.
>
> **Hover und Auswahl teilen sich EINE Menge und EINE Farbe**, weil
> `applySketchAccents` hovered und selected schon immer gleich behandelt
> (`let on = (key == hover) || selected.contains(key)`). Zwei Farben waeren
> ein drittes Highlight-Idiom im selben Viewport.
>
> **Der Akzent reist auf dem LEICHTEN Pfad** (`buildOverlaysPayload`), der
> ohnehin jeden Frame gepusht wird — `sceneSignature` bleibt unangetastet, ein
> Hover laedt also kein Mesh neu. Auf dem leichten Pfad ist der Schluessel
> IMMER dabei, auch leer: ein geloeschter Akzent muss reisen, sonst bleibt das
> letzte Highlight stehen.
>
> **Zwei Fehler dabei gefunden und behoben:** (1) die Akzent-Ribbons sind
> kamera-zugewandt und muessen beim Orbit/Zoom neu ausgerichtet werden wie die
> Sketch-Ribbons — sonst stehen sie nach dem Drehen quer. (2) Die
> Overlay-Entity haengt an `root`, nicht am Solid, verschwindet also NICHT mit
> ihm; ein zurueckgerolltes oder geloeschtes Feature haette seine
> hervorgehobenen Kanten im Raum stehen lassen.
>
> **Ein Koerper pro Feature:** ein Pick auf einem ZWEITEN Solid beginnt eine
> neue Menge statt zu mischen. Inventors Fillet arbeitet auf einem Solid, und
> eine Menge ueber zwei haette keine sinnvolle Basis zum Modifizieren.
>
> **Neu/berührt:** `PartScene.swift`, `RealityPartView.swift`,
> `app_state.dart` (`pickedEdgeDisplay`, `pickedEdgeSolid`, `hoverEdge`,
> `setHoverEdge`, Koerperwechsel-Regel), `reality_scene.dart`
> (`_edgeAccentPayload` in beiden Payloads), `widgets/viewport3d.dart`
> (Hover-Zweig + Solid/Display beim Tap); 7 Tests ANGEHAENGT an das
> bestehende `reality_scene_test.dart` statt einer neuen Datei.
>
> **Verifikationsstand — ehrlich:** kein `flutter analyze`, keine Host-Tests,
> und Swift wurde NICHT kompiliert (kein Xcode). Host-testbar und getestet ist
> die Payload-Seite (leer/gesetzt, Hover+Auswahl verschmolzen, keine
> Doppelung, leerer Schluessel auf dem leichten Pfad, Koerperwechsel,
> Abbruch). Der RENDER ist reine Geraete-Sache, wie jeder 3D-Meilenstein
> vorher.
>
> **OFFEN:** der CPU-Painter (`part_render.dart`) zeichnet den Kanten-Akzent
> NICHT — auf Nicht-iOS und in Galerie-Thumbnails fehlt er also. Fuer
> Thumbnails richtig so, fuer Desktop-Entwicklung ein blinder Fleck.

> **M134 — Aufraeumen: vier Kopien derselben Mathematik zusammengelegt.
> Grund: in M104 wurde Funktionalitaet nachgebaut, die es laengst gab.**
>
> **Was schon da war und uebersehen wurde.** Fuer SKIZZENKURVEN existiert die
> Kette Hover → Auswahl → Highlight vollstaendig, und sie wurde ausdruecklich
> als Geruest gebaut — der Kommentar in `viewport3d.dart:635` sagt woertlich
> „nothing consumes the selection yet — this makes them addressable for
> later". Konkret: `_pickSketchCurve` (Polylinien-Pick), `_distToSeg`,
> `sketchKey()`, `_hoverSketch` + `_selSketch` inkl. Tap-Toggle,
> `hoverSketch`/`selSketch` im Payload, und Swift-seitig
> `applySketchAccents`, das die adressierte Kurve umfaerbt
> (`sketchEntities` ist EINE Entity pro Kurve, mit Key).
>
> **Zusammengelegt (vier → eine):** neu `lib/pick_math.dart`, ein BLATT (nur
> `dart:ui`). Enthaelt `segDistSq` und `PickBest`. Blatt sein MUSS es: in
> keine der bestehenden Dateien konnte es wandern, weil `part_model`
> `tools.dart` importiert — alles, was `tools` importiert, darf also nicht
> nach `part_model` zurueckgreifen. Bisherige Kopien: `tools._distToSegment`,
> `viewport3d._distToSeg`, die private in `part_pick`, und
> `snap.closestOnSegment`. Alle vier delegieren jetzt.
>
> **Nebenbei ein echter Bug behoben:** `_pickSketchCurve` brach Gleichstaende
> NUR ueber den Pixelabstand auf, der Kanten- und Flaechen-Pick dagegen ueber
> die TIEFE. Eine Kurve auf der ABGEWANDTEN Seite des Modells konnte damit
> die gewinnen, auf die man zeigt. `PickBest` erzwingt jetzt ueberall
> dieselbe Regel: naeher schlaegt naeher-am-Cursor, Pixel entscheiden nur bei
> gleicher Tiefe.
>
> **Ebenfalls doppelt und jetzt geteilt:** die Rodrigues-Rotation lag ZWEIMAL
> in `part_model.dart` (`PartCamera._rotate` und, neu dazugekommen, inline in
> `mat34Rotated`) → `rotateAboutAxis`; die Box-Projektion auf eine Richtung
> lag in `originAxisSpan` und, neu dazugekommen, als 8-Ecken-Schleife in
> `bodySpanAlong` → `boxSpanAlong` (die Vorzeichen-Variante braucht 2 statt 8
> Skalarprodukte; gegen die Brute-Force-Variante ueber 20 000 Zufallsboxen
> geprueft, 0 Abweichungen).
>
> **BEWUSST NICHT angefasst:** `part_model._segDist`, der Inline-Fall in
> `constraints.dart:486` und `modify._lineParam`. Dieselbe Formel, ABER mit
> Degeneriert-Schwelle 1e-18 statt 1e-12. Das blind anzugleichen aendert das
> Verhalten des Constraint-Solvers bei Segmenten zwischen 1e-9 und 1e-6
> Laenge, und ohne laufende Tests ist das kein Tausch, den man machen sollte.
> Steht hier, damit es nicht wieder uebersehen wird.
>
> **Neu/berührt:** neu `lib/pick_math.dart`, neu `test/pick_math_test.dart`
> (14 Tests, inkl. Degeneriert-Fall und Stabilitaet bei Gleichstand);
> `part_pick.dart`, `widgets/viewport3d.dart`, `tools.dart`, `snap.dart`,
> `part_model.dart`.
>
> **Verifikationsstand — ehrlich:** kein `flutter analyze`, keine Host-Tests
> (weiterhin kein Dart in der Session). Numerisch nachgerechnet: die
> umgeschriebene `mat34Rotated` liefert dieselben fuenf Eigenschaften wie
> vorher (Achsenpunkte bleiben stehen, Radius erhalten, Hin-und-Rueck =
> Identitaet, orthonormal, det = +1), und `boxSpanAlong` stimmt exakt mit der
> 8-Ecken-Variante ueberein. Ein Compile-Bruch, den dieses Aufraeumen selbst
> erzeugt hatte (`viewport3d:688` rief das geloeschte `_distToSeg`), wurde
> gefunden und behoben.
>
> **OFFEN, unveraendert:** B-Rep-KANTEN sind Swift-seitig EINE zusammengefasste
> Entity pro Solid (`edgeEntity()` baut ein einziges `RibbonBuilder.mesh`
> ueber alle Kantenpolylinien mit EINEM Material), es gibt keinen Key und
> keine Per-Kanten-Entity — deshalb kann bisher keine einzelne Kante getoent
> werden. `solidPayload` schickt ausserdem `edgeIds` (M101) gar nicht mit.
> ACHTUNG beim Beheben: naive Per-Kanten-Entities machen M67-M70 zunichte
> (ein Zahnrad hat 440 Kanten). Richtige Form sind ZWEI Meshes je Solid —
> „alle Kanten ausser den akzentuierten" und „die akzentuierten" — neu gebaut
> nur wenn sich die Akzent-MENGE aendert.

> **M133 — Die Pick-Schicht: Kanten in 3D auswaehlen, und der Flaechen-Pick
> fuer „To". Damit ist M103 wirklich fertig und M105 nur noch Dialog.**
>
> **Kanten-Pick liegt in `part_pick.dart`, NICHT im Viewport.** Der Viewport
> braucht eine lebende `Cam3`, einen Widget-Baum und ein Geraet; diese Datei
> braucht nichts davon. Sie bekommt die Meshes und ZWEI CLOSURES (Weltpunkt →
> Bildschirm, Weltpunkt → Tiefe) und liefert eine Entscheidung — also ist die
> Mathematik, die entscheidet WELCHE Kante getroffen wurde, host-testbar. Der
> Widget-Teil ist zwanzig Zeilen Verdrahtung.
>
> **Warum Kanten kein Sonderfall des Flaechen-Picks sind.** Eine Flaeche ist
> ein Gebiet, der Baryzentrik-Test beantwortet „drin oder nicht". Eine Kante
> ist eine Kurve ohne Breite — es gibt kein „drin". Die Antwort ist immer
> „die naechste, falls nah genug", und das braucht eine Pixeltoleranz UND
> einen Tie-Break.
>
> **Der Tie-Break ist TIEFE, nicht Pixelabstand.** An jedem realen Modell
> projizieren die Silhouette einer nahen Flaeche und eine Kante auf der
> ABGEWANDTEN Seite desselben Koerpers staendig ein paar Pixel nebeneinander;
> nach Pixelabstand zu waehlen liefert etwa in der Haelfte der Faelle die
> Kante, die man gar nicht sieht. Der Flaechen-Pick loest Ueberlappungen aus
> genau demselben Grund ueber die Tiefe. Pixelabstand entscheidet nur noch bei
> gleicher Tiefe (zwei Kanten an einer Ecke).
>
> **Beinahe-Fehler, im Test festgenagelt:** der erste Wurf speicherte den
> TIPP-PUNKT als Fingerabdruck. `EdgeSel.bestMatch` vergleicht aber gegen
> `occt_shape_edge_info`, dessen Anker der BOGENLAENGEN-MITTELPUNKT ist — ein
> Tipp nahe einem Ende einer langen Kante haette also gegen deren Mitte
> verglichen und die Kante fuer verschwunden erklaert. `EdgePick.toSel()`
> liefert jetzt den Mittelpunkt, und der wird ueber die Bogenlaenge gelaufen,
> nicht am mittleren INDEX genommen: der Diskretisierer setzt Punkte dort, wo
> die Kruemmung sie braucht, auf einem Bogen liegt der mittlere Index also
> nirgends in der Mitte.
>
> **„To" ist verdrahtet.** Der Flaechen-Pick benutzt `_pickSolidFace`
> unveraendert — eine PLANARE Flaeche ist genau der Fall, den
> `resolveExtrudeSpan` analytisch loest. Ein Tipp auf „To" armiert sofort den
> Pick (wie Inventor), ein Wechsel weg entwaffnet.
>
> **Esc ist jetzt geschichtet:** Esc waehrend eines Picks bricht den PICK ab,
> nicht den Dialog — vorher haette es die gerade eingegebenen Profile und
> Einstellungen mitgenommen. `cancelExtrude` entwaffnet ausserdem alle
> Arm-Flags, sonst schluckt der Viewport nach dem Schliessen weiter Taps, ohne
> dass es dafuer noch eine sichtbare Ursache oder eine Abbruch-Zeile gibt.
>
> **Neu/berührt:** neu `lib/part_pick.dart`; `app_state.dart`
> (`pickingExtentFace`/`extentFacePicked`, `pickingEdges`/`toggleEdgePick`/
> `pickedEdges`, geschichtetes Esc, Entwaffnen beim Schliessen),
> `widgets/viewport3d.dart` (zwei Zweige im Tap-Pfad + `_pickEdgeAt`),
> `widgets/extrude_dialog.dart` (Zeile „Terminate on" ist ein Pick-Feld),
> neuer Test `test/m104_edge_pick_test.dart` (17 Tests).
>
> **Verifikationsstand — ehrlich:** wieder ohne Flutter/Dart, also KEIN
> `flutter analyze`, KEINE Host-Tests. Die Pick-Mathematik ist vollstaendig
> host-testbar und die Tests decken sie ab (Treffer, Toleranzgrenze, Tipp
> HINTER dem Segmentende, Kante ohne topologische ID, Tiefe-schlaegt-Pixel,
> Mehrfach-Mesh, Bogenlaengen-Mittelpunkt, Ende-zu-Ende-Rematch). Die
> Auswahl-Zustandsmaschine wird gegen die ECHTE `AppState` getestet, nicht
> gegen eine Kopie. NICHT getestet: alles am Zeiger — ob 14 px am Geraet die
> richtige Toleranz sind, ist eine Fingerfrage und Geraete-Sache.
>
> **OFFEN:** HOVER-Feedback fuer Kanten fehlt (der Tap-Pfad ist verdrahtet,
> der Hover-Pfad bei `viewport3d:613` nicht) — ohne Highlight sieht man vor
> dem Tippen nicht, welche Kante man treffen wuerde, und beim Verrunden ist
> das die halbe Bedienung. Ausserdem: die ausgewaehlten Kanten werden noch
> NICHT hervorgehoben gezeichnet. Beides gehoert in M105 vor die Dialoge.

> **M132 — Inventors Extents: To Next / To / Through All, in Extrude
> verdrahtet.** Das war die urspruengliche Frage.
>
> **Wo sie sitzen.** Rechts vom Wert, wie im Referenz-Panel. Das Feld SELBST
> ist die Distance-Option: waehlt man einen der drei, dimmt es; tippt man den
> aktiven Knopf nochmal, geht es zurueck auf Distance. Alle drei sind
> ausgegraut, solange es keinen Koerper gibt — Inventor macht das genauso,
> denn ein Basis-Feature hat nichts, woran es enden koennte. Die Bedingung
> dafuer existierte schon: `extrudeHasBooleanTarget`, dieselbe, die Cut und
> Intersect dimmt.
>
> **Aufgeloest wird beim Recompute, nicht beim Klicken.** `resolveExtrudeSpan`
> liefert dasselbe (Hoehe, Startversatz)-Paar wie `extrudeSpan` bisher:
> - *Through All* misst die Bounding-Box des Zielkoerpers ENTLANG der
>   Skizzennormalen und schlaegt an beiden Enden ueber. Ein Werkzeug-Deckel,
>   der mit einem Koerper-Deckel KOPLANAR liegt, ist der klassische Weg, ein
>   OCCT-Boolean zerbrechlich zu machen; der Ueberstand kostet nichts.
> - *To Next* castet `occt_ray_hits` von JEDEM Profil-Anker und nimmt den
>   kleinsten positiven Treffer. Strahlen starten auf der Skizzenebene, ein
>   Treffer bei t≈0 wird gefiltert — sonst loeste jedes To Next einer Skizze,
>   die AUF einer Flaeche liegt, zu null auf.
> - *To* loest eine PLANARE Zielflaeche analytisch (exakt in jeder Entfernung,
>   ohne Tesselierung); alles andere — Zylinder, unregelmaessige Flaechen —
>   faellt auf den Ray-Cast zurueck. Genau zwischen diesen Loesungen waehlen
>   Inventors „Alternate/Minimum Solution\"-Schalter, die noch fehlen.
>
> **`base` geht jetzt an JEDES Feature**, nicht nur an die
> koerper-modifizierenden: die Extents brauchen den Koerper, in den gebaut
> wird. Output 'new' hat keinen Vorgaenger — und genau deshalb greift dort die
> Inventor-Regel „nicht fuer Basis-Features\". Der Cache bleibt korrekt, weil
> der laufende Ketten-Schluessel den Upstream schon enthaelt.
>
> Vorschau UND Commit reichen denselben `base` durch; sonst waere ein To-Next
> im Dialog gescheitert und erst im nachfolgenden Fold gelungen.
>
> **Neu/berührt:** `part_model.dart` (`resolveExtrudeSpan`, `bodySpanAlong`,
> `nextFaceDistance`, `faceDistance`, `extentLabel`), `app_state.dart`
> (Session-Feld, `setExtrude(extent:)`, Vorschau + Commit),
> `widgets/extrude_dialog.dart` (drei Toggles + drei SVG-Icons), neuer Test
> `test/m103_extents_test.dart` (19 Tests).
>
> **Verifikationsstand — ehrlich:** wieder ohne Flutter/Dart in der Session,
> also KEIN `flutter analyze`, KEINE Host-Tests. Host-testbar ist die
> Entscheidungslogik und die analytische Planar-Mathematik (die Tests decken
> sie ab, inkl. gekippter Flaeche, Flaeche HINTER der Richtung und Flaeche
> PARALLEL zur Richtung — letztere darf nicht durch null teilen). NICHT
> host-testbar: Through All und To Next, weil ein `KernelSolid` ohne
> gelinkten Kernel keine `shape` hat; die Tests nageln dort nur fest, dass
> ehrlich gescheitert statt eine Zahl erfunden wird.
>
> **OFFEN:** Extents fehlen im Revolve (Modell traegt sie schon, Dialog
> existiert noch nicht); der FLAECHEN-Pick fuer „To\" ist noch nicht an den
> Viewport verdrahtet — `FaceSel` wird gespeichert und ausgewertet, aber
> gesetzt wird es bisher von niemandem, die Zeile im Dialog sagt deshalb
> „Select a face in 3D\" und bleibt leer. Ausserdem: Alternate/Minimum
> Solution, und Inventors „Between\"-Extent gibt es gar nicht.

> **M131 — `PartFeature`-Polymorphie, `EdgeSel` (topologische Benennung),
> Revolve/Fillet/Chamfer im Modell. Die UI fehlt noch.**
>
> **Warum zuerst.** `part.features` war `List<ExtrudeFeature>`, und Timeline,
> Browser, EOP-Marke und der Bool-Fold griffen direkt auf extrude-eigene
> Felder zu. Revolve, Fillet und Chamfer konnten schlicht nicht existieren.
> Neu: abstrakte Basis `PartFeature` (name/body/visible/output/seq/solid/
> computeError/consumedByJoin/rolledBack/builtSig + `ownSig()`), darunter
> `ExtrudeFeature`, `RevolveFeature` und — ueber die Zwischenbasis
> `BodyModifyFeature` — `FilletFeature` und `ChamferFeature`.
>
> **Der Fold kennt jetzt zwei Sorten.** Ein sketch-basiertes Feature
> KOMBINIERT sein Volumen mit dem Koerper (join/cut/intersect wie bisher).
> Ein koerper-modifizierendes Feature bekommt den akkumulierten Solid als
> EINGABE (`recomputeFeature(..., base:)`) und ersetzt ihn — es gibt da keine
> Boolean-Operation, und genau deshalb laeuft es an der Bool-Strecke vorbei.
> Ohne Vorgaenger meldet es ehrlich „nothing to modify", statt zu raten.
>
> **`EdgeSel` — der eigentliche Knackpunkt.** OCCT numeriert Kanten bei JEDEM
> Rebuild neu. „Kante 7" zu speichern haette das Fillet beim naechsten Edit
> auf eine andere Kante gesetzt. Gespeichert wird darum die GEOMETRIE:
> Bogenlaengen-Mittelpunkt, Laenge, Kurventyp, Radius — dieselbe Vertragsform
> wie `ProfileSel` sie fuer Profile schon hat. `bestMatch` sucht die
> naechstgelegene lebende Kante, ein TYPWECHSEL disqualifiziert (eine Gerade,
> die ein Bogen wurde, ist nicht dieselbe Kante), die Toleranz skaliert mit
> der Kantenlaenge, und `resolveEdges` vergibt jede lebende Kante nur EINMAL —
> sonst kollabieren zwei driftende Picks still zu einem Doppelradius-Fillet.
> Verlorene Picks werden fallengelassen und geloggt, der Rest wird weiter
> verrundet (Inventor-Verhalten).
>
> **`mat34Rotated`.** Der Shim dreht immer positiv ab der Profilebene;
> Flipped/Symmetric/Asymmetric reiten als Vor-Rotation im Placement — das
> rotatorische Gegenstueck zum z-Offset von `extrudeSpan`. Darum kann auch
> der Revolve-Pfad keinen gespiegelten Solid erzeugen. Numerisch geprueft:
> orthonormal, det = +1 (`occt_transform` VERWEIGERT alles andere), Punkte
> auf der Achse bleiben stehen, Radius erhalten, Hin-und-Rueck = Identitaet.
>
> **Achtung Fakes.** Die Test-Kernel benutzen `implements PartKernel`, nicht
> `extends` — konkrete Defaults in der Basis helfen dort NICHT. Die vier
> betroffenen Fakes wurden ergaenzt; `CountingKernel` hat `noSuchMethod` und
> war schon abgedeckt.
>
> **Neu/berührt:** `part_model.dart` (Basis, 3 Feature-Typen, EdgeSel/FaceSel,
> Recompute-Dispatch, Fold, Kernel-Interface + OCCT-Implementierungen),
> `app_state.dart` (`editFeature`-Dispatcher, generische Signaturen),
> `widgets/model_browser.dart`, 4 Test-Fakes, neuer Test
> `test/m102_feature_polymorphism_test.dart` (28 Tests).
>
> **Verifikationsstand — ehrlich:** in dieser Session standen WEDER Flutter
> noch Dart zur Verfuegung, `flutter analyze` und die Host-Tests sind also
> NICHT gelaufen. Geprueft wurden: Klammerbilanz aller beruehrten Dateien
> (Delta 0 gegen HEAD), Konstruktor/Feld/Lookup-Konsistenz der FFI-Klasse
> (36/36), Aufloesbarkeit aller im Test benutzten Symbole, und die
> Rotationsmathematik numerisch in Python. Alles Weitere ist CI-Sache.
>
> **OFFEN (M132-M136):** die Extents-Knoepfe (To Next / To / Through All) in
> Extrude UND Revolve — Modell und `occt_ray_hits` liegen, die UI fehlt; der
> Revolve-Dialog samt Achsen-Pick; Fillet-/Chamfer-Dialoge samt
> 3D-KANTEN-Pick (heute pickt der Viewport nur Flaechen, `_pickSolidFace`);
> `editFeature` oeffnet fuer alles ausser Extrude noch nichts.

> **M130 — OCCT-Shim v12: Revolve, Kanten-Identitaet, Fillet/Chamfer,
> Ray-Cast. 31 -> 38 Symbole.**
>
> Neu: `occt_revolve_profile` (Achse IN der Skizzenebene, Loecher werden wie
> beim Extrude einzeln revolviert und ausgeschnitten, Profil-kreuzt-Achse
> wird VERWEIGERT statt durch sich selbst gesweept), `occt_shape_edge_count` /
> `occt_shape_edge_info` (Fingerabdruck je Kante), `occt_mesh_edge_ids`,
> `occt_fillet_edges`, `occt_chamfer_edges` (alle drei Inventor-Methoden),
> `occt_ray_hits`.
>
> **Gefunden dabei:** die Anzeige-Kantenliste des Meshs ueberspringt
> degenerierte, Naht- und tangentenstetige Kanten — Anzeige-Index und
> `TopExp::MapShapes`-Index laufen also auseinander, sobald ein Modell einen
> Zylinder oder ein Fillet enthaelt. Ein Fillet auf dem Anzeige-Index haette
> still die FALSCHE Kante verrundet. Dafuer gibt es `occt_mesh_edge_ids`.
>
> **Smoke [20]-[23]** mit analytischen Zahlen: Rohr aus Rechteck-Revolve =
> 225*pi bei 4 Flaechen, halbe Drehung = die Haelfte, Profil ueber der Achse
> muss scheitern; Wuerfel = 12 Kanten, Fillet r=5 = 8000 - 25*(1-pi/4)*20 bei
> 7 Flaechen, r=15 muss sauber scheitern; Chamfer d=4 = 7840, d=4/45deg
> ergibt dasselbe, Winkel >= 90 muss scheitern; Strahl durch den Wuerfel
> trifft bei 10 und 30, jede Kreuzung GENAU einmal.
>
> CI-Gates auf 38 gezogen (`occt-build.yml` und der LINK CHECK in
> `m1-core-build.yml` — beide, sonst luegt einer von beiden).
>
> **Verifikationsstand — ehrlich:** das C++ wurde NIE gegen OCCT kompiliert
> (kein cmake in der Session, `backend/occt/upstream` ist ein leeres
> Submodul). Bewiesen ist nur: `smoke_occt.c` uebersetzt sauber mit
> `gcc -fsyntax-only` — und da es ausschliesslich `occt_capi.h` einbindet,
> heisst das, dass jede neue Aufrufstelle gegen die Deklarationen typprueft.
> 38 Definitionen == 38 Deklarationen, Klammern balanciert. Erwartungswert
> fuer den ersten CI-Lauf: Korrekturen an OCCT-Include-Namen.
> ## ⇢ STAND FUER DIE NAECHSTE SITZUNG (Ende dieser Sitzung, Kopf `93dd3de`)
> ## ⇢ STAND FUER DIE NAECHSTE SITZUNG (Ende dieser Sitzung, Kopf `93dd3de` + M123/M124)
>
> **Alles gruen:** `dart-checks` 632 Tests + analyze sauber, `build-core-ios`,
> `M3` und `m5-flutter-ipa` bestanden. **M123 kam danach dazu und ist auf `main`:
> CI-Lauf #305 (`2b98820`) komplett gruen — 645 Tests, analyze 51 Issues /
> 0 errors, also exakt der Ausgangsstand. In diesen Branch hereingemischt, hier
> zusammen mit M124–M128 noch nicht erneut durch die CI.**
>
> **Was in dieser Sitzung entstand:** M82–M122. Grob: Galerie-Vorschau auf der
> echten 3D-Engine, Ursprungsebenen rahmen das Teil, Share Sketch +
> Browser-Kontextmenues, klebrige Split-Buttons, zwei Spline-Fixes, das
> Freihand-Werkzeug, Zeitstrahl-Browser + End of Part, Polygon voll bestimmt,
> Koerper-Picken fuer Extrude, STEP-Import als Koerper, DXF-Export ohne
> gefaehrliche Konstruktionslinien, und der komplett native Model Browser auf
> Liquid Glass.
>
> **OFFEN — nach Wichtigkeit:**
> 0a. **HUD-Eingabe waehrend des Offsets (Rest von M124).** Inventor zeigt ein
>    schwebendes Abstandsfeld, in das man den Offsetwert TIPPT. Das Mass danach
>    zu editieren geht jetzt; das Tippen VORHER nicht. `hud.dart` ist an
>    `toolPoints`-Phasen gekoppelt (Erzeugungswerkzeuge), Offset laeuft ueber
>    `modEntity` + Hover — also ein echter Umbau, kein neuer enum-Fall.
> 0. **Geraete-Test von M123/M124 im 2D-Modus**: einen Punkt auf Kreis, Bogen,
>    Spline und Polygonkante zeichnen und dann ZIEHEN — bleibt er auf dem
>    Traeger? Am Host bewiesen, am Geraet nie gesehen.
> 1. **Geraete-Test des Panels** (M118–M122): Einziehen, EOP-Zug, ob die
>    Rollback-Wirkung jetzt stimmt, ob 78 pt eingezogen reichen, ob das Glas
>    ueberhaupt bricht. Fast alles seit M107 ist nur CI-gruen, nicht gesehen.
> 2. **DXF: Splines/Zahnraeder gehen als Polylinien raus.** Verlustig, nicht
>    gefaehrlich. Echte SPLINE-Entities brauchen eine `qcad_add_spline`-
>    Erweiterung im C-API (dxflib kann es, das Prototype-API nicht).
> 3. **Nummernkollision M90** — zweimal vergeben (mein Kontextmenue-Lift-Fix und
>    der Trackball-Orbit einer anderen Sitzung). Nur Kosmetik, aber verwirrend.
> 4. **Umbenennen-Dialoge im nativen Browser** sind weiter Flutter-`AlertDialog`s.
> 5. **CI-Zeit**: ccache ist drin, greift ab dem zweiten Lauf. Naechster Hebel
>    waere, die schweren Jobs bei reinen Dart-Aenderungen zu ueberspringen —
>    aber nur mit sorgfaeltig geprueftem Pfadfilter, sonst rutscht eine echte
>    C++-Regression durch.
>
> **Fehlermuster dieser Sitzung, bitte lesen — sie haben am meisten Zeit
> gekostet:**
> * **Vier Anlaeufe am EOP-Zug**, weil ich ueber den Code nachdachte, statt das
>   Log zu lesen: `DOWN` … 150 ms … `CANCEL` ohne `MOVE` ist ein Long-Press,
>   der die Beruehrung kassiert. Erst UIKits Kontextmenue (M102), dann der Pan
>   der Liste (M121). **Wenn ein Zug nicht ankommt, ist es fast immer ein
>   anderer Recognizer.**
> * **Zweimal Hysterese gegen ein Symptom** (M102/M103), obwohl die Ursache eine
>   Rueckkopplung war, die ich selbst gebaut hatte (M104). **Erst fragen, WARUM
>   ein Sample falsch ist.**
> * **Viermal Zeilen-Arithmetik**, obwohl die Zielposition im Modell gar nicht
>   existierte (M113). **Stimmt eine Umrechnung wiederholt nicht, fehlt meist
>   die Position.**
> * **Signatur-Fallen**: alles, was das Bild aendert, MUSS in `sceneSignature`
>   stehen (M95, M122) — sonst wird kein Rebuild geschickt und die Aenderung
>   "wirkt nicht".
> * **Ein `!` auf einem Map-Zugriff im Widget-Baum ist ein App-Killer** (M115):
>   der Fehler nimmt den ganzen Teilbaum mit, hier das komplette Ribbon.
> * **Vor dem Erweitern das vorhandene C-API lesen** (M109): STEP-Export gab es
>   laengst, mein Duplikat hat die Uebersetzungseinheit zerschossen.

> **M124 — Bemassung zwischen zwei Kreisen; zwei Luecken, eine Ursache.**
>
> Gemeldet: „Kreis Ø20 zeichnen, offsetten, 2 mm eintippen und ein Mass
> zwischen den beiden Kreisen bekommen" — und „zwei konzentrische Kreise
> anklicken und wie in Inventor ein Mass zwischen den Durchmessern".
>
> **Was wirklich fehlte.** Zwei Kreise anklicken gab die MITTELPUNKT-Distanz.
> Bei konzentrischen Kreisen ist die identisch 0: sie misst nichts und kann
> nichts treiben. Und `_commitOffset` verdrahtete Linien (parallel + `pline`-
> Mass) und Boegen (`concentric`), liess eine KREIS-Kopie aber voellig lose —
> keine Bedingung, kein Mass. Die Kopie driftete beim ersten Ziehen, und es gab
> keinen Wert, in den man 2 haette tippen koennen.
>
> **Inventor-Recherche.** Zwei Kreise = Mitte-zu-Mitte, Kante-zu-Kante gibt es
> ueber **Alt** beim Picken. Kreis bekommt Durchmesser, Bogen Radius, Rechtsklick
> tauscht. Offset (neuere Versionen) hat ein schwebendes Abstandsfeld. Dynamic
> Input: Tippen SPERRT ein Feld und erzeugt daraus ein persistentes Mass, ein
> nie beruehrtes Feld bekommt keins — das ist in `hud.dart` bereits sauber
> umgesetzt, nur eben nicht fuer Offset.
>
> **Die Loesung: ein neues `dimKind: 'gap'`** = |R2 - R1|, die Ringbreite —
> genau die Strecke, um die ein Offset einen Kreis versetzt. An allen fuenf
> Stellen eingebaut: `measureDim`, `residualCount`, Residuum, Vorzeichen-Freeze
> in `_prepare` (welcher Kreis der aeussere ist, wird EINMAL pro Solve
> eingefroren — die abs() hat ihre Ecke genau in der Loesung, und ein Paar das
> sich waehrend eines Zugs kreuzt wuerde sonst mitten im Solve die Rollen
> tauschen), und das Zeichnen. Der slvs-Shim kennt es nicht, also faellt der
> Sketch ueber die bestehende Allow-Liste auf den verifizierten Dart-LM-Pfad.
>
> * Konzentrisches Paar -> Gap-Mass. Versetzte Kreise weiter Mitte-zu-Mitte,
>   wie Inventor.
> * Kreis-Offset erzeugt `concentric` + ein Gap-Mass als **editierbaren
>   Treiber**, wie die Linien ihren d0-Treiber haben.
>
> **Ein eigener Fehler, den erst der Test fand:** ich nahm zuerst
> `chain.offsetDist` als Wert. Das ist die senkrechte Laufdistanz der LINIEN und
> ist bei einer reinen Kreiskette 0 — das Mass zog die Kopie sofort auf ihre
> Quelle zurueck (beide landeten bei r11.5). Der Wert kommt jetzt aus der
> Radiendifferenz. Lehrreich, weil es still war: die Geometrie sah richtig aus,
> bis der Solver lief.
>
> **Belegt:** Ø20 offset -> Gap 3.0 (Quelle r10, Kopie r13); Gap auf 2 -> Kopie
> exakt r12; Quelle auf Ø30 -> Kopie folgt auf r17, weil das Gap eine BEZIEHUNG
> ist und kein fester Radius. 653 Tests, analyze 51 Issues / 0 errors.

> **M123 — Punkt-auf-Kurve entstand nur an LINIEN.**
>
> Gemeldet aus dem 2D-Modus: landet ein gezeichneter Punkt auf einer Linie,
> entsteht die Bindung; landet er auf einem Kreis, einem Bogen oder einem
> Spline, entsteht **nichts**. Der Punkt sah gebunden aus und rutschte beim
> ersten Ziehen ab.
>
> **Ursache — eine Zeile.** `inferPointBindings` (constraints.dart) hatte
> `if (gs[j].type != Geo.line) continue;`. Der Snap bietet den 'on'-Fang fuer
> Kreis, Bogen, Spline, Ellipse, Zahnrad und Polylinie laengst an (snap.dart),
> der Punkt lag also bereits EXAKT auf dem Traeger — nur gefragt hat nie jemand.
> Neu ist `pointLandsOn(Geo, Offset)` fuer alle Traegertypen. Zwei Feinheiten,
> beide getestet: ein Bogen bindet nur auf dem **gezeichneten** Sweep (nie auf
> dem Gegenbogen, gleiche Pruefung wie der Snap — dafuer wurde `_angleOnArc` zu
> `angleOnArc` oeffentlich), und definierende Punkte sind ausgenommen, weil ein
> Treffer dort **Punkt-auf-Punkt** ist, die staerkere Bindung.
>
> **Wie weit der Solver schon war.** Kreis/Bogen konnten BEIDE Solverpfade
> bereits (Dart-Residuum `|q-c| - r`, slvs `SLVS_C_PT_ON_CIRCLE` hinter dem
> Shim-v4-Gate) — der Trim/Split-Cut-Bind erzeugt sie seit M38.1. Fuer
> Polylinien-Traeger (Polygon, Spline, Ellipse, Zahnrad) gab es dagegen GAR
> nichts: `residualCount` gab 0 zurueck, die Bindung waere gespeichert und
> gezeichnet, aber **nie durchgesetzt** worden, und der slvs-Packer waere auf
> `SH_PT_ON_LINE` mit einer Nicht-Linien-Entitaet durchgefallen.
>
> **Das neue Residuum.** Eine Polylinie hat keine geschlossene implizite
> Gleichung wie ein Kreis. Die Kurve wird deshalb pro Durchgang EINMAL
> abgetastet und auf ihre Tangente am naechsten Punkt reduziert
> (`_OnCurve`-Rahmen, gleiche Freeze-Idee wie die Tangenten-Zweige). Das
> Residuum ist danach O(1) und tastet nie ab. **Der teuerste Fehler dabei:**
> `residualCount` laeuft IM Jacobi-Kern (`_residuals` ruft es pro Constraint pro
> Auswertung) — dort die Kurve zu erzeugen kostete auf einem 60-Punkt-Spline das
> ~100-fache. Es entscheidet jetzt nach der Stuetzpunktzahl, ohne abzutasten.
>
> **`_lm` laeuft in Durchgaengen.** Eine Tangente ist nicht die Kurve: bewegt
> sich der Traeger weit, minimiert LM sauber gegen die Tangente und der Punkt
> liegt trotzdem daneben (~d²/2R). Also: konvergieren → Rahmen auf die Kurve
> zurueckwerfen → erneut konvergieren. Ohne Punkt-auf-Kurve-Constraint laeuft
> genau ein Durchgang, alles andere bleibt unveraendert. Der erste Anlauf haengte
> den Rueckwurf an den `lambda`-Ueberlauf und lief nie — die Schleife endet
> normal, sobald der STALE Rahmen konvergiert ist.
>
> **Traeger folgt starr.** Jeder Stuetzpunkt haelt einen gleichen Anteil der
> Normalen, damit eine reine VERSCHIEBUNG des Traegers exakt ist. Die echten
> Basisgewichte numerisch zu messen war gebaut und wurde **verworfen**: ein
> Kurven-Neuaufbau pro Stuetzpunkt pro Rahmen, auf einem 60-Punkt-Freihand-Spline
> (M87) 28 ms pro Solve gegen 0.4 ms ohne Bindung. Eine VERFORMUNG faengt jetzt
> der Rueckwurf ein (eigener Test: ein Stuetzpunkt wird gezogen, der gebundene
> Punkt landet auf der verformten Kurve).
>
> **slvs.** Der Shim kennt keine Polylinien-Entitaet, also **Bail auf den
> verifizierten Dart-LM-Pfad** (wie das Pattern-Constraint) statt einer falschen
> Gleichung; der Packer wurde zusaetzlich abgesichert, damit ein Nicht-Linien-
> Traeger dort nie als Linie landet.
>
> **Auch repariert:** das manuelle Coincident-Werkzeug nahm als zweiten Pick nur
> Linien und widersprach damit der eigenen Automatik und dem Cut-Bind.
>
> **Zahlen (Host, Container-CPU — das Geraet ist schneller).** Zug-Solve mit
> 6-Punkt-Spline: 671 us ohne, 969 us mit Bindung. Im 124-Parameter-Sketch
> kostet die ALTE Punkt-auf-Linie-Bindung 37.7 ms gegen 5.0 ms fuer M123 — die
> Kosten sind dort die Sketch-Groesse, nicht der Traeger.
>
> **Ehrliche Restschuld:** der Rahmen ist eine pro Durchgang erneuerte
> Linearisierung, keine exakte NURBS-Projektion. Fuer eine echte Projektion
> muesste der Kurvenparameter als zusaetzliche Unbekannte in den
> Parametervektor — das beruehrt `_pack`/`_unpack`/`paramsOfPoint` und die
> Rang-Analyse und war mir fuer diese Aenderung zu invasiv. Konvergiert ein
> Solve seine Durchgaenge nicht, faellt er durch das normale Residuen-Gate und
> wird verworfen, statt falsch gezeigt zu werden.

> **M122 — End of Part wirkte nicht richtig, und der Extrude-Dialog lag hinter
> dem Browser.**
>
> **(1) "Der ganze Koerper ist weg, obwohl nur eine Extrusion wegsollte."**
> `setEndOfPart` hat nur `rolledBack` umgelegt und NIE neu gerechnet. Die
> Join-Kette blieb damit stehen: `consumedByJoin` zeigte weiter auf ein
> Feature, das jetzt zurueckgerollt ist. Extrusion2 unsichtbar, weil
> zurueckgerollt — Extrusion1 unsichtbar, weil "in Extrusion2 aufgegangen".
> Beide weg, also der ganze Koerper. Jetzt laeuft `recomputeAllFeatures` direkt
> nach `applyEndOfPart`.
>
> **(2) "Auf Skizzen hat es gar keine Wirkung."** Zurueckgerollte Skizzen
> fliegen seit M113 aus dem Payload, aber `sceneSignature` kannte weder
> `cs.rolledBack` noch `eopAfter` — die Signatur blieb also gleich, es wurde
> kein Rebuild geschickt, und in 3D aenderte sich nichts. Beide stehen jetzt
> drin. (Dieselbe Falle wie M95; die Signatur muss ALLES enthalten, was das
> Bild veraendert.)
>
> **(3) Ziehen "mal ja, mal nein".** `indexPathForItem(at:)` liefert im
> Haarspalt ZWISCHEN Zellen nil; beginnt der Zug dort, scheiterte die Geste und
> die Liste scrollte stattdessen. `eopIndex(at:)` probiert jetzt ein paar
> Punkte um die Beruehrung herum.
>
> **(4) Extrude-Dialog** startete auf (12, 12) — also direkt unter der
> schwebenden Browser-Karte. Er parkt jetzt rechts, vertikal zentriert, und
> bleibt verschiebbar.

> **M121 — Panel-Durchgang: Groesse, abgeschnittene Icons, und der EOP-Zug
> eine Ebene tiefer.**
>
> **EOP, die eigentliche Ursache im nativen Panel.** Einen Pan-Recognizer an
> eine `UICollectionView` zu haengen reicht nicht: die Liste hat ihren EIGENEN
> `panGestureRecognizer`, der wurde zuerst installiert, und der Pan einer
> Scroll-View ist gierig — er beanspruchte die Beruehrung, die Marke bewegte
> sich nicht. Exakt derselbe Fehler wie in der Flutter-Fassung, nur eine Ebene
> tiefer. `collection.panGestureRecognizer.require(toFail: pan)` gibt die
> Beruehrung ab, sobald der Zug auf der End-of-Part-Zeile beginnt. Das kostet
> nirgends Scrollen: `gestureRecognizerShouldBegin` lehnt fuer jede andere
> Zeile sofort ab, der Scroll-Pan ist im selben Event wieder frei. Waehrend des
> Zuges ist Scrollen abgeschaltet, damit nichts unter dem Finger wegrutscht.
>
> **Eingezogen zu schmal.** 62 pt minus 28 pt linker Inset liessen ~34 pt
> Inhalt, das 16-pt-Glyph lief gegen den Zellenrand. Jetzt 78 pt, und
> eingezogene Zellen bekommen symmetrische 4-pt-Raender statt der 12 pt, die
> fuer eine Textzeile gedacht waren.
>
> **Hoeher und weiter oben:** 82 % Hoehe, Anker `Alignment(-1, -0.35)` — der
> tote Raum oben wird genutzt, die Triade behaelt ihre Ecke.
>
> **Weitere Befunde aus dem Durchgang, mitbehoben:** ein Tipp auf die
> ORDNER-Zeile (Solid Bodies / Origin) klappt sie jetzt auf — vorher reagierte
> nur das 20-pt-Chevron auf einer 264-pt-Zeile; die gerade GEOEFFNETE Skizze
> ist im Baum hervorgehoben (der Baum beantwortet "wo bin ich"); der
> Scroll-Indikator ist auf `.white` gestellt, weil der Standard schwarz auf
> Glas ist; die Dokument-Zeile ganz oben ist eine Beschriftung und schluckt
> ihren Tipp still, statt so zu tun, als waere sie ein Knopf.

> **M121 — Eingezogen war zu schmal, und oben lag Platz brach.**
>
> **Breite.** Die Karte behaelt ihren 28-pt-Rand links, von 62 pt blieben also
> nur ~34 pt Inhalt — und gegen den 12-pt-Innenrand der Zelle wurde das
> 16-pt-Glyph abgeschnitten. Jetzt 78 pt, und die eingezogenen Zeilen bekommen
> einen schlanken, SYMMETRISCHEN Innenrand (4/4 statt 12/4), damit die
> Icon-Spalte mittig steht statt gegen die Kante zu druecken.
>
> **Hoehe und Lage.** 82 % statt 75 %, und die Karte sitzt bei `Alignment(-1,
> -0.35)` ueber der Mitte: oben war ungenutzter Raum, waehrend unten nur die
> Triade Platz braucht.

> **M120 — Drei gemeldete Symptome, zwei Ursachen.**
>
> **(1) Der Einzieh-Griff lag AUF der Karte und fraß die Ordner-Klicks.** Die
> Karte war per `width:` bemessen, der Griff-Streifen daneben per `right: 0` —
> also lief die Karte UNTER dem Streifen weiter. Ein Flutter-`GestureDetector`
> ueber einer Plattform-View schluckt die Beruehrung, und genau deshalb klappte
> ein Tipp auf das Disclosure-Chevron von *Solid Bodies* oder *Origin* nicht
> den Ordner auf, sondern zog das Panel ein. Die Karte endet jetzt per
> `right: _kHandle` genau dort, wo der Streifen beginnt — ueberlappen ist damit
> konstruktiv ausgeschlossen.
>
> **(2) Kein linker Rand.** Die Insets wurden EINMAL beim Init auf
> `container.bounds` gerechnet — zu dem Zeitpunkt oft `zero` — und
> `flexibleWidth/Height` SKALIERT diesen Rahmen anschliessend, statt den Rand zu
> erhalten. Ergebnis: die Karte klebte an der iPad-Kante. Glas und
> `UICollectionView` haengen jetzt an **Auto-Layout-Constraints** mit den
> Inset-Konstanten; die halten bei jeder Groessenaenderung.
>
> **Lehre:** `frame` + `autoresizingMask` und ein Rand, der erhalten bleiben
> soll, passen nicht zusammen — Autoresizing skaliert, es respektiert keine
> Konstanten.

> **M119 — Panel-Feinschliff und ein schnelleres CI.**
>
> **Griff AUSSERHALB der Karte.** Der Chevron sitzt jetzt in einem 24-pt-Streifen
> NEBEN dem Glas, nicht darauf, und blendet sich ein, wenn der Zeiger in die
> Naehe kommt. Ein dauerhaft angeklebter Griff an einem CAD-Panel ist
> Bildrauschen; man sucht ihn, wenn man ihn braucht. **Wichtig dabei:** auf
> einem Geraet ganz ohne Zeiger gibt es nie ein `onEnter` — dort bliebe er
> unerreichbar. Er ist deshalb sichtbar, bis zum ERSTEN Hover-Ereignis; danach
> gilt die Naehe-Regel.
>
> Karte auf **75 %** Hoehe, linker Rand auf 28 pt, rechter auf 0 (der Streifen
> liefert den Abstand).
>
> **CI: ccache fuer den C++-Teil.** Fast jeder Commit hier fasst nur Dart an,
> trotzdem wurde jedes Mal die komplette native Seite neu uebersetzt — das ist
> der Loewenanteil der ~20 Minuten. `build-core-ios` benutzt jetzt ccache
> (`CMAKE_C/CXX_COMPILER_LAUNCHER`), der Cache-Key haengt am Hash der
> C++-Quellen, `restore-keys` laesst ihn bei echten Backend-Aenderungen warm
> starten statt kalt. Beim ersten Lauf passiert nichts (leerer Cache), ab dem
> zweiten sollte eine reine Dart-Aenderung den nativen Teil in Sekunden statt
> Minuten durchlaufen.
>
> **Nicht angefasst:** OCCT ist bereits ueber `actions/cache` abgedeckt, und
> `m5-flutter-ipa` ist Flutter-gebunden. Wenn es weiter zu lang dauert, waere
> der naechste Hebel, die schweren Jobs bei reinen Dart-Aenderungen ganz zu
> ueberspringen — das braucht aber einen Pfadfilter, den man erst validieren
> sollte, sonst faellt eine echte C++-Regression durch.

> **M118 — Der Browser laesst sich einziehen.**
>
> Chevron am RECHTEN Rand der Karte: Tippen schaltet um, ein horizontaler Wisch
> darauf tut dasselbe in der Richtung, in die man wischt — das ist die Geste,
> die man zuerst probiert. Die Breite animiert (264 ↔ 62), damit es wie EIN
> gleitendes Objekt wirkt und nicht wie zwei getauschte Zustaende.
>
> **Eingezogen bleibt der Zeitstrahl, als Icons:** Skizzen, Features und die
> End-of-Part-Marke. Die Ordner (Solid Bodies, Origin) und die Beschriftungen
> sind das, wofuer man das Panel AUFmacht — also genau das, was das Einziehen
> entfernt. Jede Zeile behaelt ihre id, ein Tipp tut in beiden Breiten
> dasselbe, und die Kontextmenues bleiben ebenfalls dran.
>
> Nativ: ohne Label wird die Zelle icon-only und das Glyph mittig gesetzt,
> sonst klebte die Spalte dort, wo vorher der Text anfing. Linker Rand auf
> 18 pt, damit die Karte nie auf der iPad-Kante sitzt.

> **M117 — Import gehoert in das "+"-Menue der Galerie, nicht ins Ribbon.**
>
> Der Knopf aus M111 ist aus BEIDEN Ribbons entfernt. Stattdessen steht
> **"Import STEP / DXF…"** als dritter Eintrag unter *New 2D Sketch* und
> *New 3D Part* — denn genau das ist er: ein dritter Weg, an ein Dokument zu
> kommen. Im Ribbon stand er zwischen Modellierwerkzeugen, im falschen Regal.
> Eine STEP wird zu einem NEUEN PART (ein Koerper je Solid), eine DXF zu einer
> neuen Skizze; benannt nach der Datei, mit Kollisionszaehler. So muss man
> nicht erst ein leeres Dokument anlegen, nur um irgendwo hin zu importieren —
> genau das erzwang der Ribbon-Knopf.
>
> Der ACAD-Knopf im Skizzen-Ribbon bleibt, hat aber wieder seine eigene
> Aufgabe: DXF in die BEREITS OFFENE Skizze mergen. Das ist etwas anderes als
> ein Dokument aus einer Datei anzulegen.
>
> **Browser vertikal zentriert** (`Alignment.centerLeft`): halbe Hoehe, mittig
> an der linken Kante, Luft darueber und die Triade frei darunter.

> **M116 — Der Browser ist eine Karte, keine Wand.** Halbe Viewport-Hoehe,
> oben links verankert (`FractionallySizedBox(heightFactor: 0.5)` in einem
> `Align` innerhalb des `Positioned.fill`), damit die Ursprungs-Triade unten
> links darunter sichtbar bleibt. Raender auf 12 pt links/oben/unten und 6 pt
> rechts, damit der Baum seine Breite behaelt. Laeuft die Liste ueber, scrollt
> sie — das kann die `UICollectionView` von sich aus.
>
> Das `Align` ist wichtig: `Positioned.fill` allein wuerde den ganzen Stack
> belegen; ein `Align` trifft beim Hit-Test nur sein Kind, Tipps neben der
> Karte gehen also weiter an den Viewport.

> **M115 — KRITISCH: c697a81 hatte GAR KEIN Ribbon. Meine Schuld, ein
> falscher Map-Name.**
>
> Der Import-Knopf aus M111 stand als `IC['acad']!` im Quelltext — das Icon
> liegt aber in der Map **`IN`**, nicht `IC`. Der Null-Check-Operator warf also
> beim Bauen, Flutter ersetzte das GESAMTE Ribbon durch sein rotes
> Error-Widget (das ist der rote Balken im Screenshot), und damit waren alle
> Werkzeuge weg — inklusive des Import-Knopfes, den die Aenderung gerade
> hinzufuegen wollte. Im Geraete-Log steht es woertlich:
> `widget: build failed: Null check operator used on a null value`.
>
> **Warum die CI das nicht gefangen hat:** die Icon-Maps sind
> `Map<String, String>`, ein fehlender Schluessel ist also ein Laufzeit-`null`
> und kein Typfehler. `flutter analyze` kann das nicht sehen, und kein
> Host-Test baute das Ribbon.
>
> **Behoben** (`IN['acad']`), und der ganze Ribbon-Quelltext wurde gegen alle
> fuenf Maps auditiert — das war der einzige Treffer. Neu
> `test/m115_ribbon_icons_test.dart`: liest `ribbon.dart` und prueft JEDEN
> `IC/IN/CN/MO/MD['key']`-Zugriff gegen die Map, in der er nachschlaegt. Die
> Maps sind einfache Top-Level-Konstanten, das kostet also nichts und faengt
> die ganze Fehlerklasse, bevor sie ein Geraet erreicht.
>
> **Lehre:** ein `!` auf einem Map-Zugriff im Widget-Baum ist ein
> App-Killer, kein lokaler Fehler — der Fehler nimmt den kompletten Teilbaum
> mit. Fuer Icons lieber einen Fallback als `!`.

> **M114 — Der Bogen-Slot hat endlich Konstruktionsgeometrie. Und zwar
> LINIEN, nicht den Mittenbogen, an dem ich in M92 haengengeblieben bin.**
>
> Damals hiess es hier "keine saubere Loesung": ein Bogen hat fuenf Parameter
> (Mitte, Radius, zwei Winkel), und ihn mit `concentric` plus beiden
> Endpunkten festzunageln sind SECHS Gleichungen vom Rang FUENF — genau die
> ueberzaehlige Zeile, die laut den Notizen des linearen Slots die
> Normalgleichungen singulaer macht, libslvs die Skizze fuer inkonsistent
> erklaeren laesst und das Ziehen flackern liess. Weniger festnageln laesst ihn
> ausbeulen.
>
> **Die Loesung war, die Form zu wechseln:** zwei Konstruktions-LINIEN vom
> Sweep-Mittelpunkt zu den beiden Kappenmittelpunkten. Vier Parameter je Linie,
> je zwei Koinzidenzen — voll bestimmt, kein ueberzaehliger Rang, die sechs
> Freiheitsgrade des Slots bleiben unberuehrt. Praktisch sind sie sogar besser
> als ein Mittenbogen: man bekommt den Sweep-Mittelpunkt und die beiden Radien
> zum Bemassen, und genau danach greift man beim Bogen-Slot.
>
> (Punkt 0 eines Bogens ist sein Mittelpunkt, also sind beide Enden gewoehnliche
> Punkt-Koinzidenzen — nichts Neues im Solver noetig.)

> **M113 — End of Part zaehlt jetzt ZEILEN. Damit ist das "springt ueber die
> Skizze" an der Wurzel weg.**
>
> Vier Anlaeufe (M96, M99, M100, M103) haben versucht, das in der
> Zeilen-Arithmetik des Browsers zu reparieren. Der Fehler lag im MODELL:
> `eopAfter` zaehlte **Features**, eine Skizze hatte also gar keinen Slot, und
> keine Umrechnung kann eine Position erzeugen, die es nicht gibt. Inventor
> rollt Skizzen ebenfalls zurueck. Jetzt zaehlt `eopAfter`
> **Zeitstrahl-Knoten**: Slot == Zeile, die Marke kann ueber einer Skizze
> stehen, und die gesamte Umrechnung ist ersatzlos entfallen — in beiden
> Browsern.
>
> `applyEndOfPart` laeuft ueber `partTimeline`: Features darunter →
> `rolledBack`, Skizzen darunter → neues abgeleitetes `ChildSketch.rolledBack`
> (nicht persistiert), das Payload und beide Painter wie unsichtbar behandeln.
> Eine KONSUMIERTE Skizze hat keine eigene Zeile und folgt darum ihrem Feature.
>
> **Migration.** Alte Dokumente speichern unter `eop` eine FEATURE-Zahl. Die
> wird beim Laden umgerechnet (Zeitstrahl ablaufen, bis so viele Features
> passiert sind), geschrieben wird nur noch `eopNodes`. Im Test festgenagelt:
> eine Datei mit `eop: 1` zeigt nach dem Laden exakt dieselbe Auswahl gebauter
> Features wie vorher.
>
> **Lehre, dritte Wiederholung derselben Sorte:** wenn eine Koordinaten-
> umrechnung viermal nicht stimmt, ist meist nicht die Umrechnung falsch,
> sondern es gibt die Zielposition im Modell gar nicht.

> **M111/M112 — STEP-Import als Koerper, ein Import-Knopf, und der
> DXF-Export ist nicht mehr gefaehrlich.**
>
> **STEP-Import.** `occt_split_solids` (neu im Shim) + `importStepSolids`
> zerlegen die Datei in SOLIDS; `AppState.importStepIntoPart` legt daraus je
> einen Koerper an. Die Features tragen `imported = true`, und der
> Feature-Recompute laesst sie in Ruhe: sie werden aus NICHTS berechnet, ein
> Neuaufbau aus nicht existierenden Eingaben wuerde die eben importierte
> Geometrie loeschen. Die STEP-Datei wandert nach `<part>_imports/` und wird
> beim OEFFNEN des Parts neu gelesen (M112) — der B-Rep wird bewusst NICHT
> serialisiert, die Datei ist die Quelle der Wahrheit. Pro Datei einmal
> gelesen und der Reihe nach verteilt: eine STEP mit vier Solids wird zu vier
> Features, und viermal zu lesen waere langsam und ein Leck, weil jeder Lesevorgang
> alle vier liefert. Fehlt die Datei, sagt das Feature es (`computeError`)
> statt still leer zu bleiben.
>
> **Ein Import-Eintrag** in BEIDEN Ribbons (Skizze und Part), nativer Picker,
> Endung entscheidet: STEP → Koerper, DXF → Skizzengeometrie. Den Nutzer den
> passenden Menuepunkt fuer die Datei suchen zu lassen, die er ohnehin gleich
> auswaehlt, waere Zeremonie.
>
> **DXF-Export: der Produktionsblocker ist weg.** Bisher wurde die
> STORAGE-Datei durchgereicht — und Konstruktions-/Mittellinien sind nur wegen
> eines Dart-seitigen Stil-Tags im SIDECAR Konstruktion; im DXF selbst steht
> davon nichts. Wer daraus fertigt, fraest die Hilfslinien mit. Jetzt wird eine
> **Export-Kopie** geschrieben, in der Konstruktionsgeometrie auf dem Layer
> **`Defpoints`** liegt — die seit AutoCAD ueberall verstandene Konvention fuer
> "sichtbar, aber nie geplottet". Die Geometrie bleibt vorhanden (sichtbar,
> fangbar, re-importierbar), sie kann nur nicht mehr mit dem Teil verwechselt
> werden. Enthaelt eine Skizze gar keine Konstruktionsgeometrie, wird
> unveraendert die Originaldatei verschickt.
>
> **Offen:** Splines/Zahnraeder gehen weiter als Polylinien raus (verlustig,
> nicht falsch) — echte SPLINE-Entities waeren der naechste Schritt.

> **M109 (KORRIGIERT) — STEP-Export gab es LAENGST. Mein Zusatz war ein
> Duplikat und hat den Shim zerschossen.**
>
> Ich habe `occt_step_write`/`occt_step_read` in den Shim geschrieben, ohne
> vorher nachzusehen: `occt_export_step` und `occt_import_step` existieren seit
> Langem, mit FFI-Bindung und Menue-Anbindung (Galerie-Karte → Share/Export,
> Part → STEP, Skizze → DXF, `home_view._sendFile`). Schlimmer: mein Block
> landete zwischen `extern "C"` und der folgenden Funktion, also war die
> Uebersetzungseinheit kaputt. Beides ist zurueckgenommen, Shim wieder v11.
>
> **Lehre, teuer bezahlt:** erst das vorhandene C-API lesen, dann etwas
> hinzufuegen. Der Header ist kurz genug, das kostet eine Minute.
>
> **M110 — was WIRKLICH fehlte: `occt_split_solids`.** `occt_import_step`
> liefert `OneShape()`, bei einer Baugruppe also ein Compound. Die Einheit des
> Browsers ist aber ein KOERPER — eine importierte Baugruppe soll als mehrere
> Bodies ankommen, die man einzeln ausblenden, umbenennen und boolschen kann,
> genau wie die selbst gebauten. Neu daher `occt_split_solids(shape, out, max)`
> (Explorer ueber `TopAbs_SOLID`) plus `OcctFfi.importStepSolids(path)`, das
> beides verbindet und bei einer Datei ohne Solids eine leere Liste liefert,
> damit der Aufrufer etwas Ehrliches sagen kann statt einen leeren Body
> anzulegen.


> **M108 — Der native Browser schwebt, ist dichter und dunkel.**
>
> **Schwebend.** Er belegt keine eigene Spalte mehr; der Viewport laeuft in
> voller Breite darunter und der Browser liegt als Panel darueber
> (`Stack` in `main.dart`), 10 pt eingerueckt, 18 pt Eckenradius. Damit hat das
> Glas ueberhaupt erst etwas zu brechen — vorher stand hinter ihm nur die
> Fensterfarbe. Auf Nicht-iOS bleibt es eine Spalte: ein deckender Flutter-Baum,
> der ueber dem Modell schwebt, wuerde es nur verdecken.
>
> **Textfarbe.** Der eigentliche Grund fuer das ausgewaschene Grau mit fast
> schwarzer Schrift: das Glas loeste HELL auf, und UIKit waehlt dann dunkle
> Label-Farben. `overrideUserInterfaceStyle = .dark` auf dem Container laesst
> das Material dunkel rendern und `.label` hell werden — dieselbe Entscheidung,
> die jede App mit dunkler Chrome trifft. Ausgegraute Zeilen gehen auf
> `.secondaryLabel` statt `.tertiaryLabel`, das war auf Glas zu blass.
>
> **Dichter.** Schrift 11.5 statt 13, Symbole 11 pt mit fester 16-pt-Box,
> Einrueckung 11 statt 14, Zeilenraender 3/4 pt. Ein Feature-Baum will Dichte,
> keine Settings-App-Abstaende. Panelbreite 264 statt 300.
>
> **Offen:** ob die Brechung jetzt sichtbar wird — das war die eigentliche
> Frage aus M106 und sie laesst sich erst mit dem Modell dahinter beantworten.

> **M107 — Der Model Browser ist jetzt 100% natives Apple-UI auf Liquid Glass.**
>
> `UICollectionView` mit List-Konfiguration auf `UIGlassEffect`. UIKit macht
> ALLES: Zeilen, Einrueckung, Disclosure, die Augen-Schalter, die
> Kontextmenues und den End-of-Part-Zug. Dart schickt ein flaches Zeilenmodell
> (`GlassRow`) und bekommt Ereignisse zurueck — es zeichnet und trefferprueft
> in diesem Panel nichts mehr.
>
> **Warum nativ hier wirklich besser ist, nicht nur huebscher:** jeder harte
> Fehler dieses Panels sass an der Flutter/UIKit-Grenze. M48 — eine
> Plattform-View schluckte Taps, bis sie in `IgnorePointer` lag. M102 — eine
> `UIContextMenuInteraction` ueber der EOP-Zeile kassierte den Flutter-Zug, und
> es hat VIER Meilensteine gedauert, das zu finden, weil UIKits
> Long-Press-Recognizer die Beruehrung nach ~150 ms wegnimmt. Innerhalb von
> UIKit gibt es diese Grenze nicht: das Kontextmenue der Zelle und der
> Pan-Recognizer verhandeln in EINEM Gestensystem. Genau deshalb duerfen Zug
> und Menue auf derselben Zeile endlich nebeneinander existieren.
>
> **Die Regeln bleiben in Dart.** Zeitstrahl-Reihenfolge, Pinning der geteilten
> Skizze, was als zurueckgerollt gilt, wie viele ZEILEN einem Slot entsprechen —
> das alles rechnet `native_browser.dart`; die native Seite meldet beim Ziehen
> nur die zurueckgelegte Strecke in Zeilen. Damit liegt die Fachlogik weiter an
> einer Stelle und Swift bleibt ein schneller, dummer Renderer.
>
> **Fallback bleibt:** auf Nicht-iOS (und im Host-Test) laeuft unveraendert der
> Flutter-Baum aus `model_browser.dart`. Nichts daran wurde entfernt, der Umbau
> ist also in einem Commit ruecknehmbar.
>
> **Neu:** `packages/native_menu/ios/Classes/GlassBrowser.swift`,
> `packages/native_menu/lib/glass_browser.dart`,
> `lib/widgets/native_browser.dart` (Zeilenmodell),
> `lib/widgets/native_browser_host.dart` (Ereignis-Routing), `main.dart`.
>
> **Verifikationsstand — ehrlich:** `dart-checks` gruen (624), das Swift
> kompiliert erst in `m5-flutter-ipa`, und **wie es sich anfuehlt, weiss nur das
> Geraet**. Zu pruefen, in dieser Reihenfolge: (1) kommt die Liste ueberhaupt
> hoch und bricht das Glas den Viewport, (2) SF-Symbole statt der eigenen
> SVG-Icons — bewusst so, weil "natives Apple-UI" das heisst, aber es sieht
> anders aus als bisher, (3) der EOP-Zug, (4) Hybrid-Composition-Kosten neben
> der RealityKit-Surface. **Noch nicht drin:** Umbenennen-Dialoge sind weiter
> Flutter-`AlertDialog`s, und die Skizzen-Auswahl im Baum (Highlight der
> Auswahl) ist nur ueber `selected` abgebildet.

> **M106 — Der Model Browser liegt auf ECHTEM Apple Liquid Glass.**
>
> Kein in Flutter gemalter Blur: ein natives `UIVisualEffectView` mit
> **`UIGlassEffect`** (iOS 26) als Plattform-View
> (`prototype/glass_panel`, registriert im native_menu-Plugin). Das ist das
> System-Material selbst — Brechung, Glanzkante und Reaktion auf das, was
> dahinter liegt, kommen von iOS und sind client-seitig nicht nachbaubar.
> Unter iOS 26 faellt die native Seite auf `UIBlurEffect(.systemMaterial)`
> zurueck, damit das Panel lesbar bleibt; auf Nicht-iOS bleibt die bisherige
> Deckfarbe.
>
> **Bewusst nur die FLAECHE, nicht der Inhalt.** Die Zeilen zeichnet weiter
> Flutter, ueber dem Glas. Das ist kein Abkuerzen: der Browser ist der
> interaktionsdichteste Teil der App — EOP-Ziehen, Koerper-Picken,
> Hover-Highlight, Kontextmenues — und JEDER dieser Punkte hat an der
> Flutter/UIKit-Grenze schon Zeit gekostet (M48: eine Plattform-View schluckte
> Taps und musste in `IgnorePointer`; M102: eine `UIContextMenuInteraction`
> kassierte vier Meilensteine lang den EOP-Zug). Den INHALT nativ zu machen
> hiesse, all das in Swift neu zu loesen. Die Glasflaeche nimmt darum
> ausdruecklich keine Beruehrungen (`isUserInteractionEnabled = false` plus
> `IgnorePointer` auf der Dart-Seite).
>
> **Geraete-Sache und ehrlich offen:** ob die Brechung unter Flutter wirklich
> greift. Glas bricht, was in der NATIVEN Ebene darunter liegt; Flutter
> rendert in eine eigene Surface, und ob der 3D-Viewport dort ankommt oder das
> Glas flach wirkt, entscheidet die Hybrid-Composition — das ist am Geraet in
> Minuten zu sehen und blind nicht zu beantworten. Falls es flach aussieht,
> ist der naechste Schritt, die Glas-View ueber die FlutterView zu legen statt
> in den Widget-Baum. Ebenfalls zu pruefen: die Kosten der Hybrid-Composition
> neben der RealityKit-Surface (die App laeuft heute bei 60-80 fps).

> **M105 — Hover fand gekruemmte Flaechen nicht.**
>
> Das Koerper-Hovern benutzte `_pickSolidFace`. Das Ding existiert fuer
> Sketch-on-Face und ueberspringt darum JEDE nicht-planare Flaeche
> (`kFacePlane`-Test). Die runde Flaeche eines Zylinders ist genau das — auf der
> gekruemmten Seite fand das Hovern deshalb gar nichts. Neu `_pickSolidAny`:
> derselbe Dreiecks-Durchlauf mit derselben Blickrichtungs- und Tiefenlogik,
> aber OHNE Planaritaetstest, weil es beim Waehlen eines KOERPERS voellig
> gleichgueltig ist, welche Art Flaeche man beruehrt. Hover und Tap benutzen
> jetzt beide das.
>
> **NOCH OFFEN — EOP ueberspringt Skizzen, und meine Zeilenrechnung ist der
> falsche Ansatz.** Viermal nachgebessert, viermal daneben. Der Grund ist
> struktureller: `eopAfter` zaehlt **Features**, eine Skizze hat also gar keinen
> Slot, und keine Umrechnung von Zeilen aendert daran etwas — die Marke KANN
> nicht ueber einer Skizze stehen. Inventor kann das, weil dort auch Skizzen
> zurueckgerollt werden.
>
> **Der richtige Umbau (naechste Runde, nicht blind zwischendurch):**
> `eopAfter` zaehlt **Zeitstrahl-KNOTEN** statt Features. `applyEndOfPart`
> laeuft `partTimeline` durch und setzt ab dem Schnitt: Feature →
> `rolledBack = true` (wie heute), Skizze → neues abgeleitetes
> `ChildSketch.rolledBack`, das Payload und Painter wie unsichtbar behandeln.
> `partBuildOrder(p).length` als Klemmgrenze wird `partTimeline(p).length`. Die
> Zeilenabbildung im Browser entfaellt damit komplett, weil Slot == Zeile ist —
> und genau das ist der Grund, es so zu machen: die ganze Fehlerklasse
> verschwindet, statt noch einmal umgerechnet zu werden.

> **M104 — Das Flackern war eine Rueckkopplung, die ich in M100 selbst gebaut
> habe. Die Hysterese aus M102/M103 hat nur das Symptom behandelt und es dann
> verschlimmert.**
>
> Der Kreis: Hovern baut die boolesche Vorschau und setzt `previewReplacesBody`
> → `visibleSolids` **versteckt genau diesen Koerper** und zeichnet an seiner
> Stelle die Vorschau → das naechste Hover-Sample trifft also die
> VORSCHAU-Mesh → die gehoert dem Wegwerf-Feature der Session und steht in
> keinem `p.features` → `_bodyNameOf` gab **null** → Miss-Zaehler → Hover
> geloescht → Vorschau zurueck → echter Koerper wieder da → getroffen →
> umgeschaltet → von vorn. Das repaintet endlos, deshalb half auch Stillhalten
> irgendwann nicht mehr.
>
> **Fix an der Wurzel:** die Vorschau STEHT FUER diesen Koerper, also ist sie
> zu hovern dasselbe wie ihn zu hovern. `_bodyNameOf` bildet sie auf
> `previewReplacesBody` ab. Damit ist der Kreis zu.
>
> **Und die Zwei-Sample-Bestaetigung aus M103 ist wieder RAUS.** Sie verlangte
> fuer einen echten Wechsel ein zweites Sample, das eine langsame Hand nie
> liefert — genau deshalb wurde die Hervorhebung schlechter statt besser. Nur
> der Miss-Zaehler bleibt, damit eine Fuge zwischen Facetten das Highlight
> nicht kurz ausknipst.
>
> **EOP ueberspringt weiter Skizzen:** die Marke belegt SELBST eine Zeile, und
> zwar an dem Slot, von dem aus gezogen wird — alles darunter rutscht um eine
> Zeile, was die erste Fassung ignorierte. Ebenso die verschachtelte
> Skizzenzeile unter einem AUFGEKLAPPTEN Feature. Beides ist jetzt in der
> Zeilenabbildung drin.
>
> **Lehre (dritte Runde derselben Sorte):** erst fragen, WARUM ein Sample
> falsch ist, statt es zu daempfen. Zwei Meilensteine Hysterese haben den
> eigentlichen Kreis nur verdeckt.

> **M103 — Flackern, Klick-Auswahl und das Ueberspringen von Skizzen.**
>
> **(1) Flackern beim Mausbewegen.** M102 daempfte nur den Weg nach NULL. Ein
> Streifen ueber die Naht zwischen zwei Koerpern wechselte weiterhin beim
> ERSTEN Sample des Nachbarn — und jeder Wechsel rechnet die boolesche
> Vorschau neu. Genau das flackerte. Ein neuer Koerper muss jetzt **zweimal in
> Folge** gesehen werden, bevor umgeschaltet wird; stillhalten war deshalb
> schon vorher stabil.
>
> **(2) Klicken in 3D waehlte den falschen Koerper.** Der Tap hat frisch
> gepickt statt den GEZEIGTEN zu nehmen — an einer Naht landete der frische
> Pick auf dem Nachbarn, man klickte den hervorgehobenen Koerper und bekam den
> anderen. Der Tap nimmt jetzt `app.hoverBody`: was man sieht, ist was man
> bekommt. Fallback auf einen frischen Pick nur, wenn gar nichts hervorgehoben
> ist.
>
> **(3) EOP sprang ueber Skizzen.** Die Marke zaehlt in FEATURES, der Browser
> zeigt aber Skizzen dazwischen — ein rein in Features gemessener Zug lies sie
> eine Skizzenzeile in einem Satz ueberspringen. Der Weg wird jetzt durch das
> echte Zeilen-Layout umgerechnet (`_eopRowIndexPerSlot`): Skizzenzeilen haben
> keinen eigenen Slot, die Marke rastet auf dem naeheren Nachbarn ein und
> bleibt unter dem Finger.

> **M102 — EOP: die WIRKLICHE Ursache. Es war nie die Gesten-Arena.**
>
> Das Log sagt es seit drei Runden dasselbe: `DOWN` … rund 150 ms … `CANCEL`,
> nie ein `MOVE`. 150 ms ist kein Scroll — das ist ein **Long-Press**. Und ich
> hatte die EOP-Zeile in M91 selbst als **nativen Menue-Target** registriert:
> eine UIKit-`UIContextMenuInteraction` liegt ueber jedem registrierten Rect,
> und ihr Long-Press-Recognizer **kassiert die Flutter-Beruehrung**, sobald er
> anspringt. UIKit nahm den Finger weg, bevor Flutter einen Zug sehen konnte.
> Dass Rechtsklick und natives Menue funktionierten, war kein Zufall, sondern
> derselbe Mechanismus von der anderen Seite: genau die Interaktion, die den
> Zug stahl, war die, die noch ging.
>
> Meine ersten drei Erklaerungen waren alle falsch (Slot-Mathematik, dann
> GestureDetector-Arena, dann ListView-Physics) — jedes Mal habe ich ueber den
> Code nachgedacht, statt zu lesen, was das Log sagt. Die Zeile ist jetzt KEIN
> nativer Target mehr; ihr Menue kommt ueber den Flutter-Long-Press-Fallback,
> der nicht um den Pointer konkurriert.
>
> **Merke fuer die naechste native Flaeche:** ein Rect, das im Menue-Payload
> steht, kann in Flutter nicht mehr gezogen werden. Ziehbare Zeilen und
> UIKit-Kontextmenues schliessen sich aus.
>
> **Hover klebt jetzt.** `_pickSolidFace` liefert die vorderste Flaeche; wo
> sich zwei Koerper beruehren, kippte das bei Sub-Pixel-Bewegung hin und her
> ("springt herum"). Der gehoverte Koerper wechselt nur noch, wenn der Zeiger
> wirklich ueber einem ANDEREN steht; ein kurzer Fehlschlag (Fuge zwischen
> Facetten, eine Kante) haelt den bisherigen, und erst drei Treffer ins Leere
> loeschen ihn.
>
> **NOCH OFFEN:** der Nutzer meldet, die Vorschau stimme beim Wechsel nicht
> immer, sei aber nach dem Oeffnen der Extrusion korrekt — klingt danach, dass
> `_updateExtrudePreview` beim Hover-Wechsel zwar rechnet, die 3D-Szene aber
> nicht neu gepusht wird (die Szenensignatur kennt `preview` nur ueber
> `identityHashCode`, und ein neu gebautes Preview-Solid mit gleicher Identitaet
> waere unsichtbar). Als Erstes dort nachsehen.

> **M101 — Die beiden hartnaeckigen Fehler, diesmal an der Wurzel.**
>
> **(1) Vorschau ignorierte den gewaehlten Zielkoerper.** `_extrudeBooleanTarget`
> ging fuer ein NEUES Feature direkt auf `lastSolidFeature` — den zuletzt
> gebauten Koerper — und schaute `s.bodyName` nie an. Picken setzte den Namen
> also korrekt und der COMMIT benutzte ihn auch (im Log: "extrude created
> Extrusion3 (Solid1)"), aber die Vorschau kombinierte weiter gegen Solid2.
> Genau der Bericht: "zeigt immer die Vorschau von Solid2 + Extrusion, auch
> nachdem ich Solid1 gewaehlt habe". Das Dropdown hat das nie aufgedeckt, weil
> dort ohnehin meist der letzte Koerper stand — erst das Picken macht es
> sichtbar.
>
> **Das erklaert auch "Hover in 3D macht nichts".** Seit M100 ist der Hover
> KEIN Tint mehr, sondern die neu gerechnete Vorschau gegen den gehoverten
> Koerper — und genau die war fest auf Solid2 verdrahtet. Im Browser tintet die
> Zeile zusaetzlich, deshalb sah es dort aus, als wuerde etwas passieren, und
> in 3D nicht. EIN Fehler, zwei Symptome.
>
> **(2) EOP: Listener reicht NICHT.** Das Log sagt es woertlich: `eop DOWN` …
> `eop CANCEL`, nie ein MOVE. Ein Listener nimmt zwar nicht an der Gesten-Arena
> teil, ist ihr aber nicht entzogen: sobald das Scrollable den Pointer
> BEANSPRUCHT, schickt Flutter allen darunter ein pointer-cancel und die
> Events hoeren auf. Rohe Pointer allein waren also nicht genug. Die Liste
> wird jetzt fuer die Dauer des Zugs auf `NeverScrollableScrollPhysics`
> gestellt — kein Konkurrent, kein Cancel, der Pointer bleibt von DOWN bis UP
> bei uns. Zusaetzlich: `_kRowH` von geratenen 26 auf **32** korrigiert (am
> Geraete-Screenshot gemessen, die Zeilen stehen 32 px auseinander — mit 26
> waere die Marke im falschen Tempo gewandert), und ein Cancel mitten im Zug
> committet jetzt, statt still zu verwerfen.
>
> **Neu/berührt:** `app_state.dart` (`_extrudeBooleanTarget`),
> `widgets/model_browser.dart` (ListView-Physics, Zeilenhoehe, Cancel).

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

---

## M210–M219 — Die Performance-Messinfrastruktur (NUR Analyse, nichts optimiert)

**Branch:** `claude/perf-deep-analysis` · **Stand:** M224, auf main (M231)
zusammengefuehrt · analyze 0 Fehler, **2050 Dart-Tests**, **45 Python-Tests**
**Volle Details:** `PERFORMANCE_PROFILE.md` — was jeder Teil der App kostet,
mit Methode, Konfidenzintervallen und dem vollstaendigen Datenanhang.
`PERF_ANALYSIS.md` (Abschnitte 8–15) ist die chronologische Herleitung.
Der urspruengliche Messplan `PERF_PLAN.md` ist zurueckgezogen — die Messungen
haben ihn ueberholt; was von ihm noch gilt, steht in PERFORMANCE_PROFILE 15.5.
Dieser Eintrag ist der Einstiegspunkt.

> **WENN DU HIER BIST, UM ZU OPTIMIEREN: LIES ZUERST `OPTIMIZATION_PLAN.md`.**
> Die Messphase ist abgeschlossen. Die Arbeit ist auf **fuenf parallele
> Sessions** aufgeteilt, mit **verbindlicher Dateizustaendigkeit**. Dort steht,
> welche Befunde dir gehoeren, welche Dateien du anfassen darfst — und vor
> allem, wie du die Arbeit der anderen vier nicht zerstoerst. **Kein
> Force-Push, keine fremden Dateien, `perf/baseline.json` und
> `PERFORMANCE_PROFILE.md` fasst niemand an.**

> **DER DATENSATZ IST VOLLSTAENDIG (18.08.2026).** Der gepaarte Geraetelauf
> auf Build `230f179` liegt vor: **zwei Aufnahmen, eine Sitzung, Low Power
> Mode als kontrollierte Variable** — und zum ersten Mal **alle drei
> Suite-Stufen inklusive Stress** auf echter Hardware. Es gibt keine offene
> Messluecke mehr, die vor dem Optimieren geschlossen werden muesste.
> Einstieg: `PERFORMANCE_PROFILE.md` Abschnitt 4 (Rangliste) und 15 (was
> beantwortet ist, was offen bleibt).

### Die stehende Regel

Der Auftrag war ausdruecklich: *„Don't optimize anything, only analyse."*
Daran wurde sich gehalten — **am Verhalten der App ist nichts geaendert**.
Alles unten ist Messtechnik. Die Reparaturen sind noch zu machen und stehen
unter „Rangliste".

### Was gebaut wurde

**Die Selbstfahr-Suite** — die App misst sich selbst mit festen Eingaben, ohne
dass jemand tippt. Ausgeloest vom Bug-Button, ein JSON pro Lauf:

| Datei | Inhalt |
| --- | --- |
| `perf_scenarios.dart` | Kern: Solver, DOF-Analyse, Zahnraeder, Fixtures (`sketchFixture`, `constraintFixture`), Runner |
| `perf_scenarios_tools.dart` | JEDES Zeichenwerkzeug (generisch aus `toolMeta`), Modify, 2D-Fillet, Constraint-Inferenz, alle 12 Constraint-Typen, Freihand |
| `perf_scenarios_kernel.dart` | Jede OCCT-Operation, gegen die richtige Achse gesweept |
| `perf_scenarios_ui.dart` | Malen (phasenweise), Zug, Snap — durch den ECHTEN Painter |
| `perf_scenarios_app.dart` | Muster, Projektion, Szenen-Payload, Undo, 3D-Picken, Feature-Rebuild |
| `perf_scenarios_ramp.dart` | **Rampen**: feine Schritte statt drei Punkte, mit LOKALEM Exponent pro Schritt |
| `perf_scenarios_quality.dart` | Rauschgrenze, Speicher pro Entity/Solid, Frame-Budget-Grenzen, Cache-Wirksamkeit |
| `perf_scenarios_stress.dart` | **Opt-in** (`stress` in die Beschreibung tippen): Leitern bis zur Wand |

**Native Sonden** — was Dart nicht sehen kann:

* `packages/native_menu/ios/Classes/PerfProbe.swift` — Thermalzustand,
  `phys_footprint` (iOS killt darauf, nicht auf RSS), Restspeicher,
  CPU pro Thread. Gezogen vor UND nach der Suite.
* `packages/reality_view/ios/Classes/RvPerf.swift` — die Zeit JENSEITS der
  Platform-View-Grenze, phasenweise. Dart ZIEHT die Tabelle (`perfDrain`).

**Auswertung** — `ci/perf_report.py <bundle.zip>`:
1. Ist der Lauf vertrauenswuerdig (Thermik, Energiesparmodus, tote Sonden)
2. Wie weit geht es (Stress-Leitern)
3. Kostenkurven mit gefittetem n^k
4. Wo die Zeit hinging — Suite und echte Sitzung getrennt
5. `--baseline <alt.zip>` fuer den Diff

**Neu instrumentiert** (vorher unsichtbar): `sketch.analyze`, `2d.snap`,
`part.rebuildAll`, `part.rebuild.passes`, `kernel.feature.<kind>`,
`solve.slvs`, `solve.lm`, `solve.path.*`, `solve.slvs.rejected.*`.

### Rangliste der Befunde — das ist die To-do-Liste

> **Aktualisiert nach dem gepaarten Geraetelauf vom 18.08.2026 (M223).** Die
> Reihenfolge hat sich geaendert: **`analyzeSketch` steht jetzt vor
> `allEdges`**, weil es kubisch ist (k = 3.198) und bei jedem Rebuild laeuft.
> Punkt 5 unten ist ausserdem korrigiert — die Ursprungsebenen kosten 419 ms
> beim ERSTEN Aufbau, danach 2.4 ms. Details in `PERFORMANCE_PROFILE.md` §4.

**0. `analyzeSketch` ist KUBISCH — der schwerste Befund der App.**
k = 3.198 [2.835, 3.561], R² = 0.9962, unabhaengig unter Low Power Mode
k = 3.071. **8 837 ms bei 1024 Entities**, +105 MB RSS. Der Mechanismus steht
im Quelltext: `solver.dart:2517` reduziert eine dichte `m × total`-Matrix per
Gauss-Elimination auf RREF — O(m·total·rank). Die Algebra schliesst exakt
(3584 Parameter, 2562 Residuen, dof = 1022 = gemessene Gauge), und der
vorhergesagte Speicher (102.8 MB) trifft den gemessenen (105 MB) auf 2.2 %.
Laeuft bei jedem Rebuild, jedem Solve, jedem Tab-Wechsel
(`app_state.dart:2454`, `:2474`, `:8826`). Bei 1024 Entities kostet die
Analyse **221x** so viel wie der Solve, den sie begleitet.

**1. `occt_shape_edge_info` ist O(n²).** Zweifach belegt: im Quelltext
(`backend/occt/shim/occt_capi.cpp:1679` und `:1733` — ZWEI vollstaendige
Topologie-Durchlaeufe pro Aufruf, danach weggeworfen) und in der Messung (EIN
`edgeInfo` = 3.014 ms erklaert 92.7 % der 1171 ms fuer 360 Kanten; die
Kontrollen `counts()`/`bbox()` auf demselben Solid kosten 0.2 ms).
Hochgerechnet ~48 s auf dem Teil, das abgestuerzt ist.
**Reparatur gehoert in den Shim** — ein Durchlauf, der ein Array fuellt, als
Bulk-Einstiegspunkt. Dart-seitiges Batching wuerde nur die Grenzuebergaenge
sparen (7 %) und die Quadratik unberuehrt lassen.

**2. Der Solver faellt vom schnellen Pfad — Faktor 334.** Normaler Zug
0.277 ms pro Solve, davon 81 % in libslvs. Ueberbestimmt: 92.5 ms, davon
0.4 % in libslvs. Mechanismus in `solver.dart:2172`: libslvs rechnet, Dart
verifiziert gegen die eigenen Residuen, verwirft bei Residuum > 1e-4, und dann
laeuft der Dart-LM — beim Ziehen zweimal (`lm-frozen`, dann `lm-relaxed`), je
80 Iterationen ueber ein 168-Parameter-System. Bei zwei Solves pro Frame sind
das ~185 ms/Frame ≈ 5 fps. Erklaert auch die 3.92-s-Spitze aus der ersten
Sitzung: `solve.total` Schlechtestwert 178.7 ms bei p50 0.275 ms, waehrend
`ffi.slvs.solve` bei 4.1 ms bleibt.

**3. Der Painter loest ZWEIMAL pro Frame.** `viewport.dart:2088` (Segment
`ent.dofColour`) und `:2683` (Segment `constraints`) rufen beide
`displayGeometry`. 60 gemalte Frames → 120 Solves. Zusammen 87 % der Malzeit
im Zug; das eigentliche Zeichnen ist 12.5 %.

**4. → nach oben verschoben, siehe Punkt 0.** (Die alte Schaetzung n^2.33 kam
aus der Rampe, die bei 256 Entities endete. Die Stress-Leiter bis 1024 hat
sie als kubisch entlarvt.)

**4b. Gemustertes Fillet: 142.9 ms PRO Vorkommen — jetzt gemessen.**
`applyBlendOccurrence` (`part_model.dart:6179`) ruft `edgesOf` → `allEdges`
je Vorkommen. `app.blendPattern.edgeQuery`: k = 0.999, R² = 1.0000, exakt
linear in der Vorkommenszahl. **97.6 % der Kosten eines gemusterten Fillets
sind die Kantenaufzaehlung**, nur 2.4 % die Bool'sche Faltung. Acht Vorkommen
auf einem 180-Kanten-Koerper = 1.14 s.

**5. RealityKit: die Ursprungsebenen — aber nur beim ERSTEN Mal.**
Der teuerste Szenen-Push der Sitzung: **419.67 ms, davon 419.47 ms (99.95 %)
Ursprungsebenen**. Im eingeschwungenen Zustand danach: **2.4 ms**. Faktor 177.
Der Mesh-Upload ist in beiden Faellen praktisch kostenlos. Die alte Zahl
(55.44 ms) war eine Einzelbeobachtung und um eine Groessenordnung zu klein.

**5b. Der 3D-Push-Pfad ist NICHT teuer — fruehere Lesart korrigiert.**
`3d.push` kostet **0.0973 ms** im Mittel ueber 1 699 Pushes (165 ms in einer
293-s-Sitzung). Die 8.8 ms, die `rv.setCamera` meldet, sind
**Warteschlangen-Latenz** einer asynchronen Kanalantwort (p50 1.58 ms,
skaliert 5.4x wenn die Uhr nur 1.93x langsamer wird) — ein SYMPTOM der
blockierenden FFI aus Punkt 1, kein eigener Kostenposten.

**6. Fillet:** die Kandidatensuche (`allEdges`) kostet bei EINER Kante 4.9x das
Verrunden. Und der Radius zaehlt massiv: r=1.0 ≈ 10 ms, r=4.0 ≈ 664 ms auf
demselben Solid — Faktor 66.

**Mit Zahlen entlastet:** Zahnradgenerierung (linear, Cache traegt), Snapping
(0.0044 ms/Event, 5x billiger als Picken), DOF-Faerbung, Booleans,
Tessellierung, `allGeometry`, Ribbon-Rebuilds, Start (76 ms), 3D-Picken,
Projektion, Szenen-Payload, Dokument-Codec.

### M220 — nach der Zusammenfuehrung mit main (PERF_ANALYSIS Abschnitt 15)

main brachte M209-M213 mit, darunter die Partmuster und die Flaechen-Provenienz
— Pfade, fuer die es keine einzige Messung gab. Vier Quelltextbefunde kommen
in die Rangliste, einer davon schaerft Befund 1:

**1 (praezisiert). `occt_shape_edge_info` macht VIER Ganzform-Operationen pro
Aufruf, nicht zwei.** Zusaetzlich zu den beiden `TopExp::MapShapes*`: eine
Bounding Box der ganzen Form (`:1832`) und ein `BRepClass3d_SolidClassifier`
ueber die ganze Form (`:1836`). Beide stehen im Konvexitaetszweig, der nur bei
Kanten mit **genau zwei** Nachbarflaechen laeuft — auf einem geschlossenen
Solid also bei der Mehrheit. **Folge fuer die Reparatur:** der
Bulk-Einstiegspunkt muss alle vier aus der Schleife heben. Wer nur die zwei
Karten hebt, laesst den Klassifizierer pro Kante stehen und die Quadratik
bleibt.

**7. `newSurfacesOf` ist quadratisch in der Flaechenzahl** —
`base.any(...)` in einer Schleife ueber `result` (`part_model.dart:3701`), pro
koerpermodifizierendem Feature bei **jedem Rebuild** (`:6990`), mit
`faceSurfaces` gleich zweimal daneben. Steckt heute unaufgetrennt in
`part.rebuildAll`.

**8. `attributeFaces` ist ein dreifaches Produkt** — Flaechen x Features x
Flaechen-je-Feature, mit `sameSurfaceAs` im Innersten
(`part_model.dart:3721`). Haengt am Flaechenpicken (`app_state.dart:4859`),
gecacht pro Mesh-Identitaet.

**9. `faceSurfaces` laeuft ein zweites Mal fuer eine Log-Zeile**
(`app_state.dart:4864`) — direkt nachdem `attributeFaces` dieselbe Zerlegung
intern berechnet hat, nur um eine Anzahl in einen Text zu schreiben. Dieselbe
Art wie Befund 3, aber hinter dem Cache und damit milder.

**Neu gemessen, damit der naechste Geraetelauf das alles beantwortet:** zehn
Szenariofamilien, 26 Einzelmessungen, alle im automatischen Tier (kein `stress`
noetig), dazu zwoelf Abdeckungstests:

* `kernel.query.edgeInfoScale.{24,60,120,240}` — EIN `edgeInfo` auf Kante 1,
  auf wachsender Form. Macht den O(n)-pro-Aufruf **von aussen falsifizierbar**:
  steigt die Kurve, ist Befund 1 doppelt belegt; bleibt sie flach, ist der
  Quelltextbefund falsch.
* `kernel.mirror.{24,120}` — das neue `occt_mirror`, gegen `transform` auf
  DEMSELBEN Solid. Die Differenz ist der Preis der Spiegelung.
* `app.provenance.{faceSurfaces,newSurfaces,attribute}.*` — Rebuild-Pfad und
  Pick-Pfad getrennt, weil es verschiedene Budgets sind.
* `app.pattern.occurrences.*` — **alle vier Musterarten**: rechteckig, entlang
  einer Kurve, kreisfoermig, skizzengetrieben (mit `sketchPatternPoints`
  davor, weil die App sie zusammen faehrt) und gespiegelt.

**Noch offen und bewusst nicht auf Verdacht gebaut:** `applyBlendOccurrence`
(gemusterte Fillets) und der Ende-zu-Ende-Rebuild eines echten
PatternFeature. Beide brauchen eine Fixture MIT Kernel; ohne OCCT auf der
Entwicklungsmaschine liesse sich nicht pruefen, ob sie ihr Thema erreichen,
und eine Fixture, die still nichts misst, ist schlimmer als eine fehlende.

### M221–M222a — was seither dazukam (noch ohne Geraetezahlen)

**M221 — der Grund reist im JSON.** `Perf.note(name, text)` traegt kurze
Freitextbefunde in der Suite-eigenen JSON. Vorher ging ein Kernel-Grund ins
Ereignislog, und der Geraetelauf vom 11.8. hat bewiesen, dass dieser Weg nicht
funktionieren KANN: `log.txt` wird beim Druck auf den Bug-Knopf geschrieben
(10:47:45), die Suite laeuft danach (10:48:10). Deshalb steht
`kernel.sweepTwist.fail` seit drei Laeufen ohne Ursache da. Erster Eintrag
gewinnt; `ci/perf_report.py` druckt den Grund unter den Zaehler.

**M221 — die Simulator-Bahn hat einen Zustellweg.** `sim-perf` war seit Lauf
32 gruen und KEINE seiner Zahlen je gelesen, weil Artefakte auf Blob-Storage
liegen, den der Proxy verweigert. Jetzt committet der Workflow seine Aufnahme
auf den Branch `ci-logs-perf`. Ergebnis der ersten Aufnahme: der Simulator ist
KEIN skaliertes Geraet (Streuung Faktor 63 zwischen Operationen, CV 138 %,
gegen 8.3 % beim Energiesparmodus). Es gibt keinen Umrechnungsfaktor. Bahn B
ist damit ein Build- und Verlinkungstest, der nebenbei Zahlen produziert —
keine Performance-Bahn. Siehe PERFORMANCE_PROFILE Abschnitt 13.

**M221a — das Undo-Journal hat eine Groesse.** Es ist unbegrenzt per Design;
gemessen war bisher nur die DAUER eines Checkpoints. Neu
`app.journal.{depth,bytes,bytesPerEntry}`. Zu lesen ist bytesPerEntry.

**M221b — das gemusterte Fillet.** `applyBlendOccurrence` ruft
`kernel.edgesOf` und damit `allEdges` PRO VORKOMMEN auf — die zwei am
schlechtesten skalierenden Verhalten der Codebasis komponieren. Aus gemessenen
Zahlen ausmultipliziert: 9.4 s bei acht Vorkommen auf 360 Kanten. Zwei
Szenarien machen daraus eine Messung statt einer Herleitung.

**M222 — main (M212-M231) zusammengefuehrt.** Und zum ZWEITEN Mal kamen neue
Kerneleinstiege ungemessen an: `occt_delete_faces`, `occt_move_faces`,
`occt_scale_shape`, `occt_export_step_named` (Shim v17 → v20), spaeter noch
`occt_export_step` und `occt_revolve_hits_face`. Zweimal ist ein Muster:
**jede Zusammenfuehrung mit main bringt ungemessene Kerneloperationen mit.**
Die Liste in `m213_perf_coverage_test.dart` ist die Stelle, an der das
auffliegt. Neu gemessen ausserdem `facesOf` (Delete-Face-Pickpfad) und die
Bezier-Kette (Konstruktion und Abflachung getrennt).

**M222a — die Messwerkzeuge pruefen sich selbst.** `ci/perf_report.py` und
`ci/perf_profile.py` entscheiden, was jede Zahl im Profil bedeutet, und hatten
keinen einzigen Test. Jetzt 19 (mit der Schranke aus M224 zusammen 45),
gegen ANALYTISCHE Wahrheit: ein exaktes Potenzgesetz muss seinen
Exponenten exakt zurueckliefern, ein Intervall muss den wahren Wert
enthalten, zwei Punkte duerfen nie ein Intervall liefern.
Laufen in beiden Workflows vor `flutter analyze`.

### M223 — der gepaarte Geraetelauf (18.08.2026, Build `230f179`)

**Der Datensatz ist damit vollstaendig.** Zwei Aufnahmen, **eine durchgehende
App-Sitzung**, 170 s auseinander, Low Power Mode als aufgezeichnete
Behandlung — und zum ersten Mal **alle drei Suite-Stufen auf Hardware**.

| | Aufnahme A | Aufnahme B |
| --- | --- | --- |
| Low Power Mode | **AN** | **AUS** (Referenzarm) |
| Stress-Stufe | ja | ja |
| Sitzungsdauer | 142 428 ms | 292 797 ms (kumulativ, enthaelt A) |

**Wichtig fuer jede Auswertung:** die Suite-JSONs sind unabhaengig und
vergleichbar, der Sitzungs-Snapshot in B ist KUMULATIV und enthaelt A. Nie
differenzieren. (PERFORMANCE_PROFILE §2.2.)

**Was neu ist:**

- **`analyzeSketch` ist kubisch** — siehe Punkt 0 der Rangliste.
- **Die Isolation von `allEdges` ist vollstaendig.** Kontroll-Leiter
  `buildOnly` auf IDENTISCHEN Solids, die sogar MEHR tut (volle
  Tessellierung): **200.3x billiger** bei gleicher Groesse, k = 1.063 gegen
  2.012, Intervalle ohne Ueberlappung. `buildOnly` erreicht die VIERFACHE
  Groesse (1920 Punkte, 5760 Kanten) in 245 ms. Und die Exponenten
  komponieren quantitativ: 0.985 (Kosten pro `edgeInfo`) + 1 = 1.985 gegen
  gemessene 2.012 — 1.3 % Abweichung.
- **`Perf.note` hat beim ersten Einsatz geliefert.** `kernel.sweepTwist` gibt
  null zurueck, weil `occt_sweep_profile: twist is not implemented yet` — drei
  Laeufe offen, kein Defekt. Punkt erledigt.
- **Der Energiesparmodus-Faktor ist 1.9253 [1.8979, 1.9531]** aus 142
  gepaarten Spans (vorher: 4 Punkte, 1.893 — Abweichung 1.7 %). Aufwaermen
  als Alternativerklaerung ausgeschlossen (Steigung ueber die
  Ausfuehrungsreihenfolge: +0.000095, R² = 0.0006).
- **KORREKTUR: der Faktor ist NICHT uniform.** Speichergebundene Arbeit 1.624,
  native FFI 1.910, Dart-Rechnung 2.273 (Welch t = 3.86, p ≈ 0.002). Die
  fruehere Uniformitaetsbehauptung stammte aus vier Punkten. Fuer
  Hochrechnungen auf aeltere Geraete gilt der klassenspezifische Wert.
- **Keine Leiter endete am Speicher.** Spitzen-RSS 850 MB gegen 7374 MB
  physisch. 64 Solids gleichzeitig gehalten: k = 0.984, **0 MB Netto-Delta**
  nach Freigabe — kein Leck.
- **Die 2D-Grenze ist eine Zahl:** Ziehen kostet 10.7 ms/Frame bei 512
  Entities (Referenzarm), 20.4 ms im Energiesparmodus. Gegen ein 16.7-ms-
  Budget heisst das: bei voller Taktrate innerhalb, gedrosselt darueber.

### M224 — der Regressionswaechter

Jede Zahl in PERFORMANCE_PROFILE ist eine Momentaufnahme. Bis M224 hat nichts
eine Regression **erkannt** — die Werkzeuge konnten zwei Bundles vergleichen,
wenn ein Mensch auf beide zeigt, und das ist ein Lesehilfsmittel, keine
Schranke.

```
python3 ci/perf_gate.py --record <bundle.zip>   # Basislinie einfrieren
python3 ci/perf_gate.py <bundle.zip>            # vergleichen; Exit 1 wenn schlechter
```

Die eingecheckte Basislinie ist der **Referenzarm** des gepaarten Laufs:
Build `230f179`, Energiesparmodus AUS, thermisch `nominal` an beiden Enden,
alle drei Runner — 273 Spans, 373 Szenario-Spans, 46 Zaehler, 195 Gauges.

**Die Beweisreihenfolge ist die aus PERFORMANCE_PROFILE 1.1** und kehrt die
Intuition um: **Zaehler zuerst** (exakt, prozessorunabhaengig — jede Aenderung
ist ein Fehlschlag, null Fehlalarme), dann **Gauges** (Fixturegroessen und
Leiterhoehen), erst zuletzt **Dauern** — gegen die vom Lauf selbst gemessene
Rauschgrenze, nicht gegen eine geratene Prozentzahl.

**Zwei Entscheidungen, die die Daten erzwungen haben:**

- **Er VERWEIGERT den Dauervergleich ueber Taktzustaende hinweg.** Der
  Energiesparmodus skaliert die App um 1.9253, und nicht uniform. Ein
  gedrosselter Lauf gegen die ungedrosselte Basislinie meldete sonst ~93 %
  Regression in allem. Zaehler und Gauges werden trotzdem geprueft — genau
  dafuer sind sie die primaere Stufe.
- **Er prueft PRO SZENARIO, nicht nur pro Span.** Nachgemessen, nicht
  angenommen: eine injizierte 40-%-Regression in `ffi.occt.allEdges` in EINEM
  Szenario bewegte den App-weiten Mittelwert dieses Spans um **6.9 %** — unter
  jeder brauchbaren Schwelle, weil derselbe Span auch in Rampen, Fillet-
  Szenarien und im Blend-Muster laeuft. Der Aggregatwert allein haette sie
  durchgelassen.

**Der Nachweis, dass es funktioniert:** gegen den gedrosselten Arm gefahren
meldet die Schranke genau drei Dinge — die gefallene Leiterhoehe
(`stress.allEdges.maxSize` 480 → 240), die daraus folgende Kantenzahl und den
daraus folgenden Zaehler (−1440 `edgeInfo`-Aufrufe) — **und sonst nichts**, auf
einem Lauf, dessen Dauern voellig unbrauchbar waren.

**Die Ausschlussliste ist hergeleitet, nicht geraten.** Die zwei Arme liefen
IDENTISCHE Fixtures auf demselben Build, also kann ein Gauge, der sich zwischen
ihnen unterscheidet, keine Fixturegroesse beschreiben. 125 tun es; ihre
Klassifikation ergibt genau vier Regeln (57 gefittete Exponenten, 48 kumulative
Zaehler, 9 Native-Drain-Worsts, 5 abgeleitete `quality.*`, 4 Dokumentzustaende).

**25 der 45 Python-Tests** decken die Schranke ab, etwa die Haelfte davon
prueft, dass etwas NICHT ausloest: eine Schranke, die bei Rauschen anschlaegt,
wird abgeschaltet und ist dann schlimmer als keine.

### Wie man es benutzt

1. Einen Build **neuer als `6beb184`** sideloaden. Die IPA kommt aus
   `m1-core-build.yml` per `workflow_dispatch` auf diesem Branch — sie laeuft
   NICHT automatisch, weil der Workflow nur auf Pushes nach main hoert.
2. **Das gepaarte Protokoll** (validiert in M223, PERFORMANCE_PROFILE §15.2):
   erst Energiesparmodus AN mit `stress`, dann AUS mit `stress`, in
   DERSELBEN Sitzung, Geraet kuehl, Thermalzustand `nominal`. Der Paarlauf
   liefert den Taktfaktor mit einem 1.4-%-Intervall und schliesst Aufwaermen
   als Erklaerung aus — beides geht mit Einzellaeufen nicht.
3. Vorher **eine Minute lang benutzen**: Teil oeffnen, in 3D umkreisen, Part-
   Tab, Modellbrowser, ein paar Entities zeichnen und eine ziehen, speichern.
   Sonst bleiben die 40 sitzungsabhaengigen Spans leer (PERFORMANCE_PROFILE
   §15.2).
4. Bug-Button, Beschreibung **`stress`**. Dauert Minuten statt Sekunden.
   Stirbt die App dabei, ist DAS die Antwort auf 'wie weit geht es'; das
   Bundle trotzdem schicken.
5. `python3 ci/perf_report.py <bundle.zip>` — oder mit
   `--baseline <alter.zip>` fuer den Diff. Fuer den vollstaendigen Anhang:
   `python3 ci/perf_profile.py <bundle.zip> > appendix.md`.
6. **`python3 ci/perf_gate.py <bundle.zip>`** — die Regressionsschranke gegen
   `perf/baseline.json`. Exit 1 heisst schlechter geworden. Nach einer
   BEABSICHTIGTEN Verbesserung die Basislinie neu aufnehmen
   (`--record`) — aber nie, um einen Fehlschlag stillzulegen, den man nicht
   erklaeren kann.

Ein zweiter Lauf mit Energiesparmodus AN und ohne `stress` verlaengert die
Laengsschnittreihe aus PERFORMANCE_PROFILE Abschnitt 12 unter denselben
Bedingungen wie die bisherigen drei.

**Beim Lesen zuerst pruefen:** `lowPowerMode` und den Thermalzustand. Der Lauf
vom 6.8. abends lief im Energiesparmodus und war dadurch gleichmaessig ~2x
langsamer als der davor — ohne die native Sonde haette der Bericht „alles
doppelt so langsam" gemeldet und eine Regressionssuche ausgeloest, die es
nicht gibt.

### Was noch fehlt

1. **RealityKits eigener Renderloop.** `RvPerf` misst bis zur Uebergabe; was
   der Renderer danach auf seinem eigenen Zeitplan tut, gehoert dem OS.
2. **Ein Sampling-Profiler** (VM-Service `getCpuSamples` → Perfetto). Die
   Suite sagt, welche OPERATION was kostet; ein Profiler saegt, welche ZEILE.
   Fuer `analyzeSketch` ist das der Unterschied zwischen „die Ranganalyse ist
   kubisch" und „diese Schleife ist es".
3. ~~**`kernel.sweepTwist` liefert null**~~ **ERLEDIGT (M223):**
   `occt_sweep_profile: twist is not implemented yet`. Kein Defekt.
4. **`footprintMB` gegen `residentMB`** — **eingegrenzt (M223), nicht
   erklaert.** Das Verhaeltnis ist keine Konstante: 3.60 / 2.52 / 4.00 / 2.47
   ueber die vier Sondenpunkte, also ≈ 4 VOR und ≈ 2.5 NACH der Suite. Die
   fruehere Zahl „4–5" war eine Einzelmessung. Was den Footprint belegt,
   bleibt unbekannt. iOS killt auf den Footprint, nicht auf RSS.
5. ~~**Die Stress- und Rampen-Tiers sind noch nie auf dem Geraet gelaufen.**~~
   **ERLEDIGT (M223):** alle sieben Leitern in beiden Armen. Die Ausfallzahlen
   in PERFORMANCE_PROFILE sind keine Hochrechnungen mehr — `allEdges` ist bis
   an seine Wand gefahren (480 Profilpunkte / 10 017 ms).
6. ~~**Ein Lauf ohne Energiesparmodus.**~~ **ERLEDIGT (M223):** Aufnahme B ist
   ungedrosselt und der Referenzarm des Berichts. Beide Arme sind aufgehoben,
   wie Abschnitt 3.5 empfiehlt.
7. **Ein speicherbeschraenktes Geraet.** Die Achse, die der Energiesparmodus
   NICHT abdeckt — und M223 hat gezeigt, dass er sie sogar SYSTEMATISCH
   UNTERSCHAETZT (speichergebunden 1.62 gegen 2.27 bei Dart-Rechnung). Die
   Achse, auf der die App im Feld gestorben ist.
7b. ~~**Ein Regressionswaechter**~~ **GEBAUT (M224)** — `perf/baseline.json`
   plus `ci/perf_gate.py`. Siehe unten und PERFORMANCE_PROFILE 15.4. Offen
   bleibt nur: er ist noch nie gegen ein ZWEITES Geraetebundle gelaufen (es
   gibt nach der Basislinie keins), und er laeuft nicht bei jedem Push, weil
   CI kein Geraetebundle erzeugen kann.
8. **Vier Features ohne Fixture:** Hole, Combine, Split, Delete Face /
   Direct Edit. Bei den Feature-Arten ist das milde (`kernel.feature.<kind>`
   bepreist sie in jedem Rebuild), bei Delete Face und Direct Edit bewusst:
   beide brauchen eine gueltige topologische Flaechen-ID und eine Operation,
   die der Kernel annimmt, und eine Fixture, die daneben greift, meldet eine
   schnelle Null. Siehe PERFORMANCE_PROFILE 14.4.

### Lehren aus dieser Sitzung

* **Ein Szenario, das nichts misst, liefert trotzdem eine Zahl — und die ist
  von einer schnellen nicht zu unterscheiden.** Drei Fixtures waren kaputt
  (`gear.curve` mass den Memo, `dofColour` eine Skizze ohne Constraints,
  `2d.snap` existierte gar nicht), und spaeter drei Werkzeuge (`eqCurve`,
  `circleTangent`, `slotOverall` gaben null zurueck). Deshalb pruefen die
  Tests in `m213_perf_coverage_test.dart` keine Zeiten, sondern **dass jedes
  Szenario sein Thema erreicht**.
* **Test und Benchmark muessen durch DENSELBEN Einstiegspunkt laufen**
  (`buildToolForPerf`). Den Aufruf im Test nachzubauen ist der Weg, auf dem
  ein Test gruen bleibt, waehrend der Benchmark etwas anderes misst.
* **`group()` nimmt in flutter_test kein `timeout:`** — nur `test()` und
  `testWidgets()`. Diesen Fehler habe ich in dieser Sitzung ZWEIMAL gemacht.
  Library-Annotation `@Timeout(...)` benutzen.
* **Swift importiert nur Makros, die schlichte Konstanten sind.**
  `THREAD_BASIC_INFO_COUNT` und Verwandte sind aus `sizeof` gebaut und muessen
  als `MemoryLayout<...>.size / MemoryLayout<natural_t>.size` gerechnet werden.
* **Vor dem Warten pruefen, ob der CI-Lauf zum HEAD gehoert.** Ich habe einen
  veralteten Lauf beobachtet und ein Ergebnis vom falschen Commit gemeldet.
* **Der Shim hat zwei Profilkodierungen:** `extrudeProfile`/`extrudePolygon`
  nehmen (x,y)-PAARE, `extrudeProfileArcs`/`revolve`/`sweep`/`loft`/`coil`
  nehmen (x,y,bulge)-TRIPEL. Die falsche wirft nicht — sie gibt null zurueck,
  und die Operation liest sich als kostenlos.
