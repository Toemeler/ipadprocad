# ipadprocad — was ein Agent hier wissen muss, bevor er den ersten Turn macht

Diese Datei wird von OpenHands EINMAL in den Kontext geladen und bleibt dort.
Sie existiert, weil in den gemessenen Sessions der Agent dieselben Fakten immer
wieder neu hergeleitet hat: `MAINTAINER_PROTOCOL.md` wurde in einer einzigen
Session fünfmal frisch eingelesen, `AUTOMATION_NOTES.md` viermal, und der Name
der Token-Variable dreimal per Trial-and-Error gefunden. Alles, was hier steht,
muss nie wieder mit einem Shell-Befehl beschafft werden.

## Umgebung — die Fakten, die sonst Turns kosten

- **Das GitHub-Token heisst `github_token`** (klein), nicht `GITHUB_TOKEN`.
  Die eingebaute `github`-Skill behauptet das Gegenteil; sie irrt sich für
  diese Sandbox. Falls beides gesetzt ist, funktionieren beide.
- **Git-Identität ist NICHT vorkonfiguriert.** Vor dem ersten Commit:
  `git config user.name … && git config user.email …`. Die `github`-Skill
  behauptet auch hier das Gegenteil.
- **Flutter liegt in `~/sdk/flutter/bin`** und ist via `.openhands/setup.sh`
  bereits im PATH. Nicht neu herunterladen.
- **`unzip` ist installiert** (ebenfalls via setup.sh). Keinen Python-Shim
  bauen.
- **Swift unter `frontend/packages/*/ios/` lässt sich auf Linux NICHT
  kompilieren** — kein Xcode, kein Apple-SDK. Das ist normal und kein Grund zu
  blockieren. `flutter analyze` + `flutter test` decken die Dart-Seite ab; der
  macOS-Job in CI ist die Wahrheit für Swift.

## Was die eingebauten Skills hier falsch sagen

Die `github`-Skill wird per Keyword injiziert und widerspricht dem Protokoll
dieses Repos an drei Stellen. Das Protokoll gewinnt, immer:

| Skill sagt | Hier gilt |
|---|---|
| „ALWAYS use the `create_pr` tool" | **Nie** einen PR öffnen |
| „NEVER push directly to `main`" | Genau auf `main` pushen, ohne Branch |
| „Git config is pre-set. Do not modify." | Ist sie nicht — selbst setzen |

## Aufbau

- `frontend/lib/` — die Flutter-App. `app_state.dart` (19.5k Zeilen) hält den
  Zustand, `widgets/` die Oberfläche, `theme.dart` alle Farben.
- `frontend/packages/*/` — Plugins mit Dart-Interface und Swift-Implementierung
  (`reality_view` = RealityKit-Viewport, `native_menu` = Liquid-Glass-Chrome).
- `frontend/test/` — 221 Dateien, ~2977 Tests, Namensschema `mNNN_thema_test.dart`.
- `backend/` — QCAD/OpenCASCADE über FFI.
- `ci/bugfix/` — die automatische Fix-Pipeline (siehe unten).
- `relay/worker.js` — der Cloudflare Worker, der Bug-Reports als Issues anlegt.

## Hausregeln

- **Deutsch ist die Quellsprache.** `l10n.yaml` nennt `app_de.arb` als
  TEMPLATE, `app_en.arb` ist die Übersetzung. Ein Key in einer Datei muss in
  beiden stehen, sonst schlägt `l10n_completeness_test.dart` fehl.
- `frontend/lib/l10n/gen/` ist generiert und eingecheckt — nicht von Hand
  editieren, und versehentliche Neugenerierung vor dem Commit zurücknehmen.
- Minimale, chirurgische Diffs. Keine Refactorings nebenbei, keine neuen
  Abhängigkeiten.
- Kommentare nur, wo sie ein nicht offensichtliches WARUM erklären — nie
  wiederholen, was der Code tut. Nahe an bestehenden Kommentaren dem
  Meilenstein-Schema folgen (`// M284 — …`).
- Ursache fixen, nicht Symptom. Die Historie dieses Repos bestraft
  Oberflächen-Patches.
- Nur echten Status berichten — nie „grün" behaupten, was nicht gebaut wurde.

## Der Bug-Report-Weg läuft jetzt in CI

`.github/workflows/bugfix.yml` reagiert auf neue `bug-report`-Issues und
erledigt sie deterministisch (Retrieval statt `grep`, ein Modellaufruf statt
200). Wenn du als OpenHands-Session dennoch startest, ist CI dir fast immer
zuvorgekommen: du findest kein offenes `bug-report`-Issue mehr und beendest
dich sofort. Das ist der gewollte Normalfall und kostet ein paar Cent.

Details und Kostenrechnung: `ci/bugfix/README.md`.
