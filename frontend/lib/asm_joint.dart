// M249 — Inventor's ASSEMBLE > JOINT, as a model.
//
// The same seam asm_constraints.dart sits on: this file holds what a joint IS
// — its types, the frame a pick reduces to, and which freedoms each type
// leaves — and holds no solver (asm_solver.dart), no UI
// (widgets/joint_dialog.dart) and no picking (asm_pick.dart).
//
// ---------------------------------------------------------------------------
// What Inventor actually does (researched 2026-08-25)
// ---------------------------------------------------------------------------
//
// ESTABLISHED. help.autodesk.com and knowledge.autodesk.com are blocked by the
// network egress proxy in the environment this was written in, so the wording
// below is quoted from search-result summaries of "Create Joints Reference"
// (GUID-6AA68E8F) and "To Define and Manage Joint Relationships"
// (GUID-21DC3336) rather than from the pages themselves. Every line marked
// ESTABLISHED appeared in more than one summary, in the same words.
//
// The Place Joint dialog's Type list has SEVEN entries, not six:
//
//   Automatic     the default. "Automatic determines the joint type based on
//                 the following rules: Rotational is selected if the two
//                 selected origins are circular. Cylindrical is selected if
//                 the two selected origins are points on a cylinder. Ball is
//                 selected if the two selected origins are points on a sphere.
//                 Rigid is selected for all other origin selections."
//   Rigid         "positions a component and removes all degrees of freedom.
//                 Used for components that do not move; welded and bolted
//                 joints are examples."                       0 DOF
//   Rotational    "specifies one rotational degree of freedom."
//                                                             1 rotational
//   Slider        "positions a component and specifies one translational
//                 degree of freedom. A slide block moving in a track is an
//                 example."                                   1 translational
//   Cylindrical   "specifies one translational and one rotational degree of
//                 freedom. A shaft in a hole is an example."  1 + 1
//   Planar        "specifies two translational and one rotational degree of
//                 freedom perpendicular to the linear. Use this joint to place
//                 a component on a planar face. The component can rotate or
//                 slide on the plane."                        2 + 1
//   Ball          "specifies three rotational degrees of freedom. A ball and
//                 socket joint is an example."                3 rotational
//
// Note that Slider and Planar are absent from the Automatic rule list. That is
// not an omission in the summary: Automatic names four outcomes and those two
// are not among them, so they are only ever chosen by hand.
//
// ESTABLISHED — the JOINT ORIGIN is a point, and it snaps:
//
//   "You can select endpoints, midpoints and center points to create
//   relationships. Hovering the cursor around the entity activates the
//   required Joint Origin shown by the green dot glyph."
//   "When a rectangular face is selected, the active point can be on any of
//   the corners, on the midpoints of any edge, or at the center point of the
//   face. The location of the cursor when selecting defines which point is
//   assigned."
//   "When a straight edge is selected, the active point can be on either end
//   or at the center point of the edge."
//   "When spherical geometry is selected, the active point is at the center of
//   the geometry."
//
// ESTABLISHED — the rest of the dialog: a Connect area holding the two origin
// pickers and a GAP value ("a Gap value provides the flexibility of joining
// the reference points at an offset"); an Align area whose "Alignment
// references are automatically selected based on the First and Second Origin
// references"; an Animate section that plays the joint's motion once both
// origins are defined; and a LIMITS tab with Angular and Linear Start /
// Current / End values, where "the availability of the Angular or Linear
// options depends on the joint type ... limits are not available for Rigid
// joints".
//
// INFERRED, and stated as such: Autodesk never publishes which constraints a
// joint is equivalent to, and there is a good reason for that — a joint is not
// a bundle of constraints in Inventor either, it is one relationship with its
// own degrees of freedom. The DOF counts above are the specification, and the
// residual family below is this app's reading of them.
//
// ---------------------------------------------------------------------------
// THE REPRESENTATION, and why it is not an expansion into constraints
// ---------------------------------------------------------------------------
//
// Two ways to build this were open. A joint could EXPAND into ordinary
// AsmConstraints when it is created — a rotational joint becomes an Insert, a
// cylindrical joint becomes a Mate between two axes — which needs no solver
// code at all. Or a joint can be its own residual family.
//
// This is the second, for three reasons that are all the same reason:
//
//   * A JOINT ORIGIN IS A POINT, AND A CONSTRAINT'S IS NOT. Mate on two planes
//     says "these planes are coincident" and is completely indifferent to
//     WHERE on them you tapped — any point on a plane defines it, and
//     asm_solver._mate is right to use the kernel's own. A joint says "this
//     point on this face meets that point on that face". Expanding a joint
//     into constraints would have to throw the origin away and then invent
//     two more constraints to put it back, and the two extra would be
//     constraints the user never asked for and cannot see the reason for.
//
//   * THE EXPANSION IS NOT UNIFORM. Rotational happens to be Insert and
//     Cylindrical happens to be Mate-on-two-axes, but Slider and Rigid are two
//     and three constraints respectively, and Planar's "2 translational and 1
//     rotational" has no single constraint at all. A representation that is
//     one row for three types and three rows for another is not a
//     representation, it is a coincidence.
//
//   * THE BROWSER WOULD LIE. Inventor lists a joint as ONE relationship named
//     "Rotational:1", and deleting it deletes the joint. Three rows named
//     "Mate:4", "Mate:5", "Angle:2" are not that, and no amount of grouping in
//     the browser would make them behave like it under Suppress or Edit.
//
// What the family costs is small, because it is ONE parameterised residual
// with four switchable blocks — see [JointLocks] — and it is written that way
// because the six types differ only in which blocks they emit. That is also
// what makes the DOF claim above a TESTABLE assertion rather than a comment:
// AsmSolveReport.dof is 6·bodies minus the rank of the real Jacobian, so
// "a rotational joint leaves exactly one" is an expectation a test can write,
// and m249_joint_test.dart writes all six.
//
// A joint is nonetheless an [AsmConstraint] — six new [AsmKind] values, not a
// second document type. asm_constraints.dart's own header says why: everything
// outside the solver treats a relationship alike (a row in the Relationships
// folder, saved together, named in one sequence, suppressed and deleted the
// same way), and that is exactly as true of a joint as of a mate.
//
// ---------------------------------------------------------------------------
// THE FRAME: Z IS THE JOINT AXIS, IN ALL SIX TYPES
// ---------------------------------------------------------------------------
//
// Each pick reduces to an origin, an axis and a reference direction — see
// [AsmJointFrame]. The origin is [AsmRef.anchor], which M244 already records
// as the middle of what was picked (a face's centre, a circular edge's centre,
// an edge's midpoint); the axis is the plane's normal or the axis's direction.
//
// Every type is then stated against that one axis:
//
//   Rigid        axis aligned, origins together, twist held        0 DOF
//   Rotational   axis aligned, origins together                    1 rot  (z)
//   Slider       axis aligned, origins together ACROSS z, twist    1 trans(z)
//   Cylindrical  axis aligned, origins together ACROSS z           1 + 1  (z)
//   Planar       axis aligned, origins together ALONG z            2 + 1
//   Ball         origins together                                  3 rot
//
// ---------------------------------------------------------------------------
// Honest scope note
// ---------------------------------------------------------------------------
//
// Four deliberate differences from Inventor, none of them hidden by the UI:
//
//   * ORIGIN SNAPPING IS COARSER. asm_pick reduces a tap to a face centre, a
//     circle centre or an edge midpoint (M244) — which is three of Inventor's
//     snaps and the three that matter. A face CORNER and an edge END are not
//     offered, because the pick records one anchor per face rather than a
//     cursor-dependent one. Pointing at a corner therefore gives the centre.
//
//   * SLIDER SLIDES ALONG ITS OWN Z, so it is made by pointing at what the
//     component slides ALONG — an edge, a shaft — rather than at the face it
//     slides ON. Inventor takes the direction from its Align references, which
//     this has no equivalent of; taking it from the axis is the reading that
//     needs no third pick and never leaves the direction ambiguous.
//
//   * ALIGN IS DERIVED, NEVER PICKED. Rigid and Slider have to hold the
//     rotation about z, and Inventor holds it against Align 1 / Align 2. Here
//     the twist is CAPTURED at creation from where the two components already
//     are, which is the same thing "Predict Offset and Orientation" does for a
//     constraint's offset: the joint holds the parts as they are rather than
//     snapping them to an alignment nobody asked for. See [AsmConstraint.twist].
//
//   * LIMITS ARE NOT BUILT. Inventor's Limits tab bounds a joint's remaining
//     freedom, which needs the solver to grow inequality residuals; this
//     solver has only equalities. A joint here has its freedom or it does not.
import 'dart:math' as math;

import 'asm_constraints.dart';
import 'part_model.dart';
import 'quat.dart' show Placement;
import 'work_features.dart' show WorkRefSource;

/// The Type list of the Place Joint dialog, in Inventor's own order.
///
/// [automatic] is a dialog choice and never a stored one: it RESOLVES to one
/// of the other six when the joint is created (see [resolveAutomaticJoint]),
/// exactly as Inventor's does. That is why the stored types are [AsmKind]
/// values and this enum is not — a document must never have to be read by
/// something that would then have to re-run the inference to know what the
/// joint does.
enum AsmJointType { automatic, rigid, rotational, slider, cylindrical, planar, ball }

/// The stored [AsmKind] a dialog type names, or null for [AsmJointType.automatic].
AsmKind? jointKindOf(AsmJointType t) => switch (t) {
      AsmJointType.automatic => null,
      AsmJointType.rigid => AsmKind.jointRigid,
      AsmJointType.rotational => AsmKind.jointRotational,
      AsmJointType.slider => AsmKind.jointSlider,
      AsmJointType.cylindrical => AsmKind.jointCylindrical,
      AsmJointType.planar => AsmKind.jointPlanar,
      AsmJointType.ball => AsmKind.jointBall,
    };

/// The dialog type a stored kind is, for re-opening the dialog on an existing
/// joint. Never [AsmJointType.automatic] — see [jointKindOf].
AsmJointType jointTypeOf(AsmKind k) => switch (k) {
      AsmKind.jointRigid => AsmJointType.rigid,
      AsmKind.jointRotational => AsmJointType.rotational,
      AsmKind.jointSlider => AsmJointType.slider,
      AsmKind.jointCylindrical => AsmJointType.cylindrical,
      AsmKind.jointPlanar => AsmJointType.planar,
      _ => AsmJointType.ball,
    };

/// Which of the four residual blocks a joint type emits.
///
/// This IS the joint family: the six types differ in nothing else, and the
/// degrees of freedom each one claims are 6 minus the ranks below. Written as
/// data rather than as a switch inside the solver so that the DOF table and
/// the equations cannot drift apart — [jointDof] counts the same fields the
/// solver reads.
class JointLocks {
  const JointLocks({
    required this.axis,
    required this.along,
    required this.perp,
    required this.twist,
  });

  /// The second frame's axis lies along the first's (or against it, for the
  /// opposed solution). Rank 2 — a direction has two degrees of freedom.
  final bool axis;

  /// The origins are separated along the axis by exactly the GAP. Rank 1.
  final bool along;

  /// The origins are not separated ACROSS the axis at all. Rank 2.
  final bool perp;

  /// The rotation about the axis is held where creation found it. Rank 1.
  /// See [AsmConstraint.twist] for why it is captured rather than picked.
  final bool twist;

  /// How many independent freedoms these blocks remove.
  int get rank => (axis ? 2 : 0) + (along ? 1 : 0) + (perp ? 2 : 0) +
      (twist ? 1 : 0);
}

/// The locks each joint type applies. The table the milestone is about.
JointLocks jointLocks(AsmKind k) => switch (k) {
      AsmKind.jointRigid => const JointLocks(
          axis: true, along: true, perp: true, twist: true),
      AsmKind.jointRotational => const JointLocks(
          axis: true, along: true, perp: true, twist: false),
      AsmKind.jointSlider => const JointLocks(
          axis: true, along: false, perp: true, twist: true),
      AsmKind.jointCylindrical => const JointLocks(
          axis: true, along: false, perp: true, twist: false),
      AsmKind.jointPlanar => const JointLocks(
          axis: true, along: true, perp: false, twist: false),
      // Ball holds the origins together and nothing else. It is the one type
      // with no axis term, which is what leaves all three rotations open.
      AsmKind.jointBall => const JointLocks(
          axis: false, along: true, perp: true, twist: false),
      // Not a joint. An empty lock set emits nothing, which is the honest
      // answer for a caller that asked the wrong question.
      _ => const JointLocks(
          axis: false, along: false, perp: false, twist: false),
    };

/// How many degrees of freedom [k] leaves the jointed component.
///
/// Inventor's own numbers — 0, 1, 1, 2, 3, 3 — and this is where they are
/// asserted against the solver rather than described: with one grounded body
/// and one free one, [AsmSolveReport.dof] must come back exactly this.
int jointDof(AsmKind k) => 6 - jointLocks(k).rank;

/// Every joint kind, in the dialog's order.
const List<AsmKind> kJointKinds = [
  AsmKind.jointRigid,
  AsmKind.jointRotational,
  AsmKind.jointSlider,
  AsmKind.jointCylindrical,
  AsmKind.jointPlanar,
  AsmKind.jointBall,
];

// ---------------------------------------------------------------------------
// the frame a pick reduces to
// ---------------------------------------------------------------------------

/// A joint origin: a point, an axis through it, and a reference direction
/// across it.
///
/// The difference from an [AsmGeom] is the POINT, and it is the whole
/// difference between a joint and a constraint. A plane's own `at` is whatever
/// OCCT chose for it — very often the sketch origin, far from the face (see
/// [AsmRef.anchor]) — and a constraint may use it because any point on a plane
/// defines that plane. A joint may not: "these two faces meet HERE" is what
/// the user pointed at, so the origin comes from the anchor.
class AsmJointFrame {
  const AsmJointFrame(this.origin, this.axis, this.ref);

  /// Where the joint is, in whichever frame the caller supplied.
  final Vec3 origin;

  /// The joint's Z. Unit, or zero when the pick offered no direction (a
  /// vertex, a sphere centre) — [hasAxis] says which.
  final Vec3 axis;

  /// A unit direction ACROSS [axis], for measuring the twist. Arbitrary but
  /// DETERMINISTIC: it is derived from the axis alone, so the same pick always
  /// produces the same reference and a captured twist keeps meaning the same
  /// angle across a save and a reload.
  final Vec3 ref;

  bool get hasAxis => axis.length > 0.5;

  /// The same frame under a placement — the step from a component's own
  /// coordinates to the world's.
  ///
  /// A frame is ALWAYS built in the component's own frame and then placed,
  /// never built from world geometry directly, and that is not a stylistic
  /// preference: [ref] is derived from the axis by [jointRefDir], whose choice
  /// of seed direction JUMPS as the axis swings past the diagonal. Derived
  /// from a world axis it would therefore jump mid-solve, and the twist
  /// residual measured against it would be discontinuous — a step change in a
  /// residual is a Jacobian that lies, and Levenberg-Marquardt would chase it
  /// for ever. Derived in the component's own frame it is a constant that the
  /// placement simply carries, and the twist is a smooth function of the pose.
  AsmJointFrame placed(Placement at) => AsmJointFrame(
      at.apply(origin), at.applyDir(axis), at.applyDir(ref));
}

/// The frame a reference's geometry and anchor stand for.
///
/// [anchor] and [geom] must be in the SAME coordinates — both local, or both
/// world. The result is in those coordinates too.
///
/// For a plane the origin is the anchor PROJECTED onto the plane, so a joint
/// made by pointing at a face sits exactly on that face however far the
/// kernel's reference point is from it. For an axis it is the anchor projected
/// onto the axis, which for a circular edge is its centre and for a cylinder
/// is the point on the axis level with the band that was touched.
AsmJointFrame jointFrameOf(AsmGeom geom, Vec3 anchor) {
  final d = geom.dir.length < 1e-9 ? Vec3.zero : geom.dir.normalized();
  if (d.length < 0.5) return AsmJointFrame(anchor, Vec3.zero, Vec3.zero);
  final origin = switch (geom.kind) {
    AsmGeomKind.plane => anchor - d * ((anchor - geom.at).dot(d)),
    AsmGeomKind.axis => geom.at + d * ((anchor - geom.at).dot(d)),
    AsmGeomKind.point => anchor,
  };
  return AsmJointFrame(origin, d, jointRefDir(d));
}

/// A unit direction across [axis], chosen the same way every time.
///
/// The same rule asm_pick's marker uses to build a patch on a plane: cross
/// with whichever world axis the direction leans on least, which is the only
/// choice that never produces a near-zero cross product. Deterministic matters
/// here more than elsewhere — a captured twist is an angle measured FROM this
/// direction, so a reference that varied would make a reloaded joint hold a
/// different pose than the one that was saved.
///
/// Deterministic is NOT continuous, and the difference is why every caller
/// must pass a LOCAL axis: the seed swaps as the axis crosses a diagonal, so
/// this direction jumps. See [AsmJointFrame.placed].
Vec3 jointRefDir(Vec3 axis) {
  final v = axis.normalized();
  if (v.length < 0.5) return Vec3.zero;
  final ax = v.x.abs(), ay = v.y.abs(), az = v.z.abs();
  final other = (ax <= ay && ax <= az)
      ? const Vec3(1, 0, 0)
      : (ay <= az ? const Vec3(0, 1, 0) : const Vec3(0, 0, 1));
  return v.cross(other).normalized();
}

/// The signed angle from [a] to [b] about [axis], in radians, in (-pi, pi].
///
/// Both directions are re-orthogonalised against the axis first. Without that
/// a reference that has drifted out of the plane — which it does the moment
/// the two axes are not yet aligned — measures an angle that is not a rotation
/// about anything.
double jointTwistBetween(Vec3 a, Vec3 b, Vec3 axis) {
  final z = axis.normalized();
  if (z.length < 0.5) return 0;
  Vec3 flat(Vec3 v) {
    final p = v - z * v.dot(z);
    return p.length < 1e-9 ? Vec3.zero : p.normalized();
  }

  final u = flat(a), w = flat(b);
  if (u.length < 0.5 || w.length < 0.5) return 0;
  return math.atan2(u.cross(w).dot(z), u.dot(w));
}

// ---------------------------------------------------------------------------
// Automatic
// ---------------------------------------------------------------------------

/// Which joint type Inventor's Automatic would choose for this pair.
///
/// The rule is the documented one, in the documented order — see the header:
/// circular origins give Rotational, points on a cylinder give Cylindrical,
/// points on a sphere give Ball, and everything else gives Rigid. BOTH origins
/// have to agree; a circular edge against a flat face is "all other origin
/// selections", which is Rigid.
AsmKind resolveAutomaticJoint(AsmGeom a, AsmGeom b) {
  if (_isCircular(a) && _isCircular(b)) return AsmKind.jointRotational;
  if (_isCylinder(a) && _isCylinder(b)) return AsmKind.jointCylindrical;
  if (_isSphere(a) && _isSphere(b)) return AsmKind.jointBall;
  return AsmKind.jointRigid;
}

/// A circular or elliptical EDGE — the thing you point at to hinge two parts.
///
/// [AsmGeom.source] is what tells it from a cylindrical face: both reduce to
/// an axis with a radius, and M247 put the pick's own kind alongside the
/// reduction for exactly this class of question. A reference written before
/// that carries no source, and an axis with a radius is far more often a
/// circle than anything else, so that is what it reads as.
bool _isCircular(AsmGeom g) =>
    g.source == WorkRefSource.circle ||
    (g.source == null && g.isAxis && g.radius > 1e-9);

bool _isCylinder(AsmGeom g) =>
    g.source == WorkRefSource.revolved && g.radius > 1e-9;

bool _isSphere(AsmGeom g) => g.source == WorkRefSource.sphere;
