# Maintainer-Protokoll für Bug-Reports

Bug-Reports werden seit M287 von `.github/workflows/bugfix.yml` erledigt, nicht
mehr von einer OpenHands-Session. Diese Datei beschreibt beides: was die
Pipeline tut, und was du tust, falls du als Session trotzdem startest.

Warum der Wechsel: drei gemessene Sessions brauchten 193, 212 und 387
Modell-Turns für je einen Fix ($1.49, $1.60, $3.12). 65–77 % dieser Turns waren
Umgebung und Suche, nicht Denken. Die Pipeline macht das deterministisch und
ruft das Modell 1–4 mal. Details und Zahlen: `ci/bugfix/README.md`.

## Wenn du eine OpenHands-Session bist

**Prüfe zuerst, ob überhaupt etwas offen ist.** CI startet innerhalb von
Sekunden nach dem Issue und nimmt das `bug-report`-Label weg. Wenn kein Issue
mehr offen mit `bug-report` gelabelt ist, bist du redundant — beende dich
sofort. Das ist der Normalfall und ausdrücklich in Ordnung.

    curl -s -H "Authorization: Bearer ${github_token}" \
      "https://api.github.com/repos/Toemeler/ipadprocad/issues?state=open&labels=bug-report"

Ist doch etwas offen (CI aus, fehlgeschlagen, oder `openhands-blocked`), gilt
der Ablauf unten. Alles über die Umgebung — Tokenname, Flutter-Pfad, `unzip`,
Hausregeln — steht in `.openhands/microagents/repo.md` und ist bereits in
deinem Kontext. Lies es nicht erneut ein.

## Ablauf pro Issue

1. **Beanspruchen.** `bug-report` entfernen, `openhands-working` setzen — in
   einem Schritt. Schlägt das Entfernen mit 404 fehl, hat jemand anders das
   Issue; überspringen.
2. **Lesen.** Issue-Body plus den Diagnose-Bundle von der `bug-reports`-Branch
   (`git show origin/bug-reports:bugreports/<stem>.zip`). Lies `report.md`
   zuerst — die App triagiert sich darin bereits selbst und sagt dir, ob
   `log.txt` oder `state.txt` die interessante Datei ist.
3. **Fixen.** Ursache, nicht Symptom. Dazu ein Test unter `frontend/test/`, der
   **ohne den Fix fehlschlägt** und mit ihm besteht. Ein Test, der so oder so
   besteht, pinnt nichts.
4. **Beweisen, nicht behaupten.** Aus `frontend/`:
   `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` (0 Fehler)
   und `flutter test` (alles grün). Beides muss laufen, bevor `main` angefasst
   wird. Läuft es aus Infrastrukturgründen gar nicht, sag das explizit und
   pushe nicht.
5. **Pushen.** `git fetch origin main && git rebase origin/main`, dann ein
   Commit pro Issue, erste Zeile `Bugfix #<nr>: <kurz>` (nicht das
   `M<nr>:`-Schema — das gehört der menschlichen Session). `git push origin main`.
6. **Schliessen** mit Ursache und Commit-SHA, und `bugreports/AUTOMATION_NOTES.md`
   um eine kurze Zeile ergänzen (anhängen, nicht neu schreiben).

Wenn du die Ursache nicht sicher findest oder der Fix eine menschliche
Entscheidung braucht: **nicht raten**. `openhands-working` weg,
`openhands-blocked` hin, ein Kommentar mit Befund und — wenn vorhanden — dem
vorgeschlagenen Diff. Weiter zum nächsten Issue.

## Was Turns kostet und nichts bringt

Gemessen in den alten Sessions, hier verboten:

- **Keine Pixel-Analyse von `screenshot.png`.** Der 3D-Körper ist eine
  RealityKit-Platform-View und ist **nie** im Screenshot — ein leer wirkender
  Viewport ist kein Befund. Nimm `reality.txt`, `mesh.txt`, `state.txt`. Eine
  Session hat 39 Turns damit verbrannt.
- **Kein `sleep`-Polling.** `flutter test` im Vordergrund laufen lassen, einmal.
  Jedes `sleep 60` ist ein voller Modellaufruf, der „noch nicht fertig" sagt.
- **Nichts zweimal lesen.** Protokoll, Notes und Bundle einmal. Wenn du merkst,
  dass du etwas erneut liest, ist der Kontext kondensiert worden — arbeite mit
  dem, was du weisst, statt neu herzuleiten.
- **Kein Datei-Dump.** `grep -m20`, `sed -n 'a,bp'` mit engem Bereich. Ganze
  Dateien sind bei `ribbon.dart` (2902 Zeilen) und `app_state.dart` (19550)
  teurer als der ganze Fix.

## Harte Regeln, ohne Ausnahme

- Nie einen Pull Request öffnen. Nie auf eine andere Branch als `main` pushen.
- Nie Code pushen, der `flutter analyze` und `flutter test` nicht bestanden hat.
- Nie force-pushen, nie fremde Historie umschreiben.
- Nie behaupten, ein Fix funktioniere, ohne den Test laufen gelassen zu haben.
- Die `bug-reports`-Branch nur lesen — sie gehört dem Relay.
- `.github/workflows/*`, `relay/*` und `ci/*` nicht als Teil eines Bugfixes
  ändern, ausser das Issue handelt genau davon.
- Im Zweifel, ob ein Push sicher ist: ist er nicht. Dann blockieren.
