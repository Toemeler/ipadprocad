#!/usr/bin/env bash
# Wird von OpenHands nach dem Klonen ausgeführt, bevor der Agent den ersten
# Turn macht.
#
# WARUM DIESE DATEI EXISTIERT
# ---------------------------
# In den gemessenen Sessions hat der Agent die Umgebung selbst gebaut — und
# zwar jedes Mal neu, mit dem Sprachmodell, einen Shell-Befehl pro ~55.000
# Token schwerem Turn:
#
#   * Flutter herunterladen und entpacken: 9 Turns, und es begann erst 22
#     Minuten nach Sessionstart, also innerhalb des 30-Minuten-Budgets
#   * `unzip` fehlt im Sandbox-Image -> der Agent schrieb sich einen
#     Python-Shim: 7-14 Turns
#   * `flutter pub get`: nochmal ein Turn plus Wartezeit
#
# Das sind 16-28 Turns pro Issue für etwas, das keine Intelligenz braucht und
# hier einmal, deterministisch und ohne Token passiert.
#
# Idempotent: mehrfaches Ausführen ist billig, weil alles vorher geprüft wird.
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/sdk/flutter}"

echo "[setup] unzip/zip sicherstellen"
# `flutter test` ruft in m184_bug_report_test.dart echte zip/unzip-Binaries
# auf. Fehlen sie, schlägt ein Test fehl, der mit dem Bugfix nichts zu tun hat
# — und der Agent sucht den Fehler in seinem eigenen Patch.
if ! command -v unzip >/dev/null 2>&1; then
  (sudo apt-get update -qq && sudo apt-get install -y -qq unzip zip) \
    || apt-get install -y -qq unzip zip \
    || echo "[setup] WARNUNG: unzip konnte nicht installiert werden"
fi

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "[setup] Flutter (stable) installieren nach $FLUTTER_DIR"
  mkdir -p "$(dirname "$FLUTTER_DIR")"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
else
  echo "[setup] Flutter ist bereits da"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# In die Shell-Profile schreiben, damit JEDER Turn des Agenten Flutter im PATH
# hat. Ohne das exportiert der Agent den PATH in jedem einzelnen Befehl neu —
# in den Logs gut sichtbar und eine ständige Quelle von "command not found",
# das dann als Turn zurückkommt.
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  grep -qs "$FLUTTER_DIR/bin" "$rc" 2>/dev/null \
    || echo "export PATH=\"$FLUTTER_DIR/bin:\$PATH\"" >> "$rc"
done

echo "[setup] flutter precache + pub get (wärmt den Cache für analyze/test)"
flutter --version || true
(cd frontend && flutter pub get) || echo "[setup] WARNUNG: pub get fehlgeschlagen"

echo "[setup] fertig"
