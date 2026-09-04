// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get languageName => 'English';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsButton => 'Settings';

  @override
  String get settingsDone => 'Done';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceFooter =>
      '“System” follows your iPad’s setting.';

  @override
  String get bugAutofix => 'Let the automation fix it';

  @override
  String get bugAutofixOn => 'The report goes straight to the fix automation.';

  @override
  String get bugAutofixOff =>
      'The report waits for a session you start yourself.';

  @override
  String get settingsAccent => 'Accent colour';

  @override
  String get settingsAccentFooter =>
      '“Scheme” uses the colour of the chosen appearance. Every colour here is checked for legibility.';

  @override
  String get accentScheme => 'Scheme';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentMagenta => 'Magenta';

  @override
  String get accentAmber => 'Amber';

  @override
  String get accentGreen => 'Green';

  @override
  String get accentRed => 'Red';

  @override
  String get settingsBackdrop => 'Backdrop';

  @override
  String get settingsBackdropFooter =>
      'The gallery only. A picture is veiled so cards stay readable.';

  @override
  String get backdropAuto => 'Match Appearance';

  @override
  String get backdropInk => 'Ink';

  @override
  String get backdropSlate => 'Slate';

  @override
  String get backdropForest => 'Forest';

  @override
  String get backdropSand => 'Sand';

  @override
  String get backdropLinen => 'Linen';

  @override
  String get backdropImage => 'Custom Picture';

  @override
  String get backdropChooseImage => 'Choose a Picture …';

  @override
  String get backdropRemoveImage => 'Remove Picture';

  @override
  String get backdropImageFailed => 'That picture could not be used.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsRibbon => 'Ribbon';

  @override
  String get ribbonTop => 'Top';

  @override
  String get ribbonBottom => 'Bottom';

  @override
  String get ribbonLeft => 'Left';

  @override
  String get ribbonRight => 'Right';

  @override
  String get settingsSync => 'Sharing';

  @override
  String get settingsShareCode => 'Share Code';

  @override
  String get settingsShareCodeSet => 'Enter a Share Code';

  @override
  String get settingsNewShareCode => 'Create a Share Code';

  @override
  String get settingsStopSharing => 'Stop Sharing';

  @override
  String get settingsSyncStatus => 'Devices';

  @override
  String get settingsSyncLooking => 'Looking…';

  @override
  String settingsSyncDevices(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n devices',
      one: '1 device',
      zero: 'Looking…',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncFooter =>
      'Devices on the same network that use the same code keep the same documents and settings. Nothing leaves your network and there is no account. The connection is not encrypted, so use it on a network you trust. Sharing never deletes: a document on any device ends up on all of them.';

  @override
  String get syncPromptTitle => 'Share Code';

  @override
  String get syncPromptBody =>
      'Type the code from your other device, or create one there and type it here.';

  @override
  String get syncPromptPlaceholder => 'ABCD-EFGH-JKLM';

  @override
  String get syncPromptJoin => 'Share';

  @override
  String get syncBadCode =>
      'That is not a share code. It is twelve letters and digits, in three groups.';

  @override
  String get syncStopTitle => 'Stop sharing on this device?';

  @override
  String get syncStopBody =>
      'This device keeps the documents it has and stops sending and receiving. The other devices are not affected.';

  @override
  String get syncCodeCopied => 'Share code copied.';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsReportProblem => 'Report a Problem';

  @override
  String get settingsShareLog => 'Share the Log';

  @override
  String get settingsDiagnosticsFooter =>
      'A report includes the open document and this session’s log.';

  @override
  String get settingsIconPreview => 'Icon Preview';

  @override
  String get iconPreviewHelp =>
      'Run tools/icon-sync/serve.py on the PC you draw on, then type the address it prints. Leave empty to use the built-in icons.';

  @override
  String get iconPreviewTurnOff => 'Turn off';

  @override
  String get iconPreviewConnect => 'Connect';

  @override
  String get iconPreviewIdle => 'Off — showing the built-in icons.';

  @override
  String iconPreviewUnreachable(String host, String error) {
    return 'Cannot reach $host\n$error';
  }

  @override
  String iconPreviewLive(int count, String host) {
    return '$count icon(s) live from $host';
  }

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsBuild => 'Version';

  @override
  String get settingsKernel3d => '3D Kernel';

  @override
  String get settingsKernel2d => '2D Kernel';

  @override
  String get settingsSystem => 'System';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get done => 'Done';

  @override
  String get apply => 'Apply';

  @override
  String get close => 'Close';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get create => 'Create';

  @override
  String get select => 'Select';

  @override
  String get finish => 'Finish';

  @override
  String get discard => 'Discard';

  @override
  String get edit => 'Edit';

  @override
  String get hide => 'Hide';

  @override
  String get openEllipsis => 'Open…';

  @override
  String get exportEllipsis => 'Export…';

  @override
  String get shareEllipsis => 'Share…';

  @override
  String get dlgOpenTitle => 'Open';

  @override
  String get dlgSaveCopyTitle => 'Save a copy';

  @override
  String get filterOpenableDocuments => 'Documents this app can open';

  @override
  String get filterAllFiles => 'All files';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get panelSketch => 'Sketch';

  @override
  String get panelCreate => 'Create';

  @override
  String get panelModify => 'Modify';

  @override
  String get panelWorkFeatures => 'Work Features';

  @override
  String get panelPattern => 'Pattern';

  @override
  String get panelLayer => 'Layer';

  @override
  String get panelConstrain => 'Constrain';

  @override
  String get panelInsert => 'Insert';

  @override
  String get panelView => 'View';

  @override
  String get panelExit => 'Exit';

  @override
  String get panelProjectGeometry => 'Project Geometry';

  @override
  String get btnCreateNewSketch => 'Create\nNew Sketch';

  @override
  String get btnStart2dSketch => 'Start\n2D Sketch';

  @override
  String get btnStartNewLayer => 'Start\nNew Layer';

  @override
  String get btnExtrude => 'Extrude';

  @override
  String get btnRevolve => 'Revolve';

  @override
  String get btnSweep => 'Sweep';

  @override
  String get btnLoft => 'Loft';

  @override
  String get btnCoil => 'Coil';

  @override
  String get btnEmboss => 'Emboss';

  @override
  String get btnDerive => 'Derive';

  @override
  String get btnDecal => 'Decal';

  @override
  String get btnFillet => 'Fillet';

  @override
  String get btnChamfer => 'Chamfer';

  @override
  String get btnShell => 'Shell';

  @override
  String get btnDraft => 'Draft';

  @override
  String get btnThread => 'Thread';

  @override
  String get btnHole => 'Hole';

  @override
  String get btnSplit => 'Split';

  @override
  String get btnCombine => 'Combine';

  @override
  String get btnPlane => 'Plane';

  @override
  String get btnAxis => 'Axis';

  @override
  String get btnPoint => 'Point';

  @override
  String get btnLine => 'Line';

  @override
  String get btnCircle => 'Circle';

  @override
  String get btnArc => 'Arc';

  @override
  String get btnRectangle => 'Rectangle';

  @override
  String get btnText => 'Text';

  @override
  String get btnDimension => 'Dimension';

  @override
  String get btnRectangular => 'Rectangular';

  @override
  String get btnCircular => 'Circular';

  @override
  String get btnMirror => 'Mirror';

  @override
  String get btnImage => 'Image';

  @override
  String get btnAcad => 'ACAD';

  @override
  String get btnConstruction => 'Construction';

  @override
  String get btnParameters => 'Parameters';

  @override
  String get btnGear => 'Gear';

  @override
  String get btnProjectGeometry => 'Project\nGeometry';

  @override
  String get btnSliceGraphics => 'Slice\nGraphics';

  @override
  String get btnTrim => 'Trim';

  @override
  String get btnSelfSymmetric => 'Self Symmetric';

  @override
  String get btnAssociative => 'Associative';

  @override
  String get btnFitted => 'Fitted';

  @override
  String get flyLineB => 'Line';

  @override
  String get flyLineSub => 'Line';

  @override
  String get flyMidlineSub => 'Midpoint Line';

  @override
  String get flySplineB => 'Spline';

  @override
  String get flySplineCvSub => 'Control Vertex';

  @override
  String get flySplineInterpSub => 'Interpolation';

  @override
  String get flySplineFreeSub => 'Freehand';

  @override
  String get flyEqCurveB => 'Equation Curve';

  @override
  String get flyBridgeB => 'Bridge Curve';

  @override
  String get flyCircleB => 'Circle';

  @override
  String get flyCenterPointSub => 'Center Point';

  @override
  String get flyTangentSub => 'Tangent';

  @override
  String get flyEllipseB => 'Ellipse';

  @override
  String get flyArcB => 'Arc';

  @override
  String get flyThreePointSub => 'Three Point';

  @override
  String get flyRectB => 'Rectangle';

  @override
  String get flyTwoPointSub => 'Two Point';

  @override
  String get flyTwoPointCenterSub => 'Two Point Center';

  @override
  String get flyThreePointCenterSub => 'Three Point Center';

  @override
  String get flySlotB => 'Slot';

  @override
  String get flySlotCcSub => 'Center to Center';

  @override
  String get flySlotOverallSub => 'Overall';

  @override
  String get flySlot3aSub => 'Three Point Arc';

  @override
  String get flySlotCpaSub => 'Center Point Arc';

  @override
  String get flyPolygonB => 'Polygon';

  @override
  String get flyFilletB => 'Fillet';

  @override
  String get flyChamferB => 'Chamfer';

  @override
  String get flyTextB => 'Text';

  @override
  String get flyGeomTextB => 'Geometry Text';

  @override
  String get flyMoveB => 'Move';

  @override
  String get flySizeB => 'Size';

  @override
  String get flyScaleB => 'Scale';

  @override
  String get flyRotateB => 'Rotate';

  @override
  String get flyDeleteB => 'Delete';

  @override
  String get flyAxisB => 'Axis';

  @override
  String get flyAxisOnLineB => 'On Line or Edge';

  @override
  String get flyAxisParPtB => 'Parallel to Line through Point';

  @override
  String get flyAxisTwoPtB => 'Through Two Points';

  @override
  String get flyAxisTwoPlB => 'Intersection of Two Planes';

  @override
  String get flyAxisNormPtB => 'Normal to Plane through Point';

  @override
  String get flyAxisCircB => 'Through Center of Circular Edge';

  @override
  String get flyAxisRevB => 'Through Revolved Face or Feature';

  @override
  String get flyPointB => 'Point';

  @override
  String get flyPointGroundB => 'Grounded Point';

  @override
  String get flyPointVertexB => 'On Vertex, Sketch Point, or Midpoint';

  @override
  String get flyPointThreePlB => 'Intersection of Three Planes';

  @override
  String get flyPointTwoLnB => 'Intersection of Two Lines';

  @override
  String get flyPointPlLnB => 'Intersection of Plane/Surface and Line';

  @override
  String get flyPointLoopB => 'Center Point of Loop of Edges';

  @override
  String get flyPointTorusB => 'Center Point of Torus';

  @override
  String get flyPointSphereB => 'Center Point of Sphere';

  @override
  String get flyPlaneB => 'Plane';

  @override
  String get flyPlaneOffsetB => 'Offset from Plane';

  @override
  String get flyPlaneParallelPtB => 'Parallel to Plane through Point';

  @override
  String get flyPlaneMid2B => 'Midplane between Two Planes';

  @override
  String get flyPlaneMidTorusB => 'Midplane of Torus';

  @override
  String get flyPlaneAngleEdgeB => 'Angle to Plane around Edge';

  @override
  String get flyPlaneThreePtsB => 'Three Points';

  @override
  String get flyPlaneTwoEdgesB => 'Two Coplanar Edges';

  @override
  String get flyPlaneTanSurfEdgeB => 'Tangent to Surface through Edge';

  @override
  String get flyPlaneTanSurfPtB => 'Tangent to Surface through Point';

  @override
  String get flyPlaneTanParallelB => 'Tangent to Surface and Parallel to Plane';

  @override
  String get flyPlaneNormalAxisB => 'Normal to Axis through Point';

  @override
  String get flyPlaneNormalCurveB => 'Normal to Curve at Point';

  @override
  String get browserTitle => 'Model';

  @override
  String get nodeOrigin => 'Origin';

  @override
  String get nodeXAxis => 'X Axis';

  @override
  String get nodeYAxis => 'Y Axis';

  @override
  String get nodeCenterPoint => 'Center Point';

  @override
  String get nodeEndOfPart => 'End of Part';

  @override
  String get nodeEndOfSketch => 'End of Sketch';

  @override
  String nodeSolidBodies(int count) {
    return 'Solid Bodies($count)';
  }

  @override
  String nodeOccurrence(int index) {
    return 'Occurrence $index';
  }

  @override
  String get nodeAutoProjected => 'Automatically projected';

  @override
  String get ctxUseAsTargetBody => 'Use as Target Body';

  @override
  String get ctxDeleteBody => 'Delete Body';

  @override
  String get ctxEditSketch => 'Edit Sketch';

  @override
  String get ctxShareSketch => 'Share Sketch';

  @override
  String get ctxUnshare => 'Unshare';

  @override
  String get ctxEditFeature => 'Edit Feature';

  @override
  String get ctxMoveEosHere => 'Move End of Sketch here';

  @override
  String get ctxDeleteLayer => 'Delete layer';

  @override
  String get ctxMoveToTop => 'Move to Top';

  @override
  String get ctxMoveToEnd => 'Move to End';

  @override
  String get ctxDeleteAllLayersBelow => 'Delete all layers below';

  @override
  String get ctxDeleteAllFeaturesBelow => 'Delete all features below';

  @override
  String get ctxDeleteAllFeaturesBelowEop => 'Delete All Features Below EOP';

  @override
  String get ctxCreateSketch => 'Create Sketch';

  @override
  String get ctxEditOffset => 'Edit Offset';

  @override
  String get ctxFlipDirection => 'Flip Direction';

  @override
  String get ctxEditLayer => 'Edit Layer';

  @override
  String get ctxMoveSelectionHere => 'Move Selection Here';

  @override
  String get ctxExportDxf => 'Export DXF…';

  @override
  String get ctxShareDxf => 'Share DXF…';

  @override
  String get dlgRenameBody => 'Rename body';

  @override
  String get dlgRenameFeature => 'Rename feature';

  @override
  String get dlgRenameLayer => 'Rename layer';

  @override
  String get dlgRenameSketch => 'Rename sketch';

  @override
  String get phBodyName => 'Body name';

  @override
  String get phFeatureName => 'Feature name';

  @override
  String get phLayerName => 'Layer name';

  @override
  String get phSketchName => 'Sketch name';

  @override
  String get phPartName => 'Part name';

  @override
  String get dlgNewSketch => 'New sketch';

  @override
  String get dlgNewPart => 'New part';

  @override
  String get dlgDeleteAllFeaturesBelowEop => 'Delete all features below EOP?';

  @override
  String get dlgDeleteEverythingBelowEos =>
      'Delete everything below End of Sketch?';

  @override
  String dlgDeleteNamed(String name) {
    return 'Delete “$name”?';
  }

  @override
  String msgFeaturesRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count features are removed from the part.',
      one: 'One feature is removed from the part.',
    );
    return '$_temp0';
  }

  @override
  String msgBodyFeaturesRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count features are removed from the part.',
      one: 'Its one feature is removed from the part.',
    );
    return '$_temp0';
  }

  @override
  String msgLayersAndEntitiesRemoved(int layers, int entities) {
    String _temp0 = intl.Intl.pluralLogic(
      layers,
      locale: localeName,
      other: '$layers layers are removed',
      one: 'One layer is removed',
    );
    String _temp1 = intl.Intl.pluralLogic(
      entities,
      locale: localeName,
      other: 'with $entities entities on it.',
      one: 'with one entity on it.',
      zero: 'with nothing on it.',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get msgFeatureAndSolidRemoved =>
      'The feature and its solid are removed from the part.';

  @override
  String get msgSketchDeleted =>
      'The sketch and everything in it are removed from this iPad. This can’t be undone.';

  @override
  String get galleryNew2dSketch => 'New 2D Sketch';

  @override
  String get galleryNew3dPart => 'New 3D Part';

  @override
  String get galleryEmpty => 'Tap  +  to create a new sketch or part';

  @override
  String get errNameTaken => 'A sketch or part with that name already exists';

  @override
  String get qtReportBug => 'Report a bug';

  @override
  String get hudOverConstrained => 'Over-constrained';

  @override
  String get hudDriven => 'Driven';

  @override
  String get msgWouldOverConstrain =>
      'Adding this dimension will over-constrain the sketch. Keep it as a driven (reference) dimension?';

  @override
  String get menuHomeView => 'Home view';

  @override
  String msgCouldNotSave(String name) {
    return 'Could not save “$name”.';
  }

  @override
  String msgSavedTo(String folder) {
    return 'Saved to $folder';
  }

  @override
  String msgSavedNamed(String name) {
    return 'Saved “$name”';
  }

  @override
  String get msgCannotOpenKind => 'Prototype cannot open that kind of file.';

  @override
  String get msgNotAPrototypeDoc =>
      'That file is not a Prototype document (or is damaged).';

  @override
  String get msgCouldNotOpenDoc => 'Could not open that document.';

  @override
  String get msgCouldNotOpenFile => 'Could not open that file.';

  @override
  String get msgCouldNotImportFile => 'Could not import that file.';

  @override
  String get msgCouldNotImportImage => 'Could not import the image.';

  @override
  String get msgCouldNotImportDxf => 'Could not import the DXF file.';

  @override
  String get msgCouldNotReadDxf => 'Could not read the DXF file.';

  @override
  String get msgDxfNoSupportedEntities =>
      'The DXF file contains no supported entities.';

  @override
  String msgLayerBelowEos(String layer) {
    return '“$layer” is below End of Sketch — drag the marker down to bring it back.';
  }

  @override
  String msgLayerLockedEdit(String layer) {
    return '“$layer” is locked — unlock it to edit.';
  }

  @override
  String msgLayerLocked(String layer) {
    return '“$layer” is locked.';
  }

  @override
  String msgTargetBelowEos(String layer) {
    return '“$layer” is below End of Sketch.';
  }

  @override
  String get msgDefaultLayerNoRename =>
      'The default layer “0” can’t be renamed.';

  @override
  String get msgZeroReserved => '“0” is reserved for the default layer.';

  @override
  String msgLayerExists(String name) {
    return 'A layer named “$name” already exists.';
  }

  @override
  String get msgDefaultLayerNoDelete =>
      'The default layer “0” can’t be deleted.';

  @override
  String get msgEnterLayerToEdit =>
      'Enter a layer to edit: double-tap it in the model browser.';

  @override
  String get msgEnterLayerToSketch =>
      'Enter a layer to sketch: double-tap it in the model browser.';

  @override
  String get msgSelectThenDelete => 'Select geometry first, then delete it.';

  @override
  String get msgSelectThenMoveToLayer =>
      'Select geometry first, then move it to a layer.';

  @override
  String msgSelectThenToggle(String what) {
    return 'Select geometry first, then toggle $what.';
  }

  @override
  String get msgNothingBelowEos => 'Nothing below End of Sketch.';

  @override
  String get msgNothingBelowEop => 'Nothing below End of Part.';

  @override
  String get msgNoKernelStep =>
      'No 3D kernel linked — STEP export needs the device build.';

  @override
  String get msgNothingToExportYet =>
      'Nothing to export yet — extrude a profile first.';

  @override
  String msgStepExportFailed(String error) {
    return 'STEP export failed: $error';
  }

  @override
  String get msgStepExportEmpty => 'STEP export produced an empty file.';

  @override
  String msgExportedWithout(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exported without $names — they could not be built.',
      one: 'Exported without $names — it could not be built.',
    );
    return '$_temp0';
  }

  @override
  String msgNothingToExportEmpty(String name) {
    return 'Nothing to export — “$name” is empty.';
  }

  @override
  String get msgDxfExportFailed => 'DXF export failed.';

  @override
  String get msgOpenPartForStep =>
      'Open a part first — STEP imports arrive as solid bodies.';

  @override
  String msgNoSolidsInStep(String error) {
    return 'No solids in that STEP file ($error).';
  }

  @override
  String msgImportedBodies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count bodies.',
      one: 'Imported one body.',
    );
    return '$_temp0';
  }

  @override
  String get msgOpenPartForMesh =>
      'Open a part first — a mesh arrives as a solid body.';

  @override
  String get msgNoKernelMesh =>
      'No 3D kernel linked — converting a mesh needs the device build.';

  @override
  String get msgMeshEmpty => 'That file is empty.';

  @override
  String get msgMeshMissing => 'That file no longer exists.';

  @override
  String get msgMeshUnreadable => 'That file could not be read.';

  @override
  String get msgMeshConvertTitle => 'Converting mesh';

  @override
  String get msgMeshBuildTitle => 'Building the triangles';

  @override
  String msgMeshBuilding(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString triangles',
      one: 'One triangle',
    );
    return '$_temp0';
  }

  @override
  String get askMeshImportTitle => 'How should this model be imported?';

  @override
  String askMeshImportBody(int count, String size) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString triangles',
      one: 'One triangle',
    );
    return '$_temp0, $size mm across.';
  }

  @override
  String get askMeshImportConvert => 'As a CAD body';

  @override
  String get askMeshImportConvertWhy =>
      'Surfaces you can fillet, dimension and edit. Takes a moment.';

  @override
  String get askMeshImportFaceted => 'As a mesh';

  @override
  String get askMeshImportFacetedWhy =>
      'Exactly like the file, unconverted. Barely editable.';

  @override
  String askMeshImportTooManyFaceted(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Too many triangles for “As a mesh” (limit $limitString).';
  }

  @override
  String get meshStageReading => 'Reading the model';

  @override
  String get meshStageFinding => 'Finding surfaces';

  @override
  String get meshStageFitting => 'Fitting surfaces';

  @override
  String get meshStageShaping => 'Shaping curves';

  @override
  String get meshStageBuilding => 'Building faces';

  @override
  String get meshStageFinishing => 'Finishing';

  @override
  String get meshStageSimplifying => 'Simplifying';

  @override
  String get actionCancelling => 'Cancelling…';

  @override
  String get msgMeshImportCancelled => 'Import cancelled.';

  @override
  String get msgMeshNoGeometry => 'That file contains no usable geometry.';

  @override
  String get msgMeshTruncated =>
      'That file is damaged — a record stops part-way through.';

  @override
  String msgMeshBadIndex(String index) {
    return 'That file is damaged — a face names vertex $index, which is not in it.';
  }

  @override
  String get msgMeshNotAnArchive => 'That 3MF file is not a readable archive.';

  @override
  String get msgMeshNoModel => 'That 3MF file has no model inside it.';

  @override
  String msgMeshUnknownUnit(String unit) {
    return 'That 3MF file uses an unknown unit (“$unit”).';
  }

  @override
  String msgMeshNotWatertight(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'That mesh is not watertight ($count open edges), so it cannot become a solid.',
      one:
          'That mesh is not watertight (one open edge), so it cannot become a solid.',
    );
    return '$_temp0';
  }

  @override
  String get msgMeshConvertFailed => 'Could not convert that mesh.';

  @override
  String msgMeshConvertFailedWhy(String error) {
    return 'Could not convert that mesh: $error';
  }

  @override
  String get msgMeshNotSaved =>
      'The mesh converted, but the result could not be saved.';

  @override
  String msgMeshImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported: $count surfaces recognised.',
      one: 'Imported: one surface recognised.',
    );
    return '$_temp0';
  }

  @override
  String msgMeshImportedFacetedOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported as $count faces — no surface shape recognised.',
      one: 'Imported as one face — no surface shape recognised.',
    );
    return '$_temp0';
  }

  @override
  String msgMeshImportedFaceted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count areas stayed as triangles.',
      one: 'One area stayed as triangles.',
    );
    return '$_temp0';
  }

  @override
  String get msgMeshImportedOpen => 'Not closed — this is a surface body.';

  @override
  String msgMeshFileTooLarge(int size, int limit) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String sizeString = sizeNumberFormat.format(size);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'That file is $sizeString MB; Prototype reads meshes up to $limitString MB.';
  }

  @override
  String msgMeshTooManyTriangles(int count, int limit) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'That mesh has $countString triangles; Prototype converts up to $limitString.';
  }

  @override
  String msgMeshConverting(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Converting $countString triangles…';
  }

  @override
  String msgImportedEntities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count entities.',
      one: 'Imported one entity.',
    );
    return '$_temp0';
  }

  @override
  String get msgNothingToUndo => 'Nothing to undo.';

  @override
  String get msgNothingToRedo => 'Nothing to redo.';

  @override
  String get msgSelectPlaneForSketch =>
      'Select a plane to create the sketch on.';

  @override
  String msgUsedByFeature(String name) {
    return '$name is used by a feature — delete that first.';
  }

  @override
  String get msgSelectPlaneToOffsetFrom =>
      'Select a plane or face to offset from.';

  @override
  String get msgSelectFirstParallel =>
      'Select the first of two parallel planes or faces.';

  @override
  String get msgSelectSecondParallel =>
      'Select the second parallel plane or face.';

  @override
  String get msgNotParallel =>
      'Those two are not parallel — pick a parallel plane or face.';

  @override
  String msgPlaneHasNoOffset(String name) {
    return '$name: this plane has no offset to drag.';
  }

  @override
  String get msgDragAwayToSetOffset =>
      'Drag away from the plane to set the offset.';

  @override
  String msgNameColonDef(String name, String definition) {
    return '$name: $definition';
  }

  @override
  String msgFaceEditNeedsBody(String command) {
    return '$command needs a solid body first.';
  }

  @override
  String get msgSetScaleThenApply => 'Set the scale factor, then apply.';

  @override
  String msgSelectFacesTo(String verb) {
    return 'Select the faces to $verb.';
  }

  @override
  String get msgSelectAtLeastOneFace => 'Select at least one face.';

  @override
  String get msgNothingToEditBuildBody =>
      'Nothing to edit — build a body first.';

  @override
  String msgFeatureError(String name, String error) {
    return '$name: $error';
  }

  @override
  String msgLostFaces(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name: $count selected faces no longer exist.',
      one: '$name: one selected face no longer exists.',
    );
    return '$_temp0';
  }

  @override
  String get msgCannotCreateFeature => 'Cannot create the feature.';

  @override
  String get msgNoKernelFeatureStored =>
      'No 3D kernel linked — feature stored, solid pending.';

  @override
  String get msgHoleNeedsSketch =>
      'A hole is placed on sketch points — create a sketch first.';

  @override
  String get msgHoleNeedsBody => 'A hole needs a body to drill into.';

  @override
  String get msgTapSketchPointsForHoles =>
      'Tap the sketch points the holes go on.';

  @override
  String msgHoleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holes — tap a point to add or remove one.',
      one: 'One hole — tap a point to add or remove one.',
    );
    return '$_temp0';
  }

  @override
  String get msgHolesSameSketch =>
      'All holes of one feature come from the same sketch.';

  @override
  String get msgDiameterPositive => 'Diameter must be a number greater than 0.';

  @override
  String get msgDepthPositive => 'Depth must be a number greater than 0.';

  @override
  String msgCboreWiderThanHole(String kind) {
    return 'The $kind must be wider than the hole and deeper than 0.';
  }

  @override
  String get msgCsinkAngle =>
      'The countersink must be wider than the hole, with an angle between 0 and 180 deg.';

  @override
  String get msgSplitNeedsBody => 'Split trims a body — there is none yet.';

  @override
  String get msgSelectTrimPlane => 'Select the plane to trim with.';

  @override
  String msgTrimmingWith(String label) {
    return 'Trimming with $label. OK keeps the side that is left.';
  }

  @override
  String get msgCombineNeedsTwoBodies =>
      'Combine needs two bodies — it joins, cuts or intersects one with another.';

  @override
  String get msgTapBodyToKeep => 'Tap the body to KEEP.';

  @override
  String msgTapBodiesToCombine(String name) {
    return 'Tap the bodies to combine into $name.';
  }

  @override
  String get msgThatIsBaseBody =>
      'That is the base body — pick another one to combine with it.';

  @override
  String get msgPickKeepThenCombine =>
      'Pick the body to keep, then the bodies to combine into it.';

  @override
  String get msgSelectTargetBody =>
      'Select the target body — tap it in 3D or in the browser.';

  @override
  String msgPatternNeedsComponent(String kind) {
    return '$kind needs a component to copy — place one first.';
  }

  @override
  String msgRelationshipsDropped(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$n relationships went with the elements that were removed — Cancel puts them back.',
      one:
          '1 relationship went with the elements that were removed — Cancel puts it back.',
    );
    return '$_temp0';
  }

  @override
  String get msgTapComponentToPattern => 'Tap the component to pattern.';

  @override
  String get msgCannotPatternAnElement =>
      'A pattern element cannot be patterned — select the source component.';

  @override
  String get msgSelectComponentToCopy => 'Select a component to copy.';

  @override
  String get msgCannotCopyAnElement =>
      'A pattern element cannot be copied — copy the source component, or edit the count.';

  @override
  String msgPatternNeedsFeature(String kind) {
    return '$kind needs a feature to copy — build one first.';
  }

  @override
  String get msgSelectFeatures =>
      'Select features — tap a face in 3D, or a row in the browser.';

  @override
  String get msgTapStraightOrCircularEdge =>
      'Tap a straight edge, a circular edge, or an origin axis.';

  @override
  String get msgTapCircularOrStraightEdge =>
      'Tap a circular edge, a straight edge, or an origin axis.';

  @override
  String get msgTapPlanarFace =>
      'Tap a planar face, a work plane, or an origin plane.';

  @override
  String get msgTapSketchForOccurrences =>
      'Tap the sketch whose points place the occurrences.';

  @override
  String get msgTapSketchPointOfOriginal =>
      'Tap the sketch point the original sits on.';

  @override
  String get msgTapCurveStart =>
      'Tap the point on the curve where the pattern starts.';

  @override
  String get msgTapFaceToFollow =>
      'Tap the face the occurrences should follow.';

  @override
  String get msgTapSolidBodyToPattern => 'Tap the solid body to pattern.';

  @override
  String get msgPickSolidBodyToPattern => 'Pick the solid body to pattern.';

  @override
  String msgBuiltAfterPattern(String name) {
    return '“$name” is built after this pattern, so the pattern cannot copy it.';
  }

  @override
  String get msgEdgeNoDirection => 'That edge has no direction.';

  @override
  String get msgPickCurveFirst => 'Pick the curve for this direction first.';

  @override
  String get msgCurveGone => 'That curve is no longer available.';

  @override
  String msgSketchHasNoPoints(String name) {
    return '“$name” holds no sketch points — a sketch-driven pattern places one occurrence per point.';
  }

  @override
  String msgBasePointMustBeOf(String name) {
    return 'The base point must be a point of “$name”.';
  }

  @override
  String get msgCannotCreatePattern => 'Cannot create the pattern.';

  @override
  String msgPatternedByBroken(String name, String names, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$name” was patterned by $names — those patterns are now broken. Undo restores it.',
      one:
          '“$name” was patterned by $names — that pattern is now broken. Undo restores it.',
    );
    return '$_temp0';
  }

  @override
  String get msgTapCurveToSweep => 'Tap the curve to sweep along.';

  @override
  String get msgCurveNoLength => 'That curve has no length.';

  @override
  String get msgTapSectionsInOrder => 'Tap each section in order.';

  @override
  String get msgTapAxisLine =>
      'Tap a sketch line or an origin axis to use as the axis.';

  @override
  String get msgPickAxisLine => 'Pick a sketch line or an origin axis.';

  @override
  String get msgAxisNotInSketchPlane => 'That axis is not in the sketch plane.';

  @override
  String get msgLineGone => 'That line is no longer available.';

  @override
  String get msgAxisMustBeStraight => 'The axis must be a straight line.';

  @override
  String get msgLineNoLength => 'That line has no length.';

  @override
  String get msgCreateSketchFirstExtrude =>
      'Create a 2D sketch first — Extrude needs a closed profile.';

  @override
  String get msgProfilesSameSketch =>
      'All profiles of one extrusion must come from the same sketch.';

  @override
  String get msgPickProfile => 'Pick at least one profile to extrude.';

  @override
  String get msgSelectTerminateFace => 'Select the face to terminate on.';

  @override
  String get msgPickOneEdgeFirst =>
      'Pick one edge first, so the body is known.';

  @override
  String get msgBodyHasNoEdges => 'That body has no selectable edges.';

  @override
  String get msgSelectEdges =>
      'Select edges — tap to add, tap again to remove.';

  @override
  String get msgTapToPlaceGear => 'Tap in the sketch to place the gear.';

  @override
  String get msgCouldNotPlaceGear => 'Could not place the gear here.';

  @override
  String get msgInternalGearTeeth =>
      'Internal gear needs at least 3 teeth and a valid module.';

  @override
  String get msgGearTeeth => 'Gear needs at least 4 teeth and a valid module.';

  @override
  String get msgInternalGearPlaced =>
      'Internal gear placed — dimension the centre and one angle to fully constrain it.';

  @override
  String get msgExternalGearPlaced =>
      'External gear placed — dimension the centre and one angle to fully constrain it.';

  @override
  String get msgPlanetaryNeeds =>
      'Planetary needs sun and planet teeth ≥ 4 and ≥ 2 planets.';

  @override
  String get msgPlanetaryUndrawable =>
      'These planetary parameters cannot be drawn.';

  @override
  String get msgPlanetaryPlacedFree =>
      'Planetary set placed (as free geometry).';

  @override
  String get msgPlanetaryPlacedDimension =>
      'Planetary set placed — dimension the centre and one angle.';

  @override
  String msgPlanetaryUneven(int count) {
    return 'Planetary set placed. Note: $count planets do not evenly divide for exact meshing.';
  }

  @override
  String msgPlanetaryUnevenSpacing(int count) {
    return 'Planetary set placed ($count planets are not evenly spaced for exact meshing).';
  }

  @override
  String get msgAlreadyProjected => 'Already projected onto this layer.';

  @override
  String get msgProjectPicksOtherLayers =>
      'Project picks geometry from OTHER layers.';

  @override
  String get msgTapPolygonEdge => 'Tap an edge of the polygon to project it.';

  @override
  String get msgTapGeometryOtherLayer =>
      'Tap geometry on another layer, or the X/Y axis.';

  @override
  String get msgProjectedNoPattern => 'Projected geometry cannot be patterned.';

  @override
  String get msgProjectedNoModify =>
      'Projected geometry cannot be modified here.';

  @override
  String get msgPickDirectionLine => 'Pick a line to define the direction.';

  @override
  String get msgPickAxisPoint => 'Pick a point or center to define the axis.';

  @override
  String get msgPickMirrorLine => 'Pick a line to mirror about.';

  @override
  String get msgMirrorLineInSelection =>
      'The mirror line cannot be part of the selection.';

  @override
  String get msgSelectGeometryToPattern => 'Select geometry to pattern.';

  @override
  String get msgPickLineDirection1 => 'Pick a line under Direction 1.';

  @override
  String get msgPickPatternAxis => 'Pick the pattern axis.';

  @override
  String get msgPickTheMirrorLine => 'Pick the mirror line.';

  @override
  String get msgPatternNothingToCreate => 'The pattern has nothing to create.';

  @override
  String get msgPatternUnsatisfiable =>
      'Pattern cannot be satisfied with the current constraints.';

  @override
  String msgPatternCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pattern created ($count new elements).',
      one: 'Pattern created (one new element).',
    );
    return '$_temp0';
  }

  @override
  String get msgSelfSymNeedsOneSpline =>
      'Self Symmetric needs exactly one spline.';

  @override
  String get msgSelfSymNeedsOpenSpline =>
      'Self Symmetric needs an open spline.';

  @override
  String get msgSelfSymEndOnMirror =>
      'The spline must end on the mirror line for Self Symmetric.';

  @override
  String get msgSelfSymUnsatisfiable =>
      'Self Symmetric cannot be satisfied with the current constraints.';

  @override
  String get msgSelfSymDone => 'Spline made self-symmetric.';

  @override
  String get msgTrimBreaksConstraints =>
      'This trim would break the sketch constraints.';

  @override
  String get msgSplitBreaksConstraints =>
      'This split would break the sketch constraints.';

  @override
  String get msgNothingToOffset => 'Nothing to offset here.';

  @override
  String msgRadiusPastEdge(String radius, String most) {
    return 'R$radius runs past the end of that edge. This corner takes at most R$most.';
  }

  @override
  String get msgPickTwoThatMeet =>
      'Pick two lines, arcs or circles that can meet.';

  @override
  String get msgPickTwoNonParallel => 'Pick two non-parallel lines.';

  @override
  String get msgFilletBreaksSketch =>
      'That fillet would break the sketch — pick a valid corner or a smaller radius.';

  @override
  String get msgChamferBreaksSketch =>
      'That chamfer would break the sketch — pick a valid corner or smaller distances.';

  @override
  String get msgShapeHasNoSize => 'That shape has no size — draw it again.';

  @override
  String get msgAlreadyLocked => 'This geometry is already locked.';

  @override
  String get msgWouldOverConstrainC =>
      'Adding this constraint will over-constrain the sketch.';

  @override
  String get msgConstraintUnsatisfiable =>
      'This constraint cannot be satisfied with the current geometry.';

  @override
  String get msgTangentNeedsCurve =>
      'Tangent needs at least one curved entity.';

  @override
  String get msgTangentClosedSpline =>
      'Tangent to a CLOSED spline is not supported.';

  @override
  String get msgSmoothNeedsTwoCurves =>
      'Smooth (G2) needs two curved entities.';

  @override
  String get msgValueUnsatisfiable =>
      'This value cannot be satisfied with the current constraints.';

  @override
  String get msgValueUnsatisfiableShort =>
      'Value cannot be satisfied with the current constraints.';

  @override
  String get msgDrivenDimension =>
      'This is a driven (reference) dimension — it cannot be edited.';

  @override
  String get msgInvalidParamName => 'Invalid parameter name.';

  @override
  String get msgInvalidOrDuplicateParamName =>
      'Invalid or duplicate parameter name.';

  @override
  String msgParamNameInUse(String name) {
    return 'Parameter name “$name” is already in use.';
  }

  @override
  String msgUnknownParam(String name) {
    return 'Unknown parameter “$name”.';
  }

  @override
  String msgCircularRefDimension(String name) {
    return 'Circular reference: “$name” depends on this dimension.';
  }

  @override
  String msgCircularRefParam(String name) {
    return 'Circular reference: “$name” depends on this parameter.';
  }

  @override
  String get msgInvalidExpression => 'Invalid expression.';

  @override
  String msgParamUsedBy(String name, String user) {
    return '“$name” is used by “$user” — remove the reference first.';
  }

  @override
  String get msgEdgeIsSpline =>
      'That edge is a spline — it defines no single direction.';

  @override
  String get msgRotationAxisStraight =>
      'A rotation axis must be a straight line or an axis.';

  @override
  String get msgPickEdgeOrCurve =>
      'Pick a straight or circular edge, a sketch curve, or an origin axis.';

  @override
  String get msgTapOnTheCurve => 'Tap on the curve.';

  @override
  String get msgPickPlanarFace =>
      'Pick a planar face, a work plane, or an origin plane.';

  @override
  String get msgPickSketchPointOccurrences =>
      'Pick a sketch POINT — the occurrences go where the points are.';

  @override
  String get msgTapFaceOfFeature =>
      'Tap a face of the feature to pattern, or pick it in the browser.';

  @override
  String get msgFaceNoSingleFeature =>
      'That face cannot be traced back to one feature — pick the feature in the browser.';

  @override
  String msgAddedNamed(String name) {
    return 'Added $name.';
  }

  @override
  String msgRemovedNamed(String name) {
    return 'Removed $name.';
  }

  @override
  String get msgTapSolidBody => 'Tap a solid body.';

  @override
  String get msgTapSketchPointForHole =>
      'Tap a sketch POINT — that is where a hole goes.';

  @override
  String msgNotBuiltYet(String command) {
    return '$command: not built yet — use Offset from Plane or Midplane.';
  }

  @override
  String get dlgEquationCurve => 'Equation Curve';

  @override
  String get lblEquationHint => 'y = f(x)   (sin, cos, sqrt, ^, pi, ...)';

  @override
  String get lblXMin => 'x min';

  @override
  String get lblXMax => 'x max';

  @override
  String get dlgProperties => 'Properties';

  @override
  String get dlgParameters => 'Parameters';

  @override
  String get dlgGear => 'Gear';

  @override
  String get dlgText => 'Text';

  @override
  String get dlgFreehandSpline => 'Freehand Spline';

  @override
  String get dlgPolygon => 'Polygon';

  @override
  String lblDirectionN(String n) {
    return 'Direction $n';
  }

  @override
  String get lblAxis => 'Axis';

  @override
  String get lblMirrorLine => 'Mirror line';

  @override
  String get lblGeometry => 'Geometry';

  @override
  String get lblExtents => 'Extents';

  @override
  String get lblBoundary => 'Boundary';

  @override
  String get lblIncludeGeometry => 'Include geometry';

  @override
  String get lblSuppress => 'Suppress';

  @override
  String get tipCancel => 'Cancel';

  @override
  String get tipSelectDirectionLine => 'Select the direction line';

  @override
  String get tipFlipDirection => 'Flip direction';

  @override
  String get tipPatternAlongPath => 'Pattern along a path — not yet available';

  @override
  String get tipSelectRotationAxisPoint => 'Select the rotation axis point';

  @override
  String get tipFlipRotation => 'Flip rotation direction';

  @override
  String get tipSelectGeometryToMirror => 'Select the geometry to mirror';

  @override
  String get tipSelectMirrorLine => 'Select the mirror line';

  @override
  String get tipSelectGeometryToPattern => 'Select the geometry to pattern';

  @override
  String get msgBoundaryFillNotYet => 'Boundary fill — not yet available';

  @override
  String get msgSuppressNotYet => 'Suppress instances — not yet available';

  @override
  String get msgPickWhileSelectorBlue =>
      'Pick geometry in the viewport while the blue selector is active. OK / Done creates the pattern.';

  @override
  String get msgFilletPickTwo =>
      'Pick two lines, arcs or circles.\nFirst fillet is dimensioned; later ones reuse the radius.';

  @override
  String get msgDistance1FirstLine =>
      'Distance 1 applies to the first picked line.';

  @override
  String get msgPolygonSides => 'Sides. Pick the centre, then a corner.';

  @override
  String get hintTapBodyIn3d => 'Tap the body in 3D…';

  @override
  String get hintTapFeaturesInBrowser => 'Tap features in the browser…';

  @override
  String get hintTapPointOnCurve => 'Tap a point on the curve…';

  @override
  String get hintTapEdgeOrAxis => 'Tap an edge or axis…';

  @override
  String get hintTapCircularEdge => 'Tap a circular edge or axis…';

  @override
  String get hintTapSketchPoint => 'Tap a sketch point…';

  @override
  String get hintTapOriginalPoint => 'Tap the point the original sits on…';

  @override
  String get hintTapFaceToFollow => 'Tap the face to follow…';

  @override
  String get hintTapFaceOrPlane => 'Tap a face or plane…';

  @override
  String get msgNoDimensionsInSketch => 'No dimensions in this sketch.';

  @override
  String get btnAddNumericParameter => 'Add numeric parameter';

  @override
  String get colParameterName => 'Parameter Name';

  @override
  String get colEquation => 'Equation';

  @override
  String get colValue => 'Value';

  @override
  String get lblReference => '(reference)';

  @override
  String get lblPoints => 'Points';

  @override
  String get lblSmoothing => 'Smoothing';

  @override
  String lblFitPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fit points',
      one: 'One fit point',
    );
    return '$_temp0';
  }

  @override
  String get tipFinishEnter => 'Finish (Enter)';

  @override
  String get tipDiscardEsc => 'Discard (Esc)';

  @override
  String get lblFont => 'Font';

  @override
  String get lblSize => 'Size';

  @override
  String get lblPreview => 'Preview';

  @override
  String lblEdgeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count edges',
      one: 'One edge',
    );
    return '$_temp0';
  }

  @override
  String get btnAddEdgeSet => 'Add edge set';

  @override
  String get lblSwapFaces => 'Swap the two faces';

  @override
  String lblWorkPlaneOffset(String name) {
    return '$name  Offset';
  }

  @override
  String lblSketchPlaneN(String n) {
    return '$n Sketch Plane';
  }

  @override
  String lblNeedsExistingBody(String label) {
    return '$label (needs an existing body)';
  }

  @override
  String get tipApplyAndStartAnother => 'Apply and start another';

  @override
  String get msgSplitRemovesOtherSide =>
      'Everything on the other side of the plane is removed. Splitting into two bodies is not built.';

  @override
  String get msgGearTapToPlace =>
      'Tap in the sketch to place; then dimension the centre and one angle.';

  @override
  String get lblAutoRootTip => 'Automatic root & tip radii';

  @override
  String get dlgReportBug => 'Report a bug';

  @override
  String get msgBugPrompt =>
      'What did you expect, and what happened instead?\nThe model, every feature\'s state and the full log are attached automatically — describe only what you SAW.';

  @override
  String get hintBugExample =>
      'e.g. filleted the top edge at 2 mm and the wall disappeared instead of rounding';

  @override
  String get btnSaveReport => 'Save report';

  @override
  String get btnCopyPath => 'Copy path';

  @override
  String get btnCopyIssueLink => 'Copy issue link';

  @override
  String get btnDirect => 'Direct';

  @override
  String get btnDeleteFace => 'Delete Face';

  @override
  String get btnThickenOffset => 'Thicken / Offset';

  @override
  String get btnUcs => 'UCS';

  @override
  String get btnSketchDriven => 'Sketch Driven';

  @override
  String get btnCenterline => 'Centerline';

  @override
  String get btnConstraintSettings => 'Constraint Settings';

  @override
  String get btnCopy => 'Copy';

  @override
  String get btnDrivenDimension => 'Driven Dimension';

  @override
  String get btnExtend => 'Extend';

  @override
  String get btnPointsTool => 'Points';

  @override
  String get btnShowConstraints => 'Show Constraints';

  @override
  String get btnShowFormat => 'Show Format';

  @override
  String get btnSmoothG2 => 'Smooth (G2)';

  @override
  String get btnStretch => 'Stretch';

  @override
  String get btnCenterPoint => 'Center Point';

  @override
  String get btnSplitCurve => 'Split';

  @override
  String get btnOffsetCurve => 'Offset';

  @override
  String get btnFinish => 'Finish';

  @override
  String get btnFinishSketch => 'Finish\nSketch';

  @override
  String get featExtrusion => 'Extrusion';

  @override
  String get featRevolution => 'Revolution';

  @override
  String get featSweep => 'Sweep';

  @override
  String get featLoft => 'Loft';

  @override
  String get featCoil => 'Coil';

  @override
  String get featFillet => 'Fillet';

  @override
  String get featChamfer => 'Chamfer';

  @override
  String get featHole => 'Hole';

  @override
  String get featSplit => 'Split';

  @override
  String get featCombine => 'Combine';

  @override
  String get featDeleteFace => 'Delete Face';

  @override
  String get cmdDeleteFace => 'Delete Face';

  @override
  String get cmdMoveFaces => 'Move Faces';

  @override
  String get cmdSizeFaces => 'Size Faces';

  @override
  String get cmdScaleBody => 'Scale Body';

  @override
  String get verbDelete => 'delete';

  @override
  String get verbMove => 'move';

  @override
  String get patRectangular => 'Rectangular Pattern';

  @override
  String get patCircular => 'Circular Pattern';

  @override
  String get patSketchDriven => 'Sketch Driven Pattern';

  @override
  String get patMirror => 'Mirror';

  @override
  String get holeSimple => 'Simple';

  @override
  String get holeCounterbore => 'Counterbore';

  @override
  String get holeSpotface => 'Spotface';

  @override
  String get holeCountersink => 'Countersink';

  @override
  String get holeSimpleShort => 'Simple';

  @override
  String get holeCounterboreShort => 'C\'bore';

  @override
  String get holeSpotfaceShort => 'Spot';

  @override
  String get holeCountersinkShort => 'C\'sink';

  @override
  String get msgNoInteriorEdgesLeft => 'No interior edges left to add.';

  @override
  String get msgNoExteriorEdgesLeft => 'No exterior edges left to add.';

  @override
  String msgAddedInteriorEdges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count fillet edges.',
      one: 'Added one fillet edge.',
    );
    return '$_temp0';
  }

  @override
  String msgAddedExteriorEdges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count round edges.',
      one: 'Added one round edge.',
    );
    return '$_temp0';
  }

  @override
  String get msgUndone => 'Undo';

  @override
  String get msgRedone => 'Redo';

  @override
  String get msgShow => 'Show';

  @override
  String get extToNext => 'To Next';

  @override
  String get extToFace => 'To';

  @override
  String get extThroughAll => 'Through All';

  @override
  String get extDistance => 'Distance';

  @override
  String get wfPickEdgeFacePlanesPoints =>
      'Select an edge, a face, two planes, or two points.';

  @override
  String get wfPickLinearEdge => 'Select a linear edge or sketch line.';

  @override
  String get wfPickCircularEdge => 'Select a circular or elliptical edge.';

  @override
  String get wfPickCylConeFace => 'Select a cylindrical or conical face.';

  @override
  String get wfPickPoint => 'Select a point.';

  @override
  String get wfPickParallelLine => 'Select the line to be parallel to.';

  @override
  String get wfPickFirstPoint => 'Select the first point.';

  @override
  String get wfPickSecondPoint => 'Select the second point.';

  @override
  String get wfPlaneDragOrPickSecond =>
      'Select a face or plane — drag it for an offset, or pick a second parallel face for the midplane.';

  @override
  String get wfPlaneSecondParallelEdgeOrPoint =>
      'Select a parallel face for the midplane, an edge to angle around, or a vertex for a parallel plane — or drag for an offset.';

  @override
  String get wfPlaneSecondCoplanarOrPoint =>
      'Select a second coplanar edge, or a vertex for the normal plane.';

  @override
  String get wfPlaneTwoMorePoints => 'Select two more points for the plane.';

  @override
  String wfCannotDefinePlane(String ref) {
    return '$ref cannot define a plane.';
  }

  @override
  String wfNoPlaneFromTwo(String a, String b) {
    return '$a and $b do not define a plane.';
  }

  @override
  String get wfPickThirdPoint => 'Select the third point.';

  @override
  String get wfPickFirstPlane => 'Select the first plane or planar face.';

  @override
  String get wfPickSecondNonParallelPlane =>
      'Select a second, non-parallel plane or face.';

  @override
  String get wfPickPlane => 'Select a plane or planar face.';

  @override
  String get wfPickAxisThroughPoint =>
      'Select the point the axis runs through.';

  @override
  String get wfPickVertexCircleOrMeeting =>
      'Select a vertex, a circular edge, or geometry that meets.';

  @override
  String get wfPickVertexToGround =>
      'Select a vertex or midpoint to ground a point at.';

  @override
  String get wfPickVertexSketchPointMid =>
      'Select a vertex, sketch point, or edge midpoint.';

  @override
  String get wfPickTorusFace => 'Select a toroidal face.';

  @override
  String get wfPickSphereFace => 'Select a spherical face.';

  @override
  String get wfPickFirstLine => 'Select the first line, edge or axis.';

  @override
  String get wfPickSecondCrossingLine =>
      'Select a second line that crosses it.';

  @override
  String get wfPickCrossingLine =>
      'Select a line, edge or axis that crosses it.';

  @override
  String get wfPickSecondPlane => 'Select the second plane.';

  @override
  String get wfPickThirdPlane => 'Select the third plane.';

  @override
  String get wfPickLineOrTwoPlanes =>
      'Select a line to cross it, or two more planes.';

  @override
  String get wfPickSecondLineOrPlane =>
      'Select a second line, or a plane to cross.';

  @override
  String get wfPickSecondPlaneOrPoint =>
      'Select a second plane to intersect with, or a point for the normal through it.';

  @override
  String get wfPickSecondPointPlaneOrLine =>
      'Select a second point, a plane, or a line.';

  @override
  String get wfPickParallelPlane =>
      'Select the plane or planar face to be parallel to.';

  @override
  String get wfPickPlaneThroughPoint =>
      'Select the point the plane runs through.';

  @override
  String get wfPickFirstEdge => 'Select the first edge or line.';

  @override
  String get wfPickSecondCoplanarEdge =>
      'Select a second edge in the same plane.';

  @override
  String get wfPickNormalAxis =>
      'Select the axis, edge or line to be normal to.';

  @override
  String get wfPickCylFaceSide =>
      'Select a cylindrical face, on the side the plane goes.';

  @override
  String get wfPickCylFace => 'Select a cylindrical face.';

  @override
  String get wfPickEdgeAlongIt => 'Select an edge lying along it.';

  @override
  String get wfPickPlaneToParallel => 'Select the plane to be parallel to.';

  @override
  String get wfPickPlaneToAngleFrom => 'Select the plane to angle from.';

  @override
  String get wfPickPivotEdgeInPlane =>
      'Select the edge to pivot about — it must lie in that plane.';

  @override
  String get wfTapCurveToCross =>
      'Tap a sketch curve where the plane should cross it.';

  @override
  String wfNotStraightEdge(String ref) {
    return '$ref is not a straight edge or line.';
  }

  @override
  String wfNotCircularEdge(String ref) {
    return '$ref is not a circular or elliptical edge.';
  }

  @override
  String wfNotRevolvedFace(String ref) {
    return '$ref is not a revolved face — pick a cylinder, cone or torus.';
  }

  @override
  String wfNoPoint(String ref) {
    return '$ref does not give a point.';
  }

  @override
  String wfNotPlane(String ref) {
    return '$ref is not a plane or planar face.';
  }

  @override
  String wfNeitherPointNorLine(String ref) {
    return '$ref is neither a point nor a line.';
  }

  @override
  String wfNeitherPlaneNorLine(String ref) {
    return '$ref is neither a plane nor a line.';
  }

  @override
  String get wfNoParallelLinePicked =>
      'Neither pick is a line to be parallel to.';

  @override
  String get wfPickPointForAxis =>
      'Select a point for the axis to pass through.';

  @override
  String get wfPickPointForPlane =>
      'Select a point for the plane to pass through.';

  @override
  String get wfSamePlace => 'Those two points are in the same place.';

  @override
  String wfParallelNeverMeet(String a, String b) {
    return '$a and $b are parallel — they never meet.';
  }

  @override
  String wfParallelNeverCross(String a, String b) {
    return '$a and $b are parallel — they never cross.';
  }

  @override
  String wfCannotDefineAxis(String ref) {
    return '$ref cannot define an axis.';
  }

  @override
  String wfCannotDefinePoint(String ref) {
    return '$ref cannot define a point.';
  }

  @override
  String wfParallelPickTwoMeeting(String a, String b) {
    return '$a and $b are parallel — pick two planes that meet.';
  }

  @override
  String wfNoAxisFromTwo(String a, String b) {
    return '$a and $b do not define an axis.';
  }

  @override
  String wfNoPointFromTwo(String a, String b) {
    return '$a and $b do not define a point.';
  }

  @override
  String wfNotClosedCircle(String ref) {
    return '$ref is not a closed circular edge.';
  }

  @override
  String wfNotSphere(String ref) {
    return '$ref is not a spherical face.';
  }

  @override
  String wfNotTorus(String ref) {
    return '$ref is not a toroidal face.';
  }

  @override
  String wfNotLineEdgeAxis(String ref) {
    return '$ref is not a line, edge or axis.';
  }

  @override
  String wfNotAxisEdgeLine(String ref) {
    return '$ref is not an axis, edge or line.';
  }

  @override
  String wfNotEdgeOrLine(String ref) {
    return '$ref is not an edge or line.';
  }

  @override
  String get wfPickOnePlaneOneLine => 'Select one plane and one line.';

  @override
  String wfSkewByGap(String a, String b, String gap) {
    return '$a and $b do not meet — they pass $gap apart.';
  }

  @override
  String wfLineParallelToPlane(String line, String plane) {
    return '$line is parallel to $plane — it never crosses it.';
  }

  @override
  String wfThreeNoCommonPoint(String a, String b, String c) {
    return '$a, $b and $c do not meet at one point — two of them are parallel, or all three share a line.';
  }

  @override
  String wfNotACurve(String ref) {
    return '$ref is not a curve — tap a sketch curve where the plane should cross it.';
  }

  @override
  String get wfPickPivotEdge => 'Select the edge the plane pivots about.';

  @override
  String wfEdgeNotInPlane(String edge, String plane) {
    return '$edge is not parallel to $plane — the plane can only pivot about an edge lying in it.';
  }

  @override
  String get wfAngleNotANumber => 'The angle is not a number.';

  @override
  String wfNotCylForTangent(String ref) {
    return '$ref is not a cylindrical face — a tangent plane needs one.';
  }

  @override
  String wfPointInsideCyl(String pt, String cyl) {
    return '$pt is inside $cyl — no tangent plane passes through it.';
  }

  @override
  String wfTwoTangentThroughPoint(String cyl, String pt) {
    return 'Two planes are tangent to $cyl through $pt — tap the face on the side the plane should go.';
  }

  @override
  String wfTwoTangentParallel(String cyl, String plane) {
    return 'Two planes are tangent to $cyl parallel to $plane — tap the face on the side the plane should go.';
  }

  @override
  String wfEdgeNotParallelToAxis(String edge, String cyl) {
    return '$edge is not parallel to the axis of $cyl.';
  }

  @override
  String wfEdgeOffCylinder(String edge, String cyl, String gap) {
    return '$edge does not lie on $cyl — it is $gap mm off it.';
  }

  @override
  String wfPlaneNotParallelToAxis(String plane, String cyl) {
    return '$plane is not parallel to the axis of $cyl — no tangent plane is parallel to it.';
  }

  @override
  String wfCollinearThreePoints(String a, String b, String c) {
    return '$a, $b and $c are in a line — three points must not be collinear.';
  }

  @override
  String wfSameLineTwice(String a, String b) {
    return '$a and $b are the same line — a plane needs two distinct edges.';
  }

  @override
  String wfSkewEdges(String a, String b, String gap) {
    return '$a and $b are skew — they miss each other by $gap mm.';
  }

  @override
  String get secInputGeometry => 'Input Geometry';

  @override
  String get secOutputGeometry => 'Output Geometry';

  @override
  String get secBehavior => 'Behavior';

  @override
  String get secPlacement => 'Placement';

  @override
  String get secOutput => 'Output';

  @override
  String get secExtents => 'Extents';

  @override
  String get lblDirection => 'Direction';

  @override
  String get lblOrientation => 'Orientation';

  @override
  String get lblMethod => 'Method';

  @override
  String get lblDistance => 'Distance';

  @override
  String get lblAngle => 'Angle';

  @override
  String get lblDepth => 'Depth';

  @override
  String get lblDiameter => 'Diameter';

  @override
  String get lblType => 'Type';

  @override
  String get lblCount => 'Count';

  @override
  String get lblNumber => 'Number';

  @override
  String get lblSpacing => 'Spacing';

  @override
  String get lblDistribution => 'Distribution';

  @override
  String get lblFlip => 'Flip';

  @override
  String get lblKeep => 'Keep';

  @override
  String get lblPlaneField => 'Plane';

  @override
  String get lblFaceField => 'Face';

  @override
  String get lblEdges => 'Edges';

  @override
  String get lblRadius => 'Radius';

  @override
  String lblRadiusN(String n) {
    return 'Radius $n';
  }

  @override
  String get lblDistance1 => 'Distance 1';

  @override
  String get lblDistance2 => 'Distance 2';

  @override
  String get lblTwoDistances => 'Two Distances';

  @override
  String get lblDistanceAndAngle => 'Distance and Angle';

  @override
  String get lblEqualDistance => 'Equal distance';

  @override
  String get lblAllFillets => 'All Fillets';

  @override
  String get lblAllRounds => 'All Rounds';

  @override
  String get hintTapEdgesIn3d => 'Tap edges in 3D…';

  @override
  String get lblSelectEdges => 'Select edges';

  @override
  String get lblBodies => 'Bodies';

  @override
  String get lblBase => 'Base';

  @override
  String get lblToolbodies => 'Toolbodies';

  @override
  String get hintTapBodyToKeep => 'Tap the body to KEEP…';

  @override
  String get hintPickBaseFirst => 'Pick the base first';

  @override
  String get hintTapBodiesToCombine => 'Tap the bodies to combine…';

  @override
  String get lblOperation => 'Operation';

  @override
  String get lblKeepTool => 'Keep tool';

  @override
  String get lblYes => 'Yes';

  @override
  String get opJoin => 'Join';

  @override
  String get opCut => 'Cut';

  @override
  String get opIntersect => 'Intersect';

  @override
  String get opNewSolid => 'New Solid';

  @override
  String get lblBoolean => 'Boolean';

  @override
  String get lblTargetBody => 'Target Body';

  @override
  String get lblTrim => 'Trim';

  @override
  String get hintTapPlaneOrFace => 'Tap a plane or planar face…';

  @override
  String get lblThisSide => 'This side';

  @override
  String get lblOtherSide => 'Other side';

  @override
  String get lblProfiles => 'Profiles';

  @override
  String get hintSelectProfile => 'Select a profile in the viewport';

  @override
  String get lblFrom => 'From';

  @override
  String get lblPath => 'Path';

  @override
  String get hintTapCurveIn3d => 'Tap a curve in 3D…';

  @override
  String get lblSelectCurveOrEdge => 'Select Curve or Edge';

  @override
  String get lblPathSelected => 'Path selected';

  @override
  String get lblFollowPath => 'Follow Path';

  @override
  String get lblFixed => 'Fixed';

  @override
  String get lblGuide => 'Guide';

  @override
  String get lblTaper => 'Taper';

  @override
  String get lblTwist => 'Twist';

  @override
  String get lblSections => 'Sections';

  @override
  String get hintTapProfilesIn3d => 'Tap profiles in 3D…';

  @override
  String get hintClickToAdd => 'Click to add';

  @override
  String get lblTransition => 'Transition';

  @override
  String get lblSmooth => 'Smooth';

  @override
  String get lblRuled => 'Ruled';

  @override
  String get lblClosedLoop => 'Closed Loop';

  @override
  String get lblMergeTangentFaces => 'Merge Tangent Faces';

  @override
  String get lblRevolutionCount => 'Revolution';

  @override
  String get lblHeight => 'Height';

  @override
  String get lblPitch => 'Pitch';

  @override
  String get lblRotationAngle => 'Rotation';

  @override
  String get hintTapLineOrAxis => 'Tap a line or origin axis…';

  @override
  String get lblSelectAxis => 'Select Axis';

  @override
  String get lblFull => 'Full';

  @override
  String get lblAngleA => 'Angle A';

  @override
  String get lblAngleB => 'Angle B';

  @override
  String get lblDistanceA => 'Distance A';

  @override
  String get lblDistanceB => 'Distance B';

  @override
  String get lblTerminateOn => 'Terminate on';

  @override
  String get hintTapFaceIn3d => 'Tap a face in 3D…';

  @override
  String get lblSelectFace => 'Select face';

  @override
  String get lblFaceSelected => 'Face selected — tap to change';

  @override
  String get lblDefault => 'Default';

  @override
  String get lblFlipped => 'Flipped';

  @override
  String get lblSymmetric => 'Symmetric';

  @override
  String get lblAsymmetric => 'Asymmetric';

  @override
  String get coilRevAndHeight => 'Revolution and Height';

  @override
  String get coilPitchAndRev => 'Pitch and Revolution';

  @override
  String get coilPitchAndHeight => 'Pitch and Height';

  @override
  String get coilSpiral => 'Spiral';

  @override
  String get hintTapSketchPointsIn3d => 'Tap sketch points in 3D…';

  @override
  String get lblCountersinkDia => 'Countersink ⌀';

  @override
  String get lblTermination => 'Termination';

  @override
  String get lblIntoPart => 'Into part';

  @override
  String get ctxShow => 'Show';

  @override
  String get ctxLock => 'Lock';

  @override
  String get ctxUnlock => 'Unlock';

  @override
  String get ctxRenameEllipsis => 'Rename…';

  @override
  String ctxMoveNHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count here',
      one: 'Move one here',
    );
    return '$_temp0';
  }

  @override
  String get ctxSuppressOccurrence => 'Suppress Occurrence';

  @override
  String get ctxRestoreOccurrence => 'Restore Occurrence';

  @override
  String get nodeYzPlane => 'YZ Plane';

  @override
  String get nodeXzPlane => 'XZ Plane';

  @override
  String get nodeXyPlane => 'XY Plane';

  @override
  String get nodeZAxis => 'Z Axis';

  @override
  String get msgLayerEmptyRemoved => 'This layer is empty and will be removed.';

  @override
  String msgRemovesLayerAndEntities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This removes the layer and its $count entities.',
      one: 'This removes the layer and its one entity.',
    );
    return '$_temp0';
  }

  @override
  String get secModelParameters => 'Model Parameters';

  @override
  String get secUserParameters => 'User Parameters';

  @override
  String lblLineN(String n) {
    return 'Line $n';
  }

  @override
  String get lblSingleOpenSplineOnly => '(single open spline only)';

  @override
  String get lblSolid => 'Solid';

  @override
  String get lblSelectSolid => 'Select Solid';

  @override
  String get lblComponent => 'Component';

  @override
  String get lblSelectComponents => 'Select components';

  @override
  String lblNComponents(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Components',
      one: '1 Component',
    );
    return '$_temp0';
  }

  @override
  String get hintTapComponentIn3d => 'Tap the component in 3D…';

  @override
  String get lblFeaturePattern => 'Feature Pattern';

  @override
  String get lblOwnSpacing => 'Own spacing';

  @override
  String get lblFeature => 'Feature';

  @override
  String get lblSelectFeatures => 'Select Features';

  @override
  String get lblDirectionA => 'Direction A';

  @override
  String get lblDirectionB => 'Direction B';

  @override
  String get lblStartA => 'Start A';

  @override
  String get lblStartB => 'Start B';

  @override
  String get lblCurveStart => 'Curve start';

  @override
  String lblMmAlong(String value) {
    return '$value mm along';
  }

  @override
  String get lblAddIrregularAngle => 'Irregular Angle';

  @override
  String get lblAddIrregularDistance => 'Irregular Distance';

  @override
  String get lblSelectDir => 'Select Dir...';

  @override
  String get lblMidplane => 'Midplane';

  @override
  String get lblCurveLength => 'Curve Length';

  @override
  String get lblIdentical => 'Identical';

  @override
  String get lblIncremental => 'Incremental';

  @override
  String get lblRotational => 'Rotational';

  @override
  String get lblSketchPoint => 'Sketch Point';

  @override
  String get lblSelectPoint => 'Select Point';

  @override
  String get lblBasePoint => 'Base Point';

  @override
  String get lblFollowFace => 'Follow Face';

  @override
  String get lblMirrorPlane => 'Mirror Plane';

  @override
  String get lblCreationMethod => 'Creation Method';

  @override
  String get lblAdjust => 'Adjust';

  @override
  String get lblRemoveOriginal => 'Remove Original';

  @override
  String get lblKeepMirroredHalf => 'Keep only the mirrored half';

  @override
  String get lblPatternFeatures => 'Pattern individual features';

  @override
  String get lblPatternSolid => 'Pattern a solid';

  @override
  String get lblPick => 'Pick';

  @override
  String lblPointCount(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name ($count points)',
      one: '$name (one point)',
    );
    return '$_temp0';
  }

  @override
  String lblCoords(String x, String y) {
    return '($x, $y)';
  }

  @override
  String get conCoincident => 'Coincident';

  @override
  String get conCollinear => 'Collinear';

  @override
  String get conConcentric => 'Concentric';

  @override
  String get conLock => 'Lock';

  @override
  String get conParallel => 'Parallel';

  @override
  String get conPerpendicular => 'Perpendicular';

  @override
  String get conHorizontal => 'Horizontal';

  @override
  String get conVertical => 'Vertical';

  @override
  String get conTangent => 'Tangent';

  @override
  String get conSymmetric => 'Symmetric';

  @override
  String get conEqual => 'Equal';

  @override
  String get lblModuleMm => 'Module (mm)';

  @override
  String get lblTeeth => 'Teeth';

  @override
  String get lblCornerRadiusMm => 'Corner radius (mm)';

  @override
  String get lblSunTeeth => 'Sun teeth';

  @override
  String get lblPlanetTeeth => 'Planet teeth';

  @override
  String get lblPlanets => 'Planets';

  @override
  String get lblPressureAngle => 'Pressure angle (°)';

  @override
  String get lblProfileShift => 'Profile shift';

  @override
  String get lblBoreDia => 'Bore Ø (mm)';

  @override
  String get btnInsert => 'Insert';

  @override
  String get gearExternal => 'External';

  @override
  String get gearInternal => 'Internal';

  @override
  String get gearPlanetary => 'Planetary';

  @override
  String gearRingInfo(String teeth, String dist) {
    return 'Ring ${teeth}T · centre dist $dist';
  }

  @override
  String get hudFullyConstrained => 'Fully Constrained';

  @override
  String get hudCancelEsc => 'Cancel (Esc)';

  @override
  String hudDeleteN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count objects',
      one: 'Delete one object',
    );
    return '$_temp0';
  }

  @override
  String get hudLineKey => 'Line (L)';

  @override
  String get hudCircleKey => 'Circle (C)';

  @override
  String get hudRectKey => 'Rectangle (R)';

  @override
  String get hudDimensionKey => 'Dimension (D)';

  @override
  String get hintTapDimensionToInsert =>
      'Tap a dimension in the sketch to insert it as \"name\"';

  @override
  String get hintTextEmbedParams =>
      'Text — embed parameters as <Width> or \"d0\"';

  @override
  String get msgReportSaved => 'Report saved';

  @override
  String get msgReportFailed => 'Report FAILED';

  @override
  String get msgBugSaved =>
      'Files app > On My iPad > prototype > bugreports\nSend the .zip — it contains everything needed; no explanation has to travel with it.';

  @override
  String get msgBugBundleFailed =>
      'The bundle could not be written. The log still has the description, so the session is not lost — see the \"bug\" lines in prototype_log.txt.';

  @override
  String get msgBugUploaded =>
      'Also filed online — an AI can act on it directly.';

  @override
  String get msgBugUploadFailed =>
      'Could not reach the relay — only the local copy above exists. Send it by hand, or try again once you have a connection.';

  @override
  String get hintPickBodyTapCancel => 'Pick a body… (tap to cancel)';

  @override
  String get lblSelectBodyIn3d => 'Select body in 3D / browser';

  @override
  String get secAdvancedProperties => 'Advanced Properties';

  @override
  String get lblTaperA => 'Taper A';

  @override
  String get lblMatchShape => 'Match Shape';

  @override
  String get lblSelectFaceBtn => 'Select Face';

  @override
  String gearRingLine(String teeth, String dist, String warn) {
    return 'Ring ${teeth}T · centre dist $dist mm$warn';
  }

  @override
  String get gearUnevenWarn => ' · ⚠ planets not evenly spaced';

  @override
  String gearPitchLine(String pitch, String tip, String root) {
    return 'Pitch Ø $pitch · tip Ø $tip · root Ø $root mm';
  }

  @override
  String msgRemovesLayerAndEntitiesUndo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This removes the layer and its $count entities. This can’t be undone.',
      one: 'This removes the layer and its one entity. This can’t be undone.',
    );
    return '$_temp0';
  }

  @override
  String get valNameEmpty => 'Name must not be empty';

  @override
  String get valNameTooLong => 'Name is too long';

  @override
  String get valNameBadChars => 'Name cannot contain / \\ or :';

  @override
  String get valNameLeadingDot => 'Name cannot start with a dot';

  @override
  String valBodyNameTaken(String name) {
    return 'A body named “$name” already exists';
  }

  @override
  String valFeatureNameTaken(String name) {
    return 'A feature named “$name” already exists';
  }

  @override
  String get valSelectOneEdge => 'Select at least one edge.';

  @override
  String get valRadiusPositive => 'Radius must be > 0.';

  @override
  String valRadiusOfSetPositive(String n) {
    return 'Radius of set $n must be > 0.';
  }

  @override
  String get valEndRadiusPositive => 'End radius must be > 0.';

  @override
  String valEndRadiusOfSetPositive(String n) {
    return 'End radius of set $n must be > 0.';
  }

  @override
  String get valDistancePositive => 'Distance must be > 0.';

  @override
  String get valDistance2Positive => 'Distance 2 must be > 0.';

  @override
  String get valAngle0to90 => 'Angle must be between 0 and 90 deg.';

  @override
  String get valSelectOneComponent =>
      'Select at least one component to pattern.';

  @override
  String get valDrivingFeatureGone => 'The driving feature pattern is gone.';

  @override
  String get valSelectOneFeature => 'Select at least one feature to pattern.';

  @override
  String get valSelectDirectionA =>
      'Select a direction or a curve for Direction A.';

  @override
  String get valCountAAtLeastOne => 'Number in Direction A must be 1 or more.';

  @override
  String get valDistanceAPositive =>
      'Distance in Direction A must be greater than 0.';

  @override
  String get valCountBAtLeastOne => 'Number in Direction B must be 1 or more.';

  @override
  String get valDistanceBPositive =>
      'Distance in Direction B must be greater than 0.';

  @override
  String get valPatternNeedsTwo => 'A pattern needs more than one occurrence.';

  @override
  String get valSelectRotationAxis => 'Select the rotation axis.';

  @override
  String get valCountAtLeastOne => 'Count must be 1 or more.';

  @override
  String get valAngleNotZero => 'Angle must not be 0.';

  @override
  String get valSelectPointSketch => 'Select the sketch that holds the points.';

  @override
  String get valSelectMirrorPlane => 'Select the mirror plane.';

  @override
  String get valNoSolidToPattern => 'There is no solid to pattern yet.';

  @override
  String get valSelectPathCurve => 'Select a path curve.';

  @override
  String get valTwistUnsupported =>
      'Twist is not supported yet — leave it at 0.';

  @override
  String get valSelectTwoSections => 'Select at least two sections.';

  @override
  String get valSelectAxis => 'Select an axis.';

  @override
  String get valPitchPositive => 'Pitch must be > 0.';

  @override
  String get valRevolutionPositive => 'Revolution must be > 0.';

  @override
  String get valHeightPositive => 'Height must be > 0.';

  @override
  String get valSelectRevolveAxis => 'Select an axis of revolution.';

  @override
  String get valAxisNoDirection => 'The axis has no direction.';

  @override
  String get valAngleA0to360 => 'Angle A must be between 0 and 360 degrees.';

  @override
  String get valAngleBPositive => 'Angle B must be > 0.';

  @override
  String get valAngleABMax360 => 'Angle A + B cannot exceed 360 degrees.';

  @override
  String get valDistanceAPositiveShort => 'Distance A must be > 0.';

  @override
  String get valDistanceBPositiveShort => 'Distance B must be > 0.';

  @override
  String get valTaperRange => 'Taper must be inside (-90, 90) degrees.';

  @override
  String get lblSelectDirPlaceholder => 'Select Dir...';

  @override
  String get lblMirrorPlanePlaceholder => 'Mirror Plane';

  @override
  String get lblCenterlineGeo => 'Centerline';

  @override
  String get lblConstructionLineGeo => 'Construction line';

  @override
  String get lblLineGeo => 'Line';

  @override
  String get panelComponent => 'Component';

  @override
  String get viewShadedEdges => 'Shaded + Edges';

  @override
  String get viewRendered => 'Rendered';

  @override
  String get viewFloor => 'Display floor';

  @override
  String get cubeSetFront => 'Set Current View as Front';

  @override
  String get cubeSetTop => 'Set Current View as Top';

  @override
  String get cubeResetFront => 'Reset Front';

  @override
  String get cubeRollLeft => 'Rotate view left';

  @override
  String get cubeRollRight => 'Rotate view right';

  @override
  String get cubeStep => 'Go to adjacent view';

  @override
  String msgProjectedFace(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n edges projected',
      one: '1 edge projected',
    );
    return '$_temp0';
  }

  @override
  String get sectionNone => 'No Section';

  @override
  String get sectionHalf => 'Half Section';

  @override
  String get sectionQuarter => 'Quarter Section';

  @override
  String get sectionThreeQuarter => 'Three Quarter Section';

  @override
  String get sectionFlip1 => 'Flip Plane 1';

  @override
  String get sectionFlip2 => 'Flip Plane 2';

  @override
  String get msgPickSectionPlane => 'Tap a plane or planar face to cut at';

  @override
  String get msgPickSectionPlane2 => 'Tap the second plane';

  @override
  String get panelAppearance => 'Appearance';

  @override
  String get matPickBody => 'Nothing selected';

  @override
  String get matSteel => 'Steel';

  @override
  String get matAluminium => 'Aluminium';

  @override
  String get matGraphite => 'Graphite';

  @override
  String get matBrass => 'Brass';

  @override
  String get matCopper => 'Copper';

  @override
  String get matRed => 'Red';

  @override
  String get matGreen => 'Green';

  @override
  String get matBlue => 'Blue';

  @override
  String get matViolet => 'Violet';

  @override
  String get panelPosition => 'Position';

  @override
  String get panelRelationships => 'Relationships';

  @override
  String get btnPlace => 'Place';

  @override
  String get btnCreateComponent => 'Create';

  @override
  String get btnFreeMove => 'Free Move';

  @override
  String get btnFreeRotate => 'Free Rotate';

  @override
  String get btnJoint => 'Joint';

  @override
  String get btnConstrain => 'Constrain';

  @override
  String get btnShowRelationships => 'Show';

  @override
  String get btnShowSick => 'Show Sick';

  @override
  String get btnHideAll => 'Hide All';

  @override
  String get btnPatternComponent => 'Pattern';

  @override
  String get galleryNewAssembly => 'New Assembly';

  @override
  String get dlgNewAssembly => 'New assembly';

  @override
  String get phAssemblyName => 'Assembly name';

  @override
  String get nodeRepresentations => 'Representations';

  @override
  String get nodeRelationships => 'Relationships';

  @override
  String get dlgPlaceComponent => 'Place Component';

  @override
  String get msgAsmNoPartsToPlace =>
      'Create a 3D part first — there is nothing to place.';

  @override
  String msgAsmNoSuchPart(String name) {
    return 'There is no part named “$name”.';
  }

  @override
  String msgAsmCouldNotPlace(String name) {
    return 'Could not place “$name”.';
  }

  @override
  String msgAsmGrounded(String name) {
    return '“$name” is grounded.';
  }

  @override
  String get ctxGrounded => 'Grounded';

  @override
  String get dlgPlaceConstraint => 'Place Constraint';

  @override
  String get tabAsmAssembly => 'Assembly';

  @override
  String get tabAsmMotion => 'Motion';

  @override
  String get tabAsmTransitional => 'Transitional';

  @override
  String get tabAsmConstraintSet => 'Constraint Set';

  @override
  String get grpAsmType => 'Type';

  @override
  String get grpAsmSelections => 'Selections';

  @override
  String get grpAsmSolution => 'Solution';

  @override
  String get lblAsmOffset => 'Offset';

  @override
  String get lblAsmAngle => 'Angle';

  @override
  String get lblAsmRatio => 'Ratio';

  @override
  String get lblAsmDistance => 'Distance';

  @override
  String get cbAsmPickPartFirst => 'Pick Part First';

  @override
  String get cbAsmShowPreview => 'Show Preview';

  @override
  String get cbAsmPredict => 'Predict Offset and Orientation';

  @override
  String get cbAsmDefaultUndirected => 'Default to Undirected';

  @override
  String get lblAsmName => 'Name';

  @override
  String get hintAsmAutoName => 'Automatic';

  @override
  String tipAsmSelection(int n) {
    return 'Selection $n';
  }

  @override
  String get hintAsmPickGeometry => 'Tap a face, edge or axis';

  @override
  String get asmMate => 'Mate';

  @override
  String get asmAngle => 'Angle';

  @override
  String get asmTangent => 'Tangent';

  @override
  String get asmInsert => 'Insert';

  @override
  String get asmSymmetry => 'Symmetry';

  @override
  String get asmRotation => 'Rotation';

  @override
  String get asmRotationTranslation => 'Rotation-Translation';

  @override
  String get asmTransitional => 'Transitional';

  @override
  String get solMate => 'Mate';

  @override
  String get solFlush => 'Flush';

  @override
  String get solDirectedAngle => 'Directed Angle';

  @override
  String get solUndirectedAngle => 'Undirected Angle';

  @override
  String get solExplicitVector => 'Explicit Reference Vector';

  @override
  String get solInside => 'Inside';

  @override
  String get solOutside => 'Outside';

  @override
  String get solOpposed => 'Opposed';

  @override
  String get solAligned => 'Aligned';

  @override
  String get solSymmetric => 'Symmetric';

  @override
  String get solAsymmetric => 'Asymmetric';

  @override
  String get solForward => 'Forward';

  @override
  String get solReverse => 'Reverse';

  @override
  String get ctxSuppress => 'Suppress';

  @override
  String get ctxUnsuppress => 'Unsuppress';

  @override
  String hudAsmDof(int n) {
    return '$n degrees of freedom';
  }

  @override
  String get hudAsmFullyConstrained => 'Fully constrained';

  @override
  String get msgAsmSameComponent =>
      'Both selections are on the same component.';

  @override
  String get msgAsmPickTwo => 'Select two pieces of geometry first.';

  @override
  String get msgAsmTangentNeedsRound => 'Tangent needs a round face.';

  @override
  String get msgAsmInsertNeedsAxes =>
      'Insert needs two axes or circular edges.';

  @override
  String get msgAsmAngleNeedsDirections => 'Angle needs two directions.';

  @override
  String get msgAsmMotionNeedsAxes => 'Motion needs two axes.';

  @override
  String get msgAsmBothGrounded => 'Both components are grounded.';

  @override
  String get msgAsmMissingComponent =>
      'This relationship\'s component is missing.';

  @override
  String get msgAsmCannotSatisfy => 'This relationship cannot be satisfied.';

  @override
  String get msgAsmCannotConstrain =>
      'These selections cannot be constrained that way.';

  @override
  String msgAsmConstraintDeleted(String name) {
    return '“$name” deleted.';
  }

  @override
  String get hintAsmConstraintSet => 'Not available yet';

  @override
  String msgAsmWouldNest(String name) {
    return '“$name” already contains this assembly.';
  }

  @override
  String get dlgPlaceJoint => 'Place Joint';

  @override
  String get grpAsmConnect => 'Connect';

  @override
  String get lblAsmGap => 'Gap';

  @override
  String get jtAutomatic => 'Automatic';

  @override
  String get jtRigid => 'Rigid';

  @override
  String get jtRotational => 'Rotational';

  @override
  String get jtSlider => 'Slider';

  @override
  String get jtCylindrical => 'Cylindrical';

  @override
  String get jtPlanar => 'Planar';

  @override
  String get jtBall => 'Ball';

  @override
  String hintAsmJointAuto(String type) {
    return 'Automatic: $type';
  }

  @override
  String hintAsmJointDof(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n degrees of freedom left',
      one: 'One degree of freedom left',
      zero: 'No degrees of freedom left',
    );
    return '$_temp0';
  }

  @override
  String get msgAsmJointNeedsDirections => 'This joint needs two directions.';

  @override
  String get hintAsmShowPickComponent =>
      'Select the component whose relationships to show.';

  @override
  String msgAsmNoRelationships(String name) {
    return '“$name” has no relationships.';
  }

  @override
  String get msgAsmNoSickRelationships => 'All relationships are healthy.';

  @override
  String get dlgDrive => 'Drive Constraint';

  @override
  String get ctxDrive => 'Drive';

  @override
  String get lblDriveStart => 'Start';

  @override
  String get lblDriveEnd => 'End';

  @override
  String get lblDrivePause => 'Pause Delay';

  @override
  String get grpDriveIncrement => 'Increment';

  @override
  String get optDriveAmount => 'Amount of value';

  @override
  String get optDriveSteps => 'Total number of steps';

  @override
  String get grpDriveRepetitions => 'Repetitions';

  @override
  String get optDriveOnce => 'Start/End';

  @override
  String get optDriveBoth => 'Start/End/Start';

  @override
  String get lblDriveCycles => 'Cycles';

  @override
  String get cbDriveAdaptivity => 'Drive Adaptivity';

  @override
  String get cbDriveCollision => 'Collision Detection';

  @override
  String get hintDriveUnavailable => 'Not available in this app.';

  @override
  String get msgAsmCannotDrive => 'This relationship cannot be driven.';

  @override
  String get tipDrivePlay => 'Play';

  @override
  String get tipDriveReverse => 'Reverse';

  @override
  String get tipDrivePause => 'Pause';

  @override
  String get tipDriveToStart => 'To Start';

  @override
  String get tipDriveToEnd => 'To End';

  @override
  String get hintAsmFreeMove =>
      'Drag a component — its relationships are overridden.';

  @override
  String get hintAsmFreeRotate =>
      'Select a component, then drag the rotate symbol.';

  @override
  String msgAsmFreePositioned(String name) {
    return '“$name” is outside its relationships — the next update puts it back.';
  }

  @override
  String msgNameTaken(String name) {
    return 'A document named “$name” already exists.';
  }

  @override
  String get hintAsmCreatePickPlane =>
      'Select a plane or planar face to sketch on.';

  @override
  String msgAsmEditSubInPlace(String name) {
    return '“$name” is a subassembly — it cannot be edited in place.';
  }

  @override
  String msgAsmViewRepLocked(String name) {
    return '“$name” is locked.';
  }

  @override
  String get nodeViewReps => 'View';

  @override
  String get nodePositionalReps => 'Position';

  @override
  String get nodeLodReps => 'Level of Detail';

  @override
  String get ctxNewViewRep => 'New Representation';

  @override
  String get ctxActivateViewRep => 'Activate';

  @override
  String get ctxUpdateViewRep => 'Update';

  @override
  String get ctxLockViewRep => 'Lock';

  @override
  String get ctxUnlockViewRep => 'Unlock';

  @override
  String get ctxDeleteViewRep => 'Delete Representation';

  @override
  String get dlgRenameViewRep => 'Rename Representation';

  @override
  String get phViewRepName => 'Representation name';

  @override
  String get dlgCreateComponent => 'Create In-Place Component';

  @override
  String get lblComponentName => 'New Component Name';

  @override
  String get chkConstrainSketchPlane =>
      'Constrain sketch plane to the selected face';

  @override
  String get btnReturn => 'Return';

  @override
  String get panelReturn => 'Finish';

  @override
  String hintInPlaceEditing(String part, String assembly) {
    return 'Editing “$part” in “$assembly”.';
  }

  @override
  String get ctxEditInPlace => 'Edit in Place';

  @override
  String get ctxMakePart => 'Make Part';

  @override
  String get dlgMakePart => 'Make Part';

  @override
  String get lblNewPartName => 'New Part Name';

  @override
  String get lblTargetAssembly => 'Target Assembly';

  @override
  String hintMakePartLink(String name) {
    return 'Stays linked to “$name”.';
  }

  @override
  String msgMadePart(String part, String origin) {
    return '“$part” made from “$origin” and linked to it.';
  }

  @override
  String msgMakePartNoBody(String name) {
    return '“$name” is not built any more.';
  }

  @override
  String msgDerivedEditOrigin(String name) {
    return 'A derived body — opening “$name”.';
  }

  @override
  String get cyclesBadge => 'Cycles';

  @override
  String get rendererRealtime => 'Real-time (RealityKit)';

  @override
  String get rendererRaytraced => 'Ray-traced (Cycles)';

  @override
  String get cyclesPreparing => 'Cycles · preparing kernels';

  @override
  String cyclesSamplesOf(int samples, int target) {
    return 'Cycles · $samples/$target spp';
  }

  @override
  String get cyclesDenoised => 'denoised';

  @override
  String get cyclesFailed => 'Cycles failed';

  @override
  String get cyclesWarmupTitle => 'Preparing renderer';

  @override
  String get cyclesWarmupOnce => 'This happens once per install.';

  @override
  String get cyclesWarmupFailed => 'The renderer could not start';

  @override
  String get lblEndRadius => 'End radius';

  @override
  String lblProfileCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n profiles',
      one: 'One profile',
    );
    return '$_temp0';
  }

  @override
  String lblSectionCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sections',
      one: 'One section',
    );
    return '$_temp0';
  }

  @override
  String lblPointsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n points',
      one: 'One point',
    );
    return '$_temp0';
  }

  @override
  String get hintTapToFinish => '· tap to finish';

  @override
  String get hintTerminationNeedsBody =>
      'To Next, To and Through All need an existing body.';

  @override
  String lblFeatureCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n features',
      one: 'One feature',
    );
    return '$_temp0';
  }

  @override
  String lblSelectedCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n selected',
      one: '1 selected',
      zero: 'nothing selected',
    );
    return '$_temp0';
  }

  @override
  String get lblTotalDistance => 'Distance';

  @override
  String get hintEndRadiusOptional =>
      'Leave the end radius blank for a constant fillet; with a value the radius varies along each edge of the set.';

  @override
  String a11yClearNamed(String name) {
    return 'Clear $name';
  }

  @override
  String a11yRemoveNamed(String name) {
    return 'Remove $name';
  }

  @override
  String get btnCut => 'Cut';

  @override
  String get btnPaste => 'Paste';

  @override
  String get ctxPasteHere => 'Paste Here';

  @override
  String get ctxPasteSketchHere => 'Paste Sketch Here';

  @override
  String get ctxPartFromSketch => 'Create Part from Sketch';

  @override
  String get ctxSketchToDocument => 'Save as 2D Sketch';

  @override
  String get msgSelectThenCopy => 'Select something first, then copy.';

  @override
  String get msgSelectBodyToCopy => 'Select a solid body to copy.';

  @override
  String msgCopiedEntities(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n objects copied',
      one: '1 object copied',
    );
    return '$_temp0';
  }

  @override
  String msgCutEntities(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n objects cut',
      one: '1 object cut',
    );
    return '$_temp0';
  }

  @override
  String msgCopiedSketch(String name) {
    return 'Sketch “$name” copied.';
  }

  @override
  String msgCutSketch(String name) {
    return 'Sketch “$name” cut.';
  }

  @override
  String msgCopiedBody(String name) {
    return 'Solid body “$name” copied.';
  }

  @override
  String msgCutBody(String name) {
    return 'Solid body “$name” cut.';
  }

  @override
  String msgCopiedComponent(String name) {
    return 'Component “$name” copied.';
  }

  @override
  String msgCutComponent(String name) {
    return 'Component “$name” cut.';
  }

  @override
  String msgCopiedDocument(String name) {
    return 'Document “$name” copied.';
  }

  @override
  String msgCopyBodyFailed(String reason) {
    return 'The solid body could not be copied: $reason';
  }

  @override
  String msgNoSuchBody(String name) {
    return 'There is no “$name” in this part.';
  }

  @override
  String get msgClipboardEmpty => 'There is nothing to paste.';

  @override
  String get msgClipboardBodyGone =>
      'The copied body is no longer there — copy it again.';

  @override
  String msgPastedEntities(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n objects pasted',
      one: '1 object pasted',
    );
    return '$_temp0';
  }

  @override
  String msgPastedSketchOnPlane(String name) {
    return 'Sketch “$name” pasted.';
  }

  @override
  String msgPastedSketchDocument(String name) {
    return '2D sketch “$name” created.';
  }

  @override
  String msgPastedBody(String name) {
    return '“$name” pasted as a new solid body.';
  }

  @override
  String msgPastedBodyAsComponent(String name) {
    return '“$name” created and placed in the assembly.';
  }

  @override
  String msgPastedComponent(String name) {
    return '“$name” pasted.';
  }

  @override
  String msgPastedDocument(String name) {
    return '“$name” pasted.';
  }

  @override
  String msgPastedDerived(String name) {
    return 'Derived body from “$name” — linked to its origin.';
  }

  @override
  String msgPasteBodyFailed(String reason) {
    return 'The solid body could not be pasted: $reason';
  }

  @override
  String get msgPasteBodyNotSaved =>
      'The pasted body could not be stored inside the document.';

  @override
  String get msgPasteComponentNeedsAssembly =>
      'A component belongs in an assembly — paste it there.';

  @override
  String get msgAssemblyTakesNoSketch =>
      'An assembly holds components, not sketches.';

  @override
  String get msgCannotPasteHere => 'That cannot be pasted here.';

  @override
  String get msgCannotDeriveFromItself =>
      'A part cannot be derived from itself.';

  @override
  String msgNoBodyIn(String name) {
    return '“$name” has no solid body to derive from.';
  }

  @override
  String msgNoSuchDocument(String name) {
    return '“$name” no longer exists.';
  }

  @override
  String get msgSelectPlaneForPaste =>
      'Tap the plane or face the pasted sketch should sit on.';

  @override
  String msgPasteDroppedExpressions(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$n expressions did not come along — their parameters were not copied.',
      one: 'One expression did not come along — its parameter was not copied.',
    );
    return '$_temp0';
  }

  @override
  String msgPartFromSketch(String part, String sketch) {
    return 'Part “$part” created from sketch “$sketch”.';
  }

  @override
  String msgNotASketch(String name) {
    return '“$name” is not a 2D sketch.';
  }

  @override
  String get msgFinishSketchToPaste =>
      'Finish the sketch first — a solid body belongs to the part, not to a sketch.';

  @override
  String get settingsSamples => 'Render quality';

  @override
  String settingsSamplesRow(int samples) {
    return '$samples samples';
  }

  @override
  String get settingsSamplesFooter =>
      'How long Cycles works on an image before it stops and denoises it. More samples means a cleaner picture and a longer wait; the image is on screen the whole time and improves sample by sample.';

  @override
  String get settingsRibbonNames => 'Display names';

  @override
  String get settingsRibbonNamesFooter =>
      'Without names the band is much thinner; every command keeps its name as a tooltip.';
}
