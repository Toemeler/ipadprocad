// M234 — domain value to display string.
//
// part_model.dart keeps its English `typeLabel`, `holeTypeLabel` and
// `patternKindLabel`, and it keeps `patternTypeLabel`/`holeTypeName`, which
// are the strings that go INTO a .ptp. Nothing there changes. What changes is
// who decides how a value is spelt on screen, and that decision belongs here.
//
// The distinction is not pedantry. `holeTypeLabel(t).toLowerCase()` was
// correct English and is wrong German — nouns are capitalised — so a
// lower-casing call at the point of use is a grammar bug the moment a second
// language exists. Both spellings live in the ARB instead, one key each.
import '../asm_constraints.dart' show AsmKind, AsmSolution;
import '../asm_joint.dart' show AsmJointType, jointTypeOf;
import '../part_model.dart'
    show FaceEditKind, FeatureExtent, HoleType, PartFeature, PatternKind;
import 'l.dart';

/// The command name of a direct-edit / delete-face session.
String faceEditName(AppL10n t, FaceEditKind k) => switch (k) {
      FaceEditKind.delete => t.cmdDeleteFace,
      FaceEditKind.move => t.cmdMoveFaces,
      FaceEditKind.size => t.cmdSizeFaces,
      FaceEditKind.scale => t.cmdScaleBody,
    };

/// The verb in "Select the faces to …" / "Flächen zum … wählen."
///
/// Capitalised in German (it is a noun there), lower case in English. Not a
/// `toLowerCase()` on a shared string, for exactly that reason.
String faceEditVerb(AppL10n t, FaceEditKind k) =>
    k == FaceEditKind.delete ? t.verbDelete : t.verbMove;

/// Inventor's name for a pattern kind.
String patternKindDisplay(AppL10n t, PatternKind k) => switch (k) {
      PatternKind.rectangular => t.patRectangular,
      PatternKind.circular => t.patCircular,
      PatternKind.sketchDriven => t.patSketchDriven,
      PatternKind.mirror => t.patMirror,
    };

/// A hole type, spelt out.
String holeTypeDisplay(AppL10n t, HoleType h) => switch (h) {
      HoleType.simple => t.holeSimple,
      HoleType.counterbore => t.holeCounterbore,
      HoleType.spotface => t.holeSpotface,
      HoleType.countersink => t.holeCountersink,
    };

/// A hole type on the panel's four-way switch — short enough for a segment.
String holeTypeShortDisplay(AppL10n t, HoleType h) => switch (h) {
      HoleType.simple => t.holeSimpleShort,
      HoleType.counterbore => t.holeCounterboreShort,
      HoleType.spotface => t.holeSpotfaceShort,
      HoleType.countersink => t.holeCountersinkShort,
    };

/// What the browser and the error toasts call a feature's KIND.
///
/// Keyed off the model's own English `typeLabel`, which is a stable domain
/// value: adding a feature type without a German name here falls back to that
/// value rather than to an empty row, and l10n_completeness_test.dart is what
/// catches the omission.
String featureTypeName(AppL10n t, PartFeature f) => switch (f.typeLabel) {
      'Extrusion' => t.featExtrusion,
      'Revolution' => t.featRevolution,
      'Sweep' => t.featSweep,
      'Loft' => t.featLoft,
      'Coil' => t.featCoil,
      'Fillet' => t.featFillet,
      'Chamfer' => t.featChamfer,
      'Hole' => t.featHole,
      'Split' => t.featSplit,
      'Combine' => t.featCombine,
      'Delete Face' => t.featDeleteFace,
      'Rectangular Pattern' => t.patRectangular,
      'Circular Pattern' => t.patCircular,
      'Sketch Driven Pattern' => t.patSketchDriven,
      'Mirror' => t.patMirror,
      _ => f.typeLabel,
    };

/// Inventor's four extent (termination) options for extrude and revolve.
String extentName(AppL10n t, FeatureExtent e) => switch (e) {
      FeatureExtent.toNext => t.extToNext,
      FeatureExtent.toFace => t.extToFace,
      FeatureExtent.throughAll => t.extThroughAll,
      FeatureExtent.distance => t.extDistance,
    };

// ---------------------------------------------------------------------------
// M242 — assembly relationships
// ---------------------------------------------------------------------------

/// The localised name of a constraint TYPE. Top-level so the browser and the
/// dialog cannot disagree about what to call one.
String constraintLabel(AppL10n t, AsmKind k) => switch (k) {
      AsmKind.mate => t.asmMate,
      AsmKind.angle => t.asmAngle,
      AsmKind.tangent => t.conTangent,
      AsmKind.insert => t.asmInsert,
      AsmKind.symmetry => t.asmSymmetry,
      AsmKind.rotation => t.asmRotation,
      AsmKind.rotationTranslation => t.asmRotationTranslation,
      AsmKind.transitional => t.asmTransitional,
      // M249 — a joint is named after its TYPE everywhere it is shown, so the
      // one function that spells a relationship spells these too. Routed
      // through the joint-type label rather than repeating the seven strings,
      // because the dialog's Type list and the browser's tooltip must never be
      // able to call one joint two things.
      _ => jointTypeLabel(t, jointTypeOf(k)),
    };

/// M249 — the localised name of a JOINT TYPE, as the Place Joint dialog's Type
/// list spells it.
String jointTypeLabel(AppL10n t, AsmJointType j) => switch (j) {
      AsmJointType.automatic => t.jtAutomatic,
      AsmJointType.rigid => t.jtRigid,
      AsmJointType.rotational => t.jtRotational,
      AsmJointType.slider => t.jtSlider,
      AsmJointType.cylindrical => t.jtCylindrical,
      AsmJointType.planar => t.jtPlanar,
      AsmJointType.ball => t.jtBall,
    };

/// The localised name of a SOLUTION.
String solutionLabel(AppL10n t, AsmSolution s) => switch (s) {
      AsmSolution.mate => t.solMate,
      AsmSolution.flush => t.solFlush,
      AsmSolution.directedAngle => t.solDirectedAngle,
      AsmSolution.undirectedAngle => t.solUndirectedAngle,
      AsmSolution.explicitVector => t.solExplicitVector,
      AsmSolution.inside => t.solInside,
      AsmSolution.outside => t.solOutside,
      AsmSolution.opposed => t.solOpposed,
      AsmSolution.aligned => t.solAligned,
      AsmSolution.symmetric => t.solSymmetric,
      AsmSolution.asymmetric => t.solAsymmetric,
      AsmSolution.forward => t.solForward,
      AsmSolution.reverse => t.solReverse,
      AsmSolution.none => t.asmTransitional,
    };
