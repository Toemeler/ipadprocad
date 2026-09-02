// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppL10nDe extends AppL10n {
  AppL10nDe([String locale = 'de']) : super(locale);

  @override
  String get languageName => 'Deutsch';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsButton => 'Einstellungen';

  @override
  String get settingsDone => 'Fertig';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsAppearanceFooter =>
      '„System“ folgt der Einstellung des iPads.';

  @override
  String get bugAutofix => 'Automatisch beheben lassen';

  @override
  String get bugAutofixOn =>
      'Der Bericht wird sofort an die Fix-Automatik übergeben.';

  @override
  String get bugAutofixOff =>
      'Der Bericht wartet auf eine Sitzung, die du selbst startest.';

  @override
  String get settingsAccent => 'Akzentfarbe';

  @override
  String get settingsAccentFooter =>
      '„Schema“ nimmt die Farbe der gewählten Darstellung. Jede Farbe ist auf Lesbarkeit geprüft.';

  @override
  String get accentScheme => 'Schema';

  @override
  String get accentTeal => 'Petrol';

  @override
  String get accentBlue => 'Blau';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentMagenta => 'Magenta';

  @override
  String get accentAmber => 'Bernstein';

  @override
  String get accentGreen => 'Grün';

  @override
  String get accentRed => 'Rot';

  @override
  String get settingsBackdrop => 'Hintergrund';

  @override
  String get settingsBackdropFooter =>
      'Nur für die Galerie. Über einem Bild liegt ein Schleier.';

  @override
  String get backdropAuto => 'Wie die Darstellung';

  @override
  String get backdropInk => 'Tinte';

  @override
  String get backdropSlate => 'Schiefer';

  @override
  String get backdropForest => 'Tanne';

  @override
  String get backdropSand => 'Sand';

  @override
  String get backdropLinen => 'Leinen';

  @override
  String get backdropImage => 'Eigenes Bild';

  @override
  String get backdropChooseImage => 'Bild waehlen …';

  @override
  String get backdropRemoveImage => 'Bild entfernen';

  @override
  String get backdropImageFailed => 'Das Bild konnte nicht uebernommen werden.';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsRibbon => 'Menüband';

  @override
  String get ribbonTop => 'Oben';

  @override
  String get ribbonBottom => 'Unten';

  @override
  String get ribbonLeft => 'Links';

  @override
  String get ribbonRight => 'Rechts';

  @override
  String get settingsDiagnostics => 'Diagnose';

  @override
  String get settingsReportProblem => 'Problem melden';

  @override
  String get settingsShareLog => 'Protokoll teilen';

  @override
  String get settingsDiagnosticsFooter =>
      'Ein Bericht enthaelt das offene Dokument und das Protokoll dieser Sitzung.';

  @override
  String get settingsIconPreview => 'Icon-Vorschau';

  @override
  String get iconPreviewHelp =>
      'Starte tools/icon-sync/serve.py auf dem PC, auf dem du zeichnest, und tippe die Adresse ein, die es anzeigt. Leer lassen, um die eingebauten Icons zu verwenden.';

  @override
  String get iconPreviewTurnOff => 'Ausschalten';

  @override
  String get iconPreviewConnect => 'Verbinden';

  @override
  String get iconPreviewIdle => 'Aus — die eingebauten Icons werden gezeigt.';

  @override
  String iconPreviewUnreachable(String host, String error) {
    return '$host ist nicht erreichbar\n$error';
  }

  @override
  String iconPreviewLive(int count, String host) {
    return '$count Icon(s) live von $host';
  }

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsBuild => 'Version';

  @override
  String get settingsKernel3d => '3D-Kern';

  @override
  String get settingsKernel2d => '2D-Kern';

  @override
  String get settingsSystem => 'System';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Hell';

  @override
  String get appearanceDark => 'Dunkel';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get done => 'Fertig';

  @override
  String get apply => 'Übernehmen';

  @override
  String get close => 'Schließen';

  @override
  String get delete => 'Löschen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get duplicate => 'Duplizieren';

  @override
  String get create => 'Erstellen';

  @override
  String get select => 'Auswählen';

  @override
  String get finish => 'Fertig';

  @override
  String get discard => 'Verwerfen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get hide => 'Ausblenden';

  @override
  String get openEllipsis => 'Öffnen…';

  @override
  String get exportEllipsis => 'Exportieren…';

  @override
  String get shareEllipsis => 'Teilen…';

  @override
  String get undo => 'Rückgängig';

  @override
  String get redo => 'Wiederholen';

  @override
  String get panelSketch => 'Skizze';

  @override
  String get panelCreate => 'Erstellen';

  @override
  String get panelModify => 'Ändern';

  @override
  String get panelWorkFeatures => 'Arbeitselemente';

  @override
  String get panelPattern => 'Anordnung';

  @override
  String get panelLayer => 'Layer';

  @override
  String get panelConstrain => 'Abhängigkeit';

  @override
  String get panelInsert => 'Einfügen';

  @override
  String get panelView => 'Ansicht';

  @override
  String get panelExit => 'Beenden';

  @override
  String get panelProjectGeometry => 'Projizieren';

  @override
  String get btnCreateNewSketch => 'Neue\nSkizze';

  @override
  String get btnStart2dSketch => '2D-Skizze\nbeginnen';

  @override
  String get btnStartNewLayer => 'Neuer\nLayer';

  @override
  String get btnExtrude => 'Extrusion';

  @override
  String get btnRevolve => 'Drehung';

  @override
  String get btnSweep => 'Sweeping';

  @override
  String get btnLoft => 'Erhebung';

  @override
  String get btnCoil => 'Spirale';

  @override
  String get btnEmboss => 'Prägen';

  @override
  String get btnDerive => 'Ableiten';

  @override
  String get btnDecal => 'Aufkleber';

  @override
  String get btnFillet => 'Verrundung';

  @override
  String get btnChamfer => 'Fase';

  @override
  String get btnShell => 'Wandung';

  @override
  String get btnDraft => 'Formschräge';

  @override
  String get btnThread => 'Gewinde';

  @override
  String get btnHole => 'Bohrung';

  @override
  String get btnSplit => 'Trennen';

  @override
  String get btnCombine => 'Kombinieren';

  @override
  String get btnPlane => 'Ebene';

  @override
  String get btnAxis => 'Achse';

  @override
  String get btnPoint => 'Punkt';

  @override
  String get btnLine => 'Linie';

  @override
  String get btnCircle => 'Kreis';

  @override
  String get btnArc => 'Bogen';

  @override
  String get btnRectangle => 'Rechteck';

  @override
  String get btnText => 'Text';

  @override
  String get btnDimension => 'Bemaßung';

  @override
  String get btnRectangular => 'Rechteckig';

  @override
  String get btnCircular => 'Rund';

  @override
  String get btnMirror => 'Spiegeln';

  @override
  String get btnImage => 'Bild';

  @override
  String get btnAcad => 'ACAD';

  @override
  String get btnConstruction => 'Konstruktion';

  @override
  String get btnParameters => 'Parameter';

  @override
  String get btnGear => 'Zahnrad';

  @override
  String get btnProjectGeometry => 'Geometrie\nprojizieren';

  @override
  String get btnSliceGraphics => 'Grafik\nschneiden';

  @override
  String get btnTrim => 'Stutzen';

  @override
  String get btnSelfSymmetric => 'Selbstsymmetrisch';

  @override
  String get btnAssociative => 'Assoziativ';

  @override
  String get btnFitted => 'Angepasst';

  @override
  String get flyLineB => 'Linie';

  @override
  String get flyLineSub => 'Linie';

  @override
  String get flyMidlineSub => 'Mittellinie';

  @override
  String get flySplineB => 'Spline';

  @override
  String get flySplineCvSub => 'Steuerpunkt';

  @override
  String get flySplineInterpSub => 'Interpolation';

  @override
  String get flySplineFreeSub => 'Freihand';

  @override
  String get flyEqCurveB => 'Gleichungskurve';

  @override
  String get flyBridgeB => 'Übergangskurve';

  @override
  String get flyCircleB => 'Kreis';

  @override
  String get flyCenterPointSub => 'Mittelpunkt';

  @override
  String get flyTangentSub => 'Tangential';

  @override
  String get flyEllipseB => 'Ellipse';

  @override
  String get flyArcB => 'Bogen';

  @override
  String get flyThreePointSub => 'Drei Punkte';

  @override
  String get flyRectB => 'Rechteck';

  @override
  String get flyTwoPointSub => 'Zwei Punkte';

  @override
  String get flyTwoPointCenterSub => 'Zwei Punkte, mittig';

  @override
  String get flyThreePointCenterSub => 'Drei Punkte, mittig';

  @override
  String get flySlotB => 'Langloch';

  @override
  String get flySlotCcSub => 'Mitte zu Mitte';

  @override
  String get flySlotOverallSub => 'Gesamtlänge';

  @override
  String get flySlot3aSub => 'Bogen, drei Punkte';

  @override
  String get flySlotCpaSub => 'Bogen, Mittelpunkt';

  @override
  String get flyPolygonB => 'Polygon';

  @override
  String get flyFilletB => 'Verrundung';

  @override
  String get flyChamferB => 'Fase';

  @override
  String get flyTextB => 'Text';

  @override
  String get flyGeomTextB => 'Geometrietext';

  @override
  String get flyMoveB => 'Verschieben';

  @override
  String get flySizeB => 'Größe';

  @override
  String get flyScaleB => 'Skalieren';

  @override
  String get flyRotateB => 'Drehen';

  @override
  String get flyDeleteB => 'Löschen';

  @override
  String get flyAxisB => 'Achse';

  @override
  String get flyAxisOnLineB => 'Auf Linie oder Kante';

  @override
  String get flyAxisParPtB => 'Parallel zu Linie durch Punkt';

  @override
  String get flyAxisTwoPtB => 'Durch zwei Punkte';

  @override
  String get flyAxisTwoPlB => 'Schnitt zweier Ebenen';

  @override
  String get flyAxisNormPtB => 'Normal zu Ebene durch Punkt';

  @override
  String get flyAxisCircB => 'Durch Mittelpunkt einer Rundkante';

  @override
  String get flyAxisRevB => 'Durch Drehfläche oder -element';

  @override
  String get flyPointB => 'Punkt';

  @override
  String get flyPointGroundB => 'Fixierter Punkt';

  @override
  String get flyPointVertexB => 'Auf Eckpunkt, Skizzenpunkt oder Mittelpunkt';

  @override
  String get flyPointThreePlB => 'Schnitt dreier Ebenen';

  @override
  String get flyPointTwoLnB => 'Schnitt zweier Linien';

  @override
  String get flyPointPlLnB => 'Schnitt Ebene/Fläche und Linie';

  @override
  String get flyPointLoopB => 'Mittelpunkt einer Kantenschleife';

  @override
  String get flyPointTorusB => 'Mittelpunkt eines Torus';

  @override
  String get flyPointSphereB => 'Mittelpunkt einer Kugel';

  @override
  String get flyPlaneB => 'Ebene';

  @override
  String get flyPlaneOffsetB => 'Versatz von Ebene';

  @override
  String get flyPlaneParallelPtB => 'Parallel zu Ebene durch Punkt';

  @override
  String get flyPlaneMid2B => 'Mittelebene zwischen zwei Ebenen';

  @override
  String get flyPlaneMidTorusB => 'Mittelebene eines Torus';

  @override
  String get flyPlaneAngleEdgeB => 'Winkel zu Ebene um Kante';

  @override
  String get flyPlaneThreePtsB => 'Drei Punkte';

  @override
  String get flyPlaneTwoEdgesB => 'Zwei koplanare Kanten';

  @override
  String get flyPlaneTanSurfEdgeB => 'Tangential zu Fläche durch Kante';

  @override
  String get flyPlaneTanSurfPtB => 'Tangential zu Fläche durch Punkt';

  @override
  String get flyPlaneTanParallelB =>
      'Tangential zu Fläche und parallel zu Ebene';

  @override
  String get flyPlaneNormalAxisB => 'Normal zu Achse durch Punkt';

  @override
  String get flyPlaneNormalCurveB => 'Normal zu Kurve im Punkt';

  @override
  String get browserTitle => 'Modell';

  @override
  String get nodeOrigin => 'Ursprung';

  @override
  String get nodeXAxis => 'X-Achse';

  @override
  String get nodeYAxis => 'Y-Achse';

  @override
  String get nodeCenterPoint => 'Mittelpunkt';

  @override
  String get nodeEndOfPart => 'Ende des Bauteils';

  @override
  String get nodeEndOfSketch => 'Ende der Skizze';

  @override
  String nodeSolidBodies(int count) {
    return 'Volumenkörper ($count)';
  }

  @override
  String nodeOccurrence(int index) {
    return 'Exemplar $index';
  }

  @override
  String get nodeAutoProjected => 'Automatisch projiziert';

  @override
  String get ctxUseAsTargetBody => 'Als Zielkörper verwenden';

  @override
  String get ctxDeleteBody => 'Körper löschen';

  @override
  String get ctxEditSketch => 'Skizze bearbeiten';

  @override
  String get ctxShareSketch => 'Skizze freigeben';

  @override
  String get ctxUnshare => 'Freigabe aufheben';

  @override
  String get ctxEditFeature => 'Element bearbeiten';

  @override
  String get ctxMoveEosHere => 'Ende der Skizze hierher';

  @override
  String get ctxDeleteLayer => 'Layer löschen';

  @override
  String get ctxMoveToTop => 'An den Anfang';

  @override
  String get ctxMoveToEnd => 'Ans Ende';

  @override
  String get ctxDeleteAllLayersBelow => 'Alle Layer darunter löschen';

  @override
  String get ctxDeleteAllFeaturesBelow => 'Alle Elemente darunter löschen';

  @override
  String get ctxDeleteAllFeaturesBelowEop =>
      'Alle Elemente unterhalb EOP löschen';

  @override
  String get ctxCreateSketch => 'Skizze erstellen';

  @override
  String get ctxEditOffset => 'Versatz bearbeiten';

  @override
  String get ctxFlipDirection => 'Richtung umkehren';

  @override
  String get ctxEditLayer => 'Layer bearbeiten';

  @override
  String get ctxMoveSelectionHere => 'Auswahl hierher verschieben';

  @override
  String get ctxExportDxf => 'DXF exportieren…';

  @override
  String get ctxShareDxf => 'DXF teilen…';

  @override
  String get dlgRenameBody => 'Körper umbenennen';

  @override
  String get dlgRenameFeature => 'Element umbenennen';

  @override
  String get dlgRenameLayer => 'Layer umbenennen';

  @override
  String get dlgRenameSketch => 'Skizze umbenennen';

  @override
  String get phBodyName => 'Körpername';

  @override
  String get phFeatureName => 'Elementname';

  @override
  String get phLayerName => 'Layername';

  @override
  String get phSketchName => 'Skizzenname';

  @override
  String get phPartName => 'Bauteilname';

  @override
  String get dlgNewSketch => 'Neue Skizze';

  @override
  String get dlgNewPart => 'Neues Bauteil';

  @override
  String get dlgDeleteAllFeaturesBelowEop =>
      'Alle Elemente unterhalb EOP löschen?';

  @override
  String get dlgDeleteEverythingBelowEos =>
      'Alles unterhalb des Skizzenendes löschen?';

  @override
  String dlgDeleteNamed(String name) {
    return '„$name“ löschen?';
  }

  @override
  String msgFeaturesRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente werden aus dem Bauteil entfernt.',
      one: 'Ein Element wird aus dem Bauteil entfernt.',
    );
    return '$_temp0';
  }

  @override
  String msgBodyFeaturesRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seine $count Elemente werden aus dem Bauteil entfernt.',
      one: 'Sein einziges Element wird aus dem Bauteil entfernt.',
    );
    return '$_temp0';
  }

  @override
  String msgLayersAndEntitiesRemoved(int layers, int entities) {
    String _temp0 = intl.Intl.pluralLogic(
      layers,
      locale: localeName,
      other: '$layers Layer werden entfernt',
      one: 'Ein Layer wird entfernt',
    );
    String _temp1 = intl.Intl.pluralLogic(
      entities,
      locale: localeName,
      other: 'mit $entities Objekten darin.',
      one: 'mit einem Objekt darin.',
      zero: 'ohne Objekte darin.',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get msgFeatureAndSolidRemoved =>
      'Das Element und sein Volumenkörper werden aus dem Bauteil entfernt.';

  @override
  String get msgSketchDeleted =>
      'Die Skizze und alles darin werden von diesem iPad entfernt. Das lässt sich nicht rückgängig machen.';

  @override
  String get galleryNew2dSketch => 'Neue 2D-Skizze';

  @override
  String get galleryNew3dPart => 'Neues 3D-Bauteil';

  @override
  String get galleryEmpty =>
      'Auf  +  tippen für eine neue Skizze oder ein Bauteil';

  @override
  String get errNameTaken =>
      'Eine Skizze oder ein Bauteil mit diesem Namen existiert bereits.';

  @override
  String get qtReportBug => 'Fehler melden';

  @override
  String get hudOverConstrained => 'Überbestimmt';

  @override
  String get hudDriven => 'Abhängig';

  @override
  String get msgWouldOverConstrain =>
      'Diese Bemaßung würde die Skizze überbestimmen. Als abhängige Bemaßung (Referenzmaß) behalten?';

  @override
  String get menuHomeView => 'Startansicht';

  @override
  String msgCouldNotSave(String name) {
    return '„$name“ ließ sich nicht speichern.';
  }

  @override
  String msgSavedTo(String folder) {
    return 'Gespeichert in $folder';
  }

  @override
  String msgSavedNamed(String name) {
    return '„$name“ gespeichert';
  }

  @override
  String get msgCannotOpenKind =>
      'Prototype kann diese Art von Datei nicht öffnen.';

  @override
  String get msgNotAPrototypeDoc =>
      'Diese Datei ist kein Prototype-Dokument (oder ist beschädigt).';

  @override
  String get msgCouldNotOpenDoc => 'Dieses Dokument ließ sich nicht öffnen.';

  @override
  String get msgCouldNotOpenFile => 'Diese Datei ließ sich nicht öffnen.';

  @override
  String get msgCouldNotImportFile =>
      'Diese Datei ließ sich nicht importieren.';

  @override
  String get msgCouldNotImportImage => 'Das Bild ließ sich nicht importieren.';

  @override
  String get msgCouldNotImportDxf =>
      'Die DXF-Datei ließ sich nicht importieren.';

  @override
  String get msgCouldNotReadDxf => 'Die DXF-Datei ließ sich nicht lesen.';

  @override
  String get msgDxfNoSupportedEntities =>
      'Die DXF-Datei enthält keine unterstützten Objekte.';

  @override
  String msgLayerBelowEos(String layer) {
    return '„$layer“ liegt unter dem Skizzenende — die Marke nach unten ziehen, um ihn zurückzuholen.';
  }

  @override
  String msgLayerLockedEdit(String layer) {
    return '„$layer“ ist gesperrt — zum Bearbeiten entsperren.';
  }

  @override
  String msgLayerLocked(String layer) {
    return '„$layer“ ist gesperrt.';
  }

  @override
  String msgTargetBelowEos(String layer) {
    return '„$layer“ liegt unter dem Skizzenende.';
  }

  @override
  String get msgDefaultLayerNoRename =>
      'Der Standardlayer „0“ kann nicht umbenannt werden.';

  @override
  String get msgZeroReserved => '„0“ ist für den Standardlayer reserviert.';

  @override
  String msgLayerExists(String name) {
    return 'Ein Layer namens „$name“ existiert bereits.';
  }

  @override
  String get msgDefaultLayerNoDelete =>
      'Der Standardlayer „0“ kann nicht gelöscht werden.';

  @override
  String get msgEnterLayerToEdit =>
      'Layer betreten: im Modellbrowser doppelt antippen.';

  @override
  String get msgEnterLayerToSketch =>
      'Layer betreten, um zu zeichnen: im Modellbrowser doppelt antippen.';

  @override
  String get msgSelectThenDelete => 'Erst Geometrie wählen, dann löschen.';

  @override
  String get msgSelectThenMoveToLayer =>
      'Erst Geometrie wählen, dann auf einen Layer verschieben.';

  @override
  String msgSelectThenToggle(String what) {
    return 'Erst Geometrie wählen, dann $what umschalten.';
  }

  @override
  String get msgNothingBelowEos => 'Unter dem Skizzenende liegt nichts.';

  @override
  String get msgNothingBelowEop => 'Unter dem Bauteilende liegt nichts.';

  @override
  String get msgNoKernelStep =>
      'Kein 3D-Kern verbunden — der STEP-Export braucht den Gerätebuild.';

  @override
  String get msgNothingToExportYet =>
      'Noch nichts zu exportieren — zuerst ein Profil extrudieren.';

  @override
  String msgStepExportFailed(String error) {
    return 'STEP-Export fehlgeschlagen: $error';
  }

  @override
  String get msgStepExportEmpty =>
      'Der STEP-Export hat eine leere Datei erzeugt.';

  @override
  String msgExportedWithout(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ohne $names exportiert — sie ließen sich nicht bauen.',
      one: 'Ohne $names exportiert — es ließ sich nicht bauen.',
    );
    return '$_temp0';
  }

  @override
  String msgNothingToExportEmpty(String name) {
    return 'Nichts zu exportieren — „$name“ ist leer.';
  }

  @override
  String get msgDxfExportFailed => 'DXF-Export fehlgeschlagen.';

  @override
  String get msgOpenPartForStep =>
      'Zuerst ein Bauteil öffnen — STEP-Importe kommen als Volumenkörper an.';

  @override
  String msgNoSolidsInStep(String error) {
    return 'Keine Volumenkörper in dieser STEP-Datei ($error).';
  }

  @override
  String msgImportedBodies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Körper importiert.',
      one: 'Ein Körper importiert.',
    );
    return '$_temp0';
  }

  @override
  String get msgOpenPartForMesh =>
      'Zuerst ein Bauteil öffnen — ein Netz kommt als Volumenkörper an.';

  @override
  String get msgNoKernelMesh =>
      'Kein 3D-Kern verbunden — ein Netz umzuwandeln braucht den Gerätebuild.';

  @override
  String get msgMeshEmpty => 'Diese Datei ist leer.';

  @override
  String get msgMeshMissing => 'Diese Datei gibt es nicht mehr.';

  @override
  String get msgMeshUnreadable => 'Diese Datei ließ sich nicht lesen.';

  @override
  String get msgMeshConvertTitle => 'Netz wird umgewandelt';

  @override
  String get msgMeshBuildTitle => 'Dreiecke werden übernommen';

  @override
  String msgMeshBuilding(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Dreiecke',
      one: 'Ein Dreieck',
    );
    return '$_temp0';
  }

  @override
  String get askMeshImportTitle => 'Wie soll dieses Modell importiert werden?';

  @override
  String askMeshImportBody(int count, String size) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Dreiecke',
      one: 'Ein Dreieck',
    );
    return '$_temp0, $size mm groß.';
  }

  @override
  String get askMeshImportConvert => 'Als CAD-Körper';

  @override
  String get askMeshImportConvertWhy =>
      'Flächen zum Verrunden, Bemaßen und Bearbeiten. Dauert einen Moment.';

  @override
  String get askMeshImportFaceted => 'Als Netz';

  @override
  String get askMeshImportFacetedWhy =>
      'Genau wie die Datei, ohne Umwandlung. Kaum bearbeitbar.';

  @override
  String askMeshImportTooManyFaceted(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Für „Als Netz“ sind das zu viele Dreiecke (Grenze $limitString).';
  }

  @override
  String get meshStageReading => 'Modell wird gelesen';

  @override
  String get meshStageFinding => 'Flächen werden gesucht';

  @override
  String get meshStageFitting => 'Flächen werden angepasst';

  @override
  String get meshStageShaping => 'Rundungen werden geformt';

  @override
  String get meshStageBuilding => 'Flächen werden gebaut';

  @override
  String get meshStageFinishing => 'Wird fertiggestellt';

  @override
  String get meshStageSimplifying => 'Wird vereinfacht';

  @override
  String get actionCancelling => 'Wird abgebrochen …';

  @override
  String get msgMeshImportCancelled => 'Import abgebrochen.';

  @override
  String get msgMeshNoGeometry =>
      'Diese Datei enthält keine brauchbare Geometrie.';

  @override
  String get msgMeshTruncated =>
      'Diese Datei ist beschädigt — ein Datensatz bricht ab.';

  @override
  String msgMeshBadIndex(String index) {
    return 'Diese Datei ist beschädigt — eine Fläche nennt Punkt $index, den es nicht gibt.';
  }

  @override
  String get msgMeshNotAnArchive => 'Diese 3MF-Datei ist kein lesbares Archiv.';

  @override
  String get msgMeshNoModel => 'Diese 3MF-Datei enthält kein Modell.';

  @override
  String msgMeshUnknownUnit(String unit) {
    return 'Diese 3MF-Datei nutzt die unbekannte Einheit „$unit“.';
  }

  @override
  String msgMeshNotWatertight(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Dieses Netz ist nicht dicht ($count offene Kanten) und kann kein Volumenkörper werden.',
      one:
          'Dieses Netz ist nicht dicht (eine offene Kante) und kann kein Volumenkörper werden.',
    );
    return '$_temp0';
  }

  @override
  String get msgMeshConvertFailed => 'Das Netz ließ sich nicht umwandeln.';

  @override
  String msgMeshConvertFailedWhy(String error) {
    return 'Das Netz ließ sich nicht umwandeln: $error';
  }

  @override
  String get msgMeshNotSaved =>
      'Das Netz wurde umgewandelt, aber nicht gespeichert.';

  @override
  String msgMeshImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importiert: $count Flächen erkannt.',
      one: 'Importiert: eine Fläche erkannt.',
    );
    return '$_temp0';
  }

  @override
  String msgMeshImportedFacetedOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Als $count Flächen importiert — keine Flächenform erkannt.',
      one: 'Als eine Fläche importiert — keine Flächenform erkannt.',
    );
    return '$_temp0';
  }

  @override
  String msgMeshImportedFaceted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bereiche blieben als Dreiecke.',
      one: 'Ein Bereich blieb als Dreiecke.',
    );
    return '$_temp0';
  }

  @override
  String get msgMeshImportedOpen => 'Nicht geschlossen — ein Flächenkörper.';

  @override
  String msgMeshFileTooLarge(int size, int limit) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String sizeString = sizeNumberFormat.format(size);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Diese Datei hat $sizeString MB; Prototype liest Netze bis $limitString MB.';
  }

  @override
  String msgMeshTooManyTriangles(int count, int limit) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Dieses Netz hat $countString Dreiecke; Prototype wandelt bis $limitString um.';
  }

  @override
  String msgMeshConverting(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString Dreiecke werden umgewandelt …';
  }

  @override
  String msgImportedEntities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte importiert.',
      one: 'Ein Objekt importiert.',
    );
    return '$_temp0';
  }

  @override
  String get msgNothingToUndo => 'Nichts rückgängig zu machen.';

  @override
  String get msgNothingToRedo => 'Nichts zu wiederholen.';

  @override
  String get msgSelectPlaneForSketch =>
      'Ebene wählen, auf der die Skizze entstehen soll.';

  @override
  String msgUsedByFeature(String name) {
    return '$name wird von einem Element verwendet — dieses zuerst löschen.';
  }

  @override
  String get msgSelectPlaneToOffsetFrom =>
      'Ebene oder Fläche wählen, von der aus versetzt wird.';

  @override
  String get msgSelectFirstParallel =>
      'Erste von zwei parallelen Ebenen oder Flächen wählen.';

  @override
  String get msgSelectSecondParallel =>
      'Zweite parallele Ebene oder Fläche wählen.';

  @override
  String get msgNotParallel =>
      'Diese beiden sind nicht parallel — eine parallele Ebene oder Fläche wählen.';

  @override
  String msgPlaneHasNoOffset(String name) {
    return '$name: Diese Ebene hat keinen Versatz zum Ziehen.';
  }

  @override
  String get msgDragAwayToSetOffset =>
      'Von der Ebene wegziehen, um den Versatz zu setzen.';

  @override
  String msgNameColonDef(String name, String definition) {
    return '$name: $definition';
  }

  @override
  String msgFaceEditNeedsBody(String command) {
    return '$command braucht zuerst einen Volumenkörper.';
  }

  @override
  String get msgSetScaleThenApply =>
      'Skalierungsfaktor setzen, dann übernehmen.';

  @override
  String msgSelectFacesTo(String verb) {
    return 'Flächen zum $verb wählen.';
  }

  @override
  String get msgSelectAtLeastOneFace => 'Mindestens eine Fläche wählen.';

  @override
  String get msgNothingToEditBuildBody =>
      'Nichts zu bearbeiten — zuerst einen Körper bauen.';

  @override
  String msgFeatureError(String name, String error) {
    return '$name: $error';
  }

  @override
  String msgLostFaces(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name: $count gewählte Flächen existieren nicht mehr.',
      one: '$name: Eine gewählte Fläche existiert nicht mehr.',
    );
    return '$_temp0';
  }

  @override
  String get msgCannotCreateFeature =>
      'Das Element lässt sich nicht erstellen.';

  @override
  String get msgNoKernelFeatureStored =>
      'Kein 3D-Kern verbunden — Element gespeichert, Volumenkörper steht aus.';

  @override
  String get msgHoleNeedsSketch =>
      'Eine Bohrung sitzt auf Skizzenpunkten — zuerst eine Skizze anlegen.';

  @override
  String get msgHoleNeedsBody =>
      'Eine Bohrung braucht einen Körper zum Bohren.';

  @override
  String get msgTapSketchPointsForHoles =>
      'Skizzenpunkte für die Bohrungen antippen.';

  @override
  String msgHoleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bohrungen — Punkt antippen zum Hinzufügen oder Entfernen.',
      one: 'Eine Bohrung — Punkt antippen zum Hinzufügen oder Entfernen.',
    );
    return '$_temp0';
  }

  @override
  String get msgHolesSameSketch =>
      'Alle Bohrungen eines Elements stammen aus derselben Skizze.';

  @override
  String get msgDiameterPositive =>
      'Der Durchmesser muss eine Zahl größer als 0 sein.';

  @override
  String get msgDepthPositive => 'Die Tiefe muss eine Zahl größer als 0 sein.';

  @override
  String msgCboreWiderThanHole(String kind) {
    return 'Die $kind muss weiter als die Bohrung und tiefer als 0 sein.';
  }

  @override
  String get msgCsinkAngle =>
      'Die Senkung muss weiter als die Bohrung sein, mit einem Winkel zwischen 0 und 180 Grad.';

  @override
  String get msgSplitNeedsBody =>
      'Trennen schneidet einen Körper — es gibt noch keinen.';

  @override
  String get msgSelectTrimPlane => 'Ebene wählen, mit der geschnitten wird.';

  @override
  String msgTrimmingWith(String label) {
    return 'Schnitt mit $label. OK behält die Seite, die stehen bleibt.';
  }

  @override
  String get msgCombineNeedsTwoBodies =>
      'Kombinieren braucht zwei Körper — es vereinigt, schneidet oder verschneidet einen mit einem anderen.';

  @override
  String get msgTapBodyToKeep => 'Körper antippen, der BLEIBT.';

  @override
  String msgTapBodiesToCombine(String name) {
    return 'Körper antippen, die in $name eingehen.';
  }

  @override
  String get msgThatIsBaseBody =>
      'Das ist der Basiskörper — einen anderen zum Kombinieren wählen.';

  @override
  String get msgPickKeepThenCombine =>
      'Erst den Körper wählen, der bleibt, dann die Körper, die hineingerechnet werden.';

  @override
  String get msgSelectTargetBody =>
      'Zielkörper wählen — in 3D oder im Browser antippen.';

  @override
  String msgPatternNeedsComponent(String kind) {
    return '$kind braucht eine Komponente zum Kopieren — zuerst eine platzieren.';
  }

  @override
  String msgRelationshipsDropped(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$n Beziehungen wurden mit den entfallenen Elementen gelöscht — Abbrechen stellt sie wieder her.',
      one:
          '1 Beziehung wurde mit den entfallenen Elementen gelöscht — Abbrechen stellt sie wieder her.',
    );
    return '$_temp0';
  }

  @override
  String get msgTapComponentToPattern => 'Komponente zum Anordnen antippen.';

  @override
  String get msgCannotPatternAnElement =>
      'Ein Anordnungselement kann nicht angeordnet werden — die Ausgangskomponente wählen.';

  @override
  String get msgSelectComponentToCopy => 'Komponente zum Kopieren wählen.';

  @override
  String get msgCannotCopyAnElement =>
      'Ein Anordnungselement kann nicht kopiert werden — die Ausgangskomponente kopieren oder die Anzahl ändern.';

  @override
  String msgPatternNeedsFeature(String kind) {
    return '$kind braucht ein Element zum Kopieren — zuerst eines bauen.';
  }

  @override
  String get msgSelectFeatures =>
      'Elemente wählen — eine Fläche in 3D oder eine Zeile im Browser antippen.';

  @override
  String get msgTapStraightOrCircularEdge =>
      'Gerade Kante, Rundkante oder Ursprungsachse antippen.';

  @override
  String get msgTapCircularOrStraightEdge =>
      'Rundkante, gerade Kante oder Ursprungsachse antippen.';

  @override
  String get msgTapPlanarFace =>
      'Planare Fläche, Arbeitsebene oder Ursprungsebene antippen.';

  @override
  String get msgTapSketchForOccurrences =>
      'Die Skizze antippen, deren Punkte die Exemplare setzen.';

  @override
  String get msgTapSketchPointOfOriginal =>
      'Den Skizzenpunkt antippen, auf dem das Original sitzt.';

  @override
  String get msgTapCurveStart =>
      'Den Punkt auf der Kurve antippen, an dem die Anordnung beginnt.';

  @override
  String get msgTapFaceToFollow =>
      'Die Fläche antippen, der die Exemplare folgen sollen.';

  @override
  String get msgTapSolidBodyToPattern =>
      'Volumenkörper antippen, der angeordnet wird.';

  @override
  String get msgPickSolidBodyToPattern =>
      'Volumenkörper wählen, der angeordnet wird.';

  @override
  String msgBuiltAfterPattern(String name) {
    return '„$name“ entsteht nach dieser Anordnung, deshalb kann sie es nicht kopieren.';
  }

  @override
  String get msgEdgeNoDirection => 'Diese Kante gibt keine Richtung vor.';

  @override
  String get msgPickCurveFirst => 'Zuerst die Kurve für diese Richtung wählen.';

  @override
  String get msgCurveGone => 'Diese Kurve ist nicht mehr vorhanden.';

  @override
  String msgSketchHasNoPoints(String name) {
    return '„$name“ enthält keine Skizzenpunkte — eine skizzengesteuerte Anordnung setzt je Punkt ein Exemplar.';
  }

  @override
  String msgBasePointMustBeOf(String name) {
    return 'Der Basispunkt muss ein Punkt von „$name“ sein.';
  }

  @override
  String get msgCannotCreatePattern =>
      'Die Anordnung lässt sich nicht erstellen.';

  @override
  String msgPatternedByBroken(String name, String names, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '„$name“ wurde von $names angeordnet — diese Anordnungen sind jetzt defekt. Rückgängig stellt sie wieder her.',
      one:
          '„$name“ wurde von $names angeordnet — diese Anordnung ist jetzt defekt. Rückgängig stellt sie wieder her.',
    );
    return '$_temp0';
  }

  @override
  String get msgTapCurveToSweep => 'Kurve antippen, entlang der gezogen wird.';

  @override
  String get msgCurveNoLength => 'Diese Kurve hat keine Länge.';

  @override
  String get msgTapSectionsInOrder => 'Querschnitte der Reihe nach antippen.';

  @override
  String get msgTapAxisLine =>
      'Skizzenlinie oder Ursprungsachse antippen, die als Achse dient.';

  @override
  String get msgPickAxisLine => 'Skizzenlinie oder Ursprungsachse wählen.';

  @override
  String get msgAxisNotInSketchPlane =>
      'Diese Achse liegt nicht in der Skizzenebene.';

  @override
  String get msgLineGone => 'Diese Linie ist nicht mehr vorhanden.';

  @override
  String get msgAxisMustBeStraight => 'Die Achse muss eine gerade Linie sein.';

  @override
  String get msgLineNoLength => 'Diese Linie hat keine Länge.';

  @override
  String get msgCreateSketchFirstExtrude =>
      'Zuerst eine 2D-Skizze anlegen — die Extrusion braucht ein geschlossenes Profil.';

  @override
  String get msgProfilesSameSketch =>
      'Alle Profile einer Extrusion stammen aus derselben Skizze.';

  @override
  String get msgPickProfile => 'Mindestens ein Profil zum Extrudieren wählen.';

  @override
  String get msgSelectTerminateFace =>
      'Die Fläche wählen, auf der es enden soll.';

  @override
  String get msgPickOneEdgeFirst =>
      'Zuerst eine Kante wählen, damit der Körper feststeht.';

  @override
  String get msgBodyHasNoEdges => 'Dieser Körper hat keine wählbaren Kanten.';

  @override
  String get msgSelectEdges =>
      'Kanten wählen — antippen fügt hinzu, nochmals antippen entfernt.';

  @override
  String get msgTapToPlaceGear =>
      'In die Skizze tippen, um das Zahnrad zu setzen.';

  @override
  String get msgCouldNotPlaceGear =>
      'Das Zahnrad lässt sich hier nicht setzen.';

  @override
  String get msgInternalGearTeeth =>
      'Ein Hohlrad braucht mindestens 3 Zähne und einen gültigen Modul.';

  @override
  String get msgGearTeeth =>
      'Ein Zahnrad braucht mindestens 4 Zähne und einen gültigen Modul.';

  @override
  String get msgInternalGearPlaced =>
      'Hohlrad gesetzt — Mittelpunkt und einen Winkel bemaßen, um es vollständig zu bestimmen.';

  @override
  String get msgExternalGearPlaced =>
      'Stirnrad gesetzt — Mittelpunkt und einen Winkel bemaßen, um es vollständig zu bestimmen.';

  @override
  String get msgPlanetaryNeeds =>
      'Ein Planetensatz braucht Sonnen- und Planetenzähne ≥ 4 und ≥ 2 Planeten.';

  @override
  String get msgPlanetaryUndrawable =>
      'Diese Planetenparameter lassen sich nicht zeichnen.';

  @override
  String get msgPlanetaryPlacedFree =>
      'Planetensatz gesetzt (als freie Geometrie).';

  @override
  String get msgPlanetaryPlacedDimension =>
      'Planetensatz gesetzt — Mittelpunkt und einen Winkel bemaßen.';

  @override
  String msgPlanetaryUneven(int count) {
    return 'Planetensatz gesetzt. Hinweis: $count Planeten teilen sich nicht gleichmäßig für exakten Eingriff.';
  }

  @override
  String msgPlanetaryUnevenSpacing(int count) {
    return 'Planetensatz gesetzt ($count Planeten stehen für exakten Eingriff nicht gleichmäßig verteilt).';
  }

  @override
  String get msgAlreadyProjected => 'Auf diesen Layer bereits projiziert.';

  @override
  String get msgProjectPicksOtherLayers =>
      'Projizieren holt Geometrie von ANDEREN Layern.';

  @override
  String get msgTapPolygonEdge =>
      'Eine Kante des Polygons antippen, um es zu projizieren.';

  @override
  String get msgTapGeometryOtherLayer =>
      'Geometrie auf einem anderen Layer oder die X-/Y-Achse antippen.';

  @override
  String get msgProjectedNoPattern =>
      'Projizierte Geometrie lässt sich nicht anordnen.';

  @override
  String get msgProjectedNoModify =>
      'Projizierte Geometrie lässt sich hier nicht ändern.';

  @override
  String get msgPickDirectionLine =>
      'Eine Linie wählen, die die Richtung vorgibt.';

  @override
  String get msgPickAxisPoint =>
      'Punkt oder Mittelpunkt wählen, der die Achse vorgibt.';

  @override
  String get msgPickMirrorLine => 'Eine Linie wählen, an der gespiegelt wird.';

  @override
  String get msgMirrorLineInSelection =>
      'Die Spiegelachse darf nicht Teil der Auswahl sein.';

  @override
  String get msgSelectGeometryToPattern => 'Geometrie zum Anordnen wählen.';

  @override
  String get msgPickLineDirection1 => 'Unter Richtung 1 eine Linie wählen.';

  @override
  String get msgPickPatternAxis => 'Die Anordnungsachse wählen.';

  @override
  String get msgPickTheMirrorLine => 'Die Spiegelachse wählen.';

  @override
  String get msgPatternNothingToCreate =>
      'Die Anordnung hat nichts zu erzeugen.';

  @override
  String get msgPatternUnsatisfiable =>
      'Die Anordnung lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.';

  @override
  String msgPatternCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Anordnung erstellt ($count neue Objekte).',
      one: 'Anordnung erstellt (ein neues Objekt).',
    );
    return '$_temp0';
  }

  @override
  String get msgSelfSymNeedsOneSpline =>
      'Selbstsymmetrisch braucht genau einen Spline.';

  @override
  String get msgSelfSymNeedsOpenSpline =>
      'Selbstsymmetrisch braucht einen offenen Spline.';

  @override
  String get msgSelfSymEndOnMirror =>
      'Für Selbstsymmetrisch muss der Spline auf der Spiegelachse enden.';

  @override
  String get msgSelfSymUnsatisfiable =>
      'Selbstsymmetrisch lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.';

  @override
  String get msgSelfSymDone => 'Spline selbstsymmetrisch gemacht.';

  @override
  String get msgTrimBreaksConstraints =>
      'Dieses Stutzen würde die Abhängigkeiten der Skizze zerstören.';

  @override
  String get msgSplitBreaksConstraints =>
      'Dieses Teilen würde die Abhängigkeiten der Skizze zerstören.';

  @override
  String get msgNothingToOffset => 'Hier gibt es nichts zu versetzen.';

  @override
  String msgRadiusPastEdge(String radius, String most) {
    return 'R$radius läuft über das Ende dieser Kante hinaus. Diese Ecke nimmt höchstens R$most.';
  }

  @override
  String get msgPickTwoThatMeet =>
      'Zwei Linien, Bögen oder Kreise wählen, die sich treffen können.';

  @override
  String get msgPickTwoNonParallel => 'Zwei nicht parallele Linien wählen.';

  @override
  String get msgFilletBreaksSketch =>
      'Diese Verrundung würde die Skizze zerstören — eine gültige Ecke oder einen kleineren Radius wählen.';

  @override
  String get msgChamferBreaksSketch =>
      'Diese Fase würde die Skizze zerstören — eine gültige Ecke oder kleinere Abstände wählen.';

  @override
  String get msgShapeHasNoSize =>
      'Diese Form hat keine Größe — noch einmal zeichnen.';

  @override
  String get msgAlreadyLocked => 'Diese Geometrie ist bereits fixiert.';

  @override
  String get msgWouldOverConstrainC =>
      'Diese Abhängigkeit würde die Skizze überbestimmen.';

  @override
  String get msgConstraintUnsatisfiable =>
      'Diese Abhängigkeit lässt sich mit der vorhandenen Geometrie nicht erfüllen.';

  @override
  String get msgTangentNeedsCurve =>
      'Tangential braucht mindestens ein gekrümmtes Objekt.';

  @override
  String get msgTangentClosedSpline =>
      'Tangential an einen GESCHLOSSENEN Spline geht nicht.';

  @override
  String get msgSmoothNeedsTwoCurves =>
      'Stetig (G2) braucht zwei gekrümmte Objekte.';

  @override
  String get msgValueUnsatisfiable =>
      'Dieser Wert lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.';

  @override
  String get msgValueUnsatisfiableShort =>
      'Der Wert lässt sich mit den aktuellen Abhängigkeiten nicht erfüllen.';

  @override
  String get msgDrivenDimension =>
      'Das ist eine abhängige Bemaßung (Referenzmaß) — sie lässt sich nicht bearbeiten.';

  @override
  String get msgInvalidParamName => 'Ungültiger Parametername.';

  @override
  String get msgInvalidOrDuplicateParamName =>
      'Ungültiger oder bereits vergebener Parametername.';

  @override
  String msgParamNameInUse(String name) {
    return 'Der Parametername „$name“ ist bereits vergeben.';
  }

  @override
  String msgUnknownParam(String name) {
    return 'Unbekannter Parameter „$name“.';
  }

  @override
  String msgCircularRefDimension(String name) {
    return 'Zirkelbezug: „$name“ hängt von dieser Bemaßung ab.';
  }

  @override
  String msgCircularRefParam(String name) {
    return 'Zirkelbezug: „$name“ hängt von diesem Parameter ab.';
  }

  @override
  String get msgInvalidExpression => 'Ungültiger Ausdruck.';

  @override
  String msgParamUsedBy(String name, String user) {
    return '„$name“ wird von „$user“ verwendet — zuerst den Bezug entfernen.';
  }

  @override
  String get msgEdgeIsSpline =>
      'Diese Kante ist ein Spline — sie gibt keine eindeutige Richtung vor.';

  @override
  String get msgRotationAxisStraight =>
      'Eine Drehachse muss eine gerade Linie oder eine Achse sein.';

  @override
  String get msgPickEdgeOrCurve =>
      'Gerade Kante, Rundkante, Skizzenkurve oder Ursprungsachse wählen.';

  @override
  String get msgTapOnTheCurve => 'Auf die Kurve tippen.';

  @override
  String get msgPickPlanarFace =>
      'Planare Fläche, Arbeitsebene oder Ursprungsebene wählen.';

  @override
  String get msgPickSketchPointOccurrences =>
      'Einen Skizzen-PUNKT wählen — die Exemplare entstehen dort, wo die Punkte sind.';

  @override
  String get msgTapFaceOfFeature =>
      'Eine Fläche des anzuordnenden Elements antippen oder es im Browser wählen.';

  @override
  String get msgFaceNoSingleFeature =>
      'Diese Fläche lässt sich nicht auf ein einzelnes Element zurückführen — das Element im Browser wählen.';

  @override
  String msgAddedNamed(String name) {
    return '$name hinzugefügt.';
  }

  @override
  String msgRemovedNamed(String name) {
    return '$name entfernt.';
  }

  @override
  String get msgTapSolidBody => 'Volumenkörper antippen.';

  @override
  String get msgTapSketchPointForHole =>
      'Einen Skizzen-PUNKT antippen — dorthin kommt die Bohrung.';

  @override
  String msgNotBuiltYet(String command) {
    return '$command: noch nicht gebaut — Versatz von Ebene oder Mittelebene verwenden.';
  }

  @override
  String get dlgEquationCurve => 'Gleichungskurve';

  @override
  String get lblEquationHint => 'y = f(x)   (sin, cos, sqrt, ^, pi, …)';

  @override
  String get lblXMin => 'x min';

  @override
  String get lblXMax => 'x max';

  @override
  String get dlgProperties => 'Eigenschaften';

  @override
  String get dlgParameters => 'Parameter';

  @override
  String get dlgGear => 'Zahnrad';

  @override
  String get dlgText => 'Text';

  @override
  String get dlgFreehandSpline => 'Freihand-Spline';

  @override
  String get dlgPolygon => 'Polygon';

  @override
  String lblDirectionN(String n) {
    return 'Richtung $n';
  }

  @override
  String get lblAxis => 'Achse';

  @override
  String get lblMirrorLine => 'Spiegelachse';

  @override
  String get lblGeometry => 'Geometrie';

  @override
  String get lblExtents => 'Ausdehnung';

  @override
  String get lblBoundary => 'Begrenzung';

  @override
  String get lblIncludeGeometry => 'Geometrie einschließen';

  @override
  String get lblSuppress => 'Unterdrücken';

  @override
  String get tipCancel => 'Abbrechen';

  @override
  String get tipSelectDirectionLine => 'Richtungslinie wählen';

  @override
  String get tipFlipDirection => 'Richtung umkehren';

  @override
  String get tipPatternAlongPath =>
      'Anordnung entlang eines Pfades — noch nicht verfügbar';

  @override
  String get tipSelectRotationAxisPoint => 'Drehachsenpunkt wählen';

  @override
  String get tipFlipRotation => 'Drehrichtung umkehren';

  @override
  String get tipSelectGeometryToMirror => 'Zu spiegelnde Geometrie wählen';

  @override
  String get tipSelectMirrorLine => 'Spiegelachse wählen';

  @override
  String get tipSelectGeometryToPattern => 'Anzuordnende Geometrie wählen';

  @override
  String get msgBoundaryFillNotYet =>
      'Begrenzungsfüllung — noch nicht verfügbar';

  @override
  String get msgSuppressNotYet =>
      'Exemplare unterdrücken — noch nicht verfügbar';

  @override
  String get msgPickWhileSelectorBlue =>
      'Geometrie im Ansichtsfenster wählen, solange der blaue Auswahlschalter aktiv ist. OK / Fertig erzeugt die Anordnung.';

  @override
  String get msgFilletPickTwo =>
      'Zwei Linien, Bögen oder Kreise wählen.\nDie erste Verrundung wird bemaßt; die folgenden übernehmen den Radius.';

  @override
  String get msgDistance1FirstLine =>
      'Abstand 1 gilt für die zuerst gewählte Linie.';

  @override
  String get msgPolygonSides =>
      'Seiten. Erst den Mittelpunkt, dann eine Ecke wählen.';

  @override
  String get hintTapBodyIn3d => 'Körper in 3D antippen…';

  @override
  String get hintTapFeaturesInBrowser => 'Elemente im Browser antippen…';

  @override
  String get hintTapPointOnCurve => 'Punkt auf der Kurve antippen…';

  @override
  String get hintTapEdgeOrAxis => 'Kante oder Achse antippen…';

  @override
  String get hintTapCircularEdge => 'Rundkante oder Achse antippen…';

  @override
  String get hintTapSketchPoint => 'Skizzenpunkt antippen…';

  @override
  String get hintTapOriginalPoint =>
      'Punkt antippen, auf dem das Original sitzt…';

  @override
  String get hintTapFaceToFollow => 'Zu folgende Fläche antippen…';

  @override
  String get hintTapFaceOrPlane => 'Fläche oder Ebene antippen…';

  @override
  String get msgNoDimensionsInSketch => 'Keine Bemaßungen in dieser Skizze.';

  @override
  String get btnAddNumericParameter => 'Numerischen Parameter hinzufügen';

  @override
  String get colParameterName => 'Parametername';

  @override
  String get colEquation => 'Gleichung';

  @override
  String get colValue => 'Wert';

  @override
  String get lblReference => '(Referenz)';

  @override
  String get lblPoints => 'Punkte';

  @override
  String get lblSmoothing => 'Glättung';

  @override
  String lblFitPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stützpunkte',
      one: 'Ein Stützpunkt',
    );
    return '$_temp0';
  }

  @override
  String get tipFinishEnter => 'Fertig (Eingabe)';

  @override
  String get tipDiscardEsc => 'Verwerfen (Esc)';

  @override
  String get lblFont => 'Schrift';

  @override
  String get lblSize => 'Größe';

  @override
  String get lblPreview => 'Vorschau';

  @override
  String lblEdgeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kanten',
      one: 'Eine Kante',
    );
    return '$_temp0';
  }

  @override
  String get btnAddEdgeSet => 'Kantengruppe';

  @override
  String get lblSwapFaces => 'Die beiden Flächen tauschen';

  @override
  String lblWorkPlaneOffset(String name) {
    return '$name  Versatz';
  }

  @override
  String lblSketchPlaneN(String n) {
    return '$n Skizzenebene';
  }

  @override
  String lblNeedsExistingBody(String label) {
    return '$label (braucht einen vorhandenen Körper)';
  }

  @override
  String get tipApplyAndStartAnother => 'Übernehmen und das nächste beginnen';

  @override
  String get msgSplitRemovesOtherSide =>
      'Alles auf der anderen Seite der Ebene wird entfernt. Das Teilen in zwei Körper ist nicht gebaut.';

  @override
  String get msgGearTapToPlace =>
      'In die Skizze tippen, um es zu setzen; dann Mittelpunkt und einen Winkel bemaßen.';

  @override
  String get lblAutoRootTip => 'Fuß- und Kopfkreisradien automatisch';

  @override
  String get dlgReportBug => 'Fehler melden';

  @override
  String get msgBugPrompt =>
      'Was haben Sie erwartet, und was ist stattdessen passiert?\nDas Modell, der Zustand jedes Elements und das vollständige Protokoll werden automatisch angehängt — beschreiben Sie nur, was Sie GESEHEN haben.';

  @override
  String get hintBugExample =>
      'z. B. die obere Kante mit 2 mm verrundet, und die Wand ist verschwunden statt abgerundet zu werden';

  @override
  String get btnSaveReport => 'Bericht sichern';

  @override
  String get btnCopyPath => 'Pfad kopieren';

  @override
  String get btnCopyIssueLink => 'Issue-Link kopieren';

  @override
  String get btnDirect => 'Direkt';

  @override
  String get btnDeleteFace => 'Fläche löschen';

  @override
  String get btnThickenOffset => 'Verdicken / Versatz';

  @override
  String get btnUcs => 'BKS';

  @override
  String get btnSketchDriven => 'Skizzengesteuert';

  @override
  String get btnCenterline => 'Mittellinie';

  @override
  String get btnConstraintSettings => 'Abhängigkeitseinstellungen';

  @override
  String get btnCopy => 'Kopieren';

  @override
  String get btnDrivenDimension => 'Abhängige Bemaßung';

  @override
  String get btnExtend => 'Dehnen';

  @override
  String get btnPointsTool => 'Punkte';

  @override
  String get btnShowConstraints => 'Abhängigkeiten einblenden';

  @override
  String get btnShowFormat => 'Format einblenden';

  @override
  String get btnSmoothG2 => 'Stetig (G2)';

  @override
  String get btnStretch => 'Strecken';

  @override
  String get btnCenterPoint => 'Mittelpunkt';

  @override
  String get btnSplitCurve => 'Teilen';

  @override
  String get btnOffsetCurve => 'Versatz';

  @override
  String get btnFinish => 'Fertig';

  @override
  String get btnFinishSketch => 'Skizze\nfertig';

  @override
  String get featExtrusion => 'Extrusion';

  @override
  String get featRevolution => 'Drehung';

  @override
  String get featSweep => 'Sweeping';

  @override
  String get featLoft => 'Erhebung';

  @override
  String get featCoil => 'Spirale';

  @override
  String get featFillet => 'Verrundung';

  @override
  String get featChamfer => 'Fase';

  @override
  String get featHole => 'Bohrung';

  @override
  String get featSplit => 'Trennen';

  @override
  String get featCombine => 'Kombinieren';

  @override
  String get featDeleteFace => 'Fläche löschen';

  @override
  String get cmdDeleteFace => 'Fläche löschen';

  @override
  String get cmdMoveFaces => 'Flächen verschieben';

  @override
  String get cmdSizeFaces => 'Flächengröße ändern';

  @override
  String get cmdScaleBody => 'Körper skalieren';

  @override
  String get verbDelete => 'Löschen';

  @override
  String get verbMove => 'Verschieben';

  @override
  String get patRectangular => 'Rechteckige Anordnung';

  @override
  String get patCircular => 'Runde Anordnung';

  @override
  String get patSketchDriven => 'Skizzengesteuerte Anordnung';

  @override
  String get patMirror => 'Spiegeln';

  @override
  String get holeSimple => 'Einfach';

  @override
  String get holeCounterbore => 'Senkung';

  @override
  String get holeSpotface => 'Plansenkung';

  @override
  String get holeCountersink => 'Kegelsenkung';

  @override
  String get holeSimpleShort => 'Einfach';

  @override
  String get holeCounterboreShort => 'Senkung';

  @override
  String get holeSpotfaceShort => 'Plan';

  @override
  String get holeCountersinkShort => 'Kegel';

  @override
  String get msgNoInteriorEdgesLeft => 'Keine Innenkanten mehr zum Hinzufügen.';

  @override
  String get msgNoExteriorEdgesLeft => 'Keine Außenkanten mehr zum Hinzufügen.';

  @override
  String msgAddedInteriorEdges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Innenkanten hinzugefügt.',
      one: 'Eine Innenkante hinzugefügt.',
    );
    return '$_temp0';
  }

  @override
  String msgAddedExteriorEdges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Außenkanten hinzugefügt.',
      one: 'Eine Außenkante hinzugefügt.',
    );
    return '$_temp0';
  }

  @override
  String get msgUndone => 'Rückgängig';

  @override
  String get msgRedone => 'Wiederholt';

  @override
  String get msgShow => 'Einblenden';

  @override
  String get extToNext => 'Bis zum Nächsten';

  @override
  String get extToFace => 'Bis';

  @override
  String get extThroughAll => 'Durch alle';

  @override
  String get extDistance => 'Abstand';

  @override
  String get wfPickEdgeFacePlanesPoints =>
      'Kante, Fläche, zwei Ebenen oder zwei Punkte wählen.';

  @override
  String get wfPickLinearEdge => 'Gerade Kante oder Skizzenlinie wählen.';

  @override
  String get wfPickCircularEdge => 'Kreis- oder Ellipsenkante wählen.';

  @override
  String get wfPickCylConeFace => 'Zylinder- oder Kegelfläche wählen.';

  @override
  String get wfPickPoint => 'Punkt wählen.';

  @override
  String get wfPickParallelLine => 'Linie wählen, zu der parallel gebaut wird.';

  @override
  String get wfPickFirstPoint => 'Ersten Punkt wählen.';

  @override
  String get wfPickSecondPoint => 'Zweiten Punkt wählen.';

  @override
  String get wfPlaneDragOrPickSecond =>
      'Fläche oder Ebene wählen — ziehen ergibt einen Versatz, eine zweite parallele Fläche die Mittelebene.';

  @override
  String get wfPlaneSecondParallelEdgeOrPoint =>
      'Parallele Fläche für die Mittelebene wählen, Kante zum Abwinkeln oder Eckpunkt für eine parallele Ebene — oder ziehen für einen Versatz.';

  @override
  String get wfPlaneSecondCoplanarOrPoint =>
      'Zweite komplanare Kante wählen, oder einen Eckpunkt für die Normalebene.';

  @override
  String get wfPlaneTwoMorePoints =>
      'Zwei weitere Punkte für die Ebene wählen.';

  @override
  String wfCannotDefinePlane(String ref) {
    return '$ref kann keine Ebene festlegen.';
  }

  @override
  String wfNoPlaneFromTwo(String a, String b) {
    return '$a und $b legen keine Ebene fest.';
  }

  @override
  String get wfPickThirdPoint => 'Dritten Punkt wählen.';

  @override
  String get wfPickFirstPlane => 'Erste Ebene oder planare Fläche wählen.';

  @override
  String get wfPickSecondNonParallelPlane =>
      'Zweite, nicht parallele Ebene oder Fläche wählen.';

  @override
  String get wfPickPlane => 'Ebene oder planare Fläche wählen.';

  @override
  String get wfPickAxisThroughPoint =>
      'Punkt wählen, durch den die Achse läuft.';

  @override
  String get wfPickVertexCircleOrMeeting =>
      'Eckpunkt, Kreiskante oder sich treffende Geometrie wählen.';

  @override
  String get wfPickVertexToGround =>
      'Eckpunkt oder Mittelpunkt wählen, an dem fixiert wird.';

  @override
  String get wfPickVertexSketchPointMid =>
      'Eckpunkt, Skizzenpunkt oder Kantenmittelpunkt wählen.';

  @override
  String get wfPickTorusFace => 'Torusfläche wählen.';

  @override
  String get wfPickSphereFace => 'Kugelfläche wählen.';

  @override
  String get wfPickFirstLine => 'Erste Linie, Kante oder Achse wählen.';

  @override
  String get wfPickSecondCrossingLine =>
      'Zweite Linie wählen, die sie schneidet.';

  @override
  String get wfPickCrossingLine =>
      'Linie, Kante oder Achse wählen, die sie schneidet.';

  @override
  String get wfPickSecondPlane => 'Zweite Ebene wählen.';

  @override
  String get wfPickThirdPlane => 'Dritte Ebene wählen.';

  @override
  String get wfPickLineOrTwoPlanes =>
      'Linie wählen, die sie kreuzt, oder zwei weitere Ebenen.';

  @override
  String get wfPickSecondLineOrPlane =>
      'Zweite Linie wählen, oder eine Ebene zum Kreuzen.';

  @override
  String get wfPickSecondPlaneOrPoint =>
      'Zweite Ebene zum Schneiden wählen, oder einen Punkt für die Normale hindurch.';

  @override
  String get wfPickSecondPointPlaneOrLine =>
      'Zweiten Punkt, eine Ebene oder eine Linie wählen.';

  @override
  String get wfPickParallelPlane =>
      'Ebene oder planare Fläche wählen, zu der parallel gebaut wird.';

  @override
  String get wfPickPlaneThroughPoint =>
      'Punkt wählen, durch den die Ebene läuft.';

  @override
  String get wfPickFirstEdge => 'Erste Kante oder Linie wählen.';

  @override
  String get wfPickSecondCoplanarEdge =>
      'Zweite Kante in derselben Ebene wählen.';

  @override
  String get wfPickNormalAxis =>
      'Achse, Kante oder Linie wählen, zu der normal gebaut wird.';

  @override
  String get wfPickCylFaceSide =>
      'Zylinderfläche wählen, auf der Seite, wo die Ebene liegen soll.';

  @override
  String get wfPickCylFace => 'Zylinderfläche wählen.';

  @override
  String get wfPickEdgeAlongIt => 'Kante wählen, die darauf liegt.';

  @override
  String get wfPickPlaneToParallel =>
      'Ebene wählen, zu der parallel gebaut wird.';

  @override
  String get wfPickPlaneToAngleFrom =>
      'Ebene wählen, von der aus gewinkelt wird.';

  @override
  String get wfPickPivotEdgeInPlane =>
      'Kante zum Schwenken wählen — sie muss in dieser Ebene liegen.';

  @override
  String get wfTapCurveToCross =>
      'Skizzenkurve dort antippen, wo die Ebene sie schneiden soll.';

  @override
  String wfNotStraightEdge(String ref) {
    return '$ref ist keine gerade Kante oder Linie.';
  }

  @override
  String wfNotCircularEdge(String ref) {
    return '$ref ist keine Kreis- oder Ellipsenkante.';
  }

  @override
  String wfNotRevolvedFace(String ref) {
    return '$ref ist keine Drehfläche — Zylinder, Kegel oder Torus wählen.';
  }

  @override
  String wfNoPoint(String ref) {
    return '$ref ergibt keinen Punkt.';
  }

  @override
  String wfNotPlane(String ref) {
    return '$ref ist keine Ebene und keine planare Fläche.';
  }

  @override
  String wfNeitherPointNorLine(String ref) {
    return '$ref ist weder ein Punkt noch eine Linie.';
  }

  @override
  String wfNeitherPlaneNorLine(String ref) {
    return '$ref ist weder eine Ebene noch eine Linie.';
  }

  @override
  String get wfNoParallelLinePicked =>
      'Keine der beiden Auswahlen ist eine Linie.';

  @override
  String get wfPickPointForAxis =>
      'Punkt wählen, durch den die Achse gehen soll.';

  @override
  String get wfPickPointForPlane =>
      'Punkt wählen, durch den die Ebene gehen soll.';

  @override
  String get wfSamePlace => 'Diese beiden Punkte liegen an derselben Stelle.';

  @override
  String wfParallelNeverMeet(String a, String b) {
    return '$a und $b sind parallel — sie treffen sich nie.';
  }

  @override
  String wfParallelNeverCross(String a, String b) {
    return '$a und $b sind parallel — sie kreuzen sich nie.';
  }

  @override
  String wfCannotDefineAxis(String ref) {
    return '$ref kann keine Achse festlegen.';
  }

  @override
  String wfCannotDefinePoint(String ref) {
    return '$ref kann keinen Punkt festlegen.';
  }

  @override
  String wfParallelPickTwoMeeting(String a, String b) {
    return '$a und $b sind parallel — zwei Ebenen wählen, die sich schneiden.';
  }

  @override
  String wfNoAxisFromTwo(String a, String b) {
    return '$a und $b legen keine Achse fest.';
  }

  @override
  String wfNoPointFromTwo(String a, String b) {
    return '$a und $b legen keinen Punkt fest.';
  }

  @override
  String wfNotClosedCircle(String ref) {
    return '$ref ist keine geschlossene Kreiskante.';
  }

  @override
  String wfNotSphere(String ref) {
    return '$ref ist keine Kugelfläche.';
  }

  @override
  String wfNotTorus(String ref) {
    return '$ref ist keine Torusfläche.';
  }

  @override
  String wfNotLineEdgeAxis(String ref) {
    return '$ref ist keine Linie, Kante oder Achse.';
  }

  @override
  String wfNotAxisEdgeLine(String ref) {
    return '$ref ist keine Achse, Kante oder Linie.';
  }

  @override
  String wfNotEdgeOrLine(String ref) {
    return '$ref ist keine Kante und keine Linie.';
  }

  @override
  String get wfPickOnePlaneOneLine => 'Eine Ebene und eine Linie wählen.';

  @override
  String wfSkewByGap(String a, String b, String gap) {
    return '$a und $b treffen sich nicht — $gap Abstand.';
  }

  @override
  String wfLineParallelToPlane(String line, String plane) {
    return '$line ist parallel zu $plane — sie schneidet sie nie.';
  }

  @override
  String wfThreeNoCommonPoint(String a, String b, String c) {
    return '$a, $b und $c treffen sich nicht in einem Punkt — zwei davon sind parallel, oder alle drei teilen sich eine Gerade.';
  }

  @override
  String wfNotACurve(String ref) {
    return '$ref ist keine Kurve — Skizzenkurve dort antippen, wo die Ebene sie schneiden soll.';
  }

  @override
  String get wfPickPivotEdge => 'Kante wählen, um die die Ebene schwenkt.';

  @override
  String wfEdgeNotInPlane(String edge, String plane) {
    return '$edge ist nicht parallel zu $plane — die Ebene kann nur um eine Kante schwenken, die darin liegt.';
  }

  @override
  String get wfAngleNotANumber => 'Der Winkel ist keine Zahl.';

  @override
  String wfNotCylForTangent(String ref) {
    return '$ref ist keine Zylinderfläche — eine Tangentialebene braucht eine.';
  }

  @override
  String wfPointInsideCyl(String pt, String cyl) {
    return '$pt liegt in $cyl — dadurch geht keine Tangentialebene.';
  }

  @override
  String wfTwoTangentThroughPoint(String cyl, String pt) {
    return 'Zwei Ebenen sind tangential an $cyl durch $pt — die Fläche auf der Seite antippen, auf der die Ebene liegen soll.';
  }

  @override
  String wfTwoTangentParallel(String cyl, String plane) {
    return 'Zwei Ebenen sind tangential an $cyl und parallel zu $plane — die Fläche auf der Seite antippen, auf der die Ebene liegen soll.';
  }

  @override
  String wfEdgeNotParallelToAxis(String edge, String cyl) {
    return '$edge ist nicht parallel zur Achse von $cyl.';
  }

  @override
  String wfEdgeOffCylinder(String edge, String cyl, String gap) {
    return '$edge liegt nicht auf $cyl — sie ist $gap mm daneben.';
  }

  @override
  String wfPlaneNotParallelToAxis(String plane, String cyl) {
    return '$plane ist nicht parallel zur Achse von $cyl — dazu ist keine Tangentialebene parallel.';
  }

  @override
  String wfCollinearThreePoints(String a, String b, String c) {
    return '$a, $b und $c liegen auf einer Geraden — drei Punkte dürfen nicht kollinear sein.';
  }

  @override
  String wfSameLineTwice(String a, String b) {
    return '$a und $b sind dieselbe Linie — eine Ebene braucht zwei verschiedene Kanten.';
  }

  @override
  String wfSkewEdges(String a, String b, String gap) {
    return '$a und $b sind windschief — sie verfehlen sich um $gap mm.';
  }

  @override
  String get secInputGeometry => 'Eingabegeometrie';

  @override
  String get secOutputGeometry => 'Ausgabegeometrie';

  @override
  String get secBehavior => 'Verhalten';

  @override
  String get secPlacement => 'Platzierung';

  @override
  String get secOutput => 'Ausgabe';

  @override
  String get secExtents => 'Ausdehnung';

  @override
  String get lblDirection => 'Richtung';

  @override
  String get lblOrientation => 'Ausrichtung';

  @override
  String get lblMethod => 'Methode';

  @override
  String get lblDistance => 'Abstand';

  @override
  String get lblAngle => 'Winkel';

  @override
  String get lblDepth => 'Tiefe';

  @override
  String get lblDiameter => 'Durchmesser';

  @override
  String get lblType => 'Typ';

  @override
  String get lblCount => 'Anzahl';

  @override
  String get lblNumber => 'Anzahl';

  @override
  String get lblSpacing => 'Abstand';

  @override
  String get lblDistribution => 'Verteilung';

  @override
  String get lblFlip => 'Umkehren';

  @override
  String get lblKeep => 'Behalten';

  @override
  String get lblPlaneField => 'Ebene';

  @override
  String get lblFaceField => 'Fläche';

  @override
  String get lblEdges => 'Kanten';

  @override
  String get lblRadius => 'Radius';

  @override
  String lblRadiusN(String n) {
    return 'Radius $n';
  }

  @override
  String get lblDistance1 => 'Abstand 1';

  @override
  String get lblDistance2 => 'Abstand 2';

  @override
  String get lblTwoDistances => 'Zwei Abstände';

  @override
  String get lblDistanceAndAngle => 'Abstand und Winkel';

  @override
  String get lblEqualDistance => 'Gleicher Abstand';

  @override
  String get lblAllFillets => 'Alle Innenkanten';

  @override
  String get lblAllRounds => 'Alle Außenkanten';

  @override
  String get hintTapEdgesIn3d => 'Kanten in 3D antippen…';

  @override
  String get lblSelectEdges => 'Kanten wählen';

  @override
  String get lblBodies => 'Körper';

  @override
  String get lblBase => 'Basis';

  @override
  String get lblToolbodies => 'Werkzeugkörper';

  @override
  String get hintTapBodyToKeep => 'Körper antippen, der BLEIBT…';

  @override
  String get hintPickBaseFirst => 'Erst die Basis wählen';

  @override
  String get hintTapBodiesToCombine => 'Körper zum Kombinieren antippen…';

  @override
  String get lblOperation => 'Operation';

  @override
  String get lblKeepTool => 'Werkzeug behalten';

  @override
  String get lblYes => 'Ja';

  @override
  String get opJoin => 'Vereinigen';

  @override
  String get opCut => 'Differenz';

  @override
  String get opIntersect => 'Schnittmenge';

  @override
  String get opNewSolid => 'Neuer Körper';

  @override
  String get lblBoolean => 'Boolesch';

  @override
  String get lblTargetBody => 'Zielkörper';

  @override
  String get lblTrim => 'Beschneiden';

  @override
  String get hintTapPlaneOrFace => 'Ebene oder planare Fläche antippen…';

  @override
  String get lblThisSide => 'Diese Seite';

  @override
  String get lblOtherSide => 'Andere Seite';

  @override
  String get lblProfiles => 'Profile';

  @override
  String get hintSelectProfile => 'Profil im Ansichtsfenster wählen';

  @override
  String get lblFrom => 'Von';

  @override
  String get lblPath => 'Pfad';

  @override
  String get hintTapCurveIn3d => 'Kurve in 3D antippen…';

  @override
  String get lblSelectCurveOrEdge => 'Kurve oder Kante wählen';

  @override
  String get lblPathSelected => 'Pfad gewählt';

  @override
  String get lblFollowPath => 'Pfad folgen';

  @override
  String get lblFixed => 'Fest';

  @override
  String get lblGuide => 'Führung';

  @override
  String get lblTaper => 'Verjüngung';

  @override
  String get lblTwist => 'Verdrehung';

  @override
  String get lblSections => 'Querschnitte';

  @override
  String get hintTapProfilesIn3d => 'Profile in 3D antippen…';

  @override
  String get hintClickToAdd => 'Zum Hinzufügen tippen';

  @override
  String get lblTransition => 'Übergang';

  @override
  String get lblSmooth => 'Stetig';

  @override
  String get lblRuled => 'Geradlinig';

  @override
  String get lblClosedLoop => 'Geschlossene Schleife';

  @override
  String get lblMergeTangentFaces => 'Tangentiale Flächen zusammenfassen';

  @override
  String get lblRevolutionCount => 'Umdrehungen';

  @override
  String get lblHeight => 'Höhe';

  @override
  String get lblPitch => 'Steigung';

  @override
  String get lblRotationAngle => 'Drehwinkel';

  @override
  String get hintTapLineOrAxis => 'Linie oder Ursprungsachse antippen…';

  @override
  String get lblSelectAxis => 'Achse wählen';

  @override
  String get lblFull => 'Voll';

  @override
  String get lblAngleA => 'Winkel A';

  @override
  String get lblAngleB => 'Winkel B';

  @override
  String get lblDistanceA => 'Abstand A';

  @override
  String get lblDistanceB => 'Abstand B';

  @override
  String get lblTerminateOn => 'Enden auf';

  @override
  String get hintTapFaceIn3d => 'Fläche in 3D antippen…';

  @override
  String get lblSelectFace => 'Fläche wählen';

  @override
  String get lblFaceSelected => 'Fläche gewählt — antippen zum Ändern';

  @override
  String get lblDefault => 'Standard';

  @override
  String get lblFlipped => 'Umgekehrt';

  @override
  String get lblSymmetric => 'Symmetrisch';

  @override
  String get lblAsymmetric => 'Asymmetrisch';

  @override
  String get coilRevAndHeight => 'Umdrehungen und Höhe';

  @override
  String get coilPitchAndRev => 'Steigung und Umdrehungen';

  @override
  String get coilPitchAndHeight => 'Steigung und Höhe';

  @override
  String get coilSpiral => 'Spirale';

  @override
  String get hintTapSketchPointsIn3d => 'Skizzenpunkte in 3D antippen…';

  @override
  String get lblCountersinkDia => 'Senkung ⌀';

  @override
  String get lblTermination => 'Endbedingung';

  @override
  String get lblIntoPart => 'Ins Bauteil';

  @override
  String get ctxShow => 'Einblenden';

  @override
  String get ctxLock => 'Sperren';

  @override
  String get ctxUnlock => 'Entsperren';

  @override
  String get ctxRenameEllipsis => 'Umbenennen…';

  @override
  String ctxMoveNHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hierher verschieben',
      one: 'Eines hierher verschieben',
    );
    return '$_temp0';
  }

  @override
  String get ctxSuppressOccurrence => 'Exemplar unterdrücken';

  @override
  String get ctxRestoreOccurrence => 'Exemplar wiederherstellen';

  @override
  String get nodeYzPlane => 'YZ-Ebene';

  @override
  String get nodeXzPlane => 'XZ-Ebene';

  @override
  String get nodeXyPlane => 'XY-Ebene';

  @override
  String get nodeZAxis => 'Z-Achse';

  @override
  String get msgLayerEmptyRemoved => 'Dieser Layer ist leer und wird entfernt.';

  @override
  String msgRemovesLayerAndEntities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Damit werden der Layer und seine $count Objekte entfernt.',
      one: 'Damit werden der Layer und sein einziges Objekt entfernt.',
    );
    return '$_temp0';
  }

  @override
  String get secModelParameters => 'Modellparameter';

  @override
  String get secUserParameters => 'Benutzerparameter';

  @override
  String lblLineN(String n) {
    return 'Linie $n';
  }

  @override
  String get lblSingleOpenSplineOnly => '(nur ein offener Spline)';

  @override
  String get lblSolid => 'Volumenkörper';

  @override
  String get lblSelectSolid => 'Volumenkörper wählen';

  @override
  String get lblComponent => 'Komponente';

  @override
  String get lblSelectComponents => 'Komponenten wählen';

  @override
  String lblNComponents(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Komponenten',
      one: '1 Komponente',
    );
    return '$_temp0';
  }

  @override
  String get hintTapComponentIn3d => 'Komponente in 3D antippen…';

  @override
  String get lblFeaturePattern => 'Element-Anordnung';

  @override
  String get lblOwnSpacing => 'Eigene Abstände';

  @override
  String get lblFeature => 'Element';

  @override
  String get lblSelectFeatures => 'Elemente wählen';

  @override
  String get lblDirectionA => 'Richtung A';

  @override
  String get lblDirectionB => 'Richtung B';

  @override
  String get lblStartA => 'Start A';

  @override
  String get lblStartB => 'Start B';

  @override
  String get lblCurveStart => 'Kurvenanfang';

  @override
  String lblMmAlong(String value) {
    return '$value mm entlang';
  }

  @override
  String get lblAddIrregularAngle => 'Abweichender Winkel';

  @override
  String get lblAddIrregularDistance => 'Abweichender Abstand';

  @override
  String get lblSelectDir => 'Richtung…';

  @override
  String get lblMidplane => 'Mittelebene';

  @override
  String get lblCurveLength => 'Kurvenlänge';

  @override
  String get lblIdentical => 'Identisch';

  @override
  String get lblIncremental => 'Schrittweise';

  @override
  String get lblRotational => 'Mitdrehend';

  @override
  String get lblSketchPoint => 'Skizzenpunkt';

  @override
  String get lblSelectPoint => 'Punkt wählen';

  @override
  String get lblBasePoint => 'Basispunkt';

  @override
  String get lblFollowFace => 'Fläche folgen';

  @override
  String get lblMirrorPlane => 'Spiegelebene';

  @override
  String get lblCreationMethod => 'Erzeugungsmethode';

  @override
  String get lblAdjust => 'Anpassen';

  @override
  String get lblRemoveOriginal => 'Original entfernen';

  @override
  String get lblKeepMirroredHalf => 'Nur die gespiegelte Hälfte behalten';

  @override
  String get lblPatternFeatures => 'Einzelne Elemente anordnen';

  @override
  String get lblPatternSolid => 'Einen Volumenkörper anordnen';

  @override
  String get lblPick => 'Wählen';

  @override
  String lblPointCount(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name ($count Punkte)',
      one: '$name (ein Punkt)',
    );
    return '$_temp0';
  }

  @override
  String lblCoords(String x, String y) {
    return '($x, $y)';
  }

  @override
  String get conCoincident => 'Koinzident';

  @override
  String get conCollinear => 'Kollinear';

  @override
  String get conConcentric => 'Konzentrisch';

  @override
  String get conLock => 'Fixieren';

  @override
  String get conParallel => 'Parallel';

  @override
  String get conPerpendicular => 'Lotrecht';

  @override
  String get conHorizontal => 'Horizontal';

  @override
  String get conVertical => 'Vertikal';

  @override
  String get conTangent => 'Tangential';

  @override
  String get conSymmetric => 'Symmetrisch';

  @override
  String get conEqual => 'Gleich';

  @override
  String get lblModuleMm => 'Modul (mm)';

  @override
  String get lblTeeth => 'Zähne';

  @override
  String get lblCornerRadiusMm => 'Eckenradius (mm)';

  @override
  String get lblSunTeeth => 'Sonnenzähne';

  @override
  String get lblPlanetTeeth => 'Planetenzähne';

  @override
  String get lblPlanets => 'Planeten';

  @override
  String get lblPressureAngle => 'Eingriffswinkel (°)';

  @override
  String get lblProfileShift => 'Profilverschiebung';

  @override
  String get lblBoreDia => 'Bohrung Ø (mm)';

  @override
  String get btnInsert => 'Einfügen';

  @override
  String get gearExternal => 'Stirnrad';

  @override
  String get gearInternal => 'Hohlrad';

  @override
  String get gearPlanetary => 'Planetensatz';

  @override
  String gearRingInfo(String teeth, String dist) {
    return 'Hohlrad ${teeth}Z · Achsabstand $dist';
  }

  @override
  String get hudFullyConstrained => 'Vollständig bestimmt';

  @override
  String get hudCancelEsc => 'Abbrechen (Esc)';

  @override
  String hudDeleteN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte löschen',
      one: 'Ein Objekt löschen',
    );
    return '$_temp0';
  }

  @override
  String get hudLineKey => 'Linie (L)';

  @override
  String get hudCircleKey => 'Kreis (C)';

  @override
  String get hudRectKey => 'Rechteck (R)';

  @override
  String get hudDimensionKey => 'Bemaßung (D)';

  @override
  String get hintTapDimensionToInsert =>
      'Eine Bemaßung in der Skizze antippen, um sie als „Name“ einzufügen';

  @override
  String get hintTextEmbedParams =>
      'Text — Parameter als <Breite> oder „d0“ einbetten';

  @override
  String get msgReportSaved => 'Bericht gesichert';

  @override
  String get msgReportFailed => 'Bericht FEHLGESCHLAGEN';

  @override
  String get msgBugSaved =>
      'Dateien-App > Auf meinem iPad > prototype > bugreports\nDie .zip verschicken — sie enthält alles Nötige; es muss keine Erklärung mitreisen.';

  @override
  String get msgBugBundleFailed =>
      'Das Paket ließ sich nicht schreiben. Das Protokoll enthält die Beschreibung noch, die Sitzung ist also nicht verloren — siehe die „bug“-Zeilen in prototype_log.txt.';

  @override
  String get msgBugUploaded =>
      'Zusätzlich online abgelegt — eine KI kann direkt darauf zugreifen.';

  @override
  String get msgBugUploadFailed =>
      'Der Relay war nicht erreichbar — es gibt nur die lokale Kopie oben. Von Hand verschicken, oder es später erneut versuchen.';

  @override
  String get hintPickBodyTapCancel => 'Körper wählen… (zum Abbrechen tippen)';

  @override
  String get lblSelectBodyIn3d => 'Körper in 3D / im Browser wählen';

  @override
  String get secAdvancedProperties => 'Erweiterte Eigenschaften';

  @override
  String get lblTaperA => 'Verjüngung A';

  @override
  String get lblMatchShape => 'Form angleichen';

  @override
  String get lblSelectFaceBtn => 'Fläche wählen';

  @override
  String gearRingLine(String teeth, String dist, String warn) {
    return 'Hohlrad ${teeth}Z · Achsabstand $dist mm$warn';
  }

  @override
  String get gearUnevenWarn => ' · ⚠ Planeten nicht gleichmäßig verteilt';

  @override
  String gearPitchLine(String pitch, String tip, String root) {
    return 'Teilkreis Ø $pitch · Kopf Ø $tip · Fuß Ø $root mm';
  }

  @override
  String msgRemovesLayerAndEntitiesUndo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Entfernt den Layer und seine $count Objekte. Nicht rückgängig zu machen.',
      one:
          'Entfernt den Layer und sein einziges Objekt. Nicht rückgängig zu machen.',
    );
    return '$_temp0';
  }

  @override
  String get valNameEmpty => 'Der Name darf nicht leer sein';

  @override
  String get valNameTooLong => 'Der Name ist zu lang';

  @override
  String get valNameBadChars => 'Der Name darf / \\ und : nicht enthalten';

  @override
  String get valNameLeadingDot =>
      'Der Name darf nicht mit einem Punkt beginnen';

  @override
  String valBodyNameTaken(String name) {
    return 'Ein Körper namens „$name“ existiert bereits';
  }

  @override
  String valFeatureNameTaken(String name) {
    return 'Ein Element namens „$name“ existiert bereits';
  }

  @override
  String get valSelectOneEdge => 'Mindestens eine Kante wählen.';

  @override
  String get valRadiusPositive => 'Radius muss größer als 0 sein.';

  @override
  String valRadiusOfSetPositive(String n) {
    return 'Radius von Gruppe $n muss größer als 0 sein.';
  }

  @override
  String get valEndRadiusPositive => 'Endradius muss größer als 0 sein.';

  @override
  String valEndRadiusOfSetPositive(String n) {
    return 'Endradius von Gruppe $n muss größer als 0 sein.';
  }

  @override
  String get valDistancePositive => 'Abstand muss größer als 0 sein.';

  @override
  String get valDistance2Positive => 'Abstand 2 muss größer als 0 sein.';

  @override
  String get valAngle0to90 => 'Der Winkel muss zwischen 0 und 90 Grad liegen.';

  @override
  String get valSelectOneComponent =>
      'Mindestens eine Komponente zum Anordnen wählen.';

  @override
  String get valDrivingFeatureGone =>
      'Die treibende Element-Anordnung ist nicht mehr da.';

  @override
  String get valSelectOneFeature =>
      'Mindestens ein Element zum Anordnen wählen.';

  @override
  String get valSelectDirectionA =>
      'Richtung oder Kurve für Richtung A wählen.';

  @override
  String get valCountAAtLeastOne =>
      'Die Anzahl in Richtung A muss mindestens 1 sein.';

  @override
  String get valDistanceAPositive =>
      'Der Abstand in Richtung A muss größer als 0 sein.';

  @override
  String get valCountBAtLeastOne =>
      'Die Anzahl in Richtung B muss mindestens 1 sein.';

  @override
  String get valDistanceBPositive =>
      'Der Abstand in Richtung B muss größer als 0 sein.';

  @override
  String get valPatternNeedsTwo =>
      'Eine Anordnung braucht mehr als ein Exemplar.';

  @override
  String get valSelectRotationAxis => 'Drehachse wählen.';

  @override
  String get valCountAtLeastOne => 'Die Anzahl muss mindestens 1 sein.';

  @override
  String get valAngleNotZero => 'Der Winkel darf nicht 0 sein.';

  @override
  String get valSelectPointSketch => 'Die Skizze mit den Punkten wählen.';

  @override
  String get valSelectMirrorPlane => 'Spiegelebene wählen.';

  @override
  String get valNoSolidToPattern =>
      'Es gibt noch keinen Volumenkörper zum Anordnen.';

  @override
  String get valSelectPathCurve => 'Pfadkurve wählen.';

  @override
  String get valTwistUnsupported =>
      'Verdrehung wird noch nicht unterstützt — auf 0 lassen.';

  @override
  String get valSelectTwoSections => 'Mindestens zwei Querschnitte wählen.';

  @override
  String get valSelectAxis => 'Achse wählen.';

  @override
  String get valPitchPositive => 'Steigung muss größer als 0 sein.';

  @override
  String get valRevolutionPositive => 'Umdrehungen müssen größer als 0 sein.';

  @override
  String get valHeightPositive => 'Höhe muss größer als 0 sein.';

  @override
  String get valSelectRevolveAxis => 'Drehachse wählen.';

  @override
  String get valAxisNoDirection => 'Die Achse gibt keine Richtung vor.';

  @override
  String get valAngleA0to360 => 'Winkel A muss zwischen 0 und 360 Grad liegen.';

  @override
  String get valAngleBPositive => 'Winkel B muss größer als 0 sein.';

  @override
  String get valAngleABMax360 =>
      'Winkel A + B dürfen 360 Grad nicht überschreiten.';

  @override
  String get valDistanceAPositiveShort => 'Abstand A muss größer als 0 sein.';

  @override
  String get valDistanceBPositiveShort => 'Abstand B muss größer als 0 sein.';

  @override
  String get valTaperRange =>
      'Die Verjüngung muss zwischen -90 und 90 Grad liegen.';

  @override
  String get lblSelectDirPlaceholder => 'Richtung…';

  @override
  String get lblMirrorPlanePlaceholder => 'Spiegelebene';

  @override
  String get lblCenterlineGeo => 'Mittellinie';

  @override
  String get lblConstructionLineGeo => 'Konstruktionslinie';

  @override
  String get lblLineGeo => 'Linie';

  @override
  String get panelComponent => 'Komponente';

  @override
  String get viewShadedEdges => 'Schattiert + Kanten';

  @override
  String get viewRendered => 'Gerendert';

  @override
  String get viewFloor => 'Boden anzeigen';

  @override
  String get cubeSetFront => 'Aktuelle Ansicht als Vorne';

  @override
  String get cubeSetTop => 'Aktuelle Ansicht als Oben';

  @override
  String get cubeResetFront => 'Vorne zuruecksetzen';

  @override
  String get cubeRollLeft => 'Ansicht nach links drehen';

  @override
  String get cubeRollRight => 'Ansicht nach rechts drehen';

  @override
  String get cubeStep => 'Zur Nachbaransicht';

  @override
  String msgProjectedFace(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Kanten projiziert',
      one: '1 Kante projiziert',
    );
    return '$_temp0';
  }

  @override
  String get sectionNone => 'Kein Schnitt';

  @override
  String get sectionHalf => 'Halbschnitt';

  @override
  String get sectionQuarter => 'Viertelschnitt';

  @override
  String get sectionThreeQuarter => 'Dreiviertelschnitt';

  @override
  String get sectionFlip1 => 'Ebene 1 umkehren';

  @override
  String get sectionFlip2 => 'Ebene 2 umkehren';

  @override
  String get msgPickSectionPlane =>
      'Ebene oder ebene Flaeche zum Schneiden antippen';

  @override
  String get msgPickSectionPlane2 => 'Zweite Ebene antippen';

  @override
  String get panelAppearance => 'Aussehen';

  @override
  String get matPickBody => 'Nichts gewaehlt';

  @override
  String get matSteel => 'Stahl';

  @override
  String get matAluminium => 'Aluminium';

  @override
  String get matGraphite => 'Graphit';

  @override
  String get matBrass => 'Messing';

  @override
  String get matCopper => 'Kupfer';

  @override
  String get matRed => 'Rot';

  @override
  String get matGreen => 'Gruen';

  @override
  String get matBlue => 'Blau';

  @override
  String get matViolet => 'Violett';

  @override
  String get panelPosition => 'Position';

  @override
  String get panelRelationships => 'Beziehungen';

  @override
  String get btnPlace => 'Platzieren';

  @override
  String get btnCreateComponent => 'Erstellen';

  @override
  String get btnFreeMove => 'Frei bewegen';

  @override
  String get btnFreeRotate => 'Frei drehen';

  @override
  String get btnJoint => 'Gelenk';

  @override
  String get btnConstrain => 'Abhängig machen';

  @override
  String get btnShowRelationships => 'Einblenden';

  @override
  String get btnShowSick => 'Fehlerhafte';

  @override
  String get btnHideAll => 'Alle ausblenden';

  @override
  String get btnPatternComponent => 'Anordnung';

  @override
  String get galleryNewAssembly => 'Neue Baugruppe';

  @override
  String get dlgNewAssembly => 'Neue Baugruppe';

  @override
  String get phAssemblyName => 'Baugruppenname';

  @override
  String get nodeRepresentations => 'Darstellungen';

  @override
  String get nodeRelationships => 'Beziehungen';

  @override
  String get dlgPlaceComponent => 'Komponente platzieren';

  @override
  String get msgAsmNoPartsToPlace =>
      'Erstellen Sie zuerst ein 3D-Bauteil — es gibt nichts zu platzieren.';

  @override
  String msgAsmNoSuchPart(String name) {
    return '„$name“ ist kein Bauteil.';
  }

  @override
  String msgAsmCouldNotPlace(String name) {
    return '„$name“ konnte nicht platziert werden.';
  }

  @override
  String msgAsmGrounded(String name) {
    return '„$name“ ist fixiert.';
  }

  @override
  String get ctxGrounded => 'Fixiert';

  @override
  String get dlgPlaceConstraint => 'Abhängigkeit platzieren';

  @override
  String get tabAsmAssembly => 'Baugruppe';

  @override
  String get tabAsmMotion => 'Bewegung';

  @override
  String get tabAsmTransitional => 'Übergang';

  @override
  String get tabAsmConstraintSet => 'Abhängigkeitssatz';

  @override
  String get grpAsmType => 'Typ';

  @override
  String get grpAsmSelections => 'Auswahlen';

  @override
  String get grpAsmSolution => 'Lösung';

  @override
  String get lblAsmOffset => 'Versatz';

  @override
  String get lblAsmAngle => 'Winkel';

  @override
  String get lblAsmRatio => 'Verhältnis';

  @override
  String get lblAsmDistance => 'Abstand';

  @override
  String get cbAsmPickPartFirst => 'Bauteil zuerst wählen';

  @override
  String get cbAsmShowPreview => 'Vorschau anzeigen';

  @override
  String get cbAsmPredict => 'Versatz und Ausrichtung vorhersagen';

  @override
  String get cbAsmDefaultUndirected => 'Standardmäßig ungerichtet';

  @override
  String get lblAsmName => 'Name';

  @override
  String get hintAsmAutoName => 'Automatisch';

  @override
  String tipAsmSelection(int n) {
    return 'Auswahl $n';
  }

  @override
  String get hintAsmPickGeometry => 'Fläche, Kante oder Achse antippen';

  @override
  String get asmMate => 'Passend';

  @override
  String get asmAngle => 'Winkel';

  @override
  String get asmTangent => 'Tangential';

  @override
  String get asmInsert => 'Einfügen';

  @override
  String get asmSymmetry => 'Symmetrie';

  @override
  String get asmRotation => 'Drehung';

  @override
  String get asmRotationTranslation => 'Drehung-Translation';

  @override
  String get asmTransitional => 'Übergang';

  @override
  String get solMate => 'Passend';

  @override
  String get solFlush => 'Ausgerichtet';

  @override
  String get solDirectedAngle => 'Gerichteter Winkel';

  @override
  String get solUndirectedAngle => 'Ungerichteter Winkel';

  @override
  String get solExplicitVector => 'Expliziter Referenzvektor';

  @override
  String get solInside => 'Innen';

  @override
  String get solOutside => 'Außen';

  @override
  String get solOpposed => 'Entgegengesetzt';

  @override
  String get solAligned => 'Ausgerichtet';

  @override
  String get solSymmetric => 'Symmetrisch';

  @override
  String get solAsymmetric => 'Asymmetrisch';

  @override
  String get solForward => 'Vorwärts';

  @override
  String get solReverse => 'Rückwärts';

  @override
  String get ctxSuppress => 'Unterdrücken';

  @override
  String get ctxUnsuppress => 'Unterdrückung aufheben';

  @override
  String hudAsmDof(int n) {
    return '$n Freiheitsgrade';
  }

  @override
  String get hudAsmFullyConstrained => 'Vollständig bestimmt';

  @override
  String get msgAsmSameComponent =>
      'Beide Auswahlen liegen auf derselben Komponente.';

  @override
  String get msgAsmPickTwo => 'Zuerst zwei Geometrien auswählen.';

  @override
  String get msgAsmTangentNeedsRound => 'Tangential braucht eine runde Fläche.';

  @override
  String get msgAsmInsertNeedsAxes =>
      'Einfügen braucht zwei Achsen oder Kreiskanten.';

  @override
  String get msgAsmAngleNeedsDirections => 'Winkel braucht zwei Richtungen.';

  @override
  String get msgAsmMotionNeedsAxes => 'Bewegung braucht zwei Achsen.';

  @override
  String get msgAsmBothGrounded => 'Beide Komponenten sind fixiert.';

  @override
  String get msgAsmMissingComponent =>
      'Die Komponente dieser Abhängigkeit fehlt.';

  @override
  String get msgAsmCannotSatisfy =>
      'Diese Abhängigkeit lässt sich nicht erfüllen.';

  @override
  String get msgAsmCannotConstrain =>
      'Diese Auswahl lässt sich so nicht abhängig machen.';

  @override
  String msgAsmConstraintDeleted(String name) {
    return '„$name“ gelöscht.';
  }

  @override
  String get hintAsmConstraintSet => 'Noch nicht verfügbar';

  @override
  String msgAsmWouldNest(String name) {
    return '„$name“ enthält diese Baugruppe bereits.';
  }

  @override
  String get dlgPlaceJoint => 'Gelenk platzieren';

  @override
  String get grpAsmConnect => 'Verbinden';

  @override
  String get lblAsmGap => 'Abstand';

  @override
  String get jtAutomatic => 'Automatisch';

  @override
  String get jtRigid => 'Starr';

  @override
  String get jtRotational => 'Drehung';

  @override
  String get jtSlider => 'Schieber';

  @override
  String get jtCylindrical => 'Zylindrisch';

  @override
  String get jtPlanar => 'Eben';

  @override
  String get jtBall => 'Kugel';

  @override
  String hintAsmJointAuto(String type) {
    return 'Automatisch: $type';
  }

  @override
  String hintAsmJointDof(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Freiheitsgrade bleiben',
      one: 'Ein Freiheitsgrad bleibt',
      zero: 'Kein Freiheitsgrad bleibt',
    );
    return '$_temp0';
  }

  @override
  String get msgAsmJointNeedsDirections =>
      'Dieses Gelenk braucht zwei Richtungen.';

  @override
  String get hintAsmShowPickComponent =>
      'Komponente wählen, deren Beziehungen eingeblendet werden sollen.';

  @override
  String msgAsmNoRelationships(String name) {
    return '„$name“ hat keine Beziehungen.';
  }

  @override
  String get msgAsmNoSickRelationships => 'Alle Beziehungen sind in Ordnung.';

  @override
  String get dlgDrive => 'Abhängigkeit antreiben';

  @override
  String get ctxDrive => 'Antreiben';

  @override
  String get lblDriveStart => 'Start';

  @override
  String get lblDriveEnd => 'Ende';

  @override
  String get lblDrivePause => 'Pause';

  @override
  String get grpDriveIncrement => 'Schrittweite';

  @override
  String get optDriveAmount => 'Wert';

  @override
  String get optDriveSteps => 'Anzahl Schritte';

  @override
  String get grpDriveRepetitions => 'Wiederholungen';

  @override
  String get optDriveOnce => 'Start/Ende';

  @override
  String get optDriveBoth => 'Start/Ende/Start';

  @override
  String get lblDriveCycles => 'Zyklen';

  @override
  String get cbDriveAdaptivity => 'Adaptivität antreiben';

  @override
  String get cbDriveCollision => 'Kollisionserkennung';

  @override
  String get hintDriveUnavailable => 'In dieser App nicht verfügbar.';

  @override
  String get msgAsmCannotDrive => 'Diese Beziehung lässt sich nicht antreiben.';

  @override
  String get tipDrivePlay => 'Abspielen';

  @override
  String get tipDriveReverse => 'Rückwärts';

  @override
  String get tipDrivePause => 'Anhalten';

  @override
  String get tipDriveToStart => 'Zum Anfang';

  @override
  String get tipDriveToEnd => 'Zum Ende';

  @override
  String get hintAsmFreeMove =>
      'Komponente ziehen — Beziehungen werden dabei übergangen.';

  @override
  String get hintAsmFreeRotate => 'Komponente wählen und am Drehsymbol ziehen.';

  @override
  String msgAsmFreePositioned(String name) {
    return '„$name“ steht außerhalb seiner Beziehungen — die nächste Aktualisierung setzt es zurück.';
  }

  @override
  String msgNameTaken(String name) {
    return 'Ein Dokument namens „$name“ existiert bereits.';
  }

  @override
  String get hintAsmCreatePickPlane =>
      'Ebene oder planare Fläche zum Skizzieren wählen.';

  @override
  String msgAsmEditSubInPlace(String name) {
    return '„$name“ ist eine Unterbaugruppe — nicht vor Ort editierbar.';
  }

  @override
  String msgAsmViewRepLocked(String name) {
    return '„$name“ ist gesperrt.';
  }

  @override
  String get nodeViewReps => 'Ansicht';

  @override
  String get nodePositionalReps => 'Position';

  @override
  String get nodeLodReps => 'Detailgenauigkeit';

  @override
  String get ctxNewViewRep => 'Neue Darstellung';

  @override
  String get ctxActivateViewRep => 'Aktivieren';

  @override
  String get ctxUpdateViewRep => 'Aktualisieren';

  @override
  String get ctxLockViewRep => 'Sperren';

  @override
  String get ctxUnlockViewRep => 'Entsperren';

  @override
  String get ctxDeleteViewRep => 'Darstellung löschen';

  @override
  String get dlgRenameViewRep => 'Darstellung umbenennen';

  @override
  String get phViewRepName => 'Name der Darstellung';

  @override
  String get dlgCreateComponent => 'Komponente vor Ort erstellen';

  @override
  String get lblComponentName => 'Name der neuen Komponente';

  @override
  String get chkConstrainSketchPlane =>
      'Skizzenebene an gewählte Fläche binden';

  @override
  String get btnReturn => 'Zurück';

  @override
  String get panelReturn => 'Beenden';

  @override
  String hintInPlaceEditing(String part, String assembly) {
    return '„$part“ wird in „$assembly“ bearbeitet.';
  }

  @override
  String get ctxEditInPlace => 'Vor Ort bearbeiten';

  @override
  String get ctxMakePart => 'Bauteil erstellen';

  @override
  String get dlgMakePart => 'Bauteil erstellen';

  @override
  String get lblNewPartName => 'Name des neuen Bauteils';

  @override
  String get lblTargetAssembly => 'Zielbaugruppe';

  @override
  String hintMakePartLink(String name) {
    return 'Bleibt mit „$name“ verknüpft.';
  }

  @override
  String msgMadePart(String part, String origin) {
    return '„$part“ aus „$origin“ erstellt und damit verknüpft.';
  }

  @override
  String msgMakePartNoBody(String name) {
    return '„$name“ ist nicht mehr gebaut.';
  }

  @override
  String msgDerivedEditOrigin(String name) {
    return 'Abgeleiteter Körper — „$name“ wird geöffnet.';
  }

  @override
  String get cyclesBadge => 'Cycles';

  @override
  String get rendererRealtime => 'Echtzeit (RealityKit)';

  @override
  String get rendererRaytraced => 'Raytracing (Cycles)';

  @override
  String get cyclesPreparing => 'Cycles · Kernel werden übersetzt';

  @override
  String cyclesSamples(int samples) {
    return 'Cycles · $samples spp';
  }

  @override
  String get cyclesFailed => 'Cycles fehlgeschlagen';

  @override
  String get cyclesWarmupTitle => 'Renderer wird vorbereitet';

  @override
  String get cyclesWarmupOnce => 'Das geschieht einmal pro Installation.';

  @override
  String get cyclesWarmupFailed => 'Der Renderer konnte nicht gestartet werden';

  @override
  String get lblEndRadius => 'Endradius';

  @override
  String lblProfileCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Profile',
      one: 'Ein Profil',
    );
    return '$_temp0';
  }

  @override
  String lblSectionCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Querschnitte',
      one: 'Ein Querschnitt',
    );
    return '$_temp0';
  }

  @override
  String lblPointsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Punkte',
      one: 'Ein Punkt',
    );
    return '$_temp0';
  }

  @override
  String get hintTapToFinish => '· zum Beenden tippen';

  @override
  String get hintTerminationNeedsBody =>
      'Bis zum Nächsten, Bis und Durch alle brauchen einen vorhandenen Körper.';

  @override
  String lblFeatureCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Elemente',
      one: 'Ein Element',
    );
    return '$_temp0';
  }

  @override
  String lblSelectedCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n gewählt',
      one: '1 gewählt',
      zero: 'nichts gewählt',
    );
    return '$_temp0';
  }

  @override
  String get lblTotalDistance => 'Gesamtabstand';

  @override
  String get hintEndRadiusOptional =>
      'Endradius leer lassen für eine konstante Verrundung; mit einem Wert läuft der Radius entlang jeder Kante der Gruppe.';

  @override
  String a11yClearNamed(String name) {
    return '$name löschen';
  }

  @override
  String a11yRemoveNamed(String name) {
    return '$name entfernen';
  }

  @override
  String get btnCut => 'Ausschneiden';

  @override
  String get btnPaste => 'Einfügen';

  @override
  String get ctxPasteHere => 'Hier einfügen';

  @override
  String get ctxPasteSketchHere => 'Skizze hier einfügen';

  @override
  String get ctxPartFromSketch => 'Bauteil aus Skizze';

  @override
  String get ctxSketchToDocument => 'Als 2D-Skizze speichern';

  @override
  String get msgSelectThenCopy => 'Erst etwas auswählen, dann kopieren.';

  @override
  String get msgSelectBodyToCopy => 'Volumenkörper zum Kopieren wählen.';

  @override
  String msgCopiedEntities(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Objekte kopiert',
      one: '1 Objekt kopiert',
    );
    return '$_temp0';
  }

  @override
  String msgCutEntities(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Objekte ausgeschnitten',
      one: '1 Objekt ausgeschnitten',
    );
    return '$_temp0';
  }

  @override
  String msgCopiedSketch(String name) {
    return 'Skizze „$name“ kopiert.';
  }

  @override
  String msgCutSketch(String name) {
    return 'Skizze „$name“ ausgeschnitten.';
  }

  @override
  String msgCopiedBody(String name) {
    return 'Volumenkörper „$name“ kopiert.';
  }

  @override
  String msgCutBody(String name) {
    return 'Volumenkörper „$name“ ausgeschnitten.';
  }

  @override
  String msgCopiedComponent(String name) {
    return 'Komponente „$name“ kopiert.';
  }

  @override
  String msgCutComponent(String name) {
    return 'Komponente „$name“ ausgeschnitten.';
  }

  @override
  String msgCopiedDocument(String name) {
    return 'Dokument „$name“ kopiert.';
  }

  @override
  String msgCopyBodyFailed(String reason) {
    return 'Der Volumenkörper konnte nicht kopiert werden: $reason';
  }

  @override
  String msgNoSuchBody(String name) {
    return '„$name“ gibt es in diesem Bauteil nicht.';
  }

  @override
  String get msgClipboardEmpty => 'Die Zwischenablage ist leer.';

  @override
  String get msgClipboardBodyGone =>
      'Der kopierte Volumenkörper ist nicht mehr da — bitte neu kopieren.';

  @override
  String msgPastedEntities(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Objekte eingefügt',
      one: '1 Objekt eingefügt',
    );
    return '$_temp0';
  }

  @override
  String msgPastedSketchOnPlane(String name) {
    return 'Skizze „$name“ eingefügt.';
  }

  @override
  String msgPastedSketchDocument(String name) {
    return '2D-Skizze „$name“ angelegt.';
  }

  @override
  String msgPastedBody(String name) {
    return '„$name“ als neuer Volumenkörper eingefügt.';
  }

  @override
  String msgPastedBodyAsComponent(String name) {
    return '„$name“ angelegt und in der Baugruppe platziert.';
  }

  @override
  String msgPastedComponent(String name) {
    return '„$name“ eingefügt.';
  }

  @override
  String msgPastedDocument(String name) {
    return '„$name“ eingefügt.';
  }

  @override
  String msgPastedDerived(String name) {
    return 'Abgeleiteter Volumenkörper aus „$name“ — mit dem Ursprung verknüpft.';
  }

  @override
  String msgPasteBodyFailed(String reason) {
    return 'Der Volumenkörper konnte nicht eingefügt werden: $reason';
  }

  @override
  String get msgPasteBodyNotSaved =>
      'Der eingefügte Volumenkörper konnte nicht im Dokument abgelegt werden.';

  @override
  String get msgPasteComponentNeedsAssembly =>
      'Eine Komponente gehört in eine Baugruppe — dort einfügen.';

  @override
  String get msgAssemblyTakesNoSketch =>
      'Eine Baugruppe nimmt Komponenten auf, keine Skizzen.';

  @override
  String get msgCannotPasteHere => 'Das lässt sich hier nicht einfügen.';

  @override
  String get msgCannotDeriveFromItself =>
      'Ein Bauteil kann sich nicht selbst ableiten.';

  @override
  String msgNoBodyIn(String name) {
    return '„$name“ hat keinen Volumenkörper zum Ableiten.';
  }

  @override
  String msgNoSuchDocument(String name) {
    return '„$name“ gibt es nicht mehr.';
  }

  @override
  String get msgSelectPlaneForPaste =>
      'Ebene oder Fläche antippen, auf der die eingefügte Skizze liegen soll.';

  @override
  String msgPasteDroppedExpressions(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$n Formeln wurden nicht übernommen — ihre Parameter kamen nicht mit.',
      one: 'Eine Formel wurde nicht übernommen — ihr Parameter kam nicht mit.',
    );
    return '$_temp0';
  }

  @override
  String msgPartFromSketch(String part, String sketch) {
    return 'Bauteil „$part“ aus Skizze „$sketch“ erstellt.';
  }

  @override
  String msgNotASketch(String name) {
    return '„$name“ ist keine 2D-Skizze.';
  }

  @override
  String get msgFinishSketchToPaste =>
      'Zuerst die Skizze beenden — ein Volumenkörper gehört ins Bauteil, nicht in die Skizze.';
}
