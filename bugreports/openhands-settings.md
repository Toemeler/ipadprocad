# Die OpenHands-Automation nach M287

`openhands-automation.json` daneben ist die importierbare Fassung — exakt das
Schema der alten Datei, keine Zusatzfelder, direkt hochladbar. Diese Datei
erklärt, was sich geändert hat und was **außerhalb** der JSON gesetzt werden
muss.

## Was die JSON ändert

| | vorher | jetzt |
|---|---|---|
| Rolle | erledigt jeden Bug-Report | Auffangnetz, wenn CI aus ist oder blockiert |
| Prompt | „klone und folge dem Protokoll" | erst prüfen, ob überhaupt etwas offen ist |
| Umgebungswissen | musste erraten werden | Tokenname, Flutter-Pfad, `unzip` stehen drin |
| `timeout` | 1800 s | 900 s |

Der Prompt sagt der Session als Erstes, wie sie feststellt, dass sie
überflüssig ist. Das ist der Normalfall: `.github/workflows/bugfix.yml` nimmt
das `bug-report`-Label innerhalb von Sekunden weg, die Session findet eine
leere Liste und beendet sich, bevor sie geklont hat. Vorher blieb sie
stattdessen minutenlang am Leben und listete Issues neu, um Nachzügler
einzusammeln — Schritt 3 des alten Protokolls. Das übernimmt jetzt die
`concurrency`-Gruppe des Workflows, kostenlos.

Der Tokenname steht ausdrücklich im Prompt, weil die eingebaute `github`-Skill
das Gegenteil behauptet. In den drei gemessenen Sessions kostete allein das
Herausfinden 15–32 Turns — in einer Session dreimal neu, weil der Condenser
das Ergebnis zwischendurch aus dem Kontext geworfen hatte.

## Was NICHT in der JSON steht und trotzdem gesetzt werden muss

Die drei größten Kostentreiber sind Sandbox-/Agent-Einstellungen, keine
Automations-Felder. Ohne sie bleibt der Fallback teuer:

**1. Public Skills abschalten** (`agent_context.load_public_skills = false`)

11.204 Token in *jedem* Kontext, und für dieses Repo an drei Stellen falsch:

| Skill sagt | Hier gilt |
|---|---|
| „ALWAYS use the `create_pr` tool" | Nie einen PR öffnen |
| „NEVER push directly to `main`" | Genau auf `main` pushen |
| „Git config is pre-set. Do not modify." | Ist sie nicht |

Dazu kommt `openhands-automation` (~5.000 Token), das nur wegen des Worts
„automation" im Tag-Namen geladen wird und vom *Erstellen* von Automationen
handelt — hier durchgehend irrelevant.

**2. `condenser.max_size` von 80 auf 200**

Jede Kondensation schreibt den Prompt-Prefix um. DeepSeeks Cache greift nur bei
einem byteweise identischen Prefix ab Token 0, also wird danach der komplette
Kontext zum Miss-Preis neu abgerechnet: $1,3184/M statt $0,0441/M, Faktor 30.

Gemessen: **jede einzelne große Cache-Miss-Spitze in allen drei Sessions** lag
innerhalb von 90 Sekunden nach einer Kondensation — 9 von 9 in S1, 17 von 17 in
S3. Zusammen mit den Condenser-Aufrufen selbst waren das ~26 % der Kosten. Es
verursachte außerdem die Amnesie: `MAINTAINER_PROTOCOL.md` wurde in einer
Session fünfmal frisch eingelesen, der Bundle dreimal neu geholt.

**3. `max_message_chars` von 30000 auf 4000**

Eine einzige Werkzeugausgabe konnte 7.500 Token in den Kontext kippen, die dann
bis zur nächsten Kondensation in *jedem* Turn mitbezahlt wurden.

## Was bewusst bleibt

`reasoning_effort: high` bleibt. Reasoning-Token werden zum Output-Preis
abgerechnet ($3,9583/M) und waren 64 % aller Output-Token — aber das ist die
Qualität des Fixes. Es wird billiger, weil es weniger Turns gibt, nicht weil
weniger nachgedacht wird. (Die CI-Pipeline nutzt `medium`, weil sie einen
fertigen Kontext-Pack bekommt und die Suche schon erledigt ist.)

Modell bleibt `deepseek_deepseek-v4-pro`, unverändert.

## Reihenfolge

1. `DEEPSEEK_API_KEY` als Repository-Secret setzen (dafür ist die CI-Pipeline da).
2. Die drei Einstellungen oben in der OpenHands-UI ändern.
3. `openhands-automation.json` importieren bzw. Prompt, Name und Timeout der
   bestehenden Automation entsprechend anpassen.
4. Einen Test-Bug-Report auslösen. Erwartung: der Workflow übernimmt, die
   OpenHands-Session startet ebenfalls, findet nichts und beendet sich nach
   wenigen Cent. Beide Logs zeigen ihre Kosten.
