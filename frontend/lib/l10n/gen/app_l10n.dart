import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_de.dart';
import 'app_l10n_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n? of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n);
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// Name dieser Sprache, in dieser Sprache geschrieben. Erscheint im Sprachumschalter.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get languageName;

  /// Titel des Einstellungsblatts.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// Beschriftung der Zahnrad-Taste in der Galerie (nur fuer VoiceOver).
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsButton;

  /// Schliesst das Einstellungsblatt. iOS-Standardwort.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get settingsDone;

  /// Abschnittstitel: hell, dunkel oder wie das iPad.
  ///
  /// In de, this message translates to:
  /// **'Darstellung'**
  String get settingsAppearance;

  /// Fusszeile unter der Darstellung.
  ///
  /// In de, this message translates to:
  /// **'„System“ folgt der Einstellung des iPads.'**
  String get settingsAppearanceFooter;

  /// Kontrollkästchen im Fehlerbericht: soll die Automatik den Fehler beheben?
  ///
  /// In de, this message translates to:
  /// **'Automatisch beheben lassen'**
  String get bugAutofix;

  /// Hinweis unter dem Kontrollkästchen, wenn es aktiv ist.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht wird sofort an die Fix-Automatik übergeben.'**
  String get bugAutofixOn;

  /// Hinweis unter dem Kontrollkästchen, wenn es deaktiviert ist.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht wartet auf eine Sitzung, die du selbst startest.'**
  String get bugAutofixOff;

  /// Abschnittstitel: die Farbe für Auswahl, aktiven Tab und Fokus.
  ///
  /// In de, this message translates to:
  /// **'Akzentfarbe'**
  String get settingsAccent;

  /// Fusszeile unter der Akzentfarbe.
  ///
  /// In de, this message translates to:
  /// **'„Schema“ nimmt die Farbe der gewählten Darstellung. Jede Farbe ist auf Lesbarkeit geprüft.'**
  String get settingsAccentFooter;

  /// Akzent: die Farbe der Darstellung selbst (Standard).
  ///
  /// In de, this message translates to:
  /// **'Schema'**
  String get accentScheme;

  /// Akzent: Blaugrün.
  ///
  /// In de, this message translates to:
  /// **'Petrol'**
  String get accentTeal;

  /// Akzent: Blau.
  ///
  /// In de, this message translates to:
  /// **'Blau'**
  String get accentBlue;

  /// Akzent: Violett.
  ///
  /// In de, this message translates to:
  /// **'Indigo'**
  String get accentIndigo;

  /// Akzent: Pink.
  ///
  /// In de, this message translates to:
  /// **'Magenta'**
  String get accentMagenta;

  /// Akzent: Orange.
  ///
  /// In de, this message translates to:
  /// **'Bernstein'**
  String get accentAmber;

  /// Akzent: Grün.
  ///
  /// In de, this message translates to:
  /// **'Grün'**
  String get accentGreen;

  /// Akzent: Rot.
  ///
  /// In de, this message translates to:
  /// **'Rot'**
  String get accentRed;

  /// Abschnittstitel: der Hintergrund der Galerie.
  ///
  /// In de, this message translates to:
  /// **'Hintergrund'**
  String get settingsBackdrop;

  /// Fusszeile unter dem Hintergrund: Geltungsbereich und der Schleier.
  ///
  /// In de, this message translates to:
  /// **'Nur für die Galerie. Über einem Bild liegt ein Schleier.'**
  String get settingsBackdropFooter;

  /// Hintergrund-Auswahl: folgt hell/dunkel, der Standard.
  ///
  /// In de, this message translates to:
  /// **'Wie die Darstellung'**
  String get backdropAuto;

  /// Name der Hintergrundfarbe: fast schwarz, kuehl.
  ///
  /// In de, this message translates to:
  /// **'Tinte'**
  String get backdropInk;

  /// Name der Hintergrundfarbe: blaugrau.
  ///
  /// In de, this message translates to:
  /// **'Schiefer'**
  String get backdropSlate;

  /// Name der Hintergrundfarbe: dunkles Gruen.
  ///
  /// In de, this message translates to:
  /// **'Tanne'**
  String get backdropForest;

  /// Name der Hintergrundfarbe: warmes Papier.
  ///
  /// In de, this message translates to:
  /// **'Sand'**
  String get backdropSand;

  /// Name der Hintergrundfarbe: fast weiss.
  ///
  /// In de, this message translates to:
  /// **'Leinen'**
  String get backdropLinen;

  /// Zeile, die ein selbst gewaehltes Hintergrundbild traegt.
  ///
  /// In de, this message translates to:
  /// **'Eigenes Bild'**
  String get backdropImage;

  /// Oeffnet die Dateiauswahl fuer ein Hintergrundbild.
  ///
  /// In de, this message translates to:
  /// **'Bild waehlen …'**
  String get backdropChooseImage;

  /// Loescht das Hintergrundbild und geht zurueck zur Darstellung.
  ///
  /// In de, this message translates to:
  /// **'Bild entfernen'**
  String get backdropRemoveImage;

  /// Meldung, wenn das gewaehlte Bild nicht kopiert werden konnte.
  ///
  /// In de, this message translates to:
  /// **'Das Bild konnte nicht uebernommen werden.'**
  String get backdropImageFailed;

  /// Abschnittstitel der Sprachwahl.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguage;

  /// Abschnittstitel: wo das Menüband andockt.
  ///
  /// In de, this message translates to:
  /// **'Menüband'**
  String get settingsRibbon;

  /// Menüband oben andocken (Standard, Flush-Band).
  ///
  /// In de, this message translates to:
  /// **'Oben'**
  String get ribbonTop;

  /// Menüband unten andocken.
  ///
  /// In de, this message translates to:
  /// **'Unten'**
  String get ribbonBottom;

  /// Menüband links andocken (Seitenschiene).
  ///
  /// In de, this message translates to:
  /// **'Links'**
  String get ribbonLeft;

  /// Menüband rechts andocken (Seitenschiene).
  ///
  /// In de, this message translates to:
  /// **'Rechts'**
  String get ribbonRight;

  /// Abschnittstitel: Fehler melden, Protokoll teilen.
  ///
  /// In de, this message translates to:
  /// **'Diagnose'**
  String get settingsDiagnostics;

  /// Oeffnet den Fehlerbericht mit Beschreibung und Modellzustand.
  ///
  /// In de, this message translates to:
  /// **'Problem melden'**
  String get settingsReportProblem;

  /// Teilt die Protokolldatei ueber das iOS-Teilen-Blatt.
  ///
  /// In de, this message translates to:
  /// **'Protokoll teilen'**
  String get settingsShareLog;

  /// Fusszeile der Diagnose: sagt, was mitgeschickt wird.
  ///
  /// In de, this message translates to:
  /// **'Ein Bericht enthaelt das offene Dokument und das Protokoll dieser Sitzung.'**
  String get settingsDiagnosticsFooter;

  /// Abschnittstitel mit Version und Kernen.
  ///
  /// In de, this message translates to:
  /// **'Über'**
  String get settingsAbout;

  /// Zeile: der Build, aus dem die App gebaut wurde.
  ///
  /// In de, this message translates to:
  /// **'Version'**
  String get settingsBuild;

  /// Zeile: die OCCT-Version.
  ///
  /// In de, this message translates to:
  /// **'3D-Kern'**
  String get settingsKernel3d;

  /// Zeile: die QCAD-Version.
  ///
  /// In de, this message translates to:
  /// **'2D-Kern'**
  String get settingsKernel2d;

  /// Zeile: iPadOS-Version.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// Darstellung folgt der iPad-Einstellung.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// Das helle Schema (Chalk): kuehles graues Cremepapier.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get appearanceLight;

  /// Das dunkle Schema (Ember): warme braune Kohle.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get appearanceDark;

  /// Bestaetigen. In beiden Sprachen OK — im Deutschen ebenso ueblich wie im Englischen.
  ///
  /// In de, this message translates to:
  /// **'OK'**
  String get ok;

  /// Abbrechen. Nicht "Stornieren" (Handel) und nicht "Absagen" (Termin).
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// Vorgang abschliessen. Kurz gehalten; "Fertigstellen" waere hier doppelt so lang.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get done;

  /// Werte anwenden, Dialog bleibt offen. Inventor sagt "Übernehmen".
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get apply;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get rename;

  /// No description provided for @duplicate.
  ///
  /// In de, this message translates to:
  /// **'Duplizieren'**
  String get duplicate;

  /// No description provided for @create.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get create;

  /// No description provided for @select.
  ///
  /// In de, this message translates to:
  /// **'Auswählen'**
  String get select;

  /// No description provided for @finish.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get finish;

  /// No description provided for @discard.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get discard;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @hide.
  ///
  /// In de, this message translates to:
  /// **'Ausblenden'**
  String get hide;

  /// No description provided for @openEllipsis.
  ///
  /// In de, this message translates to:
  /// **'Öffnen…'**
  String get openEllipsis;

  /// No description provided for @exportEllipsis.
  ///
  /// In de, this message translates to:
  /// **'Exportieren…'**
  String get exportEllipsis;

  /// No description provided for @shareEllipsis.
  ///
  /// In de, this message translates to:
  /// **'Teilen…'**
  String get shareEllipsis;

  /// Werkzeugleiste. "Rückgängig" ist der Begriff, den jede deutsche Oberflaeche benutzt; die Leiste laesst 12 Zeichen zu.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get undo;

  /// Werkzeugleiste. NICHT "Wiederherstellen" (16 Zeichen, sprengt die Leiste) — "Wiederholen" ist die kurze Form, die auch Office benutzt.
  ///
  /// In de, this message translates to:
  /// **'Wiederholen'**
  String get redo;

  /// Ribbon-Gruppe. die Skizze.
  ///
  /// In de, this message translates to:
  /// **'Skizze'**
  String get panelSketch;

  /// No description provided for @panelCreate.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get panelCreate;

  /// Ribbon-Gruppe. Inventor DE: "Ändern".
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get panelModify;

  /// Ribbon-Gruppe. Inventor DE: "Arbeitselemente" (Arbeitsebene, -achse, -punkt).
  ///
  /// In de, this message translates to:
  /// **'Arbeitselemente'**
  String get panelWorkFeatures;

  /// Ribbon-Gruppe. Inventor DE: "Anordnung", nicht "Muster".
  ///
  /// In de, this message translates to:
  /// **'Anordnung'**
  String get panelPattern;

  /// Ribbon-Gruppe. "Layer" bleibt englisch — AutoCAD DE und die gesamte deutsche CAD-Praxis sagen Layer, nicht Ebene, weil Ebene in 3D die Plane ist.
  ///
  /// In de, this message translates to:
  /// **'Layer'**
  String get panelLayer;

  /// Ribbon-Gruppe. Inventor DE nennt Zwangsbedingungen "Abhängigkeiten"; dieser Sprachgebrauch ist bei den Anwendern eingeuebt.
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeit'**
  String get panelConstrain;

  /// No description provided for @panelInsert.
  ///
  /// In de, this message translates to:
  /// **'Einfügen'**
  String get panelInsert;

  /// No description provided for @panelView.
  ///
  /// In de, this message translates to:
  /// **'Ansicht'**
  String get panelView;

  /// No description provided for @panelExit.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get panelExit;

  /// Ribbon-Gruppe. Kurzform von "Geometrie projizieren"; der volle Inventor-Begriff steht auf der Schaltflaeche darunter.
  ///
  /// In de, this message translates to:
  /// **'Projizieren'**
  String get panelProjectGeometry;

  /// Grosse Schaltflaeche auf der Startseite, zweizeilig. Englisch braucht drei Woerter fuer das, was "Neue Skizze" sagt.
  ///
  /// In de, this message translates to:
  /// **'Neue\nSkizze'**
  String get btnCreateNewSketch;

  /// Bauteil-Ribbon: startet eine Skizze auf einer gewaehlten Ebene.
  ///
  /// In de, this message translates to:
  /// **'2D-Skizze\nbeginnen'**
  String get btnStart2dSketch;

  /// No description provided for @btnStartNewLayer.
  ///
  /// In de, this message translates to:
  /// **'Neuer\nLayer'**
  String get btnStartNewLayer;

  /// Inventor DE: "Extrusion". Substantiv, wie alle Feature-Befehle dort.
  ///
  /// In de, this message translates to:
  /// **'Extrusion'**
  String get btnExtrude;

  /// Inventor DE: "Drehung" — das Feature, nicht die Ansichtsdrehung (das ist "Orbit").
  ///
  /// In de, this message translates to:
  /// **'Drehung'**
  String get btnRevolve;

  /// Inventor DE laesst Sweep als "Sweeping" stehen. "Ziehen" oder "Austragung" wuerde kein Inventor-Anwender wiedererkennen.
  ///
  /// In de, this message translates to:
  /// **'Sweeping'**
  String get btnSweep;

  /// Inventor DE: "Erhebung".
  ///
  /// In de, this message translates to:
  /// **'Erhebung'**
  String get btnLoft;

  /// Inventor DE: "Spirale".
  ///
  /// In de, this message translates to:
  /// **'Spirale'**
  String get btnCoil;

  /// No description provided for @btnEmboss.
  ///
  /// In de, this message translates to:
  /// **'Prägen'**
  String get btnEmboss;

  /// No description provided for @btnDerive.
  ///
  /// In de, this message translates to:
  /// **'Ableiten'**
  String get btnDerive;

  /// No description provided for @btnDecal.
  ///
  /// In de, this message translates to:
  /// **'Aufkleber'**
  String get btnDecal;

  /// Inventor DE: "Verrundung". NICHT "Filet" — das ist Fleisch.
  ///
  /// In de, this message translates to:
  /// **'Verrundung'**
  String get btnFillet;

  /// No description provided for @btnChamfer.
  ///
  /// In de, this message translates to:
  /// **'Fase'**
  String get btnChamfer;

  /// Inventor DE: "Wandung" — den Koerper auf eine Wandstaerke aushoehlen.
  ///
  /// In de, this message translates to:
  /// **'Wandung'**
  String get btnShell;

  /// No description provided for @btnDraft.
  ///
  /// In de, this message translates to:
  /// **'Formschräge'**
  String get btnDraft;

  /// No description provided for @btnThread.
  ///
  /// In de, this message translates to:
  /// **'Gewinde'**
  String get btnThread;

  /// No description provided for @btnHole.
  ///
  /// In de, this message translates to:
  /// **'Bohrung'**
  String get btnHole;

  /// No description provided for @btnSplit.
  ///
  /// In de, this message translates to:
  /// **'Trennen'**
  String get btnSplit;

  /// No description provided for @btnCombine.
  ///
  /// In de, this message translates to:
  /// **'Kombinieren'**
  String get btnCombine;

  /// No description provided for @btnPlane.
  ///
  /// In de, this message translates to:
  /// **'Ebene'**
  String get btnPlane;

  /// No description provided for @btnAxis.
  ///
  /// In de, this message translates to:
  /// **'Achse'**
  String get btnAxis;

  /// No description provided for @btnPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt'**
  String get btnPoint;

  /// No description provided for @btnLine.
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get btnLine;

  /// No description provided for @btnCircle.
  ///
  /// In de, this message translates to:
  /// **'Kreis'**
  String get btnCircle;

  /// No description provided for @btnArc.
  ///
  /// In de, this message translates to:
  /// **'Bogen'**
  String get btnArc;

  /// No description provided for @btnRectangle.
  ///
  /// In de, this message translates to:
  /// **'Rechteck'**
  String get btnRectangle;

  /// No description provided for @btnText.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get btnText;

  /// Inventor DE: "Bemaßung". Mit ß — nach langem a steht ß, nicht ss.
  ///
  /// In de, this message translates to:
  /// **'Bemaßung'**
  String get btnDimension;

  /// No description provided for @btnRectangular.
  ///
  /// In de, this message translates to:
  /// **'Rechteckig'**
  String get btnRectangular;

  /// Inventor DE: "Runde Anordnung". Hier steht das Adjektiv allein unter dem Symbol.
  ///
  /// In de, this message translates to:
  /// **'Rund'**
  String get btnCircular;

  /// No description provided for @btnMirror.
  ///
  /// In de, this message translates to:
  /// **'Spiegeln'**
  String get btnMirror;

  /// No description provided for @btnImage.
  ///
  /// In de, this message translates to:
  /// **'Bild'**
  String get btnImage;

  /// DXF-Import. Kuerzel des Fremdformats, bleibt in beiden Sprachen stehen.
  ///
  /// In de, this message translates to:
  /// **'ACAD'**
  String get btnAcad;

  /// Konstruktionsgeometrie ein-/ausschalten. Inventor DE: "Konstruktion".
  ///
  /// In de, this message translates to:
  /// **'Konstruktion'**
  String get btnConstruction;

  /// Plural von "der Parameter" ist "die Parameter" — kein -n.
  ///
  /// In de, this message translates to:
  /// **'Parameter'**
  String get btnParameters;

  /// No description provided for @btnGear.
  ///
  /// In de, this message translates to:
  /// **'Zahnrad'**
  String get btnGear;

  /// Zweizeilig. Inventor DE: "Geometrie projizieren".
  ///
  /// In de, this message translates to:
  /// **'Geometrie\nprojizieren'**
  String get btnProjectGeometry;

  /// Inventor DE: "Grafik schneiden" — blendet das Material vor der Skizzierebene aus.
  ///
  /// In de, this message translates to:
  /// **'Grafik\nschneiden'**
  String get btnSliceGraphics;

  /// Inventor DE: "Stutzen".
  ///
  /// In de, this message translates to:
  /// **'Stutzen'**
  String get btnTrim;

  /// Spline auf sich selbst spiegeln. Langes Wort, sitzt aber in einer Zeile mit voller Breite.
  ///
  /// In de, this message translates to:
  /// **'Selbstsymmetrisch'**
  String get btnSelfSymmetric;

  /// No description provided for @btnAssociative.
  ///
  /// In de, this message translates to:
  /// **'Assoziativ'**
  String get btnAssociative;

  /// No description provided for @btnFitted.
  ///
  /// In de, this message translates to:
  /// **'Angepasst'**
  String get btnFitted;

  /// No description provided for @flyLineB.
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get flyLineB;

  /// No description provided for @flyLineSub.
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get flyLineSub;

  /// Linie durch den Mittelpunkt. Inventor DE: "Mittellinie".
  ///
  /// In de, this message translates to:
  /// **'Mittellinie'**
  String get flyMidlineSub;

  /// "Spline" ist auch im Deutschen der Fachbegriff; es gibt kein gebraeuchliches deutsches Wort dafuer.
  ///
  /// In de, this message translates to:
  /// **'Spline'**
  String get flySplineB;

  /// Inventor DE: Spline ueber Steuerpunkte.
  ///
  /// In de, this message translates to:
  /// **'Steuerpunkt'**
  String get flySplineCvSub;

  /// No description provided for @flySplineInterpSub.
  ///
  /// In de, this message translates to:
  /// **'Interpolation'**
  String get flySplineInterpSub;

  /// No description provided for @flySplineFreeSub.
  ///
  /// In de, this message translates to:
  /// **'Freihand'**
  String get flySplineFreeSub;

  /// Inventor DE: "Gleichungskurve".
  ///
  /// In de, this message translates to:
  /// **'Gleichungskurve'**
  String get flyEqCurveB;

  /// Inventor DE: "Übergangskurve" — verbindet zwei Kurven tangenten- oder kruemmungsstetig.
  ///
  /// In de, this message translates to:
  /// **'Übergangskurve'**
  String get flyBridgeB;

  /// No description provided for @flyCircleB.
  ///
  /// In de, this message translates to:
  /// **'Kreis'**
  String get flyCircleB;

  /// No description provided for @flyCenterPointSub.
  ///
  /// In de, this message translates to:
  /// **'Mittelpunkt'**
  String get flyCenterPointSub;

  /// Konstruktionsmethode: tangential an vorhandene Geometrie.
  ///
  /// In de, this message translates to:
  /// **'Tangential'**
  String get flyTangentSub;

  /// No description provided for @flyEllipseB.
  ///
  /// In de, this message translates to:
  /// **'Ellipse'**
  String get flyEllipseB;

  /// Inventor DE: "Bogen". Nicht "Kreisbogen" — die Gruppe sagt schon, dass es ein Kreisbogen ist.
  ///
  /// In de, this message translates to:
  /// **'Bogen'**
  String get flyArcB;

  /// No description provided for @flyThreePointSub.
  ///
  /// In de, this message translates to:
  /// **'Drei Punkte'**
  String get flyThreePointSub;

  /// No description provided for @flyRectB.
  ///
  /// In de, this message translates to:
  /// **'Rechteck'**
  String get flyRectB;

  /// No description provided for @flyTwoPointSub.
  ///
  /// In de, this message translates to:
  /// **'Zwei Punkte'**
  String get flyTwoPointSub;

  /// No description provided for @flyTwoPointCenterSub.
  ///
  /// In de, this message translates to:
  /// **'Zwei Punkte, mittig'**
  String get flyTwoPointCenterSub;

  /// No description provided for @flyThreePointCenterSub.
  ///
  /// In de, this message translates to:
  /// **'Drei Punkte, mittig'**
  String get flyThreePointCenterSub;

  /// Inventor DE: "Langloch".
  ///
  /// In de, this message translates to:
  /// **'Langloch'**
  String get flySlotB;

  /// No description provided for @flySlotCcSub.
  ///
  /// In de, this message translates to:
  /// **'Mitte zu Mitte'**
  String get flySlotCcSub;

  /// Langloch ueber die Gesamtlaenge bemasst, nicht ueber den Mittenabstand.
  ///
  /// In de, this message translates to:
  /// **'Gesamtlänge'**
  String get flySlotOverallSub;

  /// No description provided for @flySlot3aSub.
  ///
  /// In de, this message translates to:
  /// **'Bogen, drei Punkte'**
  String get flySlot3aSub;

  /// No description provided for @flySlotCpaSub.
  ///
  /// In de, this message translates to:
  /// **'Bogen, Mittelpunkt'**
  String get flySlotCpaSub;

  /// No description provided for @flyPolygonB.
  ///
  /// In de, this message translates to:
  /// **'Polygon'**
  String get flyPolygonB;

  /// No description provided for @flyFilletB.
  ///
  /// In de, this message translates to:
  /// **'Verrundung'**
  String get flyFilletB;

  /// No description provided for @flyChamferB.
  ///
  /// In de, this message translates to:
  /// **'Fase'**
  String get flyChamferB;

  /// No description provided for @flyTextB.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get flyTextB;

  /// Text, der als Geometrie und nicht als Schriftobjekt entsteht.
  ///
  /// In de, this message translates to:
  /// **'Geometrietext'**
  String get flyGeomTextB;

  /// No description provided for @flyMoveB.
  ///
  /// In de, this message translates to:
  /// **'Verschieben'**
  String get flyMoveB;

  /// Direktbearbeitung: Flaeche vergroessern/verkleinern. Inventor DE: "Größe".
  ///
  /// In de, this message translates to:
  /// **'Größe'**
  String get flySizeB;

  /// No description provided for @flyScaleB.
  ///
  /// In de, this message translates to:
  /// **'Skalieren'**
  String get flyScaleB;

  /// No description provided for @flyRotateB.
  ///
  /// In de, this message translates to:
  /// **'Drehen'**
  String get flyRotateB;

  /// No description provided for @flyDeleteB.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get flyDeleteB;

  /// No description provided for @flyAxisB.
  ///
  /// In de, this message translates to:
  /// **'Achse'**
  String get flyAxisB;

  /// No description provided for @flyAxisOnLineB.
  ///
  /// In de, this message translates to:
  /// **'Auf Linie oder Kante'**
  String get flyAxisOnLineB;

  /// No description provided for @flyAxisParPtB.
  ///
  /// In de, this message translates to:
  /// **'Parallel zu Linie durch Punkt'**
  String get flyAxisParPtB;

  /// No description provided for @flyAxisTwoPtB.
  ///
  /// In de, this message translates to:
  /// **'Durch zwei Punkte'**
  String get flyAxisTwoPtB;

  /// No description provided for @flyAxisTwoPlB.
  ///
  /// In de, this message translates to:
  /// **'Schnitt zweier Ebenen'**
  String get flyAxisTwoPlB;

  /// No description provided for @flyAxisNormPtB.
  ///
  /// In de, this message translates to:
  /// **'Normal zu Ebene durch Punkt'**
  String get flyAxisNormPtB;

  /// No description provided for @flyAxisCircB.
  ///
  /// In de, this message translates to:
  /// **'Durch Mittelpunkt einer Rundkante'**
  String get flyAxisCircB;

  /// No description provided for @flyAxisRevB.
  ///
  /// In de, this message translates to:
  /// **'Durch Drehfläche oder -element'**
  String get flyAxisRevB;

  /// No description provided for @flyPointB.
  ///
  /// In de, this message translates to:
  /// **'Punkt'**
  String get flyPointB;

  /// Inventor DE: "Fixierter Punkt" — haengt an keiner Geometrie.
  ///
  /// In de, this message translates to:
  /// **'Fixierter Punkt'**
  String get flyPointGroundB;

  /// No description provided for @flyPointVertexB.
  ///
  /// In de, this message translates to:
  /// **'Auf Eckpunkt, Skizzenpunkt oder Mittelpunkt'**
  String get flyPointVertexB;

  /// No description provided for @flyPointThreePlB.
  ///
  /// In de, this message translates to:
  /// **'Schnitt dreier Ebenen'**
  String get flyPointThreePlB;

  /// No description provided for @flyPointTwoLnB.
  ///
  /// In de, this message translates to:
  /// **'Schnitt zweier Linien'**
  String get flyPointTwoLnB;

  /// No description provided for @flyPointPlLnB.
  ///
  /// In de, this message translates to:
  /// **'Schnitt Ebene/Fläche und Linie'**
  String get flyPointPlLnB;

  /// No description provided for @flyPointLoopB.
  ///
  /// In de, this message translates to:
  /// **'Mittelpunkt einer Kantenschleife'**
  String get flyPointLoopB;

  /// No description provided for @flyPointTorusB.
  ///
  /// In de, this message translates to:
  /// **'Mittelpunkt eines Torus'**
  String get flyPointTorusB;

  /// No description provided for @flyPointSphereB.
  ///
  /// In de, this message translates to:
  /// **'Mittelpunkt einer Kugel'**
  String get flyPointSphereB;

  /// No description provided for @flyPlaneB.
  ///
  /// In de, this message translates to:
  /// **'Ebene'**
  String get flyPlaneB;

  /// Inventor DE: "Versatz". Nicht "Offset" — Inventor uebersetzt es.
  ///
  /// In de, this message translates to:
  /// **'Versatz von Ebene'**
  String get flyPlaneOffsetB;

  /// No description provided for @flyPlaneParallelPtB.
  ///
  /// In de, this message translates to:
  /// **'Parallel zu Ebene durch Punkt'**
  String get flyPlaneParallelPtB;

  /// No description provided for @flyPlaneMid2B.
  ///
  /// In de, this message translates to:
  /// **'Mittelebene zwischen zwei Ebenen'**
  String get flyPlaneMid2B;

  /// No description provided for @flyPlaneMidTorusB.
  ///
  /// In de, this message translates to:
  /// **'Mittelebene eines Torus'**
  String get flyPlaneMidTorusB;

  /// No description provided for @flyPlaneAngleEdgeB.
  ///
  /// In de, this message translates to:
  /// **'Winkel zu Ebene um Kante'**
  String get flyPlaneAngleEdgeB;

  /// No description provided for @flyPlaneThreePtsB.
  ///
  /// In de, this message translates to:
  /// **'Drei Punkte'**
  String get flyPlaneThreePtsB;

  /// No description provided for @flyPlaneTwoEdgesB.
  ///
  /// In de, this message translates to:
  /// **'Zwei koplanare Kanten'**
  String get flyPlaneTwoEdgesB;

  /// No description provided for @flyPlaneTanSurfEdgeB.
  ///
  /// In de, this message translates to:
  /// **'Tangential zu Fläche durch Kante'**
  String get flyPlaneTanSurfEdgeB;

  /// No description provided for @flyPlaneTanSurfPtB.
  ///
  /// In de, this message translates to:
  /// **'Tangential zu Fläche durch Punkt'**
  String get flyPlaneTanSurfPtB;

  /// No description provided for @flyPlaneTanParallelB.
  ///
  /// In de, this message translates to:
  /// **'Tangential zu Fläche und parallel zu Ebene'**
  String get flyPlaneTanParallelB;

  /// No description provided for @flyPlaneNormalAxisB.
  ///
  /// In de, this message translates to:
  /// **'Normal zu Achse durch Punkt'**
  String get flyPlaneNormalAxisB;

  /// No description provided for @flyPlaneNormalCurveB.
  ///
  /// In de, this message translates to:
  /// **'Normal zu Kurve im Punkt'**
  String get flyPlaneNormalCurveB;

  /// Kopfzeile des Modellbrowsers. Inventor DE: "Modell".
  ///
  /// In de, this message translates to:
  /// **'Modell'**
  String get browserTitle;

  /// Browser-Knoten mit den drei Ursprungsebenen, -achsen und dem Mittelpunkt.
  ///
  /// In de, this message translates to:
  /// **'Ursprung'**
  String get nodeOrigin;

  /// Mit Bindestrich: im Deutschen wird die Buchstaben-Wort-Fuegung durchgekoppelt.
  ///
  /// In de, this message translates to:
  /// **'X-Achse'**
  String get nodeXAxis;

  /// No description provided for @nodeYAxis.
  ///
  /// In de, this message translates to:
  /// **'Y-Achse'**
  String get nodeYAxis;

  /// No description provided for @nodeCenterPoint.
  ///
  /// In de, this message translates to:
  /// **'Mittelpunkt'**
  String get nodeCenterPoint;

  /// Inventor DE: "Ende des Bauteils". das Bauteil, deshalb "des".
  ///
  /// In de, this message translates to:
  /// **'Ende des Bauteils'**
  String get nodeEndOfPart;

  /// die Skizze, deshalb "der".
  ///
  /// In de, this message translates to:
  /// **'Ende der Skizze'**
  String get nodeEndOfSketch;

  /// Browser-Knoten. "Volumenkörper" ist im Plural formgleich mit dem Singular, deshalb kein plural-Block.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper ({count})'**
  String nodeSolidBodies(int count);

  /// Ein Exemplar einer Anordnung. Inventor DE nennt die Kopien einer Anordnung "Exemplare".
  ///
  /// In de, this message translates to:
  /// **'Exemplar {index}'**
  String nodeOccurrence(int index);

  /// No description provided for @nodeAutoProjected.
  ///
  /// In de, this message translates to:
  /// **'Automatisch projiziert'**
  String get nodeAutoProjected;

  /// No description provided for @ctxUseAsTargetBody.
  ///
  /// In de, this message translates to:
  /// **'Als Zielkörper verwenden'**
  String get ctxUseAsTargetBody;

  /// No description provided for @ctxDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Körper löschen'**
  String get ctxDeleteBody;

  /// No description provided for @ctxEditSketch.
  ///
  /// In de, this message translates to:
  /// **'Skizze bearbeiten'**
  String get ctxEditSketch;

  /// Skizze fuer andere Elemente sichtbar machen. "Freigeben" im Sinne von Inventors "gemeinsam verwenden", nicht im Sinne von Teilen/Versenden.
  ///
  /// In de, this message translates to:
  /// **'Skizze freigeben'**
  String get ctxShareSketch;

  /// No description provided for @ctxUnshare.
  ///
  /// In de, this message translates to:
  /// **'Freigabe aufheben'**
  String get ctxUnshare;

  /// Inventor DE nennt ein Feature "Element".
  ///
  /// In de, this message translates to:
  /// **'Element bearbeiten'**
  String get ctxEditFeature;

  /// No description provided for @ctxMoveEosHere.
  ///
  /// In de, this message translates to:
  /// **'Ende der Skizze hierher'**
  String get ctxMoveEosHere;

  /// No description provided for @ctxDeleteLayer.
  ///
  /// In de, this message translates to:
  /// **'Layer löschen'**
  String get ctxDeleteLayer;

  /// No description provided for @ctxMoveToTop.
  ///
  /// In de, this message translates to:
  /// **'An den Anfang'**
  String get ctxMoveToTop;

  /// No description provided for @ctxMoveToEnd.
  ///
  /// In de, this message translates to:
  /// **'Ans Ende'**
  String get ctxMoveToEnd;

  /// No description provided for @ctxDeleteAllLayersBelow.
  ///
  /// In de, this message translates to:
  /// **'Alle Layer darunter löschen'**
  String get ctxDeleteAllLayersBelow;

  /// No description provided for @ctxDeleteAllFeaturesBelow.
  ///
  /// In de, this message translates to:
  /// **'Alle Elemente darunter löschen'**
  String get ctxDeleteAllFeaturesBelow;

  /// EOP bleibt als Kuerzel stehen — es steht so schon im englischen UI und der Browser-Knoten daneben schreibt es aus.
  ///
  /// In de, this message translates to:
  /// **'Alle Elemente unterhalb EOP löschen'**
  String get ctxDeleteAllFeaturesBelowEop;

  /// No description provided for @ctxCreateSketch.
  ///
  /// In de, this message translates to:
  /// **'Skizze erstellen'**
  String get ctxCreateSketch;

  /// No description provided for @ctxEditOffset.
  ///
  /// In de, this message translates to:
  /// **'Versatz bearbeiten'**
  String get ctxEditOffset;

  /// No description provided for @ctxFlipDirection.
  ///
  /// In de, this message translates to:
  /// **'Richtung umkehren'**
  String get ctxFlipDirection;

  /// No description provided for @ctxEditLayer.
  ///
  /// In de, this message translates to:
  /// **'Layer bearbeiten'**
  String get ctxEditLayer;

  /// No description provided for @ctxMoveSelectionHere.
  ///
  /// In de, this message translates to:
  /// **'Auswahl hierher verschieben'**
  String get ctxMoveSelectionHere;

  /// DXF bleibt DXF — Dateiformat, kein uebersetzbares Wort.
  ///
  /// In de, this message translates to:
  /// **'DXF exportieren…'**
  String get ctxExportDxf;

  /// No description provided for @ctxShareDxf.
  ///
  /// In de, this message translates to:
  /// **'DXF teilen…'**
  String get ctxShareDxf;

  /// No description provided for @dlgRenameBody.
  ///
  /// In de, this message translates to:
  /// **'Körper umbenennen'**
  String get dlgRenameBody;

  /// No description provided for @dlgRenameFeature.
  ///
  /// In de, this message translates to:
  /// **'Element umbenennen'**
  String get dlgRenameFeature;

  /// No description provided for @dlgRenameLayer.
  ///
  /// In de, this message translates to:
  /// **'Layer umbenennen'**
  String get dlgRenameLayer;

  /// No description provided for @dlgRenameSketch.
  ///
  /// In de, this message translates to:
  /// **'Skizze umbenennen'**
  String get dlgRenameSketch;

  /// Platzhaltertext im Eingabefeld.
  ///
  /// In de, this message translates to:
  /// **'Körpername'**
  String get phBodyName;

  /// No description provided for @phFeatureName.
  ///
  /// In de, this message translates to:
  /// **'Elementname'**
  String get phFeatureName;

  /// No description provided for @phLayerName.
  ///
  /// In de, this message translates to:
  /// **'Layername'**
  String get phLayerName;

  /// Fugen-n: Skizze + Name = Skizzenname.
  ///
  /// In de, this message translates to:
  /// **'Skizzenname'**
  String get phSketchName;

  /// No description provided for @phPartName.
  ///
  /// In de, this message translates to:
  /// **'Bauteilname'**
  String get phPartName;

  /// No description provided for @dlgNewSketch.
  ///
  /// In de, this message translates to:
  /// **'Neue Skizze'**
  String get dlgNewSketch;

  /// das Bauteil -> neues.
  ///
  /// In de, this message translates to:
  /// **'Neues Bauteil'**
  String get dlgNewPart;

  /// No description provided for @dlgDeleteAllFeaturesBelowEop.
  ///
  /// In de, this message translates to:
  /// **'Alle Elemente unterhalb EOP löschen?'**
  String get dlgDeleteAllFeaturesBelowEop;

  /// No description provided for @dlgDeleteEverythingBelowEos.
  ///
  /// In de, this message translates to:
  /// **'Alles unterhalb des Skizzenendes löschen?'**
  String get dlgDeleteEverythingBelowEos;

  /// Deutsche Anfuehrungszeichen: „unten-oben“, nicht die englischen “oben-oben”.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String dlgDeleteNamed(String name);

  /// Explizite Ein-/Mehrzahl statt zusammengesetzter Fragmente. Im Singular steht "Ein Element", nicht "1 Element".
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Element wird aus dem Bauteil entfernt.} other{{count} Elemente werden aus dem Bauteil entfernt.}}'**
  String msgFeaturesRemoved(int count);

  /// Bezug ist "der Körper", deshalb "sein/seine".
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Sein einziges Element wird aus dem Bauteil entfernt.} other{Seine {count} Elemente werden aus dem Bauteil entfernt.}}'**
  String msgBodyFeaturesRemoved(int count);

  /// Zwei Zaehlungen in einem Satz, beide mit eigener Ein-/Mehrzahl. "Layer" ist im Deutschen im Plural formgleich; der Unterschied steckt im Verb (wird/werden), was die plural-Bloecke mit abdecken.
  ///
  /// In de, this message translates to:
  /// **'{layers, plural, =1{Ein Layer wird entfernt} other{{layers} Layer werden entfernt}}, {entities, plural, =0{ohne Objekte darin.} =1{mit einem Objekt darin.} other{mit {entities} Objekten darin.}}'**
  String msgLayersAndEntitiesRemoved(int layers, int entities);

  /// No description provided for @msgFeatureAndSolidRemoved.
  ///
  /// In de, this message translates to:
  /// **'Das Element und sein Volumenkörper werden aus dem Bauteil entfernt.'**
  String get msgFeatureAndSolidRemoved;

  /// No description provided for @msgSketchDeleted.
  ///
  /// In de, this message translates to:
  /// **'Die Skizze und alles darin werden von diesem iPad entfernt. Das lässt sich nicht rückgängig machen.'**
  String get msgSketchDeleted;

  /// No description provided for @galleryNew2dSketch.
  ///
  /// In de, this message translates to:
  /// **'Neue 2D-Skizze'**
  String get galleryNew2dSketch;

  /// No description provided for @galleryNew3dPart.
  ///
  /// In de, this message translates to:
  /// **'Neues 3D-Bauteil'**
  String get galleryNew3dPart;

  /// No description provided for @galleryEmpty.
  ///
  /// In de, this message translates to:
  /// **'Auf  +  tippen für eine neue Skizze oder ein Bauteil'**
  String get galleryEmpty;

  /// No description provided for @errNameTaken.
  ///
  /// In de, this message translates to:
  /// **'Eine Skizze oder ein Bauteil mit diesem Namen existiert bereits.'**
  String get errNameTaken;

  /// No description provided for @qtReportBug.
  ///
  /// In de, this message translates to:
  /// **'Fehler melden'**
  String get qtReportBug;

  /// Inventor DE: eine Skizze ist "überbestimmt", wenn eine Abhaengigkeit zu viel gesetzt ist.
  ///
  /// In de, this message translates to:
  /// **'Überbestimmt'**
  String get hudOverConstrained;

  /// Referenzmass: wird von der Geometrie getrieben, treibt sie nicht. Inventor DE: "abhängige Bemaßung".
  ///
  /// In de, this message translates to:
  /// **'Abhängig'**
  String get hudDriven;

  /// No description provided for @msgWouldOverConstrain.
  ///
  /// In de, this message translates to:
  /// **'Diese Bemaßung würde die Skizze überbestimmen. Als abhängige Bemaßung (Referenzmaß) behalten?'**
  String get msgWouldOverConstrain;

  /// Zurueck in die Ausgangsansicht des 3D-Fensters.
  ///
  /// In de, this message translates to:
  /// **'Startansicht'**
  String get menuHomeView;

  /// No description provided for @msgCouldNotSave.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ließ sich nicht speichern.'**
  String msgCouldNotSave(String name);

  /// No description provided for @msgSavedTo.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert in {folder}'**
  String msgSavedTo(String folder);

  /// No description provided for @msgSavedNamed.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ gespeichert'**
  String msgSavedNamed(String name);

  /// No description provided for @msgCannotOpenKind.
  ///
  /// In de, this message translates to:
  /// **'Prototype kann diese Art von Datei nicht öffnen.'**
  String get msgCannotOpenKind;

  /// No description provided for @msgNotAPrototypeDoc.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist kein Prototype-Dokument (oder ist beschädigt).'**
  String get msgNotAPrototypeDoc;

  /// No description provided for @msgCouldNotOpenDoc.
  ///
  /// In de, this message translates to:
  /// **'Dieses Dokument ließ sich nicht öffnen.'**
  String get msgCouldNotOpenDoc;

  /// No description provided for @msgCouldNotOpenFile.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ließ sich nicht öffnen.'**
  String get msgCouldNotOpenFile;

  /// No description provided for @msgCouldNotImportFile.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ließ sich nicht importieren.'**
  String get msgCouldNotImportFile;

  /// No description provided for @msgCouldNotImportImage.
  ///
  /// In de, this message translates to:
  /// **'Das Bild ließ sich nicht importieren.'**
  String get msgCouldNotImportImage;

  /// No description provided for @msgCouldNotImportDxf.
  ///
  /// In de, this message translates to:
  /// **'Die DXF-Datei ließ sich nicht importieren.'**
  String get msgCouldNotImportDxf;

  /// No description provided for @msgCouldNotReadDxf.
  ///
  /// In de, this message translates to:
  /// **'Die DXF-Datei ließ sich nicht lesen.'**
  String get msgCouldNotReadDxf;

  /// No description provided for @msgDxfNoSupportedEntities.
  ///
  /// In de, this message translates to:
  /// **'Die DXF-Datei enthält keine unterstützten Objekte.'**
  String get msgDxfNoSupportedEntities;

  /// der Layer -> "ihn".
  ///
  /// In de, this message translates to:
  /// **'„{layer}“ liegt unter dem Skizzenende — die Marke nach unten ziehen, um ihn zurückzuholen.'**
  String msgLayerBelowEos(String layer);

  /// No description provided for @msgLayerLockedEdit.
  ///
  /// In de, this message translates to:
  /// **'„{layer}“ ist gesperrt — zum Bearbeiten entsperren.'**
  String msgLayerLockedEdit(String layer);

  /// No description provided for @msgLayerLocked.
  ///
  /// In de, this message translates to:
  /// **'„{layer}“ ist gesperrt.'**
  String msgLayerLocked(String layer);

  /// No description provided for @msgTargetBelowEos.
  ///
  /// In de, this message translates to:
  /// **'„{layer}“ liegt unter dem Skizzenende.'**
  String msgTargetBelowEos(String layer);

  /// No description provided for @msgDefaultLayerNoRename.
  ///
  /// In de, this message translates to:
  /// **'Der Standardlayer „0“ kann nicht umbenannt werden.'**
  String get msgDefaultLayerNoRename;

  /// No description provided for @msgZeroReserved.
  ///
  /// In de, this message translates to:
  /// **'„0“ ist für den Standardlayer reserviert.'**
  String get msgZeroReserved;

  /// No description provided for @msgLayerExists.
  ///
  /// In de, this message translates to:
  /// **'Ein Layer namens „{name}“ existiert bereits.'**
  String msgLayerExists(String name);

  /// No description provided for @msgDefaultLayerNoDelete.
  ///
  /// In de, this message translates to:
  /// **'Der Standardlayer „0“ kann nicht gelöscht werden.'**
  String get msgDefaultLayerNoDelete;

  /// No description provided for @msgEnterLayerToEdit.
  ///
  /// In de, this message translates to:
  /// **'Layer betreten: im Modellbrowser doppelt antippen.'**
  String get msgEnterLayerToEdit;

  /// No description provided for @msgEnterLayerToSketch.
  ///
  /// In de, this message translates to:
  /// **'Layer betreten, um zu zeichnen: im Modellbrowser doppelt antippen.'**
  String get msgEnterLayerToSketch;

  /// No description provided for @msgSelectThenDelete.
  ///
  /// In de, this message translates to:
  /// **'Erst Geometrie wählen, dann löschen.'**
  String get msgSelectThenDelete;

  /// No description provided for @msgSelectThenMoveToLayer.
  ///
  /// In de, this message translates to:
  /// **'Erst Geometrie wählen, dann auf einen Layer verschieben.'**
  String get msgSelectThenMoveToLayer;

  /// No description provided for @msgSelectThenToggle.
  ///
  /// In de, this message translates to:
  /// **'Erst Geometrie wählen, dann {what} umschalten.'**
  String msgSelectThenToggle(String what);

  /// No description provided for @msgNothingBelowEos.
  ///
  /// In de, this message translates to:
  /// **'Unter dem Skizzenende liegt nichts.'**
  String get msgNothingBelowEos;

  /// No description provided for @msgNothingBelowEop.
  ///
  /// In de, this message translates to:
  /// **'Unter dem Bauteilende liegt nichts.'**
  String get msgNothingBelowEop;

  /// STEP bleibt STEP: Dateiformat.
  ///
  /// In de, this message translates to:
  /// **'Kein 3D-Kern verbunden — der STEP-Export braucht den Gerätebuild.'**
  String get msgNoKernelStep;

  /// No description provided for @msgNothingToExportYet.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts zu exportieren — zuerst ein Profil extrudieren.'**
  String get msgNothingToExportYet;

  /// {error} kommt aus dem Kernel und bleibt in dessen Sprache — er wird nicht uebersetzt.
  ///
  /// In de, this message translates to:
  /// **'STEP-Export fehlgeschlagen: {error}'**
  String msgStepExportFailed(String error);

  /// No description provided for @msgStepExportEmpty.
  ///
  /// In de, this message translates to:
  /// **'Der STEP-Export hat eine leere Datei erzeugt.'**
  String get msgStepExportEmpty;

  /// No description provided for @msgExportedWithout.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ohne {names} exportiert — es ließ sich nicht bauen.} other{Ohne {names} exportiert — sie ließen sich nicht bauen.}}'**
  String msgExportedWithout(int count, String names);

  /// No description provided for @msgNothingToExportEmpty.
  ///
  /// In de, this message translates to:
  /// **'Nichts zu exportieren — „{name}“ ist leer.'**
  String msgNothingToExportEmpty(String name);

  /// No description provided for @msgDxfExportFailed.
  ///
  /// In de, this message translates to:
  /// **'DXF-Export fehlgeschlagen.'**
  String get msgDxfExportFailed;

  /// No description provided for @msgOpenPartForStep.
  ///
  /// In de, this message translates to:
  /// **'Zuerst ein Bauteil öffnen — STEP-Importe kommen als Volumenkörper an.'**
  String get msgOpenPartForStep;

  /// No description provided for @msgNoSolidsInStep.
  ///
  /// In de, this message translates to:
  /// **'Keine Volumenkörper in dieser STEP-Datei ({error}).'**
  String msgNoSolidsInStep(String error);

  /// "Körper" ist im Plural formgleich; der Unterschied steckt im Zahlwort, deshalb trotzdem zwei Formen.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Körper importiert.} other{{count} Körper importiert.}}'**
  String msgImportedBodies(int count);

  /// Gegenstück zu msgOpenPartForStep. "Netz" ist der übliche deutsche CAD-Begriff für ein Dreiecksnetz (STL/OBJ/3MF).
  ///
  /// In de, this message translates to:
  /// **'Zuerst ein Bauteil öffnen — ein Netz kommt als Volumenkörper an.'**
  String get msgOpenPartForMesh;

  /// Wie msgNoKernelStep: auf dem Host ist kein OCCT gelinkt.
  ///
  /// In de, this message translates to:
  /// **'Kein 3D-Kern verbunden — ein Netz umzuwandeln braucht den Gerätebuild.'**
  String get msgNoKernelMesh;

  /// Null Bytes.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist leer.'**
  String get msgMeshEmpty;

  /// Zwischen Auswahl und Lesen verschwunden — bei iCloud-Dateien keine Seltenheit.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei gibt es nicht mehr.'**
  String get msgMeshMissing;

  /// Rechte, ein nicht geladener iCloud-Platzhalter. Der OS-Grund geht ins Log, nicht in die Meldung.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ließ sich nicht lesen.'**
  String get msgMeshUnreadable;

  /// Titel der nativen Fortschrittskarte, waehrend ein Netz umgewandelt wird.
  ///
  /// In de, this message translates to:
  /// **'Netz wird umgewandelt'**
  String get msgMeshConvertTitle;

  /// Titel der Fortschrittskarte auf dem 1:1-Weg, wo nichts umgewandelt, sondern nur gebaut wird.
  ///
  /// In de, this message translates to:
  /// **'Dreiecke werden übernommen'**
  String get msgMeshBuildTitle;

  /// Untertitel der Fortschrittskarte auf dem 1:1-Weg.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Dreieck}other{{count} Dreiecke}}'**
  String msgMeshBuilding(int count);

  /// Titel des nativen Dialogs beim Import einer STL/OBJ/3MF-Datei.
  ///
  /// In de, this message translates to:
  /// **'Wie soll dieses Modell importiert werden?'**
  String get askMeshImportTitle;

  /// Was in der Datei steckt, damit die Wahl auf Zahlen und nicht auf Vermutungen beruht. {size} ist die Diagonale.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Dreieck}other{{count} Dreiecke}}, {size} mm groß.'**
  String askMeshImportBody(int count, String size);

  /// Die erste Wahl im Import-Dialog: Rueckfuehrung in echte Flaechen.
  ///
  /// In de, this message translates to:
  /// **'Als CAD-Körper'**
  String get askMeshImportConvert;

  /// Was die Umwandlung kann und was sie kostet.
  ///
  /// In de, this message translates to:
  /// **'Flächen zum Verrunden, Bemaßen und Bearbeiten. Dauert einen Moment.'**
  String get askMeshImportConvertWhy;

  /// Die zweite Wahl im Import-Dialog: das Netz unveraendert als Koerper.
  ///
  /// In de, this message translates to:
  /// **'Als Netz'**
  String get askMeshImportFaceted;

  /// Was der 1:1-Weg kann und was er nicht kann.
  ///
  /// In de, this message translates to:
  /// **'Genau wie die Datei, ohne Umwandlung. Kaum bearbeitbar.'**
  String get askMeshImportFacetedWhy;

  /// Statt der zweiten Wahl, wenn das Netz ueber kMaxFacetedTriangles liegt. Die Wahl wird gar nicht erst angeboten, weil der Kern sie danach ablehnen wuerde.
  ///
  /// In de, this message translates to:
  /// **'Für „Als Netz“ sind das zu viele Dreiecke (Grenze {limit}).'**
  String askMeshImportTooManyFaceted(int limit);

  /// Fortschrittskarte, Schritt 1 (OCCT_MS_WELDING).
  ///
  /// In de, this message translates to:
  /// **'Modell wird gelesen'**
  String get meshStageReading;

  /// Schritt 2 (OCCT_MS_SEGMENTING).
  ///
  /// In de, this message translates to:
  /// **'Flächen werden gesucht'**
  String get meshStageFinding;

  /// Schritt 3 (OCCT_MS_FITTING). Der laengste Schritt.
  ///
  /// In de, this message translates to:
  /// **'Flächen werden angepasst'**
  String get meshStageFitting;

  /// Schritt 4 (OCCT_MS_FREEFORM).
  ///
  /// In de, this message translates to:
  /// **'Rundungen werden geformt'**
  String get meshStageShaping;

  /// Schritt 5 und 7 (OCCT_MS_BUILDING, OCCT_MS_FACETED).
  ///
  /// In de, this message translates to:
  /// **'Flächen werden gebaut'**
  String get meshStageBuilding;

  /// Schritt 6 (OCCT_MS_SEWING). Nicht „vernaeht“ — das ist der Algorithmus, nicht die Sache.
  ///
  /// In de, this message translates to:
  /// **'Wird fertiggestellt'**
  String get meshStageFinishing;

  /// Schritt 8 (OCCT_MS_MERGING).
  ///
  /// In de, this message translates to:
  /// **'Wird vereinfacht'**
  String get meshStageSimplifying;

  /// Der Abbrechen-Knopf, nachdem er gedrueckt wurde. Bis zu vier Sekunden lang, weil OCCTs Flaechen-Zusammenfassung sich nicht unterbrechen laesst.
  ///
  /// In de, this message translates to:
  /// **'Wird abgebrochen …'**
  String get actionCancelling;

  /// Nach einem Abbruch. Kein Fehler — deshalb ohne Fehlerton und ohne Details.
  ///
  /// In de, this message translates to:
  /// **'Import abgebrochen.'**
  String get msgMeshImportCancelled;

  /// Formal in Ordnung, aber ohne Dreiecke: ein STL nur aus entarteten Facetten, ein OBJ ohne f-Zeilen.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei enthält keine brauchbare Geometrie.'**
  String get msgMeshNoGeometry;

  /// Ein Punkt mit zwei Koordinaten, ein Dreieck ohne dritte Ecke.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist beschädigt — ein Datensatz bricht ab.'**
  String get msgMeshTruncated;

  /// OBJ und 3MF verweisen per Index auf Punkte; ein Verweis ins Leere ist ein kaputtes Modell, kein leerer.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist beschädigt — eine Fläche nennt Punkt {index}, den es nicht gibt.'**
  String msgMeshBadIndex(String index);

  /// 3MF ist ein ZIP. Ist es keines, hilft kein Weiterlesen.
  ///
  /// In de, this message translates to:
  /// **'Diese 3MF-Datei ist kein lesbares Archiv.'**
  String get msgMeshNotAnArchive;

  /// ZIP in Ordnung, aber ohne .model-Teil darin.
  ///
  /// In de, this message translates to:
  /// **'Diese 3MF-Datei enthält kein Modell.'**
  String get msgMeshNoModel;

  /// Deutsche Anführungszeichen. Abgelehnt statt geraten: eine geratene Einheit skaliert das Bauteil stillschweigend.
  ///
  /// In de, this message translates to:
  /// **'Diese 3MF-Datei nutzt die unbekannte Einheit „{unit}“.'**
  String msgMeshUnknownUnit(String unit);

  /// Die brauchbarste Fehlermeldung des Umwandlers: „nicht dicht“ kann man reparieren, „Vernähen fehlgeschlagen“ nicht.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Dieses Netz ist nicht dicht (eine offene Kante) und kann kein Volumenkörper werden.} other{Dieses Netz ist nicht dicht ({count} offene Kanten) und kann kein Volumenkörper werden.}}'**
  String msgMeshNotWatertight(int count);

  /// Wenn der Kern keinen Grund nennt.
  ///
  /// In de, this message translates to:
  /// **'Das Netz ließ sich nicht umwandeln.'**
  String get msgMeshConvertFailed;

  /// Der Grund kommt aus dem Kern und bleibt englisch — er ist eine Diagnose, keine Oberflächenmeldung.
  ///
  /// In de, this message translates to:
  /// **'Das Netz ließ sich nicht umwandeln: {error}'**
  String msgMeshConvertFailedWhy(String error);

  /// Der Körper wird beim Öffnen aus seiner Datei neu gelesen; ohne diese Datei wäre er nach dem Neuöffnen leer.
  ///
  /// In de, this message translates to:
  /// **'Das Netz wurde umgewandelt, aber nicht gespeichert.'**
  String get msgMeshNotSaved;

  /// Gezählt werden die als Ebene, Zylinder, Kegel, Kugel oder Torus ERKANNTEN Flächen — das ist die Zahl, die verrät, ob sich das Modell danach noch abrunden lässt. Die Aufschlüsselung nach Art steht im Log.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Importiert: eine Fläche erkannt.} other{Importiert: {count} Flächen erkannt.}}'**
  String msgMeshImported(int count);

  /// Der ehrliche Fall: es kam etwas an, aber nur Dreiecke.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Als eine Fläche importiert — keine Flächenform erkannt.} other{Als {count} Flächen importiert — keine Flächenform erkannt.}}'**
  String msgMeshImportedFacetedOnly(int count);

  /// Zusatz zu msgMeshImported. Getrennter Satz statt angehängtem Fragment, damit beide Sprachen ihre eigene Wortstellung behalten.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Bereich blieb als Dreiecke.} other{{count} Bereiche blieben als Dreiecke.}}'**
  String msgMeshImportedFaceted(int count);

  /// Das Netz hatte Löcher; daraus kann nur ein Flächenkörper werden, und das muss dastehen.
  ///
  /// In de, this message translates to:
  /// **'Nicht geschlossen — ein Flächenkörper.'**
  String get msgMeshImportedOpen;

  /// Vor dem Lesen abgefangen: eine Datei dieser Groesse einzulesen wuerde die App abschiessen, nicht bremsen.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei hat {size} MB; Prototype liest Netze bis {limit} MB.'**
  String msgMeshFileTooLarge(int size, int limit);

  /// Die Umwandlung laeuft auf dem UI-Thread, weil der Kern einfaedig ist; die Grenze haelt die Wartezeit endlich.
  ///
  /// In de, this message translates to:
  /// **'Dieses Netz hat {count} Dreiecke; Prototype wandelt bis {limit} um.'**
  String msgMeshTooManyTriangles(int count, int limit);

  /// Steht waehrend der Umwandlung auf dem Schirm. Der Kern blockiert den UI-Thread, also ist dies das einzige Lebenszeichen, das der Nutzer bekommt.
  ///
  /// In de, this message translates to:
  /// **'{count} Dreiecke werden umgewandelt …'**
  String msgMeshConverting(int count);

  /// No description provided for @msgImportedEntities.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Objekt importiert.} other{{count} Objekte importiert.}}'**
  String msgImportedEntities(int count);

  /// No description provided for @msgNothingToUndo.
  ///
  /// In de, this message translates to:
  /// **'Nichts rückgängig zu machen.'**
  String get msgNothingToUndo;

  /// No description provided for @msgNothingToRedo.
  ///
  /// In de, this message translates to:
  /// **'Nichts zu wiederholen.'**
  String get msgNothingToRedo;

  /// No description provided for @msgSelectPlaneForSketch.
  ///
  /// In de, this message translates to:
  /// **'Ebene wählen, auf der die Skizze entstehen soll.'**
  String get msgSelectPlaneForSketch;

  /// No description provided for @msgUsedByFeature.
  ///
  /// In de, this message translates to:
  /// **'{name} wird von einem Element verwendet — dieses zuerst löschen.'**
  String msgUsedByFeature(String name);

  /// No description provided for @msgSelectPlaneToOffsetFrom.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder Fläche wählen, von der aus versetzt wird.'**
  String get msgSelectPlaneToOffsetFrom;

  /// No description provided for @msgSelectFirstParallel.
  ///
  /// In de, this message translates to:
  /// **'Erste von zwei parallelen Ebenen oder Flächen wählen.'**
  String get msgSelectFirstParallel;

  /// No description provided for @msgSelectSecondParallel.
  ///
  /// In de, this message translates to:
  /// **'Zweite parallele Ebene oder Fläche wählen.'**
  String get msgSelectSecondParallel;

  /// No description provided for @msgNotParallel.
  ///
  /// In de, this message translates to:
  /// **'Diese beiden sind nicht parallel — eine parallele Ebene oder Fläche wählen.'**
  String get msgNotParallel;

  /// No description provided for @msgPlaneHasNoOffset.
  ///
  /// In de, this message translates to:
  /// **'{name}: Diese Ebene hat keinen Versatz zum Ziehen.'**
  String msgPlaneHasNoOffset(String name);

  /// No description provided for @msgDragAwayToSetOffset.
  ///
  /// In de, this message translates to:
  /// **'Von der Ebene wegziehen, um den Versatz zu setzen.'**
  String get msgDragAwayToSetOffset;

  /// Nur ein Doppelpunkt-Muster. {definition} ist der GESPEICHERTE Definitionssatz eines Arbeitselements ("Through X Axis and Y Axis") und bleibt englisch — er steht so in der .ptp-Datei und darf nicht uebersetzt werden, sonst aendert sich das Dateiformat. Siehe S12-i18n.md.
  ///
  /// In de, this message translates to:
  /// **'{name}: {definition}'**
  String msgNameColonDef(String name, String definition);

  /// No description provided for @msgFaceEditNeedsBody.
  ///
  /// In de, this message translates to:
  /// **'{command} braucht zuerst einen Volumenkörper.'**
  String msgFaceEditNeedsBody(String command);

  /// No description provided for @msgSetScaleThenApply.
  ///
  /// In de, this message translates to:
  /// **'Skalierungsfaktor setzen, dann übernehmen.'**
  String get msgSetScaleThenApply;

  /// {verb} steht hier als substantiviertes Verb ("zum Verschieben"), deshalb gross und mit "zum".
  ///
  /// In de, this message translates to:
  /// **'Flächen zum {verb} wählen.'**
  String msgSelectFacesTo(String verb);

  /// No description provided for @msgSelectAtLeastOneFace.
  ///
  /// In de, this message translates to:
  /// **'Mindestens eine Fläche wählen.'**
  String get msgSelectAtLeastOneFace;

  /// No description provided for @msgNothingToEditBuildBody.
  ///
  /// In de, this message translates to:
  /// **'Nichts zu bearbeiten — zuerst einen Körper bauen.'**
  String get msgNothingToEditBuildBody;

  /// {error} ist die Kernel-Meldung und bleibt in deren Sprache.
  ///
  /// In de, this message translates to:
  /// **'{name}: {error}'**
  String msgFeatureError(String name, String error);

  /// Ersetzt das englische "face(s)" mit Klammer-s, das im Deutschen gar nicht erst funktioniert.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{{name}: Eine gewählte Fläche existiert nicht mehr.} other{{name}: {count} gewählte Flächen existieren nicht mehr.}}'**
  String msgLostFaces(String name, int count);

  /// No description provided for @msgCannotCreateFeature.
  ///
  /// In de, this message translates to:
  /// **'Das Element lässt sich nicht erstellen.'**
  String get msgCannotCreateFeature;

  /// No description provided for @msgNoKernelFeatureStored.
  ///
  /// In de, this message translates to:
  /// **'Kein 3D-Kern verbunden — Element gespeichert, Volumenkörper steht aus.'**
  String get msgNoKernelFeatureStored;

  /// No description provided for @msgHoleNeedsSketch.
  ///
  /// In de, this message translates to:
  /// **'Eine Bohrung sitzt auf Skizzenpunkten — zuerst eine Skizze anlegen.'**
  String get msgHoleNeedsSketch;

  /// No description provided for @msgHoleNeedsBody.
  ///
  /// In de, this message translates to:
  /// **'Eine Bohrung braucht einen Körper zum Bohren.'**
  String get msgHoleNeedsBody;

  /// No description provided for @msgTapSketchPointsForHoles.
  ///
  /// In de, this message translates to:
  /// **'Skizzenpunkte für die Bohrungen antippen.'**
  String get msgTapSketchPointsForHoles;

  /// No description provided for @msgHoleCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eine Bohrung — Punkt antippen zum Hinzufügen oder Entfernen.} other{{count} Bohrungen — Punkt antippen zum Hinzufügen oder Entfernen.}}'**
  String msgHoleCount(int count);

  /// No description provided for @msgHolesSameSketch.
  ///
  /// In de, this message translates to:
  /// **'Alle Bohrungen eines Elements stammen aus derselben Skizze.'**
  String get msgHolesSameSketch;

  /// No description provided for @msgDiameterPositive.
  ///
  /// In de, this message translates to:
  /// **'Der Durchmesser muss eine Zahl größer als 0 sein.'**
  String get msgDiameterPositive;

  /// No description provided for @msgDepthPositive.
  ///
  /// In de, this message translates to:
  /// **'Die Tiefe muss eine Zahl größer als 0 sein.'**
  String get msgDepthPositive;

  /// {kind} ist "Senkung"/"Plansenkung" — weiblich, deshalb "die … muss".
  ///
  /// In de, this message translates to:
  /// **'Die {kind} muss weiter als die Bohrung und tiefer als 0 sein.'**
  String msgCboreWiderThanHole(String kind);

  /// No description provided for @msgCsinkAngle.
  ///
  /// In de, this message translates to:
  /// **'Die Senkung muss weiter als die Bohrung sein, mit einem Winkel zwischen 0 und 180 Grad.'**
  String get msgCsinkAngle;

  /// No description provided for @msgSplitNeedsBody.
  ///
  /// In de, this message translates to:
  /// **'Trennen schneidet einen Körper — es gibt noch keinen.'**
  String get msgSplitNeedsBody;

  /// No description provided for @msgSelectTrimPlane.
  ///
  /// In de, this message translates to:
  /// **'Ebene wählen, mit der geschnitten wird.'**
  String get msgSelectTrimPlane;

  /// No description provided for @msgTrimmingWith.
  ///
  /// In de, this message translates to:
  /// **'Schnitt mit {label}. OK behält die Seite, die stehen bleibt.'**
  String msgTrimmingWith(String label);

  /// Vereinigen / Differenz / Schnittmenge sind Inventors drei Kombinationsarten.
  ///
  /// In de, this message translates to:
  /// **'Kombinieren braucht zwei Körper — es vereinigt, schneidet oder verschneidet einen mit einem anderen.'**
  String get msgCombineNeedsTwoBodies;

  /// No description provided for @msgTapBodyToKeep.
  ///
  /// In de, this message translates to:
  /// **'Körper antippen, der BLEIBT.'**
  String get msgTapBodyToKeep;

  /// No description provided for @msgTapBodiesToCombine.
  ///
  /// In de, this message translates to:
  /// **'Körper antippen, die in {name} eingehen.'**
  String msgTapBodiesToCombine(String name);

  /// No description provided for @msgThatIsBaseBody.
  ///
  /// In de, this message translates to:
  /// **'Das ist der Basiskörper — einen anderen zum Kombinieren wählen.'**
  String get msgThatIsBaseBody;

  /// No description provided for @msgPickKeepThenCombine.
  ///
  /// In de, this message translates to:
  /// **'Erst den Körper wählen, der bleibt, dann die Körper, die hineingerechnet werden.'**
  String get msgPickKeepThenCombine;

  /// No description provided for @msgSelectTargetBody.
  ///
  /// In de, this message translates to:
  /// **'Zielkörper wählen — in 3D oder im Browser antippen.'**
  String get msgSelectTargetBody;

  /// M248 — die Anordnung im Baugruppen-Menüband, ohne platzierte Komponente.
  ///
  /// In de, this message translates to:
  /// **'{kind} braucht eine Komponente zum Kopieren — zuerst eine platzieren.'**
  String msgPatternNeedsComponent(String kind);

  /// M248 — die Vorschau setzt die Anordnung wirklich; eine kleinere Anzahl löscht Elemente und deren Beziehungen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Beziehung wurde mit den entfallenen Elementen gelöscht — Abbrechen stellt sie wieder her.} other{{n} Beziehungen wurden mit den entfallenen Elementen gelöscht — Abbrechen stellt sie wieder her.}}'**
  String msgRelationshipsDropped(int n);

  /// M248 — der Aufruf, wenn die Auswahl für die Ausgangskomponenten scharf ist.
  ///
  /// In de, this message translates to:
  /// **'Komponente zum Anordnen antippen.'**
  String get msgTapComponentToPattern;

  /// M248 — eine Anordnung ihrer eigenen Ausgabe wäre ein Zyklus.
  ///
  /// In de, this message translates to:
  /// **'Ein Anordnungselement kann nicht angeordnet werden — die Ausgangskomponente wählen.'**
  String get msgCannotPatternAnElement;

  /// M248 — Kopieren wirkt auf die aktuelle Auswahl.
  ///
  /// In de, this message translates to:
  /// **'Komponente zum Kopieren wählen.'**
  String get msgSelectComponentToCopy;

  /// M248 — die Kopie wäre eine gewöhnliche Komponente, die nur wie ein Element aussieht.
  ///
  /// In de, this message translates to:
  /// **'Ein Anordnungselement kann nicht kopiert werden — die Ausgangskomponente kopieren oder die Anzahl ändern.'**
  String get msgCannotCopyAnElement;

  /// No description provided for @msgPatternNeedsFeature.
  ///
  /// In de, this message translates to:
  /// **'{kind} braucht ein Element zum Kopieren — zuerst eines bauen.'**
  String msgPatternNeedsFeature(String kind);

  /// No description provided for @msgSelectFeatures.
  ///
  /// In de, this message translates to:
  /// **'Elemente wählen — eine Fläche in 3D oder eine Zeile im Browser antippen.'**
  String get msgSelectFeatures;

  /// No description provided for @msgTapStraightOrCircularEdge.
  ///
  /// In de, this message translates to:
  /// **'Gerade Kante, Rundkante oder Ursprungsachse antippen.'**
  String get msgTapStraightOrCircularEdge;

  /// No description provided for @msgTapCircularOrStraightEdge.
  ///
  /// In de, this message translates to:
  /// **'Rundkante, gerade Kante oder Ursprungsachse antippen.'**
  String get msgTapCircularOrStraightEdge;

  /// No description provided for @msgTapPlanarFace.
  ///
  /// In de, this message translates to:
  /// **'Planare Fläche, Arbeitsebene oder Ursprungsebene antippen.'**
  String get msgTapPlanarFace;

  /// No description provided for @msgTapSketchForOccurrences.
  ///
  /// In de, this message translates to:
  /// **'Die Skizze antippen, deren Punkte die Exemplare setzen.'**
  String get msgTapSketchForOccurrences;

  /// No description provided for @msgTapSketchPointOfOriginal.
  ///
  /// In de, this message translates to:
  /// **'Den Skizzenpunkt antippen, auf dem das Original sitzt.'**
  String get msgTapSketchPointOfOriginal;

  /// No description provided for @msgTapCurveStart.
  ///
  /// In de, this message translates to:
  /// **'Den Punkt auf der Kurve antippen, an dem die Anordnung beginnt.'**
  String get msgTapCurveStart;

  /// No description provided for @msgTapFaceToFollow.
  ///
  /// In de, this message translates to:
  /// **'Die Fläche antippen, der die Exemplare folgen sollen.'**
  String get msgTapFaceToFollow;

  /// No description provided for @msgTapSolidBodyToPattern.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper antippen, der angeordnet wird.'**
  String get msgTapSolidBodyToPattern;

  /// No description provided for @msgPickSolidBodyToPattern.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper wählen, der angeordnet wird.'**
  String get msgPickSolidBodyToPattern;

  /// No description provided for @msgBuiltAfterPattern.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ entsteht nach dieser Anordnung, deshalb kann sie es nicht kopieren.'**
  String msgBuiltAfterPattern(String name);

  /// No description provided for @msgEdgeNoDirection.
  ///
  /// In de, this message translates to:
  /// **'Diese Kante gibt keine Richtung vor.'**
  String get msgEdgeNoDirection;

  /// No description provided for @msgPickCurveFirst.
  ///
  /// In de, this message translates to:
  /// **'Zuerst die Kurve für diese Richtung wählen.'**
  String get msgPickCurveFirst;

  /// No description provided for @msgCurveGone.
  ///
  /// In de, this message translates to:
  /// **'Diese Kurve ist nicht mehr vorhanden.'**
  String get msgCurveGone;

  /// No description provided for @msgSketchHasNoPoints.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ enthält keine Skizzenpunkte — eine skizzengesteuerte Anordnung setzt je Punkt ein Exemplar.'**
  String msgSketchHasNoPoints(String name);

  /// No description provided for @msgBasePointMustBeOf.
  ///
  /// In de, this message translates to:
  /// **'Der Basispunkt muss ein Punkt von „{name}“ sein.'**
  String msgBasePointMustBeOf(String name);

  /// No description provided for @msgCannotCreatePattern.
  ///
  /// In de, this message translates to:
  /// **'Die Anordnung lässt sich nicht erstellen.'**
  String get msgCannotCreatePattern;

  /// No description provided for @msgPatternedByBroken.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{„{name}“ wurde von {names} angeordnet — diese Anordnung ist jetzt defekt. Rückgängig stellt sie wieder her.} other{„{name}“ wurde von {names} angeordnet — diese Anordnungen sind jetzt defekt. Rückgängig stellt sie wieder her.}}'**
  String msgPatternedByBroken(String name, String names, int count);

  /// No description provided for @msgTapCurveToSweep.
  ///
  /// In de, this message translates to:
  /// **'Kurve antippen, entlang der gezogen wird.'**
  String get msgTapCurveToSweep;

  /// No description provided for @msgCurveNoLength.
  ///
  /// In de, this message translates to:
  /// **'Diese Kurve hat keine Länge.'**
  String get msgCurveNoLength;

  /// No description provided for @msgTapSectionsInOrder.
  ///
  /// In de, this message translates to:
  /// **'Querschnitte der Reihe nach antippen.'**
  String get msgTapSectionsInOrder;

  /// No description provided for @msgTapAxisLine.
  ///
  /// In de, this message translates to:
  /// **'Skizzenlinie oder Ursprungsachse antippen, die als Achse dient.'**
  String get msgTapAxisLine;

  /// No description provided for @msgPickAxisLine.
  ///
  /// In de, this message translates to:
  /// **'Skizzenlinie oder Ursprungsachse wählen.'**
  String get msgPickAxisLine;

  /// No description provided for @msgAxisNotInSketchPlane.
  ///
  /// In de, this message translates to:
  /// **'Diese Achse liegt nicht in der Skizzenebene.'**
  String get msgAxisNotInSketchPlane;

  /// No description provided for @msgLineGone.
  ///
  /// In de, this message translates to:
  /// **'Diese Linie ist nicht mehr vorhanden.'**
  String get msgLineGone;

  /// No description provided for @msgAxisMustBeStraight.
  ///
  /// In de, this message translates to:
  /// **'Die Achse muss eine gerade Linie sein.'**
  String get msgAxisMustBeStraight;

  /// No description provided for @msgLineNoLength.
  ///
  /// In de, this message translates to:
  /// **'Diese Linie hat keine Länge.'**
  String get msgLineNoLength;

  /// No description provided for @msgCreateSketchFirstExtrude.
  ///
  /// In de, this message translates to:
  /// **'Zuerst eine 2D-Skizze anlegen — die Extrusion braucht ein geschlossenes Profil.'**
  String get msgCreateSketchFirstExtrude;

  /// No description provided for @msgProfilesSameSketch.
  ///
  /// In de, this message translates to:
  /// **'Alle Profile einer Extrusion stammen aus derselben Skizze.'**
  String get msgProfilesSameSketch;

  /// No description provided for @msgPickProfile.
  ///
  /// In de, this message translates to:
  /// **'Mindestens ein Profil zum Extrudieren wählen.'**
  String get msgPickProfile;

  /// No description provided for @msgSelectTerminateFace.
  ///
  /// In de, this message translates to:
  /// **'Die Fläche wählen, auf der es enden soll.'**
  String get msgSelectTerminateFace;

  /// No description provided for @msgPickOneEdgeFirst.
  ///
  /// In de, this message translates to:
  /// **'Zuerst eine Kante wählen, damit der Körper feststeht.'**
  String get msgPickOneEdgeFirst;

  /// No description provided for @msgBodyHasNoEdges.
  ///
  /// In de, this message translates to:
  /// **'Dieser Körper hat keine wählbaren Kanten.'**
  String get msgBodyHasNoEdges;

  /// No description provided for @msgSelectEdges.
  ///
  /// In de, this message translates to:
  /// **'Kanten wählen — antippen fügt hinzu, nochmals antippen entfernt.'**
  String get msgSelectEdges;

  /// No description provided for @msgTapToPlaceGear.
  ///
  /// In de, this message translates to:
  /// **'In die Skizze tippen, um das Zahnrad zu setzen.'**
  String get msgTapToPlaceGear;

  /// No description provided for @msgCouldNotPlaceGear.
  ///
  /// In de, this message translates to:
  /// **'Das Zahnrad lässt sich hier nicht setzen.'**
  String get msgCouldNotPlaceGear;

  /// Innenverzahntes Rad = Hohlrad. "der Modul" (Verzahnungsgroesse), nicht "das Modul" (Baugruppe).
  ///
  /// In de, this message translates to:
  /// **'Ein Hohlrad braucht mindestens 3 Zähne und einen gültigen Modul.'**
  String get msgInternalGearTeeth;

  /// No description provided for @msgGearTeeth.
  ///
  /// In de, this message translates to:
  /// **'Ein Zahnrad braucht mindestens 4 Zähne und einen gültigen Modul.'**
  String get msgGearTeeth;

  /// No description provided for @msgInternalGearPlaced.
  ///
  /// In de, this message translates to:
  /// **'Hohlrad gesetzt — Mittelpunkt und einen Winkel bemaßen, um es vollständig zu bestimmen.'**
  String get msgInternalGearPlaced;

  /// Aussenverzahntes Stirnrad. "Extern" waere die Uebersetzung, "Stirnrad" ist das Bauteil.
  ///
  /// In de, this message translates to:
  /// **'Stirnrad gesetzt — Mittelpunkt und einen Winkel bemaßen, um es vollständig zu bestimmen.'**
  String get msgExternalGearPlaced;

  /// No description provided for @msgPlanetaryNeeds.
  ///
  /// In de, this message translates to:
  /// **'Ein Planetensatz braucht Sonnen- und Planetenzähne ≥ 4 und ≥ 2 Planeten.'**
  String get msgPlanetaryNeeds;

  /// No description provided for @msgPlanetaryUndrawable.
  ///
  /// In de, this message translates to:
  /// **'Diese Planetenparameter lassen sich nicht zeichnen.'**
  String get msgPlanetaryUndrawable;

  /// No description provided for @msgPlanetaryPlacedFree.
  ///
  /// In de, this message translates to:
  /// **'Planetensatz gesetzt (als freie Geometrie).'**
  String get msgPlanetaryPlacedFree;

  /// No description provided for @msgPlanetaryPlacedDimension.
  ///
  /// In de, this message translates to:
  /// **'Planetensatz gesetzt — Mittelpunkt und einen Winkel bemaßen.'**
  String get msgPlanetaryPlacedDimension;

  /// No description provided for @msgPlanetaryUneven.
  ///
  /// In de, this message translates to:
  /// **'Planetensatz gesetzt. Hinweis: {count} Planeten teilen sich nicht gleichmäßig für exakten Eingriff.'**
  String msgPlanetaryUneven(int count);

  /// No description provided for @msgPlanetaryUnevenSpacing.
  ///
  /// In de, this message translates to:
  /// **'Planetensatz gesetzt ({count} Planeten stehen für exakten Eingriff nicht gleichmäßig verteilt).'**
  String msgPlanetaryUnevenSpacing(int count);

  /// No description provided for @msgAlreadyProjected.
  ///
  /// In de, this message translates to:
  /// **'Auf diesen Layer bereits projiziert.'**
  String get msgAlreadyProjected;

  /// No description provided for @msgProjectPicksOtherLayers.
  ///
  /// In de, this message translates to:
  /// **'Projizieren holt Geometrie von ANDEREN Layern.'**
  String get msgProjectPicksOtherLayers;

  /// No description provided for @msgTapPolygonEdge.
  ///
  /// In de, this message translates to:
  /// **'Eine Kante des Polygons antippen, um es zu projizieren.'**
  String get msgTapPolygonEdge;

  /// No description provided for @msgTapGeometryOtherLayer.
  ///
  /// In de, this message translates to:
  /// **'Geometrie auf einem anderen Layer oder die X-/Y-Achse antippen.'**
  String get msgTapGeometryOtherLayer;

  /// No description provided for @msgProjectedNoPattern.
  ///
  /// In de, this message translates to:
  /// **'Projizierte Geometrie lässt sich nicht anordnen.'**
  String get msgProjectedNoPattern;

  /// No description provided for @msgProjectedNoModify.
  ///
  /// In de, this message translates to:
  /// **'Projizierte Geometrie lässt sich hier nicht ändern.'**
  String get msgProjectedNoModify;

  /// No description provided for @msgPickDirectionLine.
  ///
  /// In de, this message translates to:
  /// **'Eine Linie wählen, die die Richtung vorgibt.'**
  String get msgPickDirectionLine;

  /// No description provided for @msgPickAxisPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt oder Mittelpunkt wählen, der die Achse vorgibt.'**
  String get msgPickAxisPoint;

  /// No description provided for @msgPickMirrorLine.
  ///
  /// In de, this message translates to:
  /// **'Eine Linie wählen, an der gespiegelt wird.'**
  String get msgPickMirrorLine;

  /// No description provided for @msgMirrorLineInSelection.
  ///
  /// In de, this message translates to:
  /// **'Die Spiegelachse darf nicht Teil der Auswahl sein.'**
  String get msgMirrorLineInSelection;

  /// No description provided for @msgSelectGeometryToPattern.
  ///
  /// In de, this message translates to:
  /// **'Geometrie zum Anordnen wählen.'**
  String get msgSelectGeometryToPattern;

  /// No description provided for @msgPickLineDirection1.
  ///
  /// In de, this message translates to:
  /// **'Unter Richtung 1 eine Linie wählen.'**
  String get msgPickLineDirection1;

  /// No description provided for @msgPickPatternAxis.
  ///
  /// In de, this message translates to:
  /// **'Die Anordnungsachse wählen.'**
  String get msgPickPatternAxis;

  /// No description provided for @msgPickTheMirrorLine.
  ///
  /// In de, this message translates to:
  /// **'Die Spiegelachse wählen.'**
  String get msgPickTheMirrorLine;

  /// No description provided for @msgPatternNothingToCreate.
  ///
  /// In de, this message translates to:
  /// **'Die Anordnung hat nichts zu erzeugen.'**
  String get msgPatternNothingToCreate;

  /// No description provided for @msgPatternUnsatisfiable.
  ///
  /// In de, this message translates to:
  /// **'Die Anordnung lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.'**
  String get msgPatternUnsatisfiable;

  /// No description provided for @msgPatternCreated.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Anordnung erstellt (ein neues Objekt).} other{Anordnung erstellt ({count} neue Objekte).}}'**
  String msgPatternCreated(int count);

  /// No description provided for @msgSelfSymNeedsOneSpline.
  ///
  /// In de, this message translates to:
  /// **'Selbstsymmetrisch braucht genau einen Spline.'**
  String get msgSelfSymNeedsOneSpline;

  /// No description provided for @msgSelfSymNeedsOpenSpline.
  ///
  /// In de, this message translates to:
  /// **'Selbstsymmetrisch braucht einen offenen Spline.'**
  String get msgSelfSymNeedsOpenSpline;

  /// No description provided for @msgSelfSymEndOnMirror.
  ///
  /// In de, this message translates to:
  /// **'Für Selbstsymmetrisch muss der Spline auf der Spiegelachse enden.'**
  String get msgSelfSymEndOnMirror;

  /// No description provided for @msgSelfSymUnsatisfiable.
  ///
  /// In de, this message translates to:
  /// **'Selbstsymmetrisch lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.'**
  String get msgSelfSymUnsatisfiable;

  /// No description provided for @msgSelfSymDone.
  ///
  /// In de, this message translates to:
  /// **'Spline selbstsymmetrisch gemacht.'**
  String get msgSelfSymDone;

  /// No description provided for @msgTrimBreaksConstraints.
  ///
  /// In de, this message translates to:
  /// **'Dieses Stutzen würde die Abhängigkeiten der Skizze zerstören.'**
  String get msgTrimBreaksConstraints;

  /// No description provided for @msgSplitBreaksConstraints.
  ///
  /// In de, this message translates to:
  /// **'Dieses Teilen würde die Abhängigkeiten der Skizze zerstören.'**
  String get msgSplitBreaksConstraints;

  /// No description provided for @msgNothingToOffset.
  ///
  /// In de, this message translates to:
  /// **'Hier gibt es nichts zu versetzen.'**
  String get msgNothingToOffset;

  /// Die Radien kommen bereits formatiert an — im Deutschen mit Dezimalkomma, siehe Fmt.num.
  ///
  /// In de, this message translates to:
  /// **'R{radius} läuft über das Ende dieser Kante hinaus. Diese Ecke nimmt höchstens R{most}.'**
  String msgRadiusPastEdge(String radius, String most);

  /// No description provided for @msgPickTwoThatMeet.
  ///
  /// In de, this message translates to:
  /// **'Zwei Linien, Bögen oder Kreise wählen, die sich treffen können.'**
  String get msgPickTwoThatMeet;

  /// No description provided for @msgPickTwoNonParallel.
  ///
  /// In de, this message translates to:
  /// **'Zwei nicht parallele Linien wählen.'**
  String get msgPickTwoNonParallel;

  /// No description provided for @msgFilletBreaksSketch.
  ///
  /// In de, this message translates to:
  /// **'Diese Verrundung würde die Skizze zerstören — eine gültige Ecke oder einen kleineren Radius wählen.'**
  String get msgFilletBreaksSketch;

  /// No description provided for @msgChamferBreaksSketch.
  ///
  /// In de, this message translates to:
  /// **'Diese Fase würde die Skizze zerstören — eine gültige Ecke oder kleinere Abstände wählen.'**
  String get msgChamferBreaksSketch;

  /// No description provided for @msgShapeHasNoSize.
  ///
  /// In de, this message translates to:
  /// **'Diese Form hat keine Größe — noch einmal zeichnen.'**
  String get msgShapeHasNoSize;

  /// No description provided for @msgAlreadyLocked.
  ///
  /// In de, this message translates to:
  /// **'Diese Geometrie ist bereits fixiert.'**
  String get msgAlreadyLocked;

  /// No description provided for @msgWouldOverConstrainC.
  ///
  /// In de, this message translates to:
  /// **'Diese Abhängigkeit würde die Skizze überbestimmen.'**
  String get msgWouldOverConstrainC;

  /// No description provided for @msgConstraintUnsatisfiable.
  ///
  /// In de, this message translates to:
  /// **'Diese Abhängigkeit lässt sich mit der vorhandenen Geometrie nicht erfüllen.'**
  String get msgConstraintUnsatisfiable;

  /// No description provided for @msgTangentNeedsCurve.
  ///
  /// In de, this message translates to:
  /// **'Tangential braucht mindestens ein gekrümmtes Objekt.'**
  String get msgTangentNeedsCurve;

  /// No description provided for @msgTangentClosedSpline.
  ///
  /// In de, this message translates to:
  /// **'Tangential an einen GESCHLOSSENEN Spline geht nicht.'**
  String get msgTangentClosedSpline;

  /// G2 = kruemmungsstetig. Inventor DE: "Stetig (G2)".
  ///
  /// In de, this message translates to:
  /// **'Stetig (G2) braucht zwei gekrümmte Objekte.'**
  String get msgSmoothNeedsTwoCurves;

  /// No description provided for @msgValueUnsatisfiable.
  ///
  /// In de, this message translates to:
  /// **'Dieser Wert lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.'**
  String get msgValueUnsatisfiable;

  /// No description provided for @msgValueUnsatisfiableShort.
  ///
  /// In de, this message translates to:
  /// **'Der Wert lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.'**
  String get msgValueUnsatisfiableShort;

  /// No description provided for @msgDrivenDimension.
  ///
  /// In de, this message translates to:
  /// **'Das ist eine abhängige Bemaßung (Referenzmaß) — sie lässt sich nicht bearbeiten.'**
  String get msgDrivenDimension;

  /// No description provided for @msgInvalidParamName.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Parametername.'**
  String get msgInvalidParamName;

  /// No description provided for @msgInvalidOrDuplicateParamName.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger oder bereits vergebener Parametername.'**
  String get msgInvalidOrDuplicateParamName;

  /// No description provided for @msgParamNameInUse.
  ///
  /// In de, this message translates to:
  /// **'Der Parametername „{name}“ ist bereits vergeben.'**
  String msgParamNameInUse(String name);

  /// No description provided for @msgUnknownParam.
  ///
  /// In de, this message translates to:
  /// **'Unbekannter Parameter „{name}“.'**
  String msgUnknownParam(String name);

  /// No description provided for @msgCircularRefDimension.
  ///
  /// In de, this message translates to:
  /// **'Zirkelbezug: „{name}“ hängt von dieser Bemaßung ab.'**
  String msgCircularRefDimension(String name);

  /// No description provided for @msgCircularRefParam.
  ///
  /// In de, this message translates to:
  /// **'Zirkelbezug: „{name}“ hängt von diesem Parameter ab.'**
  String msgCircularRefParam(String name);

  /// No description provided for @msgInvalidExpression.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Ausdruck.'**
  String get msgInvalidExpression;

  /// No description provided for @msgParamUsedBy.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ wird von „{user}“ verwendet — zuerst den Bezug entfernen.'**
  String msgParamUsedBy(String name, String user);

  /// No description provided for @msgEdgeIsSpline.
  ///
  /// In de, this message translates to:
  /// **'Diese Kante ist ein Spline — sie gibt keine eindeutige Richtung vor.'**
  String get msgEdgeIsSpline;

  /// No description provided for @msgRotationAxisStraight.
  ///
  /// In de, this message translates to:
  /// **'Eine Drehachse muss eine gerade Linie oder eine Achse sein.'**
  String get msgRotationAxisStraight;

  /// No description provided for @msgPickEdgeOrCurve.
  ///
  /// In de, this message translates to:
  /// **'Gerade Kante, Rundkante, Skizzenkurve oder Ursprungsachse wählen.'**
  String get msgPickEdgeOrCurve;

  /// No description provided for @msgTapOnTheCurve.
  ///
  /// In de, this message translates to:
  /// **'Auf die Kurve tippen.'**
  String get msgTapOnTheCurve;

  /// No description provided for @msgPickPlanarFace.
  ///
  /// In de, this message translates to:
  /// **'Planare Fläche, Arbeitsebene oder Ursprungsebene wählen.'**
  String get msgPickPlanarFace;

  /// No description provided for @msgPickSketchPointOccurrences.
  ///
  /// In de, this message translates to:
  /// **'Einen Skizzen-PUNKT wählen — die Exemplare entstehen dort, wo die Punkte sind.'**
  String get msgPickSketchPointOccurrences;

  /// No description provided for @msgTapFaceOfFeature.
  ///
  /// In de, this message translates to:
  /// **'Eine Fläche des anzuordnenden Elements antippen oder es im Browser wählen.'**
  String get msgTapFaceOfFeature;

  /// No description provided for @msgFaceNoSingleFeature.
  ///
  /// In de, this message translates to:
  /// **'Diese Fläche lässt sich nicht auf ein einzelnes Element zurückführen — das Element im Browser wählen.'**
  String get msgFaceNoSingleFeature;

  /// No description provided for @msgAddedNamed.
  ///
  /// In de, this message translates to:
  /// **'{name} hinzugefügt.'**
  String msgAddedNamed(String name);

  /// No description provided for @msgRemovedNamed.
  ///
  /// In de, this message translates to:
  /// **'{name} entfernt.'**
  String msgRemovedNamed(String name);

  /// No description provided for @msgTapSolidBody.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper antippen.'**
  String get msgTapSolidBody;

  /// No description provided for @msgTapSketchPointForHole.
  ///
  /// In de, this message translates to:
  /// **'Einen Skizzen-PUNKT antippen — dorthin kommt die Bohrung.'**
  String get msgTapSketchPointForHole;

  /// No description provided for @msgNotBuiltYet.
  ///
  /// In de, this message translates to:
  /// **'{command}: noch nicht gebaut — Versatz von Ebene oder Mittelebene verwenden.'**
  String msgNotBuiltYet(String command);

  /// No description provided for @dlgEquationCurve.
  ///
  /// In de, this message translates to:
  /// **'Gleichungskurve'**
  String get dlgEquationCurve;

  /// Die Funktionsnamen sind Bezeichner des Ausdrucks-Parsers und bleiben englisch — sie werden so EINGEGEBEN.
  ///
  /// In de, this message translates to:
  /// **'y = f(x)   (sin, cos, sqrt, ^, pi, …)'**
  String get lblEquationHint;

  /// No description provided for @lblXMin.
  ///
  /// In de, this message translates to:
  /// **'x min'**
  String get lblXMin;

  /// No description provided for @lblXMax.
  ///
  /// In de, this message translates to:
  /// **'x max'**
  String get lblXMax;

  /// Kopfzeile aller Element-Dialoge. Inventor DE: "Eigenschaften".
  ///
  /// In de, this message translates to:
  /// **'Eigenschaften'**
  String get dlgProperties;

  /// No description provided for @dlgParameters.
  ///
  /// In de, this message translates to:
  /// **'Parameter'**
  String get dlgParameters;

  /// No description provided for @dlgGear.
  ///
  /// In de, this message translates to:
  /// **'Zahnrad'**
  String get dlgGear;

  /// No description provided for @dlgText.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get dlgText;

  /// No description provided for @dlgFreehandSpline.
  ///
  /// In de, this message translates to:
  /// **'Freihand-Spline'**
  String get dlgFreehandSpline;

  /// No description provided for @dlgPolygon.
  ///
  /// In de, this message translates to:
  /// **'Polygon'**
  String get dlgPolygon;

  /// No description provided for @lblDirectionN.
  ///
  /// In de, this message translates to:
  /// **'Richtung {n}'**
  String lblDirectionN(String n);

  /// No description provided for @lblAxis.
  ///
  /// In de, this message translates to:
  /// **'Achse'**
  String get lblAxis;

  /// No description provided for @lblMirrorLine.
  ///
  /// In de, this message translates to:
  /// **'Spiegelachse'**
  String get lblMirrorLine;

  /// No description provided for @lblGeometry.
  ///
  /// In de, this message translates to:
  /// **'Geometrie'**
  String get lblGeometry;

  /// Inventor DE: "Ausdehnung" — wie weit die Anordnung reicht.
  ///
  /// In de, this message translates to:
  /// **'Ausdehnung'**
  String get lblExtents;

  /// No description provided for @lblBoundary.
  ///
  /// In de, this message translates to:
  /// **'Begrenzung'**
  String get lblBoundary;

  /// No description provided for @lblIncludeGeometry.
  ///
  /// In de, this message translates to:
  /// **'Geometrie einschließen'**
  String get lblIncludeGeometry;

  /// Inventor DE: ein Element "unterdrücken" heisst, es aus der Berechnung nehmen.
  ///
  /// In de, this message translates to:
  /// **'Unterdrücken'**
  String get lblSuppress;

  /// No description provided for @tipCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get tipCancel;

  /// No description provided for @tipSelectDirectionLine.
  ///
  /// In de, this message translates to:
  /// **'Richtungslinie wählen'**
  String get tipSelectDirectionLine;

  /// No description provided for @tipFlipDirection.
  ///
  /// In de, this message translates to:
  /// **'Richtung umkehren'**
  String get tipFlipDirection;

  /// No description provided for @tipPatternAlongPath.
  ///
  /// In de, this message translates to:
  /// **'Anordnung entlang eines Pfades — noch nicht verfügbar'**
  String get tipPatternAlongPath;

  /// No description provided for @tipSelectRotationAxisPoint.
  ///
  /// In de, this message translates to:
  /// **'Drehachsenpunkt wählen'**
  String get tipSelectRotationAxisPoint;

  /// No description provided for @tipFlipRotation.
  ///
  /// In de, this message translates to:
  /// **'Drehrichtung umkehren'**
  String get tipFlipRotation;

  /// No description provided for @tipSelectGeometryToMirror.
  ///
  /// In de, this message translates to:
  /// **'Zu spiegelnde Geometrie wählen'**
  String get tipSelectGeometryToMirror;

  /// No description provided for @tipSelectMirrorLine.
  ///
  /// In de, this message translates to:
  /// **'Spiegelachse wählen'**
  String get tipSelectMirrorLine;

  /// No description provided for @tipSelectGeometryToPattern.
  ///
  /// In de, this message translates to:
  /// **'Anzuordnende Geometrie wählen'**
  String get tipSelectGeometryToPattern;

  /// No description provided for @msgBoundaryFillNotYet.
  ///
  /// In de, this message translates to:
  /// **'Begrenzungsfüllung — noch nicht verfügbar'**
  String get msgBoundaryFillNotYet;

  /// No description provided for @msgSuppressNotYet.
  ///
  /// In de, this message translates to:
  /// **'Exemplare unterdrücken — noch nicht verfügbar'**
  String get msgSuppressNotYet;

  /// No description provided for @msgPickWhileSelectorBlue.
  ///
  /// In de, this message translates to:
  /// **'Geometrie im Ansichtsfenster wählen, solange der blaue Auswahlschalter aktiv ist. OK / Fertig erzeugt die Anordnung.'**
  String get msgPickWhileSelectorBlue;

  /// No description provided for @msgFilletPickTwo.
  ///
  /// In de, this message translates to:
  /// **'Zwei Linien, Bögen oder Kreise wählen.\nDie erste Verrundung wird bemaßt; die folgenden übernehmen den Radius.'**
  String get msgFilletPickTwo;

  /// No description provided for @msgDistance1FirstLine.
  ///
  /// In de, this message translates to:
  /// **'Abstand 1 gilt für die zuerst gewählte Linie.'**
  String get msgDistance1FirstLine;

  /// No description provided for @msgPolygonSides.
  ///
  /// In de, this message translates to:
  /// **'Seiten. Erst den Mittelpunkt, dann eine Ecke wählen.'**
  String get msgPolygonSides;

  /// No description provided for @hintTapBodyIn3d.
  ///
  /// In de, this message translates to:
  /// **'Körper in 3D antippen…'**
  String get hintTapBodyIn3d;

  /// No description provided for @hintTapFeaturesInBrowser.
  ///
  /// In de, this message translates to:
  /// **'Elemente im Browser antippen…'**
  String get hintTapFeaturesInBrowser;

  /// No description provided for @hintTapPointOnCurve.
  ///
  /// In de, this message translates to:
  /// **'Punkt auf der Kurve antippen…'**
  String get hintTapPointOnCurve;

  /// No description provided for @hintTapEdgeOrAxis.
  ///
  /// In de, this message translates to:
  /// **'Kante oder Achse antippen…'**
  String get hintTapEdgeOrAxis;

  /// No description provided for @hintTapCircularEdge.
  ///
  /// In de, this message translates to:
  /// **'Rundkante oder Achse antippen…'**
  String get hintTapCircularEdge;

  /// No description provided for @hintTapSketchPoint.
  ///
  /// In de, this message translates to:
  /// **'Skizzenpunkt antippen…'**
  String get hintTapSketchPoint;

  /// No description provided for @hintTapOriginalPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt antippen, auf dem das Original sitzt…'**
  String get hintTapOriginalPoint;

  /// No description provided for @hintTapFaceToFollow.
  ///
  /// In de, this message translates to:
  /// **'Zu folgende Fläche antippen…'**
  String get hintTapFaceToFollow;

  /// No description provided for @hintTapFaceOrPlane.
  ///
  /// In de, this message translates to:
  /// **'Fläche oder Ebene antippen…'**
  String get hintTapFaceOrPlane;

  /// No description provided for @msgNoDimensionsInSketch.
  ///
  /// In de, this message translates to:
  /// **'Keine Bemaßungen in dieser Skizze.'**
  String get msgNoDimensionsInSketch;

  /// No description provided for @btnAddNumericParameter.
  ///
  /// In de, this message translates to:
  /// **'Numerischen Parameter hinzufügen'**
  String get btnAddNumericParameter;

  /// No description provided for @colParameterName.
  ///
  /// In de, this message translates to:
  /// **'Parametername'**
  String get colParameterName;

  /// No description provided for @colEquation.
  ///
  /// In de, this message translates to:
  /// **'Gleichung'**
  String get colEquation;

  /// No description provided for @colValue.
  ///
  /// In de, this message translates to:
  /// **'Wert'**
  String get colValue;

  /// No description provided for @lblReference.
  ///
  /// In de, this message translates to:
  /// **'(Referenz)'**
  String get lblReference;

  /// No description provided for @lblPoints.
  ///
  /// In de, this message translates to:
  /// **'Punkte'**
  String get lblPoints;

  /// No description provided for @lblSmoothing.
  ///
  /// In de, this message translates to:
  /// **'Glättung'**
  String get lblSmoothing;

  /// Stuetzpunkte, durch die der Spline laeuft.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Stützpunkt} other{{count} Stützpunkte}}'**
  String lblFitPoints(int count);

  /// No description provided for @tipFinishEnter.
  ///
  /// In de, this message translates to:
  /// **'Fertig (Eingabe)'**
  String get tipFinishEnter;

  /// No description provided for @tipDiscardEsc.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen (Esc)'**
  String get tipDiscardEsc;

  /// No description provided for @lblFont.
  ///
  /// In de, this message translates to:
  /// **'Schrift'**
  String get lblFont;

  /// No description provided for @lblSize.
  ///
  /// In de, this message translates to:
  /// **'Größe'**
  String get lblSize;

  /// No description provided for @lblPreview.
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get lblPreview;

  /// No description provided for @lblEdgeCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eine Kante} other{{count} Kanten}}'**
  String lblEdgeCount(int count);

  /// Kurz gehalten: die Schaltflaeche sitzt in der Dialogspalte. "+ Kantengruppe hinzufügen" waere doppelt so lang wie das Original.
  ///
  /// In de, this message translates to:
  /// **'Kantengruppe'**
  String get btnAddEdgeSet;

  /// No description provided for @lblSwapFaces.
  ///
  /// In de, this message translates to:
  /// **'Die beiden Flächen tauschen'**
  String get lblSwapFaces;

  /// Zwei Leerzeichen wie im Original — sie trennen den Namen der Arbeitsebene vom Feldtitel.
  ///
  /// In de, this message translates to:
  /// **'{name}  Versatz'**
  String lblWorkPlaneOffset(String name);

  /// No description provided for @lblSketchPlaneN.
  ///
  /// In de, this message translates to:
  /// **'{n} Skizzenebene'**
  String lblSketchPlaneN(String n);

  /// No description provided for @lblNeedsExistingBody.
  ///
  /// In de, this message translates to:
  /// **'{label} (braucht einen vorhandenen Körper)'**
  String lblNeedsExistingBody(String label);

  /// No description provided for @tipApplyAndStartAnother.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen und das nächste beginnen'**
  String get tipApplyAndStartAnother;

  /// No description provided for @msgSplitRemovesOtherSide.
  ///
  /// In de, this message translates to:
  /// **'Alles auf der anderen Seite der Ebene wird entfernt. Das Teilen in zwei Körper ist nicht gebaut.'**
  String get msgSplitRemovesOtherSide;

  /// No description provided for @msgGearTapToPlace.
  ///
  /// In de, this message translates to:
  /// **'In die Skizze tippen, um es zu setzen; dann Mittelpunkt und einen Winkel bemaßen.'**
  String get msgGearTapToPlace;

  /// Fusskreis und Kopfkreis sind die Verzahnungsbegriffe fuer root und tip.
  ///
  /// In de, this message translates to:
  /// **'Fuß- und Kopfkreisradien automatisch'**
  String get lblAutoRootTip;

  /// No description provided for @dlgReportBug.
  ///
  /// In de, this message translates to:
  /// **'Fehler melden'**
  String get dlgReportBug;

  /// Der Zeilenumbruch in der Mitte gehoert zum Layout des Dialogs und steht in beiden Sprachen.
  ///
  /// In de, this message translates to:
  /// **'Was haben Sie erwartet, und was ist stattdessen passiert?\nDas Modell, der Zustand jedes Elements und das vollständige Protokoll werden automatisch angehängt — beschreiben Sie nur, was Sie GESEHEN haben.'**
  String get msgBugPrompt;

  /// No description provided for @hintBugExample.
  ///
  /// In de, this message translates to:
  /// **'z. B. die obere Kante mit 2 mm verrundet, und die Wand ist verschwunden statt abgerundet zu werden'**
  String get hintBugExample;

  /// No description provided for @btnSaveReport.
  ///
  /// In de, this message translates to:
  /// **'Bericht sichern'**
  String get btnSaveReport;

  /// No description provided for @btnCopyPath.
  ///
  /// In de, this message translates to:
  /// **'Pfad kopieren'**
  String get btnCopyPath;

  /// M285 — Knopf im Bug-Report-Ergebnisdialog, kopiert die GitHub-Issue-URL, die der Relay zurueckgegeben hat.
  ///
  /// In de, this message translates to:
  /// **'Issue-Link kopieren'**
  String get btnCopyIssueLink;

  /// Inventor DE: "Direktbearbeitung"; auf der Schaltflaeche steht die Kurzform, wie im Englischen auch.
  ///
  /// In de, this message translates to:
  /// **'Direkt'**
  String get btnDirect;

  /// No description provided for @btnDeleteFace.
  ///
  /// In de, this message translates to:
  /// **'Fläche löschen'**
  String get btnDeleteFace;

  /// No description provided for @btnThickenOffset.
  ///
  /// In de, this message translates to:
  /// **'Verdicken / Versatz'**
  String get btnThickenOffset;

  /// Benutzerkoordinatensystem. "BKS" ist das Kuerzel, das AutoCAD DE und Inventor DE benutzen — die deutschen Anwender kennen UCS nicht.
  ///
  /// In de, this message translates to:
  /// **'BKS'**
  String get btnUcs;

  /// No description provided for @btnSketchDriven.
  ///
  /// In de, this message translates to:
  /// **'Skizzengesteuert'**
  String get btnSketchDriven;

  /// No description provided for @btnCenterline.
  ///
  /// In de, this message translates to:
  /// **'Mittellinie'**
  String get btnCenterline;

  /// No description provided for @btnConstraintSettings.
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeitseinstellungen'**
  String get btnConstraintSettings;

  /// Inventor DE: "Kopieren".
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get btnCopy;

  /// No description provided for @btnDrivenDimension.
  ///
  /// In de, this message translates to:
  /// **'Abhängige Bemaßung'**
  String get btnDrivenDimension;

  /// Inventor DE: "Dehnen" — das Gegenstueck zu "Stutzen".
  ///
  /// In de, this message translates to:
  /// **'Dehnen'**
  String get btnExtend;

  /// No description provided for @btnPointsTool.
  ///
  /// In de, this message translates to:
  /// **'Punkte'**
  String get btnPointsTool;

  /// No description provided for @btnShowConstraints.
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeiten einblenden'**
  String get btnShowConstraints;

  /// No description provided for @btnShowFormat.
  ///
  /// In de, this message translates to:
  /// **'Format einblenden'**
  String get btnShowFormat;

  /// No description provided for @btnSmoothG2.
  ///
  /// In de, this message translates to:
  /// **'Stetig (G2)'**
  String get btnSmoothG2;

  /// No description provided for @btnStretch.
  ///
  /// In de, this message translates to:
  /// **'Strecken'**
  String get btnStretch;

  /// No description provided for @btnCenterPoint.
  ///
  /// In de, this message translates to:
  /// **'Mittelpunkt'**
  String get btnCenterPoint;

  /// Skizzenbefehl: eine Kurve an einem Schnittpunkt teilen. Inventor DE: "Teilen" — bewusst NICHT "Trennen", das ist der 3D-Befehl, der einen Körper schneidet.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get btnSplitCurve;

  /// Skizzenbefehl: Parallelkurve. Inventor DE: "Versatz".
  ///
  /// In de, this message translates to:
  /// **'Versatz'**
  String get btnOffsetCurve;

  /// No description provided for @btnFinish.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get btnFinish;

  /// Zweizeilig, 64 px breit. Inventor DE sagt "Skizze beenden"; das passt hier nicht in eine Zeile und "fertig" ist die Form, die auf der Schnellwerkzeugleiste daneben schon steht.
  ///
  /// In de, this message translates to:
  /// **'Skizze\nfertig'**
  String get btnFinishSketch;

  /// No description provided for @featExtrusion.
  ///
  /// In de, this message translates to:
  /// **'Extrusion'**
  String get featExtrusion;

  /// No description provided for @featRevolution.
  ///
  /// In de, this message translates to:
  /// **'Drehung'**
  String get featRevolution;

  /// No description provided for @featSweep.
  ///
  /// In de, this message translates to:
  /// **'Sweeping'**
  String get featSweep;

  /// No description provided for @featLoft.
  ///
  /// In de, this message translates to:
  /// **'Erhebung'**
  String get featLoft;

  /// No description provided for @featCoil.
  ///
  /// In de, this message translates to:
  /// **'Spirale'**
  String get featCoil;

  /// No description provided for @featFillet.
  ///
  /// In de, this message translates to:
  /// **'Verrundung'**
  String get featFillet;

  /// No description provided for @featChamfer.
  ///
  /// In de, this message translates to:
  /// **'Fase'**
  String get featChamfer;

  /// No description provided for @featHole.
  ///
  /// In de, this message translates to:
  /// **'Bohrung'**
  String get featHole;

  /// No description provided for @featSplit.
  ///
  /// In de, this message translates to:
  /// **'Trennen'**
  String get featSplit;

  /// No description provided for @featCombine.
  ///
  /// In de, this message translates to:
  /// **'Kombinieren'**
  String get featCombine;

  /// No description provided for @featDeleteFace.
  ///
  /// In de, this message translates to:
  /// **'Fläche löschen'**
  String get featDeleteFace;

  /// No description provided for @cmdDeleteFace.
  ///
  /// In de, this message translates to:
  /// **'Fläche löschen'**
  String get cmdDeleteFace;

  /// No description provided for @cmdMoveFaces.
  ///
  /// In de, this message translates to:
  /// **'Flächen verschieben'**
  String get cmdMoveFaces;

  /// No description provided for @cmdSizeFaces.
  ///
  /// In de, this message translates to:
  /// **'Flächengröße ändern'**
  String get cmdSizeFaces;

  /// No description provided for @cmdScaleBody.
  ///
  /// In de, this message translates to:
  /// **'Körper skalieren'**
  String get cmdScaleBody;

  /// Steht in "Flächen zum {verb} wählen." — im Deutschen ein substantiviertes Verb und deshalb GROSS, im Englischen klein. Genau die Stelle, an der ein maschinelles toLowerCase() falsch wird.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get verbDelete;

  /// No description provided for @verbMove.
  ///
  /// In de, this message translates to:
  /// **'Verschieben'**
  String get verbMove;

  /// Inventor DE: "Rechteckige Anordnung".
  ///
  /// In de, this message translates to:
  /// **'Rechteckige Anordnung'**
  String get patRectangular;

  /// No description provided for @patCircular.
  ///
  /// In de, this message translates to:
  /// **'Runde Anordnung'**
  String get patCircular;

  /// No description provided for @patSketchDriven.
  ///
  /// In de, this message translates to:
  /// **'Skizzengesteuerte Anordnung'**
  String get patSketchDriven;

  /// No description provided for @patMirror.
  ///
  /// In de, this message translates to:
  /// **'Spiegeln'**
  String get patMirror;

  /// No description provided for @holeSimple.
  ///
  /// In de, this message translates to:
  /// **'Einfach'**
  String get holeSimple;

  /// Zylindrische Senkung. Inventor DE: "Senkung".
  ///
  /// In de, this message translates to:
  /// **'Senkung'**
  String get holeCounterbore;

  /// No description provided for @holeSpotface.
  ///
  /// In de, this message translates to:
  /// **'Plansenkung'**
  String get holeSpotface;

  /// No description provided for @holeCountersink.
  ///
  /// In de, this message translates to:
  /// **'Kegelsenkung'**
  String get holeCountersink;

  /// No description provided for @holeSimpleShort.
  ///
  /// In de, this message translates to:
  /// **'Einfach'**
  String get holeSimpleShort;

  /// No description provided for @holeCounterboreShort.
  ///
  /// In de, this message translates to:
  /// **'Senkung'**
  String get holeCounterboreShort;

  /// No description provided for @holeSpotfaceShort.
  ///
  /// In de, this message translates to:
  /// **'Plan'**
  String get holeSpotfaceShort;

  /// No description provided for @holeCountersinkShort.
  ///
  /// In de, this message translates to:
  /// **'Kegel'**
  String get holeCountersinkShort;

  /// No description provided for @msgNoInteriorEdgesLeft.
  ///
  /// In de, this message translates to:
  /// **'Keine Innenkanten mehr zum Hinzufügen.'**
  String get msgNoInteriorEdgesLeft;

  /// No description provided for @msgNoExteriorEdgesLeft.
  ///
  /// In de, this message translates to:
  /// **'Keine Außenkanten mehr zum Hinzufügen.'**
  String get msgNoExteriorEdgesLeft;

  /// No description provided for @msgAddedInteriorEdges.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eine Innenkante hinzugefügt.} other{{count} Innenkanten hinzugefügt.}}'**
  String msgAddedInteriorEdges(int count);

  /// No description provided for @msgAddedExteriorEdges.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eine Außenkante hinzugefügt.} other{{count} Außenkanten hinzugefügt.}}'**
  String msgAddedExteriorEdges(int count);

  /// No description provided for @msgUndone.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get msgUndone;

  /// No description provided for @msgRedone.
  ///
  /// In de, this message translates to:
  /// **'Wiederholt'**
  String get msgRedone;

  /// No description provided for @msgShow.
  ///
  /// In de, this message translates to:
  /// **'Einblenden'**
  String get msgShow;

  /// Inventor DE: "Bis zum Nächsten".
  ///
  /// In de, this message translates to:
  /// **'Bis zum Nächsten'**
  String get extToNext;

  /// Inventor DE: "Bis" — bis zu einer gewaehlten Flaeche.
  ///
  /// In de, this message translates to:
  /// **'Bis'**
  String get extToFace;

  /// No description provided for @extThroughAll.
  ///
  /// In de, this message translates to:
  /// **'Durch alle'**
  String get extThroughAll;

  /// No description provided for @extDistance.
  ///
  /// In de, this message translates to:
  /// **'Abstand'**
  String get extDistance;

  /// No description provided for @wfPickEdgeFacePlanesPoints.
  ///
  /// In de, this message translates to:
  /// **'Kante, Fläche, zwei Ebenen oder zwei Punkte wählen.'**
  String get wfPickEdgeFacePlanesPoints;

  /// No description provided for @wfPickLinearEdge.
  ///
  /// In de, this message translates to:
  /// **'Gerade Kante oder Skizzenlinie wählen.'**
  String get wfPickLinearEdge;

  /// No description provided for @wfPickCircularEdge.
  ///
  /// In de, this message translates to:
  /// **'Kreis- oder Ellipsenkante wählen.'**
  String get wfPickCircularEdge;

  /// No description provided for @wfPickCylConeFace.
  ///
  /// In de, this message translates to:
  /// **'Zylinder- oder Kegelfläche wählen.'**
  String get wfPickCylConeFace;

  /// No description provided for @wfPickPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt wählen.'**
  String get wfPickPoint;

  /// No description provided for @wfPickParallelLine.
  ///
  /// In de, this message translates to:
  /// **'Linie wählen, zu der parallel gebaut wird.'**
  String get wfPickParallelLine;

  /// No description provided for @wfPickFirstPoint.
  ///
  /// In de, this message translates to:
  /// **'Ersten Punkt wählen.'**
  String get wfPickFirstPoint;

  /// No description provided for @wfPickSecondPoint.
  ///
  /// In de, this message translates to:
  /// **'Zweiten Punkt wählen.'**
  String get wfPickSecondPoint;

  /// No description provided for @wfPlaneDragOrPickSecond.
  ///
  /// In de, this message translates to:
  /// **'Fläche oder Ebene wählen — ziehen ergibt einen Versatz, eine zweite parallele Fläche die Mittelebene.'**
  String get wfPlaneDragOrPickSecond;

  /// No description provided for @wfPlaneSecondParallelEdgeOrPoint.
  ///
  /// In de, this message translates to:
  /// **'Parallele Fläche für die Mittelebene wählen, Kante zum Abwinkeln oder Eckpunkt für eine parallele Ebene — oder ziehen für einen Versatz.'**
  String get wfPlaneSecondParallelEdgeOrPoint;

  /// No description provided for @wfPlaneSecondCoplanarOrPoint.
  ///
  /// In de, this message translates to:
  /// **'Zweite komplanare Kante wählen, oder einen Eckpunkt für die Normalebene.'**
  String get wfPlaneSecondCoplanarOrPoint;

  /// No description provided for @wfPlaneTwoMorePoints.
  ///
  /// In de, this message translates to:
  /// **'Zwei weitere Punkte für die Ebene wählen.'**
  String get wfPlaneTwoMorePoints;

  /// No description provided for @wfCannotDefinePlane.
  ///
  /// In de, this message translates to:
  /// **'{ref} kann keine Ebene festlegen.'**
  String wfCannotDefinePlane(String ref);

  /// No description provided for @wfNoPlaneFromTwo.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} legen keine Ebene fest.'**
  String wfNoPlaneFromTwo(String a, String b);

  /// No description provided for @wfPickThirdPoint.
  ///
  /// In de, this message translates to:
  /// **'Dritten Punkt wählen.'**
  String get wfPickThirdPoint;

  /// No description provided for @wfPickFirstPlane.
  ///
  /// In de, this message translates to:
  /// **'Erste Ebene oder planare Fläche wählen.'**
  String get wfPickFirstPlane;

  /// No description provided for @wfPickSecondNonParallelPlane.
  ///
  /// In de, this message translates to:
  /// **'Zweite, nicht parallele Ebene oder Fläche wählen.'**
  String get wfPickSecondNonParallelPlane;

  /// No description provided for @wfPickPlane.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder planare Fläche wählen.'**
  String get wfPickPlane;

  /// No description provided for @wfPickAxisThroughPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt wählen, durch den die Achse läuft.'**
  String get wfPickAxisThroughPoint;

  /// No description provided for @wfPickVertexCircleOrMeeting.
  ///
  /// In de, this message translates to:
  /// **'Eckpunkt, Kreiskante oder sich treffende Geometrie wählen.'**
  String get wfPickVertexCircleOrMeeting;

  /// No description provided for @wfPickVertexToGround.
  ///
  /// In de, this message translates to:
  /// **'Eckpunkt oder Mittelpunkt wählen, an dem fixiert wird.'**
  String get wfPickVertexToGround;

  /// No description provided for @wfPickVertexSketchPointMid.
  ///
  /// In de, this message translates to:
  /// **'Eckpunkt, Skizzenpunkt oder Kantenmittelpunkt wählen.'**
  String get wfPickVertexSketchPointMid;

  /// No description provided for @wfPickTorusFace.
  ///
  /// In de, this message translates to:
  /// **'Torusfläche wählen.'**
  String get wfPickTorusFace;

  /// No description provided for @wfPickSphereFace.
  ///
  /// In de, this message translates to:
  /// **'Kugelfläche wählen.'**
  String get wfPickSphereFace;

  /// No description provided for @wfPickFirstLine.
  ///
  /// In de, this message translates to:
  /// **'Erste Linie, Kante oder Achse wählen.'**
  String get wfPickFirstLine;

  /// No description provided for @wfPickSecondCrossingLine.
  ///
  /// In de, this message translates to:
  /// **'Zweite Linie wählen, die sie schneidet.'**
  String get wfPickSecondCrossingLine;

  /// No description provided for @wfPickCrossingLine.
  ///
  /// In de, this message translates to:
  /// **'Linie, Kante oder Achse wählen, die sie schneidet.'**
  String get wfPickCrossingLine;

  /// No description provided for @wfPickSecondPlane.
  ///
  /// In de, this message translates to:
  /// **'Zweite Ebene wählen.'**
  String get wfPickSecondPlane;

  /// No description provided for @wfPickThirdPlane.
  ///
  /// In de, this message translates to:
  /// **'Dritte Ebene wählen.'**
  String get wfPickThirdPlane;

  /// No description provided for @wfPickLineOrTwoPlanes.
  ///
  /// In de, this message translates to:
  /// **'Linie wählen, die sie kreuzt, oder zwei weitere Ebenen.'**
  String get wfPickLineOrTwoPlanes;

  /// No description provided for @wfPickSecondLineOrPlane.
  ///
  /// In de, this message translates to:
  /// **'Zweite Linie wählen, oder eine Ebene zum Kreuzen.'**
  String get wfPickSecondLineOrPlane;

  /// No description provided for @wfPickSecondPlaneOrPoint.
  ///
  /// In de, this message translates to:
  /// **'Zweite Ebene zum Schneiden wählen, oder einen Punkt für die Normale hindurch.'**
  String get wfPickSecondPlaneOrPoint;

  /// No description provided for @wfPickSecondPointPlaneOrLine.
  ///
  /// In de, this message translates to:
  /// **'Zweiten Punkt, eine Ebene oder eine Linie wählen.'**
  String get wfPickSecondPointPlaneOrLine;

  /// No description provided for @wfPickParallelPlane.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder planare Fläche wählen, zu der parallel gebaut wird.'**
  String get wfPickParallelPlane;

  /// No description provided for @wfPickPlaneThroughPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt wählen, durch den die Ebene läuft.'**
  String get wfPickPlaneThroughPoint;

  /// No description provided for @wfPickFirstEdge.
  ///
  /// In de, this message translates to:
  /// **'Erste Kante oder Linie wählen.'**
  String get wfPickFirstEdge;

  /// No description provided for @wfPickSecondCoplanarEdge.
  ///
  /// In de, this message translates to:
  /// **'Zweite Kante in derselben Ebene wählen.'**
  String get wfPickSecondCoplanarEdge;

  /// No description provided for @wfPickNormalAxis.
  ///
  /// In de, this message translates to:
  /// **'Achse, Kante oder Linie wählen, zu der normal gebaut wird.'**
  String get wfPickNormalAxis;

  /// No description provided for @wfPickCylFaceSide.
  ///
  /// In de, this message translates to:
  /// **'Zylinderfläche wählen, auf der Seite, wo die Ebene liegen soll.'**
  String get wfPickCylFaceSide;

  /// No description provided for @wfPickCylFace.
  ///
  /// In de, this message translates to:
  /// **'Zylinderfläche wählen.'**
  String get wfPickCylFace;

  /// No description provided for @wfPickEdgeAlongIt.
  ///
  /// In de, this message translates to:
  /// **'Kante wählen, die darauf liegt.'**
  String get wfPickEdgeAlongIt;

  /// No description provided for @wfPickPlaneToParallel.
  ///
  /// In de, this message translates to:
  /// **'Ebene wählen, zu der parallel gebaut wird.'**
  String get wfPickPlaneToParallel;

  /// No description provided for @wfPickPlaneToAngleFrom.
  ///
  /// In de, this message translates to:
  /// **'Ebene wählen, von der aus gewinkelt wird.'**
  String get wfPickPlaneToAngleFrom;

  /// No description provided for @wfPickPivotEdgeInPlane.
  ///
  /// In de, this message translates to:
  /// **'Kante zum Schwenken wählen — sie muss in dieser Ebene liegen.'**
  String get wfPickPivotEdgeInPlane;

  /// No description provided for @wfTapCurveToCross.
  ///
  /// In de, this message translates to:
  /// **'Skizzenkurve dort antippen, wo die Ebene sie schneiden soll.'**
  String get wfTapCurveToCross;

  /// No description provided for @wfNotStraightEdge.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine gerade Kante oder Linie.'**
  String wfNotStraightEdge(String ref);

  /// No description provided for @wfNotCircularEdge.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Kreis- oder Ellipsenkante.'**
  String wfNotCircularEdge(String ref);

  /// No description provided for @wfNotRevolvedFace.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Drehfläche — Zylinder, Kegel oder Torus wählen.'**
  String wfNotRevolvedFace(String ref);

  /// No description provided for @wfNoPoint.
  ///
  /// In de, this message translates to:
  /// **'{ref} ergibt keinen Punkt.'**
  String wfNoPoint(String ref);

  /// No description provided for @wfNotPlane.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Ebene und keine planare Fläche.'**
  String wfNotPlane(String ref);

  /// No description provided for @wfNeitherPointNorLine.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist weder ein Punkt noch eine Linie.'**
  String wfNeitherPointNorLine(String ref);

  /// No description provided for @wfNeitherPlaneNorLine.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist weder eine Ebene noch eine Linie.'**
  String wfNeitherPlaneNorLine(String ref);

  /// No description provided for @wfNoParallelLinePicked.
  ///
  /// In de, this message translates to:
  /// **'Keine der beiden Auswahlen ist eine Linie.'**
  String get wfNoParallelLinePicked;

  /// No description provided for @wfPickPointForAxis.
  ///
  /// In de, this message translates to:
  /// **'Punkt wählen, durch den die Achse gehen soll.'**
  String get wfPickPointForAxis;

  /// No description provided for @wfPickPointForPlane.
  ///
  /// In de, this message translates to:
  /// **'Punkt wählen, durch den die Ebene gehen soll.'**
  String get wfPickPointForPlane;

  /// No description provided for @wfSamePlace.
  ///
  /// In de, this message translates to:
  /// **'Diese beiden Punkte liegen an derselben Stelle.'**
  String get wfSamePlace;

  /// No description provided for @wfParallelNeverMeet.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} sind parallel — sie treffen sich nie.'**
  String wfParallelNeverMeet(String a, String b);

  /// No description provided for @wfParallelNeverCross.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} sind parallel — sie kreuzen sich nie.'**
  String wfParallelNeverCross(String a, String b);

  /// No description provided for @wfCannotDefineAxis.
  ///
  /// In de, this message translates to:
  /// **'{ref} kann keine Achse festlegen.'**
  String wfCannotDefineAxis(String ref);

  /// No description provided for @wfCannotDefinePoint.
  ///
  /// In de, this message translates to:
  /// **'{ref} kann keinen Punkt festlegen.'**
  String wfCannotDefinePoint(String ref);

  /// No description provided for @wfParallelPickTwoMeeting.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} sind parallel — zwei Ebenen wählen, die sich schneiden.'**
  String wfParallelPickTwoMeeting(String a, String b);

  /// No description provided for @wfNoAxisFromTwo.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} legen keine Achse fest.'**
  String wfNoAxisFromTwo(String a, String b);

  /// No description provided for @wfNoPointFromTwo.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} legen keinen Punkt fest.'**
  String wfNoPointFromTwo(String a, String b);

  /// No description provided for @wfNotClosedCircle.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine geschlossene Kreiskante.'**
  String wfNotClosedCircle(String ref);

  /// No description provided for @wfNotSphere.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Kugelfläche.'**
  String wfNotSphere(String ref);

  /// No description provided for @wfNotTorus.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Torusfläche.'**
  String wfNotTorus(String ref);

  /// No description provided for @wfNotLineEdgeAxis.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Linie, Kante oder Achse.'**
  String wfNotLineEdgeAxis(String ref);

  /// No description provided for @wfNotAxisEdgeLine.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Achse, Kante oder Linie.'**
  String wfNotAxisEdgeLine(String ref);

  /// No description provided for @wfNotEdgeOrLine.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Kante und keine Linie.'**
  String wfNotEdgeOrLine(String ref);

  /// No description provided for @wfPickOnePlaneOneLine.
  ///
  /// In de, this message translates to:
  /// **'Eine Ebene und eine Linie wählen.'**
  String get wfPickOnePlaneOneLine;

  /// No description provided for @wfSkewByGap.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} treffen sich nicht — {gap} Abstand.'**
  String wfSkewByGap(String a, String b, String gap);

  /// No description provided for @wfLineParallelToPlane.
  ///
  /// In de, this message translates to:
  /// **'{line} ist parallel zu {plane} — sie schneidet sie nie.'**
  String wfLineParallelToPlane(String line, String plane);

  /// No description provided for @wfThreeNoCommonPoint.
  ///
  /// In de, this message translates to:
  /// **'{a}, {b} und {c} treffen sich nicht in einem Punkt — zwei davon sind parallel, oder alle drei teilen sich eine Gerade.'**
  String wfThreeNoCommonPoint(String a, String b, String c);

  /// No description provided for @wfNotACurve.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Kurve — Skizzenkurve dort antippen, wo die Ebene sie schneiden soll.'**
  String wfNotACurve(String ref);

  /// No description provided for @wfPickPivotEdge.
  ///
  /// In de, this message translates to:
  /// **'Kante wählen, um die die Ebene schwenkt.'**
  String get wfPickPivotEdge;

  /// No description provided for @wfEdgeNotInPlane.
  ///
  /// In de, this message translates to:
  /// **'{edge} ist nicht parallel zu {plane} — die Ebene kann nur um eine Kante schwenken, die darin liegt.'**
  String wfEdgeNotInPlane(String edge, String plane);

  /// No description provided for @wfAngleNotANumber.
  ///
  /// In de, this message translates to:
  /// **'Der Winkel ist keine Zahl.'**
  String get wfAngleNotANumber;

  /// No description provided for @wfNotCylForTangent.
  ///
  /// In de, this message translates to:
  /// **'{ref} ist keine Zylinderfläche — eine Tangentialebene braucht eine.'**
  String wfNotCylForTangent(String ref);

  /// No description provided for @wfPointInsideCyl.
  ///
  /// In de, this message translates to:
  /// **'{pt} liegt in {cyl} — dadurch geht keine Tangentialebene.'**
  String wfPointInsideCyl(String pt, String cyl);

  /// No description provided for @wfTwoTangentThroughPoint.
  ///
  /// In de, this message translates to:
  /// **'Zwei Ebenen sind tangential an {cyl} durch {pt} — die Fläche auf der Seite antippen, auf der die Ebene liegen soll.'**
  String wfTwoTangentThroughPoint(String cyl, String pt);

  /// No description provided for @wfTwoTangentParallel.
  ///
  /// In de, this message translates to:
  /// **'Zwei Ebenen sind tangential an {cyl} und parallel zu {plane} — die Fläche auf der Seite antippen, auf der die Ebene liegen soll.'**
  String wfTwoTangentParallel(String cyl, String plane);

  /// No description provided for @wfEdgeNotParallelToAxis.
  ///
  /// In de, this message translates to:
  /// **'{edge} ist nicht parallel zur Achse von {cyl}.'**
  String wfEdgeNotParallelToAxis(String edge, String cyl);

  /// No description provided for @wfEdgeOffCylinder.
  ///
  /// In de, this message translates to:
  /// **'{edge} liegt nicht auf {cyl} — sie ist {gap} mm daneben.'**
  String wfEdgeOffCylinder(String edge, String cyl, String gap);

  /// No description provided for @wfPlaneNotParallelToAxis.
  ///
  /// In de, this message translates to:
  /// **'{plane} ist nicht parallel zur Achse von {cyl} — dazu ist keine Tangentialebene parallel.'**
  String wfPlaneNotParallelToAxis(String plane, String cyl);

  /// No description provided for @wfCollinearThreePoints.
  ///
  /// In de, this message translates to:
  /// **'{a}, {b} und {c} liegen auf einer Geraden — drei Punkte dürfen nicht kollinear sein.'**
  String wfCollinearThreePoints(String a, String b, String c);

  /// No description provided for @wfSameLineTwice.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} sind dieselbe Linie — eine Ebene braucht zwei verschiedene Kanten.'**
  String wfSameLineTwice(String a, String b);

  /// No description provided for @wfSkewEdges.
  ///
  /// In de, this message translates to:
  /// **'{a} und {b} sind windschief — sie verfehlen sich um {gap} mm.'**
  String wfSkewEdges(String a, String b, String gap);

  /// No description provided for @secInputGeometry.
  ///
  /// In de, this message translates to:
  /// **'Eingabegeometrie'**
  String get secInputGeometry;

  /// No description provided for @secOutputGeometry.
  ///
  /// In de, this message translates to:
  /// **'Ausgabegeometrie'**
  String get secOutputGeometry;

  /// No description provided for @secBehavior.
  ///
  /// In de, this message translates to:
  /// **'Verhalten'**
  String get secBehavior;

  /// No description provided for @secPlacement.
  ///
  /// In de, this message translates to:
  /// **'Platzierung'**
  String get secPlacement;

  /// No description provided for @secOutput.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe'**
  String get secOutput;

  /// No description provided for @secExtents.
  ///
  /// In de, this message translates to:
  /// **'Ausdehnung'**
  String get secExtents;

  /// No description provided for @lblDirection.
  ///
  /// In de, this message translates to:
  /// **'Richtung'**
  String get lblDirection;

  /// No description provided for @lblOrientation.
  ///
  /// In de, this message translates to:
  /// **'Ausrichtung'**
  String get lblOrientation;

  /// No description provided for @lblMethod.
  ///
  /// In de, this message translates to:
  /// **'Methode'**
  String get lblMethod;

  /// No description provided for @lblDistance.
  ///
  /// In de, this message translates to:
  /// **'Abstand'**
  String get lblDistance;

  /// No description provided for @lblAngle.
  ///
  /// In de, this message translates to:
  /// **'Winkel'**
  String get lblAngle;

  /// No description provided for @lblDepth.
  ///
  /// In de, this message translates to:
  /// **'Tiefe'**
  String get lblDepth;

  /// No description provided for @lblDiameter.
  ///
  /// In de, this message translates to:
  /// **'Durchmesser'**
  String get lblDiameter;

  /// No description provided for @lblType.
  ///
  /// In de, this message translates to:
  /// **'Typ'**
  String get lblType;

  /// No description provided for @lblCount.
  ///
  /// In de, this message translates to:
  /// **'Anzahl'**
  String get lblCount;

  /// No description provided for @lblNumber.
  ///
  /// In de, this message translates to:
  /// **'Anzahl'**
  String get lblNumber;

  /// No description provided for @lblSpacing.
  ///
  /// In de, this message translates to:
  /// **'Abstand'**
  String get lblSpacing;

  /// No description provided for @lblDistribution.
  ///
  /// In de, this message translates to:
  /// **'Verteilung'**
  String get lblDistribution;

  /// No description provided for @lblFlip.
  ///
  /// In de, this message translates to:
  /// **'Umkehren'**
  String get lblFlip;

  /// No description provided for @lblKeep.
  ///
  /// In de, this message translates to:
  /// **'Behalten'**
  String get lblKeep;

  /// No description provided for @lblPlaneField.
  ///
  /// In de, this message translates to:
  /// **'Ebene'**
  String get lblPlaneField;

  /// No description provided for @lblFaceField.
  ///
  /// In de, this message translates to:
  /// **'Fläche'**
  String get lblFaceField;

  /// No description provided for @lblEdges.
  ///
  /// In de, this message translates to:
  /// **'Kanten'**
  String get lblEdges;

  /// No description provided for @lblRadius.
  ///
  /// In de, this message translates to:
  /// **'Radius'**
  String get lblRadius;

  /// No description provided for @lblRadiusN.
  ///
  /// In de, this message translates to:
  /// **'Radius {n}'**
  String lblRadiusN(String n);

  /// No description provided for @lblDistance1.
  ///
  /// In de, this message translates to:
  /// **'Abstand 1'**
  String get lblDistance1;

  /// No description provided for @lblDistance2.
  ///
  /// In de, this message translates to:
  /// **'Abstand 2'**
  String get lblDistance2;

  /// No description provided for @lblTwoDistances.
  ///
  /// In de, this message translates to:
  /// **'Zwei Abstände'**
  String get lblTwoDistances;

  /// No description provided for @lblDistanceAndAngle.
  ///
  /// In de, this message translates to:
  /// **'Abstand und Winkel'**
  String get lblDistanceAndAngle;

  /// No description provided for @lblEqualDistance.
  ///
  /// In de, this message translates to:
  /// **'Gleicher Abstand'**
  String get lblEqualDistance;

  /// No description provided for @lblAllFillets.
  ///
  /// In de, this message translates to:
  /// **'Alle Innenkanten'**
  String get lblAllFillets;

  /// No description provided for @lblAllRounds.
  ///
  /// In de, this message translates to:
  /// **'Alle Außenkanten'**
  String get lblAllRounds;

  /// No description provided for @hintTapEdgesIn3d.
  ///
  /// In de, this message translates to:
  /// **'Kanten in 3D antippen…'**
  String get hintTapEdgesIn3d;

  /// No description provided for @lblSelectEdges.
  ///
  /// In de, this message translates to:
  /// **'Kanten wählen'**
  String get lblSelectEdges;

  /// No description provided for @lblBodies.
  ///
  /// In de, this message translates to:
  /// **'Körper'**
  String get lblBodies;

  /// No description provided for @lblBase.
  ///
  /// In de, this message translates to:
  /// **'Basis'**
  String get lblBase;

  /// No description provided for @lblToolbodies.
  ///
  /// In de, this message translates to:
  /// **'Werkzeugkörper'**
  String get lblToolbodies;

  /// No description provided for @hintTapBodyToKeep.
  ///
  /// In de, this message translates to:
  /// **'Körper antippen, der BLEIBT…'**
  String get hintTapBodyToKeep;

  /// No description provided for @hintPickBaseFirst.
  ///
  /// In de, this message translates to:
  /// **'Erst die Basis wählen'**
  String get hintPickBaseFirst;

  /// No description provided for @hintTapBodiesToCombine.
  ///
  /// In de, this message translates to:
  /// **'Körper zum Kombinieren antippen…'**
  String get hintTapBodiesToCombine;

  /// No description provided for @lblOperation.
  ///
  /// In de, this message translates to:
  /// **'Operation'**
  String get lblOperation;

  /// No description provided for @lblKeepTool.
  ///
  /// In de, this message translates to:
  /// **'Werkzeug behalten'**
  String get lblKeepTool;

  /// No description provided for @lblYes.
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get lblYes;

  /// Inventor DE: die boolesche Vereinigung.
  ///
  /// In de, this message translates to:
  /// **'Vereinigen'**
  String get opJoin;

  /// Inventor DE nennt den Abzug "Differenz", nicht "Schneiden".
  ///
  /// In de, this message translates to:
  /// **'Differenz'**
  String get opCut;

  /// No description provided for @opIntersect.
  ///
  /// In de, this message translates to:
  /// **'Schnittmenge'**
  String get opIntersect;

  /// No description provided for @opNewSolid.
  ///
  /// In de, this message translates to:
  /// **'Neuer Körper'**
  String get opNewSolid;

  /// No description provided for @lblBoolean.
  ///
  /// In de, this message translates to:
  /// **'Boolesch'**
  String get lblBoolean;

  /// No description provided for @lblTargetBody.
  ///
  /// In de, this message translates to:
  /// **'Zielkörper'**
  String get lblTargetBody;

  /// No description provided for @lblTrim.
  ///
  /// In de, this message translates to:
  /// **'Beschneiden'**
  String get lblTrim;

  /// No description provided for @hintTapPlaneOrFace.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder planare Fläche antippen…'**
  String get hintTapPlaneOrFace;

  /// No description provided for @lblThisSide.
  ///
  /// In de, this message translates to:
  /// **'Diese Seite'**
  String get lblThisSide;

  /// No description provided for @lblOtherSide.
  ///
  /// In de, this message translates to:
  /// **'Andere Seite'**
  String get lblOtherSide;

  /// No description provided for @lblProfiles.
  ///
  /// In de, this message translates to:
  /// **'Profile'**
  String get lblProfiles;

  /// No description provided for @hintSelectProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil im Ansichtsfenster wählen'**
  String get hintSelectProfile;

  /// No description provided for @lblFrom.
  ///
  /// In de, this message translates to:
  /// **'Von'**
  String get lblFrom;

  /// No description provided for @lblPath.
  ///
  /// In de, this message translates to:
  /// **'Pfad'**
  String get lblPath;

  /// No description provided for @hintTapCurveIn3d.
  ///
  /// In de, this message translates to:
  /// **'Kurve in 3D antippen…'**
  String get hintTapCurveIn3d;

  /// No description provided for @lblSelectCurveOrEdge.
  ///
  /// In de, this message translates to:
  /// **'Kurve oder Kante wählen'**
  String get lblSelectCurveOrEdge;

  /// No description provided for @lblPathSelected.
  ///
  /// In de, this message translates to:
  /// **'Pfad gewählt'**
  String get lblPathSelected;

  /// No description provided for @lblFollowPath.
  ///
  /// In de, this message translates to:
  /// **'Pfad folgen'**
  String get lblFollowPath;

  /// No description provided for @lblFixed.
  ///
  /// In de, this message translates to:
  /// **'Fest'**
  String get lblFixed;

  /// No description provided for @lblGuide.
  ///
  /// In de, this message translates to:
  /// **'Führung'**
  String get lblGuide;

  /// No description provided for @lblTaper.
  ///
  /// In de, this message translates to:
  /// **'Verjüngung'**
  String get lblTaper;

  /// No description provided for @lblTwist.
  ///
  /// In de, this message translates to:
  /// **'Verdrehung'**
  String get lblTwist;

  /// No description provided for @lblSections.
  ///
  /// In de, this message translates to:
  /// **'Querschnitte'**
  String get lblSections;

  /// No description provided for @hintTapProfilesIn3d.
  ///
  /// In de, this message translates to:
  /// **'Profile in 3D antippen…'**
  String get hintTapProfilesIn3d;

  /// No description provided for @hintClickToAdd.
  ///
  /// In de, this message translates to:
  /// **'Zum Hinzufügen tippen'**
  String get hintClickToAdd;

  /// No description provided for @lblTransition.
  ///
  /// In de, this message translates to:
  /// **'Übergang'**
  String get lblTransition;

  /// No description provided for @lblSmooth.
  ///
  /// In de, this message translates to:
  /// **'Stetig'**
  String get lblSmooth;

  /// Inventor DE: "Geradlinig" — die Erhebung verbindet die Querschnitte mit Geraden statt tangentenstetig.
  ///
  /// In de, this message translates to:
  /// **'Geradlinig'**
  String get lblRuled;

  /// No description provided for @lblClosedLoop.
  ///
  /// In de, this message translates to:
  /// **'Geschlossene Schleife'**
  String get lblClosedLoop;

  /// No description provided for @lblMergeTangentFaces.
  ///
  /// In de, this message translates to:
  /// **'Tangentiale Flächen zusammenfassen'**
  String get lblMergeTangentFaces;

  /// Wendel-Parameter: die ANZAHL der Umdrehungen, nicht das Feature "Drehung".
  ///
  /// In de, this message translates to:
  /// **'Umdrehungen'**
  String get lblRevolutionCount;

  /// No description provided for @lblHeight.
  ///
  /// In de, this message translates to:
  /// **'Höhe'**
  String get lblHeight;

  /// Steigung einer Wendel. Nicht "Neigung".
  ///
  /// In de, this message translates to:
  /// **'Steigung'**
  String get lblPitch;

  /// No description provided for @lblRotationAngle.
  ///
  /// In de, this message translates to:
  /// **'Drehwinkel'**
  String get lblRotationAngle;

  /// No description provided for @hintTapLineOrAxis.
  ///
  /// In de, this message translates to:
  /// **'Linie oder Ursprungsachse antippen…'**
  String get hintTapLineOrAxis;

  /// No description provided for @lblSelectAxis.
  ///
  /// In de, this message translates to:
  /// **'Achse wählen'**
  String get lblSelectAxis;

  /// No description provided for @lblFull.
  ///
  /// In de, this message translates to:
  /// **'Voll'**
  String get lblFull;

  /// No description provided for @lblAngleA.
  ///
  /// In de, this message translates to:
  /// **'Winkel A'**
  String get lblAngleA;

  /// No description provided for @lblAngleB.
  ///
  /// In de, this message translates to:
  /// **'Winkel B'**
  String get lblAngleB;

  /// No description provided for @lblDistanceA.
  ///
  /// In de, this message translates to:
  /// **'Abstand A'**
  String get lblDistanceA;

  /// No description provided for @lblDistanceB.
  ///
  /// In de, this message translates to:
  /// **'Abstand B'**
  String get lblDistanceB;

  /// No description provided for @lblTerminateOn.
  ///
  /// In de, this message translates to:
  /// **'Enden auf'**
  String get lblTerminateOn;

  /// No description provided for @hintTapFaceIn3d.
  ///
  /// In de, this message translates to:
  /// **'Fläche in 3D antippen…'**
  String get hintTapFaceIn3d;

  /// No description provided for @lblSelectFace.
  ///
  /// In de, this message translates to:
  /// **'Fläche wählen'**
  String get lblSelectFace;

  /// No description provided for @lblFaceSelected.
  ///
  /// In de, this message translates to:
  /// **'Fläche gewählt — antippen zum Ändern'**
  String get lblFaceSelected;

  /// No description provided for @lblDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard'**
  String get lblDefault;

  /// No description provided for @lblFlipped.
  ///
  /// In de, this message translates to:
  /// **'Umgekehrt'**
  String get lblFlipped;

  /// No description provided for @lblSymmetric.
  ///
  /// In de, this message translates to:
  /// **'Symmetrisch'**
  String get lblSymmetric;

  /// No description provided for @lblAsymmetric.
  ///
  /// In de, this message translates to:
  /// **'Asymmetrisch'**
  String get lblAsymmetric;

  /// No description provided for @coilRevAndHeight.
  ///
  /// In de, this message translates to:
  /// **'Umdrehungen und Höhe'**
  String get coilRevAndHeight;

  /// No description provided for @coilPitchAndRev.
  ///
  /// In de, this message translates to:
  /// **'Steigung und Umdrehungen'**
  String get coilPitchAndRev;

  /// No description provided for @coilPitchAndHeight.
  ///
  /// In de, this message translates to:
  /// **'Steigung und Höhe'**
  String get coilPitchAndHeight;

  /// No description provided for @coilSpiral.
  ///
  /// In de, this message translates to:
  /// **'Spirale'**
  String get coilSpiral;

  /// No description provided for @hintTapSketchPointsIn3d.
  ///
  /// In de, this message translates to:
  /// **'Skizzenpunkte in 3D antippen…'**
  String get hintTapSketchPointsIn3d;

  /// No description provided for @lblCountersinkDia.
  ///
  /// In de, this message translates to:
  /// **'Senkung ⌀'**
  String get lblCountersinkDia;

  /// Inventor DE: "Endbedingung" — wo das Element aufhört.
  ///
  /// In de, this message translates to:
  /// **'Endbedingung'**
  String get lblTermination;

  /// No description provided for @lblIntoPart.
  ///
  /// In de, this message translates to:
  /// **'Ins Bauteil'**
  String get lblIntoPart;

  /// No description provided for @ctxShow.
  ///
  /// In de, this message translates to:
  /// **'Einblenden'**
  String get ctxShow;

  /// No description provided for @ctxLock.
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get ctxLock;

  /// No description provided for @ctxUnlock.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get ctxUnlock;

  /// No description provided for @ctxRenameEllipsis.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen…'**
  String get ctxRenameEllipsis;

  /// No description provided for @ctxMoveNHere.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eines hierher verschieben} other{{count} hierher verschieben}}'**
  String ctxMoveNHere(int count);

  /// No description provided for @ctxSuppressOccurrence.
  ///
  /// In de, this message translates to:
  /// **'Exemplar unterdrücken'**
  String get ctxSuppressOccurrence;

  /// No description provided for @ctxRestoreOccurrence.
  ///
  /// In de, this message translates to:
  /// **'Exemplar wiederherstellen'**
  String get ctxRestoreOccurrence;

  /// No description provided for @nodeYzPlane.
  ///
  /// In de, this message translates to:
  /// **'YZ-Ebene'**
  String get nodeYzPlane;

  /// No description provided for @nodeXzPlane.
  ///
  /// In de, this message translates to:
  /// **'XZ-Ebene'**
  String get nodeXzPlane;

  /// No description provided for @nodeXyPlane.
  ///
  /// In de, this message translates to:
  /// **'XY-Ebene'**
  String get nodeXyPlane;

  /// No description provided for @nodeZAxis.
  ///
  /// In de, this message translates to:
  /// **'Z-Achse'**
  String get nodeZAxis;

  /// No description provided for @msgLayerEmptyRemoved.
  ///
  /// In de, this message translates to:
  /// **'Dieser Layer ist leer und wird entfernt.'**
  String get msgLayerEmptyRemoved;

  /// No description provided for @msgRemovesLayerAndEntities.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Damit werden der Layer und sein einziges Objekt entfernt.} other{Damit werden der Layer und seine {count} Objekte entfernt.}}'**
  String msgRemovesLayerAndEntities(int count);

  /// No description provided for @secModelParameters.
  ///
  /// In de, this message translates to:
  /// **'Modellparameter'**
  String get secModelParameters;

  /// No description provided for @secUserParameters.
  ///
  /// In de, this message translates to:
  /// **'Benutzerparameter'**
  String get secUserParameters;

  /// No description provided for @lblLineN.
  ///
  /// In de, this message translates to:
  /// **'Linie {n}'**
  String lblLineN(String n);

  /// No description provided for @lblSingleOpenSplineOnly.
  ///
  /// In de, this message translates to:
  /// **'(nur ein offener Spline)'**
  String get lblSingleOpenSplineOnly;

  /// No description provided for @lblSolid.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper'**
  String get lblSolid;

  /// No description provided for @lblSelectSolid.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper wählen'**
  String get lblSelectSolid;

  /// M248 — die Eingabegeometrie der Baugruppen-Anordnung.
  ///
  /// In de, this message translates to:
  /// **'Komponente'**
  String get lblComponent;

  /// M248 — Platzhalter der Komponentenauswahl.
  ///
  /// In de, this message translates to:
  /// **'Komponenten wählen'**
  String get lblSelectComponents;

  /// M248 — wie viele Komponenten angeordnet werden.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Komponente} other{{n} Komponenten}}'**
  String lblNComponents(int n);

  /// M248 — der Hinweis am Auswahlfeld für Komponenten.
  ///
  /// In de, this message translates to:
  /// **'Komponente in 3D antippen…'**
  String get hintTapComponentIn3d;

  /// M248 — die assoziative Anordnung folgt einer Anordnung im Bauteil.
  ///
  /// In de, this message translates to:
  /// **'Element-Anordnung'**
  String get lblFeaturePattern;

  /// M248 — keine treibende Element-Anordnung: die Anordnung rechnet selbst.
  ///
  /// In de, this message translates to:
  /// **'Eigene Abstände'**
  String get lblOwnSpacing;

  /// No description provided for @lblFeature.
  ///
  /// In de, this message translates to:
  /// **'Element'**
  String get lblFeature;

  /// No description provided for @lblSelectFeatures.
  ///
  /// In de, this message translates to:
  /// **'Elemente wählen'**
  String get lblSelectFeatures;

  /// No description provided for @lblDirectionA.
  ///
  /// In de, this message translates to:
  /// **'Richtung A'**
  String get lblDirectionA;

  /// No description provided for @lblDirectionB.
  ///
  /// In de, this message translates to:
  /// **'Richtung B'**
  String get lblDirectionB;

  /// No description provided for @lblStartA.
  ///
  /// In de, this message translates to:
  /// **'Start A'**
  String get lblStartA;

  /// No description provided for @lblStartB.
  ///
  /// In de, this message translates to:
  /// **'Start B'**
  String get lblStartB;

  /// No description provided for @lblCurveStart.
  ///
  /// In de, this message translates to:
  /// **'Kurvenanfang'**
  String get lblCurveStart;

  /// No description provided for @lblMmAlong.
  ///
  /// In de, this message translates to:
  /// **'{value} mm entlang'**
  String lblMmAlong(String value);

  /// No description provided for @lblAddIrregularAngle.
  ///
  /// In de, this message translates to:
  /// **'Abweichender Winkel'**
  String get lblAddIrregularAngle;

  /// No description provided for @lblAddIrregularDistance.
  ///
  /// In de, this message translates to:
  /// **'Abweichender Abstand'**
  String get lblAddIrregularDistance;

  /// No description provided for @lblSelectDir.
  ///
  /// In de, this message translates to:
  /// **'Richtung…'**
  String get lblSelectDir;

  /// No description provided for @lblMidplane.
  ///
  /// In de, this message translates to:
  /// **'Mittelebene'**
  String get lblMidplane;

  /// No description provided for @lblCurveLength.
  ///
  /// In de, this message translates to:
  /// **'Kurvenlänge'**
  String get lblCurveLength;

  /// No description provided for @lblIdentical.
  ///
  /// In de, this message translates to:
  /// **'Identisch'**
  String get lblIdentical;

  /// No description provided for @lblIncremental.
  ///
  /// In de, this message translates to:
  /// **'Schrittweise'**
  String get lblIncremental;

  /// No description provided for @lblRotational.
  ///
  /// In de, this message translates to:
  /// **'Mitdrehend'**
  String get lblRotational;

  /// No description provided for @lblSketchPoint.
  ///
  /// In de, this message translates to:
  /// **'Skizzenpunkt'**
  String get lblSketchPoint;

  /// No description provided for @lblSelectPoint.
  ///
  /// In de, this message translates to:
  /// **'Punkt wählen'**
  String get lblSelectPoint;

  /// No description provided for @lblBasePoint.
  ///
  /// In de, this message translates to:
  /// **'Basispunkt'**
  String get lblBasePoint;

  /// No description provided for @lblFollowFace.
  ///
  /// In de, this message translates to:
  /// **'Fläche folgen'**
  String get lblFollowFace;

  /// No description provided for @lblMirrorPlane.
  ///
  /// In de, this message translates to:
  /// **'Spiegelebene'**
  String get lblMirrorPlane;

  /// No description provided for @lblCreationMethod.
  ///
  /// In de, this message translates to:
  /// **'Erzeugungsmethode'**
  String get lblCreationMethod;

  /// No description provided for @lblAdjust.
  ///
  /// In de, this message translates to:
  /// **'Anpassen'**
  String get lblAdjust;

  /// No description provided for @lblRemoveOriginal.
  ///
  /// In de, this message translates to:
  /// **'Original entfernen'**
  String get lblRemoveOriginal;

  /// No description provided for @lblKeepMirroredHalf.
  ///
  /// In de, this message translates to:
  /// **'Nur die gespiegelte Hälfte behalten'**
  String get lblKeepMirroredHalf;

  /// No description provided for @lblPatternFeatures.
  ///
  /// In de, this message translates to:
  /// **'Einzelne Elemente anordnen'**
  String get lblPatternFeatures;

  /// No description provided for @lblPatternSolid.
  ///
  /// In de, this message translates to:
  /// **'Einen Volumenkörper anordnen'**
  String get lblPatternSolid;

  /// No description provided for @lblPick.
  ///
  /// In de, this message translates to:
  /// **'Wählen'**
  String get lblPick;

  /// No description provided for @lblPointCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{{name} (ein Punkt)} other{{name} ({count} Punkte)}}'**
  String lblPointCount(String name, int count);

  /// No description provided for @lblCoords.
  ///
  /// In de, this message translates to:
  /// **'({x}, {y})'**
  String lblCoords(String x, String y);

  /// No description provided for @conCoincident.
  ///
  /// In de, this message translates to:
  /// **'Koinzident'**
  String get conCoincident;

  /// No description provided for @conCollinear.
  ///
  /// In de, this message translates to:
  /// **'Kollinear'**
  String get conCollinear;

  /// No description provided for @conConcentric.
  ///
  /// In de, this message translates to:
  /// **'Konzentrisch'**
  String get conConcentric;

  /// Inventor DE: "Fixieren" — die Abhaengigkeit, die Geometrie festnagelt.
  ///
  /// In de, this message translates to:
  /// **'Fixieren'**
  String get conLock;

  /// No description provided for @conParallel.
  ///
  /// In de, this message translates to:
  /// **'Parallel'**
  String get conParallel;

  /// Inventor DE: "Lotrecht", nicht "Senkrecht" — senkrecht heisst dort vertikal.
  ///
  /// In de, this message translates to:
  /// **'Lotrecht'**
  String get conPerpendicular;

  /// No description provided for @conHorizontal.
  ///
  /// In de, this message translates to:
  /// **'Horizontal'**
  String get conHorizontal;

  /// No description provided for @conVertical.
  ///
  /// In de, this message translates to:
  /// **'Vertikal'**
  String get conVertical;

  /// No description provided for @conTangent.
  ///
  /// In de, this message translates to:
  /// **'Tangential'**
  String get conTangent;

  /// No description provided for @conSymmetric.
  ///
  /// In de, this message translates to:
  /// **'Symmetrisch'**
  String get conSymmetric;

  /// No description provided for @conEqual.
  ///
  /// In de, this message translates to:
  /// **'Gleich'**
  String get conEqual;

  /// No description provided for @lblModuleMm.
  ///
  /// In de, this message translates to:
  /// **'Modul (mm)'**
  String get lblModuleMm;

  /// No description provided for @lblTeeth.
  ///
  /// In de, this message translates to:
  /// **'Zähne'**
  String get lblTeeth;

  /// No description provided for @lblCornerRadiusMm.
  ///
  /// In de, this message translates to:
  /// **'Eckenradius (mm)'**
  String get lblCornerRadiusMm;

  /// No description provided for @lblSunTeeth.
  ///
  /// In de, this message translates to:
  /// **'Sonnenzähne'**
  String get lblSunTeeth;

  /// No description provided for @lblPlanetTeeth.
  ///
  /// In de, this message translates to:
  /// **'Planetenzähne'**
  String get lblPlanetTeeth;

  /// No description provided for @lblPlanets.
  ///
  /// In de, this message translates to:
  /// **'Planeten'**
  String get lblPlanets;

  /// Verzahnungsbegriff: der Eingriffswinkel, nicht der "Druckwinkel".
  ///
  /// In de, this message translates to:
  /// **'Eingriffswinkel (°)'**
  String get lblPressureAngle;

  /// No description provided for @lblProfileShift.
  ///
  /// In de, this message translates to:
  /// **'Profilverschiebung'**
  String get lblProfileShift;

  /// No description provided for @lblBoreDia.
  ///
  /// In de, this message translates to:
  /// **'Bohrung Ø (mm)'**
  String get lblBoreDia;

  /// No description provided for @btnInsert.
  ///
  /// In de, this message translates to:
  /// **'Einfügen'**
  String get btnInsert;

  /// No description provided for @gearExternal.
  ///
  /// In de, this message translates to:
  /// **'Stirnrad'**
  String get gearExternal;

  /// No description provided for @gearInternal.
  ///
  /// In de, this message translates to:
  /// **'Hohlrad'**
  String get gearInternal;

  /// No description provided for @gearPlanetary.
  ///
  /// In de, this message translates to:
  /// **'Planetensatz'**
  String get gearPlanetary;

  /// Z fuer Zaehnezahl, wie auf einer deutschen Zeichnung.
  ///
  /// In de, this message translates to:
  /// **'Hohlrad {teeth}Z · Achsabstand {dist}'**
  String gearRingInfo(String teeth, String dist);

  /// Inventor DE: eine Skizze ist "vollständig bestimmt", wenn sie keine Freiheitsgrade mehr hat.
  ///
  /// In de, this message translates to:
  /// **'Vollständig bestimmt'**
  String get hudFullyConstrained;

  /// No description provided for @hudCancelEsc.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen (Esc)'**
  String get hudCancelEsc;

  /// No description provided for @hudDeleteN.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Ein Objekt löschen} other{{count} Objekte löschen}}'**
  String hudDeleteN(int count);

  /// Der Buchstabe ist das TASTENKUERZEL und bleibt, wie es auf der Tastatur liegt.
  ///
  /// In de, this message translates to:
  /// **'Linie (L)'**
  String get hudLineKey;

  /// No description provided for @hudCircleKey.
  ///
  /// In de, this message translates to:
  /// **'Kreis (C)'**
  String get hudCircleKey;

  /// No description provided for @hudRectKey.
  ///
  /// In de, this message translates to:
  /// **'Rechteck (R)'**
  String get hudRectKey;

  /// No description provided for @hudDimensionKey.
  ///
  /// In de, this message translates to:
  /// **'Bemaßung (D)'**
  String get hudDimensionKey;

  /// No description provided for @hintTapDimensionToInsert.
  ///
  /// In de, this message translates to:
  /// **'Eine Bemaßung in der Skizze antippen, um sie als „Name“ einzufügen'**
  String get hintTapDimensionToInsert;

  /// No description provided for @hintTextEmbedParams.
  ///
  /// In de, this message translates to:
  /// **'Text — Parameter als <Breite> oder „d0“ einbetten'**
  String get hintTextEmbedParams;

  /// No description provided for @msgReportSaved.
  ///
  /// In de, this message translates to:
  /// **'Bericht gesichert'**
  String get msgReportSaved;

  /// No description provided for @msgReportFailed.
  ///
  /// In de, this message translates to:
  /// **'Bericht FEHLGESCHLAGEN'**
  String get msgReportFailed;

  /// Der Pfad ist der, den iPadOS auf Deutsch anzeigt — die Dateien-App heisst so. "prototype" und "bugreports" sind Ordnernamen auf der Platte und bleiben.
  ///
  /// In de, this message translates to:
  /// **'Dateien-App > Auf meinem iPad > prototype > bugreports\nDie .zip verschicken — sie enthält alles Nötige; es muss keine Erklärung mitreisen.'**
  String get msgBugSaved;

  /// prototype_log.txt und die Logmarke "bug" sind Dateiname und Logmarke — sie bleiben, wie sie auf der Platte stehen.
  ///
  /// In de, this message translates to:
  /// **'Das Paket ließ sich nicht schreiben. Das Protokoll enthält die Beschreibung noch, die Sitzung ist also nicht verloren — siehe die „bug“-Zeilen in prototype_log.txt.'**
  String get msgBugBundleFailed;

  /// M285 — steht ueber dem Issue-Link im Ergebnisdialog, nur wenn ein Relay konfiguriert ist UND der Upload geklappt hat.
  ///
  /// In de, this message translates to:
  /// **'Zusätzlich online abgelegt — eine KI kann direkt darauf zugreifen.'**
  String get msgBugUploaded;

  /// M285 — nur sichtbar, wenn ein Relay konfiguriert ist und der Versand fehlgeschlagen ist; die lokale Kopie existiert in jedem Fall, das hier ist rein zusaetzlich.
  ///
  /// In de, this message translates to:
  /// **'Der Relay war nicht erreichbar — es gibt nur die lokale Kopie oben. Von Hand verschicken, oder es später erneut versuchen.'**
  String get msgBugUploadFailed;

  /// No description provided for @hintPickBodyTapCancel.
  ///
  /// In de, this message translates to:
  /// **'Körper wählen… (zum Abbrechen tippen)'**
  String get hintPickBodyTapCancel;

  /// No description provided for @lblSelectBodyIn3d.
  ///
  /// In de, this message translates to:
  /// **'Körper in 3D / im Browser wählen'**
  String get lblSelectBodyIn3d;

  /// No description provided for @secAdvancedProperties.
  ///
  /// In de, this message translates to:
  /// **'Erweiterte Eigenschaften'**
  String get secAdvancedProperties;

  /// No description provided for @lblTaperA.
  ///
  /// In de, this message translates to:
  /// **'Verjüngung A'**
  String get lblTaperA;

  /// No description provided for @lblMatchShape.
  ///
  /// In de, this message translates to:
  /// **'Form angleichen'**
  String get lblMatchShape;

  /// No description provided for @lblSelectFaceBtn.
  ///
  /// In de, this message translates to:
  /// **'Fläche wählen'**
  String get lblSelectFaceBtn;

  /// Z = Zaehnezahl, wie auf einer deutschen Zeichnung. {warn} ist leer oder der Hinweis unten.
  ///
  /// In de, this message translates to:
  /// **'Hohlrad {teeth}Z · Achsabstand {dist} mm{warn}'**
  String gearRingLine(String teeth, String dist, String warn);

  /// No description provided for @gearUnevenWarn.
  ///
  /// In de, this message translates to:
  /// **' · ⚠ Planeten nicht gleichmäßig verteilt'**
  String get gearUnevenWarn;

  /// Teilkreis / Kopfkreis / Fusskreis — die drei Verzahnungsdurchmesser.
  ///
  /// In de, this message translates to:
  /// **'Teilkreis Ø {pitch} · Kopf Ø {tip} · Fuß Ø {root} mm'**
  String gearPitchLine(String pitch, String tip, String root);

  /// No description provided for @msgRemovesLayerAndEntitiesUndo.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Entfernt den Layer und sein einziges Objekt. Nicht rückgängig zu machen.} other{Entfernt den Layer und seine {count} Objekte. Nicht rückgängig zu machen.}}'**
  String msgRemovesLayerAndEntitiesUndo(int count);

  /// No description provided for @valNameEmpty.
  ///
  /// In de, this message translates to:
  /// **'Der Name darf nicht leer sein'**
  String get valNameEmpty;

  /// No description provided for @valNameTooLong.
  ///
  /// In de, this message translates to:
  /// **'Der Name ist zu lang'**
  String get valNameTooLong;

  /// No description provided for @valNameBadChars.
  ///
  /// In de, this message translates to:
  /// **'Der Name darf / \\ und : nicht enthalten'**
  String get valNameBadChars;

  /// No description provided for @valNameLeadingDot.
  ///
  /// In de, this message translates to:
  /// **'Der Name darf nicht mit einem Punkt beginnen'**
  String get valNameLeadingDot;

  /// No description provided for @valBodyNameTaken.
  ///
  /// In de, this message translates to:
  /// **'Ein Körper namens „{name}“ existiert bereits'**
  String valBodyNameTaken(String name);

  /// No description provided for @valFeatureNameTaken.
  ///
  /// In de, this message translates to:
  /// **'Ein Element namens „{name}“ existiert bereits'**
  String valFeatureNameTaken(String name);

  /// No description provided for @valSelectOneEdge.
  ///
  /// In de, this message translates to:
  /// **'Mindestens eine Kante wählen.'**
  String get valSelectOneEdge;

  /// No description provided for @valRadiusPositive.
  ///
  /// In de, this message translates to:
  /// **'Radius muss größer als 0 sein.'**
  String get valRadiusPositive;

  /// No description provided for @valRadiusOfSetPositive.
  ///
  /// In de, this message translates to:
  /// **'Radius von Gruppe {n} muss größer als 0 sein.'**
  String valRadiusOfSetPositive(String n);

  /// No description provided for @valEndRadiusPositive.
  ///
  /// In de, this message translates to:
  /// **'Endradius muss größer als 0 sein.'**
  String get valEndRadiusPositive;

  /// No description provided for @valEndRadiusOfSetPositive.
  ///
  /// In de, this message translates to:
  /// **'Endradius von Gruppe {n} muss größer als 0 sein.'**
  String valEndRadiusOfSetPositive(String n);

  /// No description provided for @valDistancePositive.
  ///
  /// In de, this message translates to:
  /// **'Abstand muss größer als 0 sein.'**
  String get valDistancePositive;

  /// No description provided for @valDistance2Positive.
  ///
  /// In de, this message translates to:
  /// **'Abstand 2 muss größer als 0 sein.'**
  String get valDistance2Positive;

  /// No description provided for @valAngle0to90.
  ///
  /// In de, this message translates to:
  /// **'Der Winkel muss zwischen 0 und 90 Grad liegen.'**
  String get valAngle0to90;

  /// M248 — die Baugruppen-Anordnung ohne Ausgangskomponente.
  ///
  /// In de, this message translates to:
  /// **'Mindestens eine Komponente zum Anordnen wählen.'**
  String get valSelectOneComponent;

  /// M248 — eine assoziative Anordnung, deren Bauteil-Anordnung gelöscht wurde.
  ///
  /// In de, this message translates to:
  /// **'Die treibende Element-Anordnung ist nicht mehr da.'**
  String get valDrivingFeatureGone;

  /// No description provided for @valSelectOneFeature.
  ///
  /// In de, this message translates to:
  /// **'Mindestens ein Element zum Anordnen wählen.'**
  String get valSelectOneFeature;

  /// No description provided for @valSelectDirectionA.
  ///
  /// In de, this message translates to:
  /// **'Richtung oder Kurve für Richtung A wählen.'**
  String get valSelectDirectionA;

  /// No description provided for @valCountAAtLeastOne.
  ///
  /// In de, this message translates to:
  /// **'Die Anzahl in Richtung A muss mindestens 1 sein.'**
  String get valCountAAtLeastOne;

  /// No description provided for @valDistanceAPositive.
  ///
  /// In de, this message translates to:
  /// **'Der Abstand in Richtung A muss größer als 0 sein.'**
  String get valDistanceAPositive;

  /// No description provided for @valCountBAtLeastOne.
  ///
  /// In de, this message translates to:
  /// **'Die Anzahl in Richtung B muss mindestens 1 sein.'**
  String get valCountBAtLeastOne;

  /// No description provided for @valDistanceBPositive.
  ///
  /// In de, this message translates to:
  /// **'Der Abstand in Richtung B muss größer als 0 sein.'**
  String get valDistanceBPositive;

  /// No description provided for @valPatternNeedsTwo.
  ///
  /// In de, this message translates to:
  /// **'Eine Anordnung braucht mehr als ein Exemplar.'**
  String get valPatternNeedsTwo;

  /// No description provided for @valSelectRotationAxis.
  ///
  /// In de, this message translates to:
  /// **'Drehachse wählen.'**
  String get valSelectRotationAxis;

  /// No description provided for @valCountAtLeastOne.
  ///
  /// In de, this message translates to:
  /// **'Die Anzahl muss mindestens 1 sein.'**
  String get valCountAtLeastOne;

  /// No description provided for @valAngleNotZero.
  ///
  /// In de, this message translates to:
  /// **'Der Winkel darf nicht 0 sein.'**
  String get valAngleNotZero;

  /// No description provided for @valSelectPointSketch.
  ///
  /// In de, this message translates to:
  /// **'Die Skizze mit den Punkten wählen.'**
  String get valSelectPointSketch;

  /// No description provided for @valSelectMirrorPlane.
  ///
  /// In de, this message translates to:
  /// **'Spiegelebene wählen.'**
  String get valSelectMirrorPlane;

  /// No description provided for @valNoSolidToPattern.
  ///
  /// In de, this message translates to:
  /// **'Es gibt noch keinen Volumenkörper zum Anordnen.'**
  String get valNoSolidToPattern;

  /// No description provided for @valSelectPathCurve.
  ///
  /// In de, this message translates to:
  /// **'Pfadkurve wählen.'**
  String get valSelectPathCurve;

  /// No description provided for @valTwistUnsupported.
  ///
  /// In de, this message translates to:
  /// **'Verdrehung wird noch nicht unterstützt — auf 0 lassen.'**
  String get valTwistUnsupported;

  /// No description provided for @valSelectTwoSections.
  ///
  /// In de, this message translates to:
  /// **'Mindestens zwei Querschnitte wählen.'**
  String get valSelectTwoSections;

  /// No description provided for @valSelectAxis.
  ///
  /// In de, this message translates to:
  /// **'Achse wählen.'**
  String get valSelectAxis;

  /// No description provided for @valPitchPositive.
  ///
  /// In de, this message translates to:
  /// **'Steigung muss größer als 0 sein.'**
  String get valPitchPositive;

  /// No description provided for @valRevolutionPositive.
  ///
  /// In de, this message translates to:
  /// **'Umdrehungen müssen größer als 0 sein.'**
  String get valRevolutionPositive;

  /// No description provided for @valHeightPositive.
  ///
  /// In de, this message translates to:
  /// **'Höhe muss größer als 0 sein.'**
  String get valHeightPositive;

  /// No description provided for @valSelectRevolveAxis.
  ///
  /// In de, this message translates to:
  /// **'Drehachse wählen.'**
  String get valSelectRevolveAxis;

  /// No description provided for @valAxisNoDirection.
  ///
  /// In de, this message translates to:
  /// **'Die Achse gibt keine Richtung vor.'**
  String get valAxisNoDirection;

  /// No description provided for @valAngleA0to360.
  ///
  /// In de, this message translates to:
  /// **'Winkel A muss zwischen 0 und 360 Grad liegen.'**
  String get valAngleA0to360;

  /// No description provided for @valAngleBPositive.
  ///
  /// In de, this message translates to:
  /// **'Winkel B muss größer als 0 sein.'**
  String get valAngleBPositive;

  /// No description provided for @valAngleABMax360.
  ///
  /// In de, this message translates to:
  /// **'Winkel A + B dürfen 360 Grad nicht überschreiten.'**
  String get valAngleABMax360;

  /// No description provided for @valDistanceAPositiveShort.
  ///
  /// In de, this message translates to:
  /// **'Abstand A muss größer als 0 sein.'**
  String get valDistanceAPositiveShort;

  /// No description provided for @valDistanceBPositiveShort.
  ///
  /// In de, this message translates to:
  /// **'Abstand B muss größer als 0 sein.'**
  String get valDistanceBPositiveShort;

  /// No description provided for @valTaperRange.
  ///
  /// In de, this message translates to:
  /// **'Die Verjüngung muss zwischen -90 und 90 Grad liegen.'**
  String get valTaperRange;

  /// No description provided for @lblSelectDirPlaceholder.
  ///
  /// In de, this message translates to:
  /// **'Richtung…'**
  String get lblSelectDirPlaceholder;

  /// No description provided for @lblMirrorPlanePlaceholder.
  ///
  /// In de, this message translates to:
  /// **'Spiegelebene'**
  String get lblMirrorPlanePlaceholder;

  /// No description provided for @lblCenterlineGeo.
  ///
  /// In de, this message translates to:
  /// **'Mittellinie'**
  String get lblCenterlineGeo;

  /// No description provided for @lblConstructionLineGeo.
  ///
  /// In de, this message translates to:
  /// **'Konstruktionslinie'**
  String get lblConstructionLineGeo;

  /// No description provided for @lblLineGeo.
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get lblLineGeo;

  /// Ribbon-Gruppe der Baugruppe. Inventor DE: "Komponente".
  ///
  /// In de, this message translates to:
  /// **'Komponente'**
  String get panelComponent;

  /// Anzeigemodus: matte Flaechen mit allen B-Rep-Kanten darueber. Der Arbeitsmodus. Inventor DE: "Schattiert mit Kanten".
  ///
  /// In de, this message translates to:
  /// **'Schattiert + Kanten'**
  String get viewShadedEdges;

  /// Anzeigemodus: PBR-Materialien, Licht mit Schatten, keine Kanten. Bewusst nicht "Raytracing" — RealityKit rastert.
  ///
  /// In de, this message translates to:
  /// **'Gerendert'**
  String get viewRendered;

  /// Kontrollkaestchen im Anzeigemodus-Band: blendet den gerenderten Boden ein/aus. Nur im gerenderten Modus sichtbar.
  ///
  /// In de, this message translates to:
  /// **'Boden anzeigen'**
  String get viewFloor;

  /// ViewCube-Menue: dreht den Wuerfel so, dass die aktuelle Ansicht die Vorderansicht wird. Inventor DE: "Aktuelle Ansicht als Vorne".
  ///
  /// In de, this message translates to:
  /// **'Aktuelle Ansicht als Vorne'**
  String get cubeSetFront;

  /// ViewCube-Menue: dasselbe fuer die Draufsicht.
  ///
  /// In de, this message translates to:
  /// **'Aktuelle Ansicht als Oben'**
  String get cubeSetTop;

  /// ViewCube-Menue: nimmt eine neu definierte Vorderansicht zurueck.
  ///
  /// In de, this message translates to:
  /// **'Vorne zuruecksetzen'**
  String get cubeResetFront;

  /// Barrierefreier Name des gebogenen Pfeils: dreht die Ansicht um 90 Grad in der Bildebene.
  ///
  /// In de, this message translates to:
  /// **'Ansicht nach links drehen'**
  String get cubeRollLeft;

  /// Barrierefreier Name des gebogenen Pfeils, andere Richtung.
  ///
  /// In de, this message translates to:
  /// **'Ansicht nach rechts drehen'**
  String get cubeRollRight;

  /// Barrierefreier Name der vier dreieckigen Pfeile: eine Vierteldrehung zur angrenzenden Flaeche.
  ///
  /// In de, this message translates to:
  /// **'Zur Nachbaransicht'**
  String get cubeStep;

  /// Rueckmeldung nach dem Projizieren einer ganzen Flaeche.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Kante projiziert} other{{n} Kanten projiziert}}'**
  String msgProjectedFace(int n);

  /// Aussehen: kein Schnitt, das ganze Modell. Standard.
  ///
  /// In de, this message translates to:
  /// **'Kein Schnitt'**
  String get sectionNone;

  /// Aussehen: eine Ebene, die nahe Haelfte wird entfernt. Inventor: "Half Section View".
  ///
  /// In de, this message translates to:
  /// **'Halbschnitt'**
  String get sectionHalf;

  /// Aussehen: zwei Ebenen, ein Viertel des Modells bleibt stehen. Inventor: "Quarter Section View".
  ///
  /// In de, this message translates to:
  /// **'Viertelschnitt'**
  String get sectionQuarter;

  /// Aussehen: zwei Ebenen, ein Viertel wird herausgeschnitten. Inventor: "Three Quarter Section View".
  ///
  /// In de, this message translates to:
  /// **'Dreiviertelschnitt'**
  String get sectionThreeQuarter;

  /// Schnittansicht: welche Seite der ersten Ebene entfernt wird. Inventor: "Flip".
  ///
  /// In de, this message translates to:
  /// **'Ebene 1 umkehren'**
  String get sectionFlip1;

  /// Schnittansicht: welche Seite der zweiten Ebene entfernt wird.
  ///
  /// In de, this message translates to:
  /// **'Ebene 2 umkehren'**
  String get sectionFlip2;

  /// Aufforderung, waehrend die Schnittansicht auf die erste Ebene wartet.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder ebene Flaeche zum Schneiden antippen'**
  String get msgPickSectionPlane;

  /// Aufforderung, waehrend die Schnittansicht auf die zweite Ebene wartet.
  ///
  /// In de, this message translates to:
  /// **'Zweite Ebene antippen'**
  String get msgPickSectionPlane2;

  /// Ribbon-Gruppe: die Farbe eines Koerpers oder einer Komponente. Inventor DE: "Aussehen".
  ///
  /// In de, this message translates to:
  /// **'Aussehen'**
  String get panelAppearance;

  /// Steht im Aussehen-Feld, solange kein Koerper und keine Komponente gewaehlt ist.
  ///
  /// In de, this message translates to:
  /// **'Nichts gewaehlt'**
  String get matPickBody;

  /// Aussehen: das schlichte Grau, mit dem alles gebaut wird.
  ///
  /// In de, this message translates to:
  /// **'Stahl'**
  String get matSteel;

  /// Aussehen: helles Metallgrau.
  ///
  /// In de, this message translates to:
  /// **'Aluminium'**
  String get matAluminium;

  /// Aussehen: dunkles Grau.
  ///
  /// In de, this message translates to:
  /// **'Graphit'**
  String get matGraphite;

  /// Aussehen: gedaempftes Gelbgold.
  ///
  /// In de, this message translates to:
  /// **'Messing'**
  String get matBrass;

  /// Aussehen: gedaempftes Rotbraun.
  ///
  /// In de, this message translates to:
  /// **'Kupfer'**
  String get matCopper;

  /// Aussehen: gedaempftes Rot.
  ///
  /// In de, this message translates to:
  /// **'Rot'**
  String get matRed;

  /// Aussehen: gedaempftes Gruen.
  ///
  /// In de, this message translates to:
  /// **'Gruen'**
  String get matGreen;

  /// Aussehen: gedaempftes Blau.
  ///
  /// In de, this message translates to:
  /// **'Blau'**
  String get matBlue;

  /// Aussehen: gedaempftes Violett.
  ///
  /// In de, this message translates to:
  /// **'Violett'**
  String get matViolet;

  /// Ribbon-Gruppe der Baugruppe. Inventor DE: "Position".
  ///
  /// In de, this message translates to:
  /// **'Position'**
  String get panelPosition;

  /// Ribbon-Gruppe der Baugruppe. Inventor DE: "Beziehungen" (Gelenke und Abhaengigkeiten).
  ///
  /// In de, this message translates to:
  /// **'Beziehungen'**
  String get panelRelationships;

  /// No description provided for @btnPlace.
  ///
  /// In de, this message translates to:
  /// **'Platzieren'**
  String get btnPlace;

  /// Baugruppe: neues Bauteil an Ort und Stelle erstellen. Inventor DE: "Erstellen".
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get btnCreateComponent;

  /// Inventor DE: "Frei bewegen".
  ///
  /// In de, this message translates to:
  /// **'Frei bewegen'**
  String get btnFreeMove;

  /// Inventor DE: "Frei drehen".
  ///
  /// In de, this message translates to:
  /// **'Frei drehen'**
  String get btnFreeRotate;

  /// Inventor DE: "Gelenk".
  ///
  /// In de, this message translates to:
  /// **'Gelenk'**
  String get btnJoint;

  /// Inventor DE: "Abhängig machen". Steht unter einem Symbol, das mitwaechst (M235), daher das groessere Budget.
  ///
  /// In de, this message translates to:
  /// **'Abhängig machen'**
  String get btnConstrain;

  /// Beziehungen einblenden. Inventor DE: "Einblenden".
  ///
  /// In de, this message translates to:
  /// **'Einblenden'**
  String get btnShowRelationships;

  /// Inventor DE: "Fehlerhafte einblenden" — in der schmalen Zeile auf das Adjektiv gekuerzt, wie Inventor selbst "Show Sick" kuerzt.
  ///
  /// In de, this message translates to:
  /// **'Fehlerhafte'**
  String get btnShowSick;

  /// Inventor DE: "Alle ausblenden".
  ///
  /// In de, this message translates to:
  /// **'Alle ausblenden'**
  String get btnHideAll;

  /// Baugruppen-Anordnung. Inventor DE: "Anordnung", nicht "Muster".
  ///
  /// In de, this message translates to:
  /// **'Anordnung'**
  String get btnPatternComponent;

  /// Eintrag im "+"-Menue der Galerie.
  ///
  /// In de, this message translates to:
  /// **'Neue Baugruppe'**
  String get galleryNewAssembly;

  /// Titel des Dialogs, der nach dem Namen fragt.
  ///
  /// In de, this message translates to:
  /// **'Neue Baugruppe'**
  String get dlgNewAssembly;

  /// No description provided for @phAssemblyName.
  ///
  /// In de, this message translates to:
  /// **'Baugruppenname'**
  String get phAssemblyName;

  /// Browserknoten der Baugruppe. Inventor DE: "Darstellungen".
  ///
  /// In de, this message translates to:
  /// **'Darstellungen'**
  String get nodeRepresentations;

  /// Browserknoten der Baugruppe. Inventor DE: "Beziehungen".
  ///
  /// In de, this message translates to:
  /// **'Beziehungen'**
  String get nodeRelationships;

  /// Titel der Liste, aus der ein Bauteil gewaehlt wird.
  ///
  /// In de, this message translates to:
  /// **'Komponente platzieren'**
  String get dlgPlaceComponent;

  /// No description provided for @msgAsmNoPartsToPlace.
  ///
  /// In de, this message translates to:
  /// **'Erstellen Sie zuerst ein 3D-Bauteil — es gibt nichts zu platzieren.'**
  String get msgAsmNoPartsToPlace;

  /// No description provided for @msgAsmNoSuchPart.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist kein Bauteil.'**
  String msgAsmNoSuchPart(String name);

  /// No description provided for @msgAsmCouldNotPlace.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ konnte nicht platziert werden.'**
  String msgAsmCouldNotPlace(String name);

  /// Toast beim Ziehversuch an einer fixierten Komponente.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist fixiert.'**
  String msgAsmGrounded(String name);

  /// Kontextmenue einer Komponente. Inventor DE: "Fixiert".
  ///
  /// In de, this message translates to:
  /// **'Fixiert'**
  String get ctxGrounded;

  /// Titel des Abhängigkeitsdialogs. Inventor DE: "Abhängigkeit platzieren".
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeit platzieren'**
  String get dlgPlaceConstraint;

  /// Erster Reiter des Abhängigkeitsdialogs (Passend, Winkel, Tangential, Einfügen, Symmetrie).
  ///
  /// In de, this message translates to:
  /// **'Baugruppe'**
  String get tabAsmAssembly;

  /// Zweiter Reiter des Abhängigkeitsdialogs (Drehung, Drehung-Translation).
  ///
  /// In de, this message translates to:
  /// **'Bewegung'**
  String get tabAsmMotion;

  /// Dritter Reiter des Abhängigkeitsdialogs (Kurvenscheibe und Abtaster).
  ///
  /// In de, this message translates to:
  /// **'Übergang'**
  String get tabAsmTransitional;

  /// Vierter Reiter des Abhängigkeitsdialogs. Inventor DE: "Abhängigkeitssatz".
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeitssatz'**
  String get tabAsmConstraintSet;

  /// Gruppe der Typ-Schaltflächen im Abhängigkeitsdialog.
  ///
  /// In de, this message translates to:
  /// **'Typ'**
  String get grpAsmType;

  /// Gruppe der Auswahlschaltflächen im Abhängigkeitsdialog.
  ///
  /// In de, this message translates to:
  /// **'Auswahlen'**
  String get grpAsmSelections;

  /// Gruppe der Lösungsschaltflächen im Abhängigkeitsdialog.
  ///
  /// In de, this message translates to:
  /// **'Lösung'**
  String get grpAsmSolution;

  /// Beschriftung des Zahlenfelds bei Passend, Tangential und Einfügen. Mit Doppelpunkt wie in Inventor.
  ///
  /// In de, this message translates to:
  /// **'Versatz'**
  String get lblAsmOffset;

  /// Beschriftung des Zahlenfelds bei einer Winkelabhängigkeit.
  ///
  /// In de, this message translates to:
  /// **'Winkel'**
  String get lblAsmAngle;

  /// Beschriftung des Zahlenfelds bei einer Drehungsabhängigkeit (Zahnradverhältnis).
  ///
  /// In de, this message translates to:
  /// **'Verhältnis'**
  String get lblAsmRatio;

  /// Beschriftung des Zahlenfelds bei Drehung-Translation: Weg pro voller Umdrehung.
  ///
  /// In de, this message translates to:
  /// **'Abstand'**
  String get lblAsmDistance;

  /// Kontrollkästchen neben den Auswahlschaltflächen. Inventor DE: "Bauteil zuerst wählen".
  ///
  /// In de, this message translates to:
  /// **'Bauteil zuerst wählen'**
  String get cbAsmPickPartFirst;

  /// Kontrollkästchen mit dem Brillensymbol: zeigt die Wirkung vor dem Übernehmen.
  ///
  /// In de, this message translates to:
  /// **'Vorschau anzeigen'**
  String get cbAsmShowPreview;

  /// Kontrollkästchen: füllt das Zahlenfeld mit dem aktuell gemessenen Wert.
  ///
  /// In de, this message translates to:
  /// **'Versatz und Ausrichtung vorhersagen'**
  String get cbAsmPredict;

  /// Kontrollkästchen hinter dem Erweitern-Knopf: neue Winkelabhängigkeiten öffnen ungerichtet.
  ///
  /// In de, this message translates to:
  /// **'Standardmäßig ungerichtet'**
  String get cbAsmDefaultUndirected;

  /// Namensfeld hinter dem Erweitern-Knopf des Abhängigkeitsdialogs.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get lblAsmName;

  /// Platzhalter im Namensfeld: leer lassen heisst automatisch benennen.
  ///
  /// In de, this message translates to:
  /// **'Automatisch'**
  String get hintAsmAutoName;

  /// Tooltip der nummerierten Auswahlschaltflächen.
  ///
  /// In de, this message translates to:
  /// **'Auswahl {n}'**
  String tipAsmSelection(int n);

  /// Hinweis im Dialog, solange eine Auswahl fehlt.
  ///
  /// In de, this message translates to:
  /// **'Fläche, Kante oder Achse antippen'**
  String get hintAsmPickGeometry;

  /// Abhängigkeitstyp. Inventor DE: "Passend".
  ///
  /// In de, this message translates to:
  /// **'Passend'**
  String get asmMate;

  /// Abhängigkeitstyp Winkel.
  ///
  /// In de, this message translates to:
  /// **'Winkel'**
  String get asmAngle;

  /// Abhängigkeitstyp Tangential.
  ///
  /// In de, this message translates to:
  /// **'Tangential'**
  String get asmTangent;

  /// Abhängigkeitstyp Einfügen (Schraube im Loch).
  ///
  /// In de, this message translates to:
  /// **'Einfügen'**
  String get asmInsert;

  /// Abhängigkeitstyp Symmetrie.
  ///
  /// In de, this message translates to:
  /// **'Symmetrie'**
  String get asmSymmetry;

  /// Bewegungsabhängigkeit: Zahnradpaar.
  ///
  /// In de, this message translates to:
  /// **'Drehung'**
  String get asmRotation;

  /// Bewegungsabhängigkeit: Zahnstange und Ritzel.
  ///
  /// In de, this message translates to:
  /// **'Drehung-Translation'**
  String get asmRotationTranslation;

  /// Übergangsabhängigkeit: Kurvenscheibe und Abtaster.
  ///
  /// In de, this message translates to:
  /// **'Übergang'**
  String get asmTransitional;

  /// Lösung einer Passend-Abhängigkeit: Flächen zeigen aufeinander zu.
  ///
  /// In de, this message translates to:
  /// **'Passend'**
  String get solMate;

  /// Lösung einer Passend-Abhängigkeit: Flächen zeigen in dieselbe Richtung.
  ///
  /// In de, this message translates to:
  /// **'Ausgerichtet'**
  String get solFlush;

  /// Winkellösung mit festgehaltenem Referenzvektor.
  ///
  /// In de, this message translates to:
  /// **'Gerichteter Winkel'**
  String get solDirectedAngle;

  /// Winkellösung ohne Vorzeichen.
  ///
  /// In de, this message translates to:
  /// **'Ungerichteter Winkel'**
  String get solUndirectedAngle;

  /// Winkellösung mit einer dritten Auswahl als Referenzachse.
  ///
  /// In de, this message translates to:
  /// **'Expliziter Referenzvektor'**
  String get solExplicitVector;

  /// Tangentiallösung: der Zylinder liegt innen an.
  ///
  /// In de, this message translates to:
  /// **'Innen'**
  String get solInside;

  /// Tangentiallösung: der Zylinder liegt außen an.
  ///
  /// In de, this message translates to:
  /// **'Außen'**
  String get solOutside;

  /// Einfügelösung: die Teile zeigen aufeinander zu.
  ///
  /// In de, this message translates to:
  /// **'Entgegengesetzt'**
  String get solOpposed;

  /// Einfügelösung: die Teile zeigen in dieselbe Richtung.
  ///
  /// In de, this message translates to:
  /// **'Ausgerichtet'**
  String get solAligned;

  /// Symmetrielösung: gespiegelt zueinander.
  ///
  /// In de, this message translates to:
  /// **'Symmetrisch'**
  String get solSymmetric;

  /// Symmetrielösung mit umgekehrtem Richtungssinn.
  ///
  /// In de, this message translates to:
  /// **'Asymmetrisch'**
  String get solAsymmetric;

  /// Bewegungslösung: gleicher Drehsinn.
  ///
  /// In de, this message translates to:
  /// **'Vorwärts'**
  String get solForward;

  /// Bewegungslösung: umgekehrter Drehsinn.
  ///
  /// In de, this message translates to:
  /// **'Rückwärts'**
  String get solReverse;

  /// Kontextmenü einer Abhängigkeit: vorübergehend abschalten.
  ///
  /// In de, this message translates to:
  /// **'Unterdrücken'**
  String get ctxSuppress;

  /// Kontextmenü einer unterdrückten Abhängigkeit.
  ///
  /// In de, this message translates to:
  /// **'Unterdrückung aufheben'**
  String get ctxUnsuppress;

  /// Statuszeile der Baugruppe: verbleibende Freiheitsgrade.
  ///
  /// In de, this message translates to:
  /// **'{n} Freiheitsgrade'**
  String hudAsmDof(int n);

  /// Statuszeile der Baugruppe, wenn kein Freiheitsgrad übrig ist.
  ///
  /// In de, this message translates to:
  /// **'Vollständig bestimmt'**
  String get hudAsmFullyConstrained;

  /// Meldung, wenn die zweite Auswahl dieselbe Komponente betrifft wie die erste.
  ///
  /// In de, this message translates to:
  /// **'Beide Auswahlen liegen auf derselben Komponente.'**
  String get msgAsmSameComponent;

  /// Meldung, wenn OK oder Übernehmen ohne vollständige Auswahl gedrückt wird.
  ///
  /// In de, this message translates to:
  /// **'Zuerst zwei Geometrien auswählen.'**
  String get msgAsmPickTwo;

  /// Meldung: Tangential verlangt einen Zylinder auf mindestens einer Seite.
  ///
  /// In de, this message translates to:
  /// **'Tangential braucht eine runde Fläche.'**
  String get msgAsmTangentNeedsRound;

  /// Meldung: Einfügen verlangt auf beiden Seiten eine Achse.
  ///
  /// In de, this message translates to:
  /// **'Einfügen braucht zwei Achsen oder Kreiskanten.'**
  String get msgAsmInsertNeedsAxes;

  /// Meldung: eine Winkelabhängigkeit kann nicht auf einen Punkt wirken.
  ///
  /// In de, this message translates to:
  /// **'Winkel braucht zwei Richtungen.'**
  String get msgAsmAngleNeedsDirections;

  /// Meldung: eine Bewegungsabhängigkeit verlangt zwei Drehachsen.
  ///
  /// In de, this message translates to:
  /// **'Bewegung braucht zwei Achsen.'**
  String get msgAsmMotionNeedsAxes;

  /// Meldung: nichts konnte sich bewegen, weil beide Seiten fixiert sind.
  ///
  /// In de, this message translates to:
  /// **'Beide Komponenten sind fixiert.'**
  String get msgAsmBothGrounded;

  /// Meldung: die Abhängigkeit zeigt auf eine Komponente, die es nicht mehr gibt.
  ///
  /// In de, this message translates to:
  /// **'Die Komponente dieser Abhängigkeit fehlt.'**
  String get msgAsmMissingComponent;

  /// Meldung: der Löser hat die Abhängigkeit nicht erfüllen können.
  ///
  /// In de, this message translates to:
  /// **'Diese Abhängigkeit lässt sich nicht erfüllen.'**
  String get msgAsmCannotSatisfy;

  /// Meldung: das gewählte Geometriepaar passt nicht zum gewählten Typ.
  ///
  /// In de, this message translates to:
  /// **'Diese Auswahl lässt sich so nicht abhängig machen.'**
  String get msgAsmCannotConstrain;

  /// Meldung nach dem Löschen einer Abhängigkeit.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ gelöscht.'**
  String msgAsmConstraintDeleted(String name);

  /// Hinweis im leeren Reiter Abhängigkeitssatz: der Typ braucht ein BKS, das es noch nicht gibt.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht verfügbar'**
  String get hintAsmConstraintSet;

  /// Meldung: eine Baugruppe kann sich nicht selbst enthalten.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ enthält diese Baugruppe bereits.'**
  String msgAsmWouldNest(String name);

  /// Titel des Gelenkdialogs. Inventor DE: "Gelenk platzieren".
  ///
  /// In de, this message translates to:
  /// **'Gelenk platzieren'**
  String get dlgPlaceJoint;

  /// Gruppe im Gelenkdialog mit den beiden Ursprungsauswahlen und dem Abstand.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get grpAsmConnect;

  /// Zahlenfeld im Gelenkdialog: Abstand zwischen den beiden Gelenkursprüngen.
  ///
  /// In de, this message translates to:
  /// **'Abstand'**
  String get lblAsmGap;

  /// Gelenktyp: Inventor leitet den Typ aus den beiden Ursprüngen ab.
  ///
  /// In de, this message translates to:
  /// **'Automatisch'**
  String get jtAutomatic;

  /// Gelenktyp ohne Freiheitsgrad (geschweißt, verschraubt).
  ///
  /// In de, this message translates to:
  /// **'Starr'**
  String get jtRigid;

  /// Gelenktyp mit einem Drehfreiheitsgrad (Scharnier).
  ///
  /// In de, this message translates to:
  /// **'Drehung'**
  String get jtRotational;

  /// Gelenktyp mit einem Verschiebefreiheitsgrad (Schlitten in einer Führung).
  ///
  /// In de, this message translates to:
  /// **'Schieber'**
  String get jtSlider;

  /// Gelenktyp mit einem Dreh- und einem Verschiebefreiheitsgrad (Welle in einer Bohrung).
  ///
  /// In de, this message translates to:
  /// **'Zylindrisch'**
  String get jtCylindrical;

  /// Gelenktyp mit zwei Verschiebe- und einem Drehfreiheitsgrad (auf einer Fläche).
  ///
  /// In de, this message translates to:
  /// **'Eben'**
  String get jtPlanar;

  /// Gelenktyp mit drei Drehfreiheitsgraden (Kugelgelenk).
  ///
  /// In de, this message translates to:
  /// **'Kugel'**
  String get jtBall;

  /// Zeigt im Gelenkdialog, welchen Typ Automatisch aus den Auswahlen abgeleitet hat.
  ///
  /// In de, this message translates to:
  /// **'Automatisch: {type}'**
  String hintAsmJointAuto(String type);

  /// Zeigt im Gelenkdialog, wie viele Freiheitsgrade der gewählte Typ übrig lässt. Starr laesst keinen, Drehung genau einen — der Singular ist also der haeufigste Fall und keine Randbedingung.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Kein Freiheitsgrad bleibt} =1{Ein Freiheitsgrad bleibt} other{{n} Freiheitsgrade bleiben}}'**
  String hintAsmJointDof(int n);

  /// Meldung: alle Gelenke außer Kugel brauchen auf beiden Seiten eine Achse oder eine Fläche.
  ///
  /// In de, this message translates to:
  /// **'Dieses Gelenk braucht zwei Richtungen.'**
  String get msgAsmJointNeedsDirections;

  /// Hinweis, während der Befehl Einblenden auf eine Komponente wartet.
  ///
  /// In de, this message translates to:
  /// **'Komponente wählen, deren Beziehungen eingeblendet werden sollen.'**
  String get hintAsmShowPickComponent;

  /// Meldung: die gewählte Komponente ist an nichts gebunden.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ hat keine Beziehungen.'**
  String msgAsmNoRelationships(String name);

  /// Meldung: Fehlerhafte einblenden hat nichts zu zeigen.
  ///
  /// In de, this message translates to:
  /// **'Alle Beziehungen sind in Ordnung.'**
  String get msgAsmNoSickRelationships;

  /// Titel des Antriebsdialogs. Inventor DE: "Abhängigkeit antreiben".
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeit antreiben'**
  String get dlgDrive;

  /// Kontextmenü einer Beziehung: den Wert durch einen Bereich fahren.
  ///
  /// In de, this message translates to:
  /// **'Antreiben'**
  String get ctxDrive;

  /// Anfangswert des Antriebs.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get lblDriveStart;

  /// Endwert des Antriebs.
  ///
  /// In de, this message translates to:
  /// **'Ende'**
  String get lblDriveEnd;

  /// Wartezeit in Sekunden zwischen zwei Schritten.
  ///
  /// In de, this message translates to:
  /// **'Pause'**
  String get lblDrivePause;

  /// Gruppe: Schrittweite als Wert oder als Anzahl Schritte.
  ///
  /// In de, this message translates to:
  /// **'Schrittweite'**
  String get grpDriveIncrement;

  /// Schrittweite als Betrag angeben.
  ///
  /// In de, this message translates to:
  /// **'Wert'**
  String get optDriveAmount;

  /// Schrittweite als Gesamtzahl der Schritte angeben.
  ///
  /// In de, this message translates to:
  /// **'Anzahl Schritte'**
  String get optDriveSteps;

  /// Gruppe: wie oft und in welcher Richtung der Bereich durchfahren wird.
  ///
  /// In de, this message translates to:
  /// **'Wiederholungen'**
  String get grpDriveRepetitions;

  /// Einmal vorwärts, dann zurück an den Anfang.
  ///
  /// In de, this message translates to:
  /// **'Start/Ende'**
  String get optDriveOnce;

  /// Einmal vorwärts und einmal rückwärts.
  ///
  /// In de, this message translates to:
  /// **'Start/Ende/Start'**
  String get optDriveBoth;

  /// Wie oft die Wiederholung läuft.
  ///
  /// In de, this message translates to:
  /// **'Zyklen'**
  String get lblDriveCycles;

  /// Inventor-Option: Bauteile beim Antrieb anpassen. Hier nicht gebaut.
  ///
  /// In de, this message translates to:
  /// **'Adaptivität antreiben'**
  String get cbDriveAdaptivity;

  /// Inventor-Option: beim Antrieb auf Durchdringung prüfen. Hier nicht gebaut.
  ///
  /// In de, this message translates to:
  /// **'Kollisionserkennung'**
  String get cbDriveCollision;

  /// Tooltip der beiden Optionen, die Inventor hat und diese App nicht.
  ///
  /// In de, this message translates to:
  /// **'In dieser App nicht verfügbar.'**
  String get hintDriveUnavailable;

  /// Meldung: Symmetrie und Übergang haben keinen Wert zum Durchfahren.
  ///
  /// In de, this message translates to:
  /// **'Diese Beziehung lässt sich nicht antreiben.'**
  String get msgAsmCannotDrive;

  /// Tooltip der Wiedergabetaste im Antriebsdialog.
  ///
  /// In de, this message translates to:
  /// **'Abspielen'**
  String get tipDrivePlay;

  /// Tooltip der Rückwärtstaste im Antriebsdialog.
  ///
  /// In de, this message translates to:
  /// **'Rückwärts'**
  String get tipDriveReverse;

  /// Tooltip der Pausetaste im Antriebsdialog.
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get tipDrivePause;

  /// Tooltip: an den Anfang des Bereichs springen.
  ///
  /// In de, this message translates to:
  /// **'Zum Anfang'**
  String get tipDriveToStart;

  /// Tooltip: an das Ende des Bereichs springen.
  ///
  /// In de, this message translates to:
  /// **'Zum Ende'**
  String get tipDriveToEnd;

  /// Hinweis beim Start von Frei bewegen. Inventor uebergeht die Beziehungen voruebergehend.
  ///
  /// In de, this message translates to:
  /// **'Komponente ziehen — Beziehungen werden dabei übergangen.'**
  String get hintAsmFreeMove;

  /// Hinweis beim Start von Frei drehen.
  ///
  /// In de, this message translates to:
  /// **'Komponente wählen und am Drehsymbol ziehen.'**
  String get hintAsmFreeRotate;

  /// Meldung nach Frei bewegen/Frei drehen an einer Komponente mit Beziehungen.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ steht außerhalb seiner Beziehungen — die nächste Aktualisierung setzt es zurück.'**
  String msgAsmFreePositioned(String name);

  /// Meldung: der gewaehlte Name ist in der Galerie schon vergeben.
  ///
  /// In de, this message translates to:
  /// **'Ein Dokument namens „{name}“ existiert bereits.'**
  String msgNameTaken(String name);

  /// Aufforderung von Komponente erstellen: die Skizzenebene waehlen.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder planare Fläche zum Skizzieren wählen.'**
  String get hintAsmCreatePickPlane;

  /// Meldung: vor Ort bearbeiten gibt es nur fuer Bauteile.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist eine Unterbaugruppe — nicht vor Ort editierbar.'**
  String msgAsmEditSubInPlace(String name);

  /// Meldung: eine gesperrte Darstellung wird nicht aktualisiert.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist gesperrt.'**
  String msgAsmViewRepLocked(String name);

  /// Browserknoten unter Darstellungen. Inventor DE: "Ansicht".
  ///
  /// In de, this message translates to:
  /// **'Ansicht'**
  String get nodeViewReps;

  /// Browserknoten unter Darstellungen, ausgegraut. Inventor DE: "Position".
  ///
  /// In de, this message translates to:
  /// **'Position'**
  String get nodePositionalReps;

  /// Browserknoten unter Darstellungen, ausgegraut. Inventor DE: "Detailgenauigkeit".
  ///
  /// In de, this message translates to:
  /// **'Detailgenauigkeit'**
  String get nodeLodReps;

  /// Kontextmenue am Knoten Ansicht.
  ///
  /// In de, this message translates to:
  /// **'Neue Darstellung'**
  String get ctxNewViewRep;

  /// Kontextmenue an einer Ansichtsdarstellung.
  ///
  /// In de, this message translates to:
  /// **'Aktivieren'**
  String get ctxActivateViewRep;

  /// Kontextmenue: den aktuellen Anzeigezustand in die Darstellung schreiben.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get ctxUpdateViewRep;

  /// Kontextmenue: die Darstellung vor dem Rueckschreiben schuetzen.
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get ctxLockViewRep;

  /// Kontextmenue: die Sperre wieder aufheben.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get ctxUnlockViewRep;

  /// Kontextmenue an einer Ansichtsdarstellung.
  ///
  /// In de, this message translates to:
  /// **'Darstellung löschen'**
  String get ctxDeleteViewRep;

  /// Titel des Umbenennen-Dialogs.
  ///
  /// In de, this message translates to:
  /// **'Darstellung umbenennen'**
  String get dlgRenameViewRep;

  /// Platzhalter im Umbenennen-Dialog.
  ///
  /// In de, this message translates to:
  /// **'Name der Darstellung'**
  String get phViewRepName;

  /// Titel des Dialogs. Inventor DE: "Komponente vor Ort erstellen".
  ///
  /// In de, this message translates to:
  /// **'Komponente vor Ort erstellen'**
  String get dlgCreateComponent;

  /// Feldbeschriftung. Inventor DE: "Name der neuen Komponente".
  ///
  /// In de, this message translates to:
  /// **'Name der neuen Komponente'**
  String get lblComponentName;

  /// Kontrollkaestchen. Inventor DE: "Skizzenebene an gewaehlte Flaeche oder Ebene abhaengig machen"; hier gekuerzt, damit der Dialog schmal bleibt.
  ///
  /// In de, this message translates to:
  /// **'Skizzenebene an gewählte Fläche binden'**
  String get chkConstrainSketchPlane;

  /// Ribbon: aus der Bearbeitung vor Ort zurueck in die Baugruppe. Inventor DE: "Zurueck".
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get btnReturn;

  /// Ribbon-Gruppe um den Zurueck-Knopf. Inventor DE: "Beenden".
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get panelReturn;

  /// Hinweis beim Betreten der Bearbeitung vor Ort.
  ///
  /// In de, this message translates to:
  /// **'„{part}“ wird in „{assembly}“ bearbeitet.'**
  String hintInPlaceEditing(String part, String assembly);

  /// Kontextmenue an einer Komponente. Inventor DE: "Bearbeiten".
  ///
  /// In de, this message translates to:
  /// **'Vor Ort bearbeiten'**
  String get ctxEditInPlace;

  /// M255 — Kontextmenue an einem Volumenkoerper im Browser. Inventor DE: "Bauteil erstellen".
  ///
  /// In de, this message translates to:
  /// **'Bauteil erstellen'**
  String get ctxMakePart;

  /// M255 — Titel des Dialogs. Gleiche Woerter wie der Menuepunkt, damit erkennbar ist, was sich geoeffnet hat.
  ///
  /// In de, this message translates to:
  /// **'Bauteil erstellen'**
  String get dlgMakePart;

  /// M255 — Feldbeschriftung. Inventor DE: "Name des neuen Bauteils".
  ///
  /// In de, this message translates to:
  /// **'Name des neuen Bauteils'**
  String get lblNewPartName;

  /// M255 — Feldbeschriftung. Inventor DE: "Zielbaugruppe". Darf eine vorhandene Baugruppe benennen.
  ///
  /// In de, this message translates to:
  /// **'Zielbaugruppe'**
  String get lblTargetAssembly;

  /// M255 — Zeile unter den Feldern. Das Versprechen des Befehls steht dort, wo entschieden wird.
  ///
  /// In de, this message translates to:
  /// **'Bleibt mit „{name}“ verknüpft.'**
  String hintMakePartLink(String name);

  /// M255 — Bestaetigung, nachdem das Bauteil in der Baugruppe liegt.
  ///
  /// In de, this message translates to:
  /// **'„{part}“ aus „{origin}“ erstellt und damit verknüpft.'**
  String msgMadePart(String part, String origin);

  /// M255 — der Koerper ist zwischen Menue und OK verschwunden.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist nicht mehr gebaut.'**
  String msgMakePartNoBody(String name);

  /// M255 — Bearbeiten an einem abgeleiteten Koerper. Inventor DE: "Basiskomponente oeffnen".
  ///
  /// In de, this message translates to:
  /// **'Abgeleiteter Körper — „{name}“ wird geöffnet.'**
  String msgDerivedEditOrigin(String name);

  /// M304 — das Abzeichen ueber dem Viewport, waehrend der Pfadverfolger noch wartet. "Cycles" ist der Name des Renderers und bleibt in jeder Sprache stehen.
  ///
  /// In de, this message translates to:
  /// **'Cycles'**
  String get cyclesBadge;

  /// M340 — Auswahl im Anzeigemodus-Band: der Renderer, der jedes Bild zeichnet und der Kamera sofort folgt. Nur im gerenderten Modus sichtbar. RealityKit ist ein Produktname und bleibt stehen.
  ///
  /// In de, this message translates to:
  /// **'Echtzeit (RealityKit)'**
  String get rendererRealtime;

  /// M340 — Auswahl im Anzeigemodus-Band: der Pfadverfolger, der ein Bild berechnet, sobald die Kamera stillsteht. Nur im gerenderten Modus sichtbar. Cycles ist ein Produktname und bleibt stehen.
  ///
  /// In de, this message translates to:
  /// **'Raytracing (Cycles)'**
  String get rendererRaytraced;

  /// M304 — der erste Lauf uebersetzt Metals Kernel aus dem Quelltext, was zehnersekunden dauert. Waehrenddessen "spp" zu zeigen ist von einem Haenger nicht zu unterscheiden.
  ///
  /// In de, this message translates to:
  /// **'Cycles · Kernel werden übersetzt'**
  String get cyclesPreparing;

  /// M304 — Fortschritt des Pfadverfolgers. "spp" (samples per pixel) ist der Fachbegriff und wird nicht uebersetzt.
  ///
  /// In de, this message translates to:
  /// **'Cycles · {samples} spp'**
  String cyclesSamples(int samples);

  /// M304 — ein Fehlschlag, der nichts anzeigt, ist von einem Modus, der nichts tut, nicht zu unterscheiden.
  ///
  /// In de, this message translates to:
  /// **'Cycles fehlgeschlagen'**
  String get cyclesFailed;

  /// M320 — Cycles uebersetzt seine Metal-Kernel beim ersten Start aus dem Quelltext; das dauert Minuten und passiert genau einmal pro Installation. Wer in dieser Zeit auf Gerendert schaltet, muss erfahren, dass gewartet wird und nicht dass etwas kaputt ist.
  ///
  /// In de, this message translates to:
  /// **'Renderer wird vorbereitet'**
  String get cyclesWarmupTitle;

  /// M320 — der Satz, der aus einer Minute Warten eine ertraegliche Minute macht: es passiert nicht wieder.
  ///
  /// In de, this message translates to:
  /// **'Das geschieht einmal pro Installation.'**
  String get cyclesWarmupOnce;

  /// M320 — kein Metal-Geraet oder ein fehlgeschlagener Kernel-Build. Der Grund steht darunter.
  ///
  /// In de, this message translates to:
  /// **'Der Renderer konnte nicht gestartet werden'**
  String get cyclesWarmupFailed;

  /// M338 — der optionale Endradius einer Kantengruppe; leer heisst konstant.
  ///
  /// In de, this message translates to:
  /// **'Endradius'**
  String get lblEndRadius;

  /// M338 — wie viele Profile gewaehlt sind.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Ein Profil} other{{n} Profile}}'**
  String lblProfileCount(int n);

  /// M338 — wie viele Loft-Querschnitte gewaehlt sind.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Ein Querschnitt} other{{n} Querschnitte}}'**
  String lblSectionCount(int n);

  /// M338 — wie viele Skizzenpunkte gewaehlt sind.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Ein Punkt} other{{n} Punkte}}'**
  String lblPointsCount(int n);

  /// M338 — Zusatz an einer laufenden Mehrfachauswahl.
  ///
  /// In de, this message translates to:
  /// **'· zum Beenden tippen'**
  String get hintTapToFinish;

  /// M338 — Fussnote unter Verhalten, solange das Teil noch leer ist.
  ///
  /// In de, this message translates to:
  /// **'Bis zum Nächsten, Bis und Durch alle brauchen einen vorhandenen Körper.'**
  String get hintTerminationNeedsBody;

  /// M338 — wie viele Elemente gemustert werden.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Ein Element} other{{n} Elemente}}'**
  String lblFeatureCount(int n);

  /// M338 — wie viel Geometrie gewählt ist.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{nichts gewählt} =1{1 gewählt} other{{n} gewählt}}'**
  String lblSelectedCount(int n);

  /// M338 — Inventors zweite Verteilungsart: die Gesamtstrecke, die alle Exemplare zusammen einnehmen. Auf Deutsch NICHT 'Abstand', weil das schon die Luecke zwischen zweien heisst.
  ///
  /// In de, this message translates to:
  /// **'Gesamtabstand'**
  String get lblTotalDistance;

  /// M338 — Fussnote unter der Radius-Sektion der Verrundung.
  ///
  /// In de, this message translates to:
  /// **'Endradius leer lassen für eine konstante Verrundung; mit einem Wert läuft der Radius entlang jeder Kante der Gruppe.'**
  String get hintEndRadiusOptional;

  /// M341 — VoiceOver-Name des Loesch-Knopfes in einer Auswahlzeile. Der Knopf zeigt nur ein Glyph, also muss der Name sagen, WAS geloescht wird.
  ///
  /// In de, this message translates to:
  /// **'{name} löschen'**
  String a11yClearNamed(String name);

  /// M341 — VoiceOver-Name des X an einem Chip.
  ///
  /// In de, this message translates to:
  /// **'{name} entfernen'**
  String a11yRemoveNamed(String name);

  /// M345 — Inventor DE: „Ausschneiden“. Beschriftung des Knopfes und des Kontextmenue-Eintrags.
  ///
  /// In de, this message translates to:
  /// **'Ausschneiden'**
  String get btnCut;

  /// M345 — Inventor DE: „Einfügen“.
  ///
  /// In de, this message translates to:
  /// **'Einfügen'**
  String get btnPaste;

  /// M345 — Einfügen AN DER ZEIGERPOSITION, im Gegensatz zum gewoehnlichen Einfuegen, das die Koordinaten der Kopie behaelt.
  ///
  /// In de, this message translates to:
  /// **'Hier einfügen'**
  String get ctxPasteHere;

  /// M345 — auf einer Ebenen-Zeile des Modellbrowsers: die kopierte Skizze wird als neue Skizze auf dieser Ebene angelegt.
  ///
  /// In de, this message translates to:
  /// **'Skizze hier einfügen'**
  String get ctxPasteSketchHere;

  /// M345 — Galerie-Karte einer 2D-Skizze: legt ein Bauteil an, dessen erste Skizze diese ist.
  ///
  /// In de, this message translates to:
  /// **'Bauteil aus Skizze'**
  String get ctxPartFromSketch;

  /// M345 — Skizzen-Zeile im Bauteil: legt aus dieser Skizze ein eigenes 2D-Dokument an.
  ///
  /// In de, this message translates to:
  /// **'Als 2D-Skizze speichern'**
  String get ctxSketchToDocument;

  /// M345 — Kopieren wirkt auf die Auswahl.
  ///
  /// In de, this message translates to:
  /// **'Erst etwas auswählen, dann kopieren.'**
  String get msgSelectThenCopy;

  /// M345 — im Bauteil ohne Auswahl.
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper zum Kopieren wählen.'**
  String get msgSelectBodyToCopy;

  /// M345 — Bestätigung nach Strg+C in einer Skizze.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Objekt kopiert} other{{n} Objekte kopiert}}'**
  String msgCopiedEntities(int n);

  /// M345 — Bestätigung nach Strg+X in einer Skizze.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Objekt ausgeschnitten} other{{n} Objekte ausgeschnitten}}'**
  String msgCutEntities(int n);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Skizze „{name}“ kopiert.'**
  String msgCopiedSketch(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Skizze „{name}“ ausgeschnitten.'**
  String msgCutSketch(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper „{name}“ kopiert.'**
  String msgCopiedBody(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Volumenkörper „{name}“ ausgeschnitten.'**
  String msgCutBody(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Komponente „{name}“ kopiert.'**
  String msgCopiedComponent(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Komponente „{name}“ ausgeschnitten.'**
  String msgCutComponent(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Dokument „{name}“ kopiert.'**
  String msgCopiedDocument(String name);

  /// M345 — der Kern hat den Körper nicht als STEP herausgeschrieben; ohne Datei gaebe es nichts einzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Der Volumenkörper konnte nicht kopiert werden: {reason}'**
  String msgCopyBodyFailed(String reason);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'„{name}“ gibt es in diesem Bauteil nicht.'**
  String msgNoSuchBody(String name);

  /// M345 — Einfügen ohne vorheriges Kopieren.
  ///
  /// In de, this message translates to:
  /// **'Die Zwischenablage ist leer.'**
  String get msgClipboardEmpty;

  /// M345 — die STEP-Datei der Zwischenablage fehlt (Cache geleert, App neu gestartet).
  ///
  /// In de, this message translates to:
  /// **'Der kopierte Volumenkörper ist nicht mehr da — bitte neu kopieren.'**
  String get msgClipboardBodyGone;

  /// M345
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Objekt eingefügt} other{{n} Objekte eingefügt}}'**
  String msgPastedEntities(int n);

  /// M345 — eine eingefuegte Skizze wird als neue Skizze des Bauteils angelegt und bekommt dessen naechsten Namen.
  ///
  /// In de, this message translates to:
  /// **'Skizze „{name}“ eingefügt.'**
  String msgPastedSketchOnPlane(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'2D-Skizze „{name}“ angelegt.'**
  String msgPastedSketchDocument(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'„{name}“ als neuer Volumenkörper eingefügt.'**
  String msgPastedBody(String name);

  /// M345 — eine Baugruppe nimmt keine nackten Koerper auf, also entsteht beim Einfuegen ein Bauteil-Dokument, das platziert wird.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ angelegt und in der Baugruppe platziert.'**
  String msgPastedBodyAsComponent(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'„{name}“ eingefügt.'**
  String msgPastedComponent(String name);

  /// M345 — Einfuegen in der Galerie ist ein Duplikat.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ eingefügt.'**
  String msgPastedDocument(String name);

  /// M345 — ein eingefuegtes BAUTEIL wird abgeleitet (Inventors Ableiten), nicht kopiert; der Satz sagt es, weil es die eine Ausnahme von 'eine Kopie ist eine Kopie' ist.
  ///
  /// In de, this message translates to:
  /// **'Abgeleiteter Volumenkörper aus „{name}“ — mit dem Ursprung verknüpft.'**
  String msgPastedDerived(String name);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Der Volumenkörper konnte nicht eingefügt werden: {reason}'**
  String msgPasteBodyFailed(String reason);

  /// M345 — ohne Datei im Dokument kaeme der Koerper beim naechsten Oeffnen leer zurueck.
  ///
  /// In de, this message translates to:
  /// **'Der eingefügte Volumenkörper konnte nicht im Dokument abgelegt werden.'**
  String get msgPasteBodyNotSaved;

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Eine Komponente gehört in eine Baugruppe — dort einfügen.'**
  String get msgPasteComponentNeedsAssembly;

  /// M345 — sagt, wo das Kopierte stattdessen hingehoert.
  ///
  /// In de, this message translates to:
  /// **'Eine Baugruppe nimmt Komponenten auf, keine Skizzen.'**
  String get msgAssemblyTakesNoSketch;

  /// M345 — letzter Ausweg; die Faelle, die etwas Genaueres sagen koennen, sagen es.
  ///
  /// In de, this message translates to:
  /// **'Das lässt sich hier nicht einfügen.'**
  String get msgCannotPasteHere;

  /// M345
  ///
  /// In de, this message translates to:
  /// **'Ein Bauteil kann sich nicht selbst ableiten.'**
  String get msgCannotDeriveFromItself;

  /// M345
  ///
  /// In de, this message translates to:
  /// **'„{name}“ hat keinen Volumenkörper zum Ableiten.'**
  String msgNoBodyIn(String name);

  /// M345 — das kopierte Dokument wurde inzwischen geloescht oder umbenannt.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ gibt es nicht mehr.'**
  String msgNoSuchDocument(String name);

  /// M345 — dieselbe Auswahl wie beim Start einer 2D-Skizze, nur dass die Skizze fertig ankommt.
  ///
  /// In de, this message translates to:
  /// **'Ebene oder Fläche antippen, auf der die eingefügte Skizze liegen soll.'**
  String get msgSelectPlaneForPaste;

  /// M345 — die Bemassung behaelt ihren WERT und hoert auf, gerechnet zu werden.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Eine Formel wurde nicht übernommen — ihr Parameter kam nicht mit.} other{{n} Formeln wurden nicht übernommen — ihre Parameter kamen nicht mit.}}'**
  String msgPasteDroppedExpressions(int n);

  /// M345 — die Skizze bleibt, wo sie ist; das Bauteil bekommt eine Kopie.
  ///
  /// In de, this message translates to:
  /// **'Bauteil „{part}“ aus Skizze „{sketch}“ erstellt.'**
  String msgPartFromSketch(String part, String sketch);

  /// M345
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist keine 2D-Skizze.'**
  String msgNotASketch(String name);

  /// M345 — Einfuegen eines Koerpers oder Bauteils, waehrend der 2D-Editor im Bauteil offen ist.
  ///
  /// In de, this message translates to:
  /// **'Zuerst die Skizze beenden — ein Volumenkörper gehört ins Bauteil, nicht in die Skizze.'**
  String get msgFinishSketchToPaste;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppL10nDe();
    case 'en':
      return AppL10nEn();
  }

  throw FlutterError(
      'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
