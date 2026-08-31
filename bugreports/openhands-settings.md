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

## Was NICHT in der JSON steht — und auch sonst nirgends

Ursprünglich standen hier drei Sandbox-Einstellungen, die man ändern sollte.
**Nachgeprüft: keine davon ist für eine Automation erreichbar.** Der Grund
steht im generierten `main.py`, das jede Automation startet und das man nicht
bearbeiten kann:

```python
329  llm = workspace.get_llm(profile_name=model_profile)      # LLM-Profil wird benutzt
284  loaded_skills, agent_context = workspace.load_skills_from_agent_server(...)
367  agent = get_default_agent(llm=llm, cli_mode=True)        # Condenser: SDK-Default
```

### 1. `condenser.max_size` — UI-Wert wird ignoriert

`get_default_agent()` setzt den Condenser selbst. Der Beweis liegt in den
Exporten: die UI stand auf **240**, alle drei gemessenen Sessions liefen mit
**80** (`LLMSummarizingCondenser`, `keep_first=4`). Am Wert in den
LLM-Einstellungen zu drehen ändert für Automationen nichts.

Das ist die teuerste der drei und zugleich die unerreichbarste: jede
Kondensation schreibt den Prompt-Prefix um, DeepSeeks Cache greift nur bei
byteweise identischem Prefix ab Token 0, also wird danach alles zum Miss-Preis
neu abgerechnet — $1,3184/M statt $0,0441/M. Gemessen lag **jede einzelne
grosse Cache-Miss-Spitze in allen drei Sessions** innerhalb von 90 Sekunden
nach einer Kondensation (9 von 9 in S1, 17 von 17 in S3): ~26 % der Kosten.

### 2. Public Skills — werden bedingungslos geladen

`agent_context.load_public_skills` stand in allen drei Sessions bereits auf
`False`, und trotzdem waren 60 Skills geladen: Zeile 284 holt sie unabhängig
davon vom Agent-Server und Zeile 374 hängt sie an den Agenten. Ein Schalter
hätte also ohnehin nichts bewirkt.

### 3. `max_message_chars` — theoretisch erreichbar, praktisch nicht

Das ist ein Feld des LLM-Profils, nicht des Agenten, kommt also aus
`get_llm()`. Es wäre damit die einzige der drei, die ein Profil-Editor
überhaupt setzen könnte — nur gibt es dafür kein UI-Feld.

## Was stattdessen wirkt

Weil die Konfiguration nicht erreichbar ist, liegt der ganze Hebel im Prompt
und im Repository — und genau dort liegt er jetzt:

| Problem | Nicht gelöst durch | Sondern durch |
|---|---|---|
| Falscher Tokenname, PR-/Push-Regeln | Skills abschalten | `.openhands/microagents/repo.md` + Automations-Prompt widersprechen ausdrücklich |
| Flutter/`unzip` jedes Mal neu bauen | — | `.openhands/setup.sh` |
| Datei-Dumps | `max_message_chars` | Protokoll schreibt `grep -m20` und enge `sed`-Bereiche vor |
| Kondensation und ihre Amnesie | `condenser.max_size` | Die Session macht nur noch 2–3 Turns, bevor sie feststellt, dass CI das Issue hat — der Condenser feuert bei ~40 Turns und wird nie erreicht |

Die 11.204 Skill-Token bleiben also im Kontext. Bei einer Session, die nach
zwei bis drei Turns aussteigt, sind das zum Cache-Hit-Preis etwa ein halber
Cent — hinnehmbar. Teuer waren sie, weil sie 21 % eines 55k-Kontexts über 200
Turns waren *und* Falsches behaupteten; beides trifft nicht mehr zu.

## Was bewusst bleibt

`reasoning_effort: high` bleibt. Reasoning-Token werden zum Output-Preis
abgerechnet ($3,9583/M) und waren 64 % aller Output-Token — aber das ist die
Qualität des Fixes. Es wird billiger, weil es weniger Turns gibt, nicht weil
weniger nachgedacht wird. (Die CI-Pipeline nutzt `medium`, weil sie einen
fertigen Kontext-Pack bekommt und die Suche schon erledigt ist.)

Modell bleibt `deepseek_deepseek-v4-pro`, unverändert.

## Reihenfolge

1. `DEEPSEEK_API_KEY` als Repository-Secret setzen (dafür ist die CI-Pipeline da).
2. `.github/workflows/bugfix.yml` auf `main` haben — `issues`-Workflows laufen
   ausschliesslich vom Default-Branch.
3. `openhands-automation.json` importieren.
4. Einen Test-Bug-Report auslösen. Erwartung: der Workflow übernimmt, die
   OpenHands-Session startet ebenfalls, findet nichts und beendet sich nach
   wenigen Cent. Beide Logs zeigen ihre Kosten.
