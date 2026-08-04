# AUTOINSTALL — vom gruenen Build aufs iPad

Ziel: nach jedem gruenen M5 liegt der Build als Release bereit, und **ein
Shortcut** holt ihn — selbst ausgeloest, wann es passt.

    CI (M5 gruen) --> Release: IPA + source.json + latest.json
                                          |
      [Tipp 1] Shortcut ausloesen (Kontrollzentrum / Home-Screen / Widget)
                                          v
      Shortcut: neuesten Build nachschlagen, VPN an, sidestore://install
                                          |
                          [Tipp 2] "Install" in SideStore
                                          v
                      Download, Signatur, Installation (~40 s)

Der Shortcut braucht **keinen** Dienst, kein Secret, keine Mail und keine
Automation: er fragt bei jedem Auslosen `latest.json` ab und installiert, was
gerade neuestes Release ist. Push (Abschnitt 3) ist optional obendrauf — nur
das Signal „es liegt was Neues bereit", damit man nicht ins Leere tippt.

## Warum zwei Tipser und nicht null

Nachgesehen im Quelltext von SideStore, nicht in der Doku:

* `sidestore://install?url=…` landet in `SideStore/DeepLinks/URLHandler.swift`
  (Host `install`, Parameter `url`) und von dort ueber
  `importAppDeepLinkNotification` in `MyAppsViewController.importApp` — und das
  ruft **immer** `InstallAppDialog.present`, einen `UIAlertController` mit
  „Would you like to install …?" / Install / Cancel. Der Weg ueber eine
  `.ipa`-Datei (`SceneDelegate.open`) muendet im selben Dialog.
* SideStores einzige App-Intents sind `RefreshAllAppsIntent` und die
  Widget-Variante — **kein** Install-Intent. Aus einem Shortcut heraus kann
  SideStore im Hintergrund also nur nachsignieren, nicht installieren.
* Ein Auto-Update aus einer Source gibt es nicht: `autoUpdate`,
  `automaticallyUpdate`, `installUpdates` kommen im ganzen Repo nicht vor.
  `AppManager.backgroundRefresh` signiert nur bereits installierte Apps nach.

Mit unveraendertem SideStore ist ein Tipp auf „Install" also nicht wegzukriegen.
Null Tipser gaebe es nur mit (a) einem SideStore-Fork mit eigenem
Install-Intent, (b) TestFlight + Automatic Updates (99 $/Jahr) oder (c)
AltServer auf einem Dauerlaeufer im selben WLAN. Alle drei sind eigene
Projekte — dieser Weg hier kostet zwei Tipser und ist heute fertig.

## Was die CI liefert

Jeder gruene `m5-flutter-ipa` erzeugt das Release `build-<Run-Nummer>`:

| Asset | Inhalt |
| --- | --- |
| `ipadprocad-<N>.ipa` | die unsignierte IPA, ~27 MB |
| `source.json` | SideStore-/AltStore-Source, die letzten 10 Builds, neuester zuerst |
| `latest.json` | flaches Manifest fuer den Shortcut |

Feste Einstiegspunkte (GitHub leitet `latest` immer aufs neueste Release um):

    https://github.com/Toemeler/ipadprocad/releases/latest/download/source.json
    https://github.com/Toemeler/ipadprocad/releases/latest/download/latest.json

Die Version im Bundle ist die Run-Nummer: Build 361 heisst am Geraet `0.1.361`.
Damit sieht man im Info-Dialog und in SideStore, welcher Build laeuft. Aeltere
Releases bleiben stehen (15 Stueck), das ist der Rueckweg, wenn ein Build am
Geraet unbrauchbar ist.

## Einrichtung am iPad (einmalig, ~10 Minuten)

### 1. Source in SideStore eintragen

SideStore → Sources → **+** → obige `source.json`-URL. Braucht man fuer den
Zwei-Tipp-Weg nicht, aber sie ist der Rueckweg: dort stehen die letzten 10
Builds mit Datum und Commit-Zeile, und aeltere lassen sich direkt installieren.

### 2. Shortcut „Install ipadprocad" — der eigentliche Weg

Der Name muss **exakt** so lauten, falls Abschnitt 3 (Push) dazukommt: die CI
baut ihn in die Notification-URL ein. Ohne Push ist der Name frei.

1. **Erhalte Text aus Eingabe** (Shortcut-Eingabe; bei Start ohne Eingabe
   nachfragen: aus). Das ist die IPA-URL, die die Notification mitschickt.
2. **Wenn** Text *hat keinen Wert*:
   * **Inhalt von URL abrufen** → `https://github.com/Toemeler/ipadprocad/releases/latest/download/latest.json`
   * **Wörterbuchwert abrufen** → Schluessel `ipaURL`
   * Ergebnis in **Variable setzen** `IPA`
   **Sonst:** Text in **Variable setzen** `IPA`
   (So laeuft derselbe Shortcut per Notification *und* als Icon auf dem
   Home-Screen ohne Eingabe.)
3. **VPN**: hier deinen bestehenden VPN-Shortcut aufrufen (**Shortcut ausführen**)
   oder direkt **VPN einschalten**. Muss VOR dem Deep Link stehen: ohne Tunnel
   scheitert SideStore erst beim Signieren, also nach dem Download.
4. **Warten** 2 Sekunden (der Tunnel braucht einen Moment).
5. **URL öffnen** → `sidestore://install?url=` mit angehaengter Variable `IPA`.

**Wohin damit — in dieser Reihenfolge:**

* **Kontrollzentrum** (iPadOS 18+: Kontrollzentrum → **+** → Steuerung
  hinzufuegen → Shortcuts → „Install ipadprocad"). Ein Wisch von oben rechts,
  ein Tipp — auch **waehrend die CAD-App offen ist**, ohne sie zu verlassen.
  Das ist der kuerzeste Weg.
* **Lock-Screen-Widget** — Tipp direkt vom gesperrten Bildschirm.
* **Home-Screen** (Shortcut teilen → „Zum Home-Bildschirm").

Alle drei brauchen weder Push noch Secrets noch Netzdienst ausser GitHub.

### 3. Push einrichten (optional — nur das „es liegt was bereit"-Signal)

Ohne das musst du raten, wann der Build fertig ist. Drei Moeglichkeiten, von
billig nach zuverlaessig:

**GitHub-Mobile-App** (kostenlos, nichts zu bauen): App installieren →
Settings → Notifications → Actions einschalten. Meldet fertige Workflow-Laeufe.
Der Tipp fuehrt in die GitHub-App, nicht in den Shortcut — du loest den
Shortcut danach selbst aus. Kostet nichts und keinen CI-Code.

Wenn der Tipp direkt in den Shortcut fuehren soll, setzt du eins der beiden
Secrets; dann macht `ci/notify_build.sh` den Rest:

**Pushover** (5 $ einmalig, zuverlaessiger, weil die App die URL unveraendert
ans System reicht — auch eigene Schemata wie `shortcuts://`):
Repo → Settings → Secrets → Actions:

    PUSHOVER_TOKEN   Application-Token
    PUSHOVER_USER    User-Key

**ntfy** (kostenlos): Secret `NTFY_TOPIC` auf einen geratenen Topic-Namen
setzen (der Topic ist oeffentlich — der Name ist das Passwort), ntfy-App
installieren und denselben Topic abonnieren. Optional `NTFY_URL` fuer eine
eigene Instanz.

Ohne beides bleibt der Schritt ein No-op, der Build bleibt gruen, und der
Home-Screen-Shortcut holt den Build genauso.

Die Notification zeigt „Build N ready" plus die Commit-Zeile; ihr Link ist
**nicht** die IPA und nicht `sidestore://`, sondern
`shortcuts://run-shortcut?name=Install%20ipadprocad&input=text&text=<IPA-URL>` —
sonst landet man in SideStore, bevor der VPN steht.

## Was beim Installieren passiert

Gleiche Bundle-ID (`com.prototype.prototype`) heisst: SideStore installiert
**darueber**, die App wird nicht geloescht. Das ist Absicht — ein Loeschen
nimmt das Documents-Verzeichnis mit, also `logs/prototype_log.txt` und die
Modelle. Wer wirklich sauber starten will, loescht die App vorher von Hand.

## Wenn es klemmt

| Symptom | Ursache |
| --- | --- |
| SideStore oeffnet, Dialog kommt, Install schlaegt fehl | VPN stand nicht. Schritt 3/4 im Shortcut pruefen, Wartezeit erhoehen. |
| „App wurde von einem anderen Entwickler installiert" | Zertifikat gewechselt. App einmal von Hand loeschen, dann neu installieren. |
| Notification kommt, Tipp macht nichts | Shortcut-Name weicht ab. Er muss „Install ipadprocad" heissen oder `SHORTCUT_NAME` in der CI muss mitgeaendert werden. |
| Release fehlt trotz gruenem Build | Fork-PR (Token darf nur lesen) — sonst Job-Log „Publish release" lesen. |
| Alte Builds weg | Nur die letzten 15 bleiben liegen. |
