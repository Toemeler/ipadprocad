// M215 — Work Axis and Work Point: the geometry, and nothing else.
//
// Deliberately free of Flutter, AppState and the kernel, for the same reason
// part_pick.dart is: deciding WHERE a work axis goes is arithmetic, and
// arithmetic should be testable without a device, a camera or a widget tree.
// The viewport supplies picks, this file decides what they mean, app_state
// commits the answer.
//
// ---------------------------------------------------------------------------
// What Inventor actually does (researched against the Autodesk help, 2026-08)
// ---------------------------------------------------------------------------
//
// Work Axis has eight documented creation methods:
//   Axis (legacy)                          pick geometry in any order, inferred
//   On Line or Edge                        one linear edge or sketch line
//   Parallel to Line through Point         a point, then a line
//   Through Two Points                     two points; +ve runs first -> second
//   Intersection of Two Planes             two NON-parallel planes/planar faces
//   Normal to Plane through Point          a plane and a point
//   Through Center of Circular or
//     Elliptical Edge                      one circular/elliptical/fillet edge
//   Through Revolved Face or Feature       a revolved face (cylinder, cone)
//
// Work Point has nine:
//   Point (legacy)                         inferred, as above
//   Grounded Point                         a point fixed in space
//   On Vertex, Sketch Point, or Midpoint   one point
//   Intersection of Three Planes           three planes/planar faces
//   Intersection of Two Lines              two lines (edge, axis, sketch)
//   Intersection of Plane/Surface and Line a plane and a line
//   Center Point of Loop of Edges          one closed loop (circular edge)
//   Center Point of Torus                  a torus face
//   Center Point of Sphere                 a sphere face
//
// The two LEGACY entries are the ones people actually use, and they are the
// reason this file is built the way it is: the command does not ask which
// method you want, it works it out from what you touched. The named entries
// exist for the cases where a pick is ambiguous and you have to say.
//
// ---------------------------------------------------------------------------
// Honest scope note
// ---------------------------------------------------------------------------
//
// Inventor's work features are PARAMETRIC — move the face and the axis follows.
// This app's WorkPlane has never been (it bakes its frame at creation; M162
// added a stored base/offset so that ONE number stays editable, which is the
// exception that shows the rule). Axes and points here bake the same way, and
// say so in the browser rather than implying a link that does not exist.
// Making all three parametric is a real feature, not a footnote to this one.
import 'dart:math' as math;

import 'part_model.dart' show Vec3;

/// Everything a picked entity can CONTRIBUTE to a work feature.
///
/// The insight that makes the inference tractable: a pick is not "a face" or
/// "an edge", it is the set of geometric primitives it can stand in for. A
/// circular edge is a point (its centre) AND a line (its axis) AND a plane
/// (the plane it lies in) all at once, and which one matters depends entirely
/// on what else was picked. Modelling picks by their TYPE would need a case
/// per pair of types; modelling them by what they OFFER needs one case per
/// Inventor method, which is the list above.
class WorkRef {
  /// How the browser and the toast should call this pick — "XY Plane",
  /// "Edge", "Work Point1". Used to build the `def` sentence.
  final String label;

  /// The point this pick contributes, or null.
  final Vec3? point;

  /// A point on the line this pick contributes, and its UNIT direction.
  /// Both null or both set.
  final Vec3? lineAt;
  final Vec3? lineDir;

  /// A point on the plane this pick contributes, and its UNIT normal.
  final Vec3? planeAt;
  final Vec3? planeNormal;

  /// True when this pick came from a circular/elliptical edge, a cylinder, a
  /// cone, a sphere or a torus. Only used to pick the right Inventor wording
  /// for `def` — the geometry is already in the fields above.
  final WorkRefSource source;

  /// M224 — the radius of a cylindrical face, and WHERE ON IT the ray landed.
  ///
  /// The one thing a pick knows that its contributions do not: where the
  /// finger was. Everything else in this class is deliberately about what a
  /// pick can STAND IN FOR, and that is what makes the inference tractable —
  /// but a tangent plane genuinely needs more than the cylinder's geometry.
  /// There are two tangent planes through any point outside a cylinder, and
  /// Inventor picks between them by the side you clicked. Without this a
  /// tangent plane lands on the far side of the part half the time, which is
  /// exactly why M223 refused to build one.
  final double? radius;
  final Vec3? hitAt;

  const WorkRef._({
    required this.label,
    required this.source,
    this.point,
    this.lineAt,
    this.lineDir,
    this.planeAt,
    this.planeNormal,
    this.radius,
    this.hitAt,
  });

  /// A vertex, an edge midpoint, a sketch point, the origin centre point, or
  /// an existing work point.
  factory WorkRef.point(String label, Vec3 p,
          {WorkRefSource source = WorkRefSource.vertex}) =>
      WorkRef._(label: label, source: source, point: p);

  /// A linear edge, an origin axis, an existing work axis, a sketch line.
  ///
  /// [a] and [b] are the ENDS when the line is finite (a real edge); the
  /// midpoint is then also offered as a point, which is what makes Inventor's
  /// "On Vertex, Sketch Point, or Midpoint" reachable by pointing at an edge.
  /// Pass [midpoint] false for an infinite axis, which has no middle.
  factory WorkRef.line(String label, Vec3 a, Vec3 b,
      {bool midpoint = true, WorkRefSource source = WorkRefSource.edge}) {
    final d = (b - a).normalized();
    return WorkRef._(
      label: label,
      source: source,
      lineAt: a,
      lineDir: d,
      point: midpoint ? (a + b) * 0.5 : null,
    );
  }

  /// An infinite line given as a point and a direction (an origin axis, a
  /// cylinder's axis of revolution, an existing work axis).
  factory WorkRef.axis(String label, Vec3 at, Vec3 dir,
          {WorkRefSource source = WorkRefSource.axis}) =>
      WorkRef._(
          label: label,
          source: source,
          lineAt: at,
          lineDir: dir.normalized());

  /// A planar face, an origin plane, or an existing work plane.
  factory WorkRef.plane(String label, Vec3 at, Vec3 normal,
          {WorkRefSource source = WorkRefSource.plane}) =>
      WorkRef._(
          label: label,
          source: source,
          planeAt: at,
          planeNormal: normal.normalized());

  /// A circular or elliptical edge: centre, axis and plane in one pick.
  ///
  /// All three, because Inventor reaches all three through it — the centre is
  /// "Center Point of Loop of Edges", the axis is "Through Center of Circular
  /// Edge", and the plane is a perfectly good input to "Intersection of Two
  /// Planes". Offering only one of them would make the other two unreachable
  /// from the geometry that most obviously carries them.
  factory WorkRef.circle(String label, Vec3 centre, Vec3 axis) {
    final n = axis.normalized();
    return WorkRef._(
      label: label,
      source: WorkRefSource.circle,
      point: centre,
      lineAt: centre,
      lineDir: n,
      planeAt: centre,
      planeNormal: n,
    );
  }

  /// A face of revolution (cylinder or cone): contributes its axis only.
  /// A cylinder has no meaningful single point, and Inventor has no work
  /// point method that takes one — so it offers none rather than inventing
  /// the arbitrary point on the axis that the kernel happens to store.
  factory WorkRef.revolvedFace(String label, Vec3 axisAt, Vec3 axisDir) =>
      WorkRef._(
          label: label,
          source: WorkRefSource.revolved,
          lineAt: axisAt,
          lineDir: axisDir.normalized());

  /// M224 — a CYLINDRICAL face: its axis, as [revolvedFace] gives, plus the
  /// radius and the point the ray hit. Source stays [WorkRefSource.revolved]
  /// so every method that already accepts a revolved face keeps accepting it.
  factory WorkRef.cylinder(String label, Vec3 axisAt, Vec3 axisDir,
          {required double radius, Vec3? hitAt}) =>
      WorkRef._(
        label: label,
        source: WorkRefSource.revolved,
        lineAt: axisAt,
        lineDir: axisDir.normalized(),
        radius: radius,
        hitAt: hitAt,
      );

  /// A spherical face: its centre.
  factory WorkRef.sphere(String label, Vec3 centre) => WorkRef._(
      label: label, source: WorkRefSource.sphere, point: centre);

  /// A toroidal face: its centre and its axis.
  factory WorkRef.torus(String label, Vec3 centre, Vec3 axis) => WorkRef._(
        label: label,
        source: WorkRefSource.torus,
        point: centre,
        lineAt: centre,
        lineDir: axis.normalized(),
      );

  bool get hasPoint => point != null;
  bool get hasLine => lineAt != null && lineDir != null;
  bool get hasPlane => planeAt != null && planeNormal != null;

  /// Signed plane constant, i.e. `normal . x = planeD` for every x on it.
  double get planeD => planeAt!.dot(planeNormal!);
}

/// Where a [WorkRef] came from. Chooses Inventor's wording for `def`; never
/// affects the arithmetic.
enum WorkRefSource {
  vertex,
  edge,
  axis,
  plane,
  circle,
  revolved,
  sphere,
  torus
}

/// Inventor's Work Axis creation methods. [auto] is the legacy "Axis" entry —
/// pick geometry and it works out which of the others you meant.
enum WorkAxisMethod {
  auto,
  onLineOrEdge,
  parallelToLineThroughPoint,
  throughTwoPoints,
  intersectionOfTwoPlanes,
  normalToPlaneThroughPoint,
  throughCenterOfCircularEdge,
  throughRevolvedFace,
}

/// Inventor's Work Point creation methods. [auto] is the legacy "Point" entry.
enum WorkPointMethod {
  auto,
  grounded,
  onVertex,
  intersectionOfThreePlanes,
  intersectionOfTwoLines,
  intersectionOfPlaneAndLine,
  centerOfLoop,
  centerOfTorus,
  centerOfSphere,
}

/// Menu label, exactly as Inventor writes it. The ribbon shows these, so a
/// user who knows Inventor finds the entry they are looking for by name.
String workAxisMethodLabel(WorkAxisMethod m) {
  switch (m) {
    case WorkAxisMethod.auto:
      return 'Axis';
    case WorkAxisMethod.onLineOrEdge:
      return 'On Line or Edge';
    case WorkAxisMethod.parallelToLineThroughPoint:
      return 'Parallel to Line through Point';
    case WorkAxisMethod.throughTwoPoints:
      return 'Through Two Points';
    case WorkAxisMethod.intersectionOfTwoPlanes:
      return 'Intersection of Two Planes';
    case WorkAxisMethod.normalToPlaneThroughPoint:
      return 'Normal to Plane through Point';
    case WorkAxisMethod.throughCenterOfCircularEdge:
      return 'Through Center of Circular or Elliptical Edge';
    case WorkAxisMethod.throughRevolvedFace:
      return 'Through Revolved Face or Feature';
  }
}

String workPointMethodLabel(WorkPointMethod m) {
  switch (m) {
    case WorkPointMethod.auto:
      return 'Point';
    case WorkPointMethod.grounded:
      return 'Grounded Point';
    case WorkPointMethod.onVertex:
      return 'On Vertex, Sketch Point, or Midpoint';
    case WorkPointMethod.intersectionOfThreePlanes:
      return 'Intersection of Three Planes';
    case WorkPointMethod.intersectionOfTwoLines:
      return 'Intersection of Two Lines';
    case WorkPointMethod.intersectionOfPlaneAndLine:
      return 'Intersection of Plane/Surface and Line';
    case WorkPointMethod.centerOfLoop:
      return 'Center Point of Loop of Edges';
    case WorkPointMethod.centerOfTorus:
      return 'Center Point of Torus';
    case WorkPointMethod.centerOfSphere:
      return 'Center Point of Sphere';
  }
}

/// What happened when a pick was added to the collection so far.
enum WorkPickOutcome {
  /// Enough geometry: build it.
  complete,

  /// Valid so far, but the method needs more picks. [WorkAttempt.message] is
  /// the prompt for the next one.
  needMore,

  /// This pick cannot work. [WorkAttempt.message] says why, in words the user
  /// can act on. The caller drops the offending pick and stays armed — one
  /// mis-tap must never cost you the whole command.
  rejected,
}

/// A solved work axis: a point on it and a unit direction.
class WorkAxisSolution {
  final Vec3 at;
  final Vec3 dir;

  /// The sentence shown in the browser and the toast, e.g.
  /// "Intersection of Front Face and XY Plane".
  final String def;
  const WorkAxisSolution(this.at, this.dir, this.def);
}

/// A solved work point.
class WorkPointSolution {
  final Vec3 at;
  final String def;
  const WorkPointSolution(this.at, this.def);
}

/// The result of feeding the current pick list to a method.
class WorkAttempt<T> {
  final WorkPickOutcome outcome;
  final T? solution;
  final String message;
  const WorkAttempt(this.outcome, this.message, [this.solution]);

  static WorkAttempt<T> more<T>(String prompt) =>
      WorkAttempt<T>(WorkPickOutcome.needMore, prompt);
  static WorkAttempt<T> no<T>(String why) =>
      WorkAttempt<T>(WorkPickOutcome.rejected, why);
  static WorkAttempt<T> ok<T>(T s, String def) =>
      WorkAttempt<T>(WorkPickOutcome.complete, def, s);
}

// ---------------------------------------------------------------------------
// geometry
// ---------------------------------------------------------------------------

/// Two planes are parallel (or anti-parallel) within [tol] of their normals.
bool planesParallel(Vec3 n1, Vec3 n2, {double tol = 1e-9}) =>
    n1.cross(n2).length <= tol;

/// The line where two planes meet, or null when they are parallel.
///
/// `p = (d1 (n2 x dir) + d2 (dir x n1)) / |dir|^2`, dir = n1 x n2 — the
/// standard closed form, which lands the returned point on BOTH planes rather
/// than merely on the right line direction.
(Vec3 at, Vec3 dir)? planePlaneLine(
    Vec3 n1, double d1, Vec3 n2, double d2) {
  final dir = n1.cross(n2);
  final len2 = dir.dot(dir);
  if (len2 < 1e-18) return null;
  final at = (n2.cross(dir) * d1 + dir.cross(n1) * d2) * (1 / len2);
  return (at, dir.normalized());
}

/// Where a line meets a plane, or null when it is parallel to it (including
/// lying in it — an infinity of answers is not an answer).
Vec3? linePlanePoint(Vec3 at, Vec3 dir, Vec3 n, double d) {
  final den = n.dot(dir);
  if (den.abs() < 1e-12) return null;
  return at + dir * ((d - n.dot(at)) / den);
}

/// The single point three planes share, or null when they do not meet in one
/// (two parallel, or all three through a common line). Cramer's rule.
Vec3? threePlanePoint(
    Vec3 n1, double d1, Vec3 n2, double d2, Vec3 n3, double d3) {
  final c23 = n2.cross(n3);
  final det = n1.dot(c23);
  // The normals are unit, so the determinant IS the scalar triple product of
  // three unit vectors: a scale-free measure of how far from coplanar they
  // are. 1e-9 rejects "very nearly a common line" without rejecting an
  // honest right-angle corner, whose determinant is 1.
  if (det.abs() < 1e-9) return null;
  final c31 = n3.cross(n1);
  final c12 = n1.cross(n2);
  return (c23 * d1 + c31 * d2 + c12 * d3) * (1 / det);
}

/// Closest approach of two lines: the two nearest points and their distance.
/// Null when the lines are parallel.
(Vec3 a, Vec3 b, double gap)? lineLineClosest(
    Vec3 p1, Vec3 d1, Vec3 p2, Vec3 d2) {
  final w = p1 - p2;
  final a = d1.dot(d1), b = d1.dot(d2), c = d2.dot(d2);
  final d = d1.dot(w), e = d2.dot(w);
  final den = a * c - b * b;
  if (den.abs() < 1e-12) return null; // parallel: no unique nearest pair
  final s = (b * e - c * d) / den;
  final t = (a * e - b * d) / den;
  final qa = p1 + d1 * s;
  final qb = p2 + d2 * t;
  return (qa, qb, (qa - qb).length);
}

/// How far two lines may miss each other and still count as intersecting.
///
/// The inputs are ANALYTIC (the kernel's own line records, not tessellation),
/// so genuinely intersecting lines meet to machine precision and anything
/// looser would be accepting skew lines. Inventor refuses those outright; the
/// refusal here reports the measured gap so the answer is checkable rather
/// than merely negative.
const double kLineIntersectTol = 1e-6;

// ---------------------------------------------------------------------------
// axis inference
// ---------------------------------------------------------------------------

/// How many picks [m] consumes before it can build. `auto` is 0 — it commits
/// as soon as the picks so far determine an answer, which is the whole point
/// of Inventor's legacy entry.
int workAxisArity(WorkAxisMethod m) {
  switch (m) {
    case WorkAxisMethod.auto:
      return 0;
    case WorkAxisMethod.onLineOrEdge:
    case WorkAxisMethod.throughCenterOfCircularEdge:
    case WorkAxisMethod.throughRevolvedFace:
      return 1;
    case WorkAxisMethod.parallelToLineThroughPoint:
    case WorkAxisMethod.throughTwoPoints:
    case WorkAxisMethod.intersectionOfTwoPlanes:
    case WorkAxisMethod.normalToPlaneThroughPoint:
      return 2;
  }
}

/// The prompt shown while [m] is waiting for pick number [have] (0-based).
String workAxisPrompt(WorkAxisMethod m, int have) {
  switch (m) {
    case WorkAxisMethod.auto:
      return 'Select an edge, a face, two planes, or two points.';
    case WorkAxisMethod.onLineOrEdge:
      return 'Select a linear edge or sketch line.';
    case WorkAxisMethod.throughCenterOfCircularEdge:
      return 'Select a circular or elliptical edge.';
    case WorkAxisMethod.throughRevolvedFace:
      return 'Select a cylindrical or conical face.';
    case WorkAxisMethod.parallelToLineThroughPoint:
      return have == 0
          ? 'Select a point.'
          : 'Select the line to be parallel to.';
    case WorkAxisMethod.throughTwoPoints:
      return have == 0 ? 'Select the first point.' : 'Select the second point.';
    case WorkAxisMethod.intersectionOfTwoPlanes:
      return have == 0
          ? 'Select the first plane or planar face.'
          : 'Select a second, non-parallel plane or face.';
    case WorkAxisMethod.normalToPlaneThroughPoint:
      return have == 0
          ? 'Select a plane or planar face.'
          : 'Select the point the axis runs through.';
  }
}

/// Feeds the ordered pick list [refs] to [m] and reports what to do next.
///
/// [refs] is the WHOLE collection, newest last, so this stays a pure function
/// of the picks — no accumulating state to get out of step with the UI.
WorkAttempt<WorkAxisSolution> solveWorkAxis(
    WorkAxisMethod m, List<WorkRef> refs) {
  if (refs.isEmpty) {
    return WorkAttempt.more(workAxisPrompt(m, 0));
  }
  switch (m) {
    case WorkAxisMethod.auto:
      return _autoAxis(refs);

    case WorkAxisMethod.onLineOrEdge:
      {
      final r = refs.first;
      if (!r.hasLine || r.source == WorkRefSource.circle) {
        return WorkAttempt.no('${r.label} is not a straight edge or line.');
      }
      return WorkAttempt.ok(
          WorkAxisSolution(r.lineAt!, r.lineDir!, 'On ${r.label}'),
          'On ${r.label}');
      }

    case WorkAxisMethod.throughCenterOfCircularEdge:
      {
      final r = refs.first;
      if (r.source != WorkRefSource.circle) {
        return WorkAttempt.no('${r.label} is not a circular or elliptical '
            'edge.');
      }
      return WorkAttempt.ok(
          WorkAxisSolution(
              r.lineAt!, r.lineDir!, 'Through center of ${r.label}'),
          'Through center of ${r.label}');
      }

    case WorkAxisMethod.throughRevolvedFace:
      {
      final r = refs.first;
      if (r.source != WorkRefSource.revolved &&
          r.source != WorkRefSource.torus) {
        return WorkAttempt.no('${r.label} is not a revolved face — pick a '
            'cylinder, cone or torus.');
      }
      return WorkAttempt.ok(
          WorkAxisSolution(
              r.lineAt!, r.lineDir!, 'Revolution axis of ${r.label}'),
          'Revolution axis of ${r.label}');
      }

    case WorkAxisMethod.throughTwoPoints:
      {
      for (final r in refs) {
        if (!r.hasPoint) {
          return WorkAttempt.no('${r.label} does not give a point.');
        }
      }
      if (refs.length < 2) return WorkAttempt.more(workAxisPrompt(m, 1));
      return _twoPointAxis(refs[0], refs[1]);
      }

    case WorkAxisMethod.intersectionOfTwoPlanes:
      {
      for (final r in refs) {
        if (!r.hasPlane) {
          return WorkAttempt.no('${r.label} is not a plane or planar face.');
        }
      }
      if (refs.length < 2) return WorkAttempt.more(workAxisPrompt(m, 1));
      return _planeIntersectAxis(refs[0], refs[1]);
      }

    case WorkAxisMethod.normalToPlaneThroughPoint:
      {
      final plane = refs.firstWhere((r) => r.hasPlane,
          orElse: () => refs.first);
      if (!plane.hasPlane) {
        return WorkAttempt.no('${refs.first.label} is not a plane or planar '
            'face.');
      }
      if (refs.length < 2) return WorkAttempt.more(workAxisPrompt(m, 1));
      final pt = refs.firstWhere((r) => !identical(r, plane) && r.hasPoint,
          orElse: () => refs.last);
      if (!pt.hasPoint) {
        return WorkAttempt.no('${pt.label} does not give a point.');
      }
      return WorkAttempt.ok(
          WorkAxisSolution(pt.point!, plane.planeNormal!,
              'Normal to ${plane.label} through ${pt.label}'),
          'Normal to ${plane.label} through ${pt.label}');
      }

    case WorkAxisMethod.parallelToLineThroughPoint:
      {
      if (refs.length < 2) {
        if (!refs.first.hasPoint && !refs.first.hasLine) {
          return WorkAttempt.no('${refs.first.label} is neither a point nor a '
              'line.');
        }
        return WorkAttempt.more(workAxisPrompt(m, 1));
      }
      // Inventor asks for the point first, but accepting either order costs
      // nothing and saves a restart when the user reads the prompt after
      // tapping — the two inputs are not interchangeable geometrically, only
      // in the order they arrive.
      final line = refs.firstWhere((r) => r.hasLine, orElse: () => refs.first);
      final point = refs.firstWhere(
          (r) => !identical(r, line) && r.hasPoint,
          orElse: () => refs.first);
      if (!line.hasLine) {
        return WorkAttempt.no('Neither pick is a line to be parallel to.');
      }
      if (!point.hasPoint || identical(point, line)) {
        return WorkAttempt.no('Select a point for the axis to pass through.');
      }
      return WorkAttempt.ok(
          WorkAxisSolution(point.point!, line.lineDir!,
              'Parallel to ${line.label} through ${point.label}'),
          'Parallel to ${line.label} through ${point.label}');
      }
  }
}

WorkAttempt<WorkAxisSolution> _twoPointAxis(WorkRef a, WorkRef b) {
  final d = b.point! - a.point!;
  if (d.length < 1e-9) {
    return WorkAttempt.no('Those two points are in the same place.');
  }
  final def = 'Through ${a.label} and ${b.label}';
  // Inventor: "positive direction oriented in the direction from the first
  // point to the second point". Preserved, because a work axis used as a
  // revolve axis or a pattern direction has a sign that the user chose.
  return WorkAttempt.ok(
      WorkAxisSolution(a.point!, d.normalized(), def), def);
}

WorkAttempt<WorkAxisSolution> _planeIntersectAxis(WorkRef a, WorkRef b) {
  final line = planePlaneLine(
      a.planeNormal!, a.planeD, b.planeNormal!, b.planeD);
  if (line == null) {
    return WorkAttempt.no('${a.label} and ${b.label} are parallel — they '
        'never meet.');
  }
  final def = 'Intersection of ${a.label} and ${b.label}';
  return WorkAttempt.ok(WorkAxisSolution(line.$1, line.$2, def), def);
}

/// The legacy "Axis" command: commit as soon as the picks determine an answer.
///
/// Priority, and why: a single pick that carries a line IS an axis, and that
/// is the overwhelmingly common case (tap an edge, get an axis) — so it wins
/// and commits immediately. Only when the first pick cannot stand alone does
/// the command wait for a second, and then the pair decides.
///
/// The consequence is deliberate and matches Inventor: the generic command
/// can never build "Through Two Points" from two circular edges, because the
/// first circular edge already answered. That is what the named methods are
/// for, and it is why they exist in Inventor's menu at all.
WorkAttempt<WorkAxisSolution> _autoAxis(List<WorkRef> refs) {
  final first = refs.first;
  if (refs.length == 1) {
    if (first.hasLine) {
      final def = switch (first.source) {
        WorkRefSource.circle => 'Through center of ${first.label}',
        WorkRefSource.revolved => 'Revolution axis of ${first.label}',
        WorkRefSource.torus => 'Revolution axis of ${first.label}',
        _ => 'On ${first.label}',
      };
      return WorkAttempt.ok(
          WorkAxisSolution(first.lineAt!, first.lineDir!, def), def);
    }
    if (first.hasPlane) {
      return WorkAttempt.more('Select a second plane to intersect with, or a '
          'point for the normal through it.');
    }
    if (first.hasPoint) {
      return WorkAttempt.more('Select a second point, a plane, or a line.');
    }
    return WorkAttempt.no('${first.label} cannot define an axis.');
  }

  final second = refs[1];
  // Two planes -> their intersection. Checked before the point cases because
  // a plane pick that also carries a point (a circular edge) reached here
  // only by NOT being usable as a line, i.e. never.
  if (first.hasPlane && second.hasPlane) {
    if (!planesParallel(first.planeNormal!, second.planeNormal!)) {
      return _planeIntersectAxis(first, second);
    }
    return WorkAttempt.no('${first.label} and ${second.label} are parallel — '
        'pick two planes that meet.');
  }
  if (first.hasPlane && second.hasPoint) {
    final def = 'Normal to ${first.label} through ${second.label}';
    return WorkAttempt.ok(
        WorkAxisSolution(second.point!, first.planeNormal!, def), def);
  }
  if (first.hasPoint && second.hasPlane) {
    final def = 'Normal to ${second.label} through ${first.label}';
    return WorkAttempt.ok(
        WorkAxisSolution(first.point!, second.planeNormal!, def), def);
  }
  if (first.hasPoint && second.hasLine) {
    final def = 'Parallel to ${second.label} through ${first.label}';
    return WorkAttempt.ok(
        WorkAxisSolution(first.point!, second.lineDir!, def), def);
  }
  if (first.hasPoint && second.hasPoint) {
    return _twoPointAxis(first, second);
  }
  return WorkAttempt.no('${first.label} and ${second.label} do not define an '
      'axis.');
}

// ---------------------------------------------------------------------------
// point inference
// ---------------------------------------------------------------------------

int workPointArity(WorkPointMethod m) {
  switch (m) {
    case WorkPointMethod.auto:
      return 0;
    case WorkPointMethod.grounded:
    case WorkPointMethod.onVertex:
    case WorkPointMethod.centerOfLoop:
    case WorkPointMethod.centerOfTorus:
    case WorkPointMethod.centerOfSphere:
      return 1;
    case WorkPointMethod.intersectionOfTwoLines:
    case WorkPointMethod.intersectionOfPlaneAndLine:
      return 2;
    case WorkPointMethod.intersectionOfThreePlanes:
      return 3;
  }
}

String workPointPrompt(WorkPointMethod m, int have) {
  switch (m) {
    case WorkPointMethod.auto:
      return 'Select a vertex, a circular edge, or geometry that meets.';
    case WorkPointMethod.grounded:
      return 'Select a vertex or midpoint to ground a point at.';
    case WorkPointMethod.onVertex:
      return 'Select a vertex, sketch point, or edge midpoint.';
    case WorkPointMethod.centerOfLoop:
      return 'Select a circular or elliptical edge.';
    case WorkPointMethod.centerOfTorus:
      return 'Select a toroidal face.';
    case WorkPointMethod.centerOfSphere:
      return 'Select a spherical face.';
    case WorkPointMethod.intersectionOfTwoLines:
      return have == 0
          ? 'Select the first line, edge or axis.'
          : 'Select a second line that crosses it.';
    case WorkPointMethod.intersectionOfPlaneAndLine:
      return have == 0
          ? 'Select a plane or planar face.'
          : 'Select a line, edge or axis that crosses it.';
    case WorkPointMethod.intersectionOfThreePlanes:
      return switch (have) {
        0 => 'Select the first plane or planar face.',
        1 => 'Select the second plane.',
        _ => 'Select the third plane.',
      };
  }
}

WorkAttempt<WorkPointSolution> solveWorkPoint(
    WorkPointMethod m, List<WorkRef> refs) {
  if (refs.isEmpty) return WorkAttempt.more(workPointPrompt(m, 0));
  switch (m) {
    case WorkPointMethod.auto:
      return _autoPoint(refs);

    case WorkPointMethod.grounded:
    case WorkPointMethod.onVertex:
      {
      final r = refs.first;
      if (!r.hasPoint) {
        return WorkAttempt.no('${r.label} does not give a point.');
      }
      final def = m == WorkPointMethod.grounded
          ? 'Grounded at ${r.label}'
          : 'On ${r.label}';
      return WorkAttempt.ok(WorkPointSolution(r.point!, def), def);
      }

    case WorkPointMethod.centerOfLoop:
      {
      final r = refs.first;
      if (r.source != WorkRefSource.circle) {
        return WorkAttempt.no('${r.label} is not a closed circular edge.');
      }
      final def = 'Center of ${r.label}';
      return WorkAttempt.ok(WorkPointSolution(r.point!, def), def);
      }

    case WorkPointMethod.centerOfSphere:
      {
      final r = refs.first;
      if (r.source != WorkRefSource.sphere) {
        return WorkAttempt.no('${r.label} is not a spherical face.');
      }
      final def = 'Center of ${r.label}';
      return WorkAttempt.ok(WorkPointSolution(r.point!, def), def);
      }

    case WorkPointMethod.centerOfTorus:
      {
      final r = refs.first;
      if (r.source != WorkRefSource.torus) {
        return WorkAttempt.no('${r.label} is not a toroidal face.');
      }
      final def = 'Center of ${r.label}';
      return WorkAttempt.ok(WorkPointSolution(r.point!, def), def);
      }

    case WorkPointMethod.intersectionOfTwoLines:
      {
      for (final r in refs) {
        if (!r.hasLine) {
          return WorkAttempt.no('${r.label} is not a line, edge or axis.');
        }
      }
      if (refs.length < 2) return WorkAttempt.more(workPointPrompt(m, 1));
      return _twoLinePoint(refs[0], refs[1]);
      }

    case WorkPointMethod.intersectionOfPlaneAndLine:
      {
      if (refs.length < 2) {
        if (!refs.first.hasPlane && !refs.first.hasLine) {
          return WorkAttempt.no('${refs.first.label} is neither a plane nor a '
              'line.');
        }
        return WorkAttempt.more(workPointPrompt(m, 1));
      }
      final plane =
          refs.firstWhere((r) => r.hasPlane, orElse: () => refs.first);
      final line = refs.firstWhere(
          (r) => !identical(r, plane) && r.hasLine,
          orElse: () => refs.first);
      if (!plane.hasPlane || identical(plane, line) || !line.hasLine) {
        return WorkAttempt.no('Select one plane and one line.');
      }
      return _planeLinePoint(plane, line);
      }

    case WorkPointMethod.intersectionOfThreePlanes:
      {
      for (final r in refs) {
        if (!r.hasPlane) {
          return WorkAttempt.no('${r.label} is not a plane or planar face.');
        }
      }
      if (refs.length < 3) {
        return WorkAttempt.more(workPointPrompt(m, refs.length));
      }
      return _threePlanePoint(refs[0], refs[1], refs[2]);
      }
  }
}

WorkAttempt<WorkPointSolution> _twoLinePoint(WorkRef a, WorkRef b) {
  final hit = lineLineClosest(a.lineAt!, a.lineDir!, b.lineAt!, b.lineDir!);
  if (hit == null) {
    return WorkAttempt.no('${a.label} and ${b.label} are parallel — they '
        'never cross.');
  }
  final (qa, qb, gap) = hit;
  if (gap > kLineIntersectTol) {
    // Skew lines. Reporting the gap turns "it refused" into "they miss each
    // other by 3.4 mm", which is something the user can go and fix.
    return WorkAttempt.no('${a.label} and ${b.label} do not meet — they pass '
        '${_mm(gap)} apart.');
  }
  final def = 'Intersection of ${a.label} and ${b.label}';
  return WorkAttempt.ok(WorkPointSolution((qa + qb) * 0.5, def), def);
}

WorkAttempt<WorkPointSolution> _planeLinePoint(WorkRef plane, WorkRef line) {
  final p = linePlanePoint(
      line.lineAt!, line.lineDir!, plane.planeNormal!, plane.planeD);
  if (p == null) {
    return WorkAttempt.no('${line.label} is parallel to ${plane.label} — it '
        'never crosses it.');
  }
  final def = 'Intersection of ${plane.label} and ${line.label}';
  return WorkAttempt.ok(WorkPointSolution(p, def), def);
}

WorkAttempt<WorkPointSolution> _threePlanePoint(
    WorkRef a, WorkRef b, WorkRef c) {
  final p = threePlanePoint(a.planeNormal!, a.planeD, b.planeNormal!, b.planeD,
      c.planeNormal!, c.planeD);
  if (p == null) {
    return WorkAttempt.no('${a.label}, ${b.label} and ${c.label} do not meet '
        'at one point — two of them are parallel, or all three share a line.');
  }
  final def = 'Intersection of ${a.label}, ${b.label} and ${c.label}';
  return WorkAttempt.ok(WorkPointSolution(p, def), def);
}

/// The legacy "Point" command. Same shape as [_autoAxis]: a pick that IS a
/// point commits at once (tap a vertex, get a point), and only geometry that
/// cannot stand alone waits for company.
WorkAttempt<WorkPointSolution> _autoPoint(List<WorkRef> refs) {
  final first = refs.first;
  if (refs.length == 1) {
    if (first.hasPoint) {
      final def = switch (first.source) {
        WorkRefSource.circle => 'Center of ${first.label}',
        WorkRefSource.sphere => 'Center of ${first.label}',
        WorkRefSource.torus => 'Center of ${first.label}',
        WorkRefSource.edge => 'Midpoint of ${first.label}',
        _ => 'On ${first.label}',
      };
      return WorkAttempt.ok(WorkPointSolution(first.point!, def), def);
    }
    if (first.hasPlane) {
      return WorkAttempt.more('Select a line to cross it, or two more planes.');
    }
    if (first.hasLine) {
      return WorkAttempt.more('Select a second line, or a plane to cross.');
    }
    return WorkAttempt.no('${first.label} cannot define a point.');
  }

  final second = refs[1];
  if (first.hasPlane && second.hasLine && !second.hasPlane) {
    return _planeLinePoint(first, second);
  }
  if (first.hasLine && second.hasPlane && !first.hasPlane) {
    return _planeLinePoint(second, first);
  }
  if (first.hasLine && second.hasLine && !(first.hasPlane && second.hasPlane)) {
    return _twoLinePoint(first, second);
  }
  if (first.hasPlane && second.hasPlane) {
    if (refs.length < 3) {
      return WorkAttempt.more('Select a third plane.');
    }
    if (!refs[2].hasPlane) {
      return WorkAttempt.no('${refs[2].label} is not a plane or planar face.');
    }
    return _threePlanePoint(first, second, refs[2]);
  }
  return WorkAttempt.no('${first.label} and ${second.label} do not define a '
      'point.');
}

String _mm(double v) {
  final a = v.abs();
  if (a >= 1) return '${v.toStringAsFixed(2)} mm';
  if (a >= 0.001) return '${v.toStringAsFixed(4)} mm';
  return '${v.toStringAsExponential(1)} mm';
}

// ---------------------------------------------------------------------------
// display
// ---------------------------------------------------------------------------

/// How far a work axis should be drawn either side of [at], so it spans the
/// model the way Inventor's auto-sized axes do.
///
/// [lo]/[hi] are the part's bounding box. The axis is drawn over the box's
/// extent along its own direction, padded so the ends stick out and are
/// visibly infinite-ish rather than looking like a trimmed edge. A part with
/// no geometry at all still gets a usable stub instead of a zero-length
/// segment nobody can see or tap.
(Vec3 a, Vec3 b) workAxisSpan(Vec3 at, Vec3 dir, Vec3 lo, Vec3 hi,
    {double pad = 0.15, double minHalf = 10}) {
  final d = dir.normalized();
  // Project every corner of the box onto the axis; the extreme projections
  // are the span. Two dot products would do for an axis-aligned direction,
  // but a work axis is rarely axis-aligned, so walk the eight corners.
  var t0 = double.infinity, t1 = -double.infinity;
  for (var i = 0; i < 8; i++) {
    final c = Vec3(
      (i & 1) == 0 ? lo.x : hi.x,
      (i & 2) == 0 ? lo.y : hi.y,
      (i & 4) == 0 ? lo.z : hi.z,
    );
    final t = (c - at).dot(d);
    if (t < t0) t0 = t;
    if (t > t1) t1 = t;
  }
  if (!t0.isFinite || !t1.isFinite || t1 < t0) {
    t0 = -minHalf;
    t1 = minHalf;
  }
  final extra = math.max((t1 - t0) * pad, minHalf * 0.5);
  t0 -= extra;
  t1 += extra;
  if (t1 - t0 < minHalf * 2) {
    final mid = (t0 + t1) / 2;
    t0 = mid - minHalf;
    t1 = mid + minHalf;
  }
  return (at + d * t0, at + d * t1);
}

// ---------------------------------------------------------------------------
// M223 — Work PLANE methods
// ---------------------------------------------------------------------------
//
// Inventor documents thirteen. Two of them have been real since M151 and keep
// their own flow, because they are not pick-only: Offset from Plane is a DRAG
// with a live distance (M174/M169) and carries an editable base+offset (M162),
// and Midplane between Two Planes shares that flow's plane-key picking. The
// five below are pure geometry — they need nothing but picks — so they run on
// the WorkRef machinery M215 built for axes and points.
//
// The remaining six are NOT built, and each for a stated reason rather than by
// omission:
//   Angle to Plane around Edge      needs an angle to type; that is the offset
//                                   field's twin (M169) and a UI job, not a
//                                   geometry one.
//   Normal to Curve at Point        needs a CURVE contribution — a tangent at a
//                                   parameter — which WorkRef does not carry.
//   (M224 built the three Tangent to Surface methods, which had been listed
//   here as blocked: a cylinder has TWO tangent planes through an external
//   point or parallel to a plane, and Inventor resolves that with the side you
//   clicked. WorkRef now carries the hit point for exactly that, and refuses
//   rather than guessing when a pick arrives without one.)

/// Inventor's Work Plane creation methods that run on picks alone.
enum WorkPlaneMethod {
  parallelToPlaneThroughPoint,
  threePoints,
  twoCoplanarEdges,
  normalToAxisThroughPoint,
  midplaneOfTorus,
  // M224 — the three that needed the side of the face you picked.
  tangentToSurfaceThroughPoint,
  tangentToSurfaceThroughEdge,
  tangentToSurfaceParallelToPlane,
}

String workPlaneMethodLabel(WorkPlaneMethod m) {
  switch (m) {
    case WorkPlaneMethod.parallelToPlaneThroughPoint:
      return 'Parallel to Plane through Point';
    case WorkPlaneMethod.threePoints:
      return 'Three Points';
    case WorkPlaneMethod.twoCoplanarEdges:
      return 'Two Coplanar Edges';
    case WorkPlaneMethod.normalToAxisThroughPoint:
      return 'Normal to Axis through Point';
    case WorkPlaneMethod.midplaneOfTorus:
      return 'Midplane of Torus';
    case WorkPlaneMethod.tangentToSurfaceThroughPoint:
      return 'Tangent to Surface through Point';
    case WorkPlaneMethod.tangentToSurfaceThroughEdge:
      return 'Tangent to Surface through Edge';
    case WorkPlaneMethod.tangentToSurfaceParallelToPlane:
      return 'Tangent to Surface and Parallel to Plane';
  }
}

int workPlaneArity(WorkPlaneMethod m) {
  switch (m) {
    case WorkPlaneMethod.midplaneOfTorus:
      return 1;
    case WorkPlaneMethod.parallelToPlaneThroughPoint:
    case WorkPlaneMethod.twoCoplanarEdges:
    case WorkPlaneMethod.normalToAxisThroughPoint:
    case WorkPlaneMethod.tangentToSurfaceThroughPoint:
    case WorkPlaneMethod.tangentToSurfaceThroughEdge:
    case WorkPlaneMethod.tangentToSurfaceParallelToPlane:
      return 2;
    case WorkPlaneMethod.threePoints:
      return 3;
  }
}

String workPlanePrompt(WorkPlaneMethod m, int have) {
  switch (m) {
    case WorkPlaneMethod.midplaneOfTorus:
      return 'Select a toroidal face.';
    case WorkPlaneMethod.parallelToPlaneThroughPoint:
      return have == 0
          ? 'Select the plane or planar face to be parallel to.'
          : 'Select the point the plane runs through.';
    case WorkPlaneMethod.twoCoplanarEdges:
      return have == 0
          ? 'Select the first edge or line.'
          : 'Select a second edge in the same plane.';
    case WorkPlaneMethod.normalToAxisThroughPoint:
      return have == 0
          ? 'Select the axis, edge or line to be normal to.'
          : 'Select the point the plane runs through.';
    case WorkPlaneMethod.threePoints:
      return switch (have) {
        0 => 'Select the first point.',
        1 => 'Select the second point.',
        _ => 'Select the third point.',
      };
    case WorkPlaneMethod.tangentToSurfaceThroughPoint:
      return have == 0
          ? 'Select a cylindrical face, on the side the plane goes.'
          : 'Select the point the plane runs through.';
    case WorkPlaneMethod.tangentToSurfaceThroughEdge:
      return have == 0
          ? 'Select a cylindrical face.'
          : 'Select an edge lying along it.';
    case WorkPlaneMethod.tangentToSurfaceParallelToPlane:
      return have == 0
          ? 'Select a cylindrical face, on the side the plane goes.'
          : 'Select the plane to be parallel to.';
  }
}

/// A solved work plane: a point on it and a unit normal. The u/v basis is the
/// caller's business — [faceFrame] already has the app's rule for that, and a
/// second one here would be a second rule.
class WorkPlaneSolution {
  final Vec3 at;
  final Vec3 n;
  final String def;
  const WorkPlaneSolution(this.at, this.n, this.def);
}

/// Feeds the ordered pick list [refs] to [m], exactly as [solveWorkAxis] does.
WorkAttempt<WorkPlaneSolution> solveWorkPlane(
    WorkPlaneMethod m, List<WorkRef> refs) {
  if (refs.isEmpty) return WorkAttempt.more(workPlanePrompt(m, 0));
  switch (m) {
    case WorkPlaneMethod.midplaneOfTorus:
      {
        final r = refs.first;
        if (r.source != WorkRefSource.torus) {
          return WorkAttempt.no('${r.label} is not a toroidal face.');
        }
        // The torus record gives the centre and the axis; the midplane is the
        // one the tube revolves in, so the axis IS its normal.
        final def = 'Midplane of ${r.label}';
        return WorkAttempt.ok(
            WorkPlaneSolution(r.point!, r.lineDir!, def), def);
      }

    case WorkPlaneMethod.parallelToPlaneThroughPoint:
      {
        final plane =
            refs.firstWhere((r) => r.hasPlane, orElse: () => refs.first);
        if (!plane.hasPlane) {
          return WorkAttempt.no(
              '${refs.first.label} is not a plane or planar face.');
        }
        if (refs.length < 2) return WorkAttempt.more(workPlanePrompt(m, 1));
        final pt = refs.firstWhere(
            (r) => !identical(r, plane) && r.hasPoint,
            orElse: () => refs.last);
        if (!pt.hasPoint || identical(pt, plane)) {
          return WorkAttempt.no('Select a point for the plane to pass '
              'through.');
        }
        final def = 'Parallel to ${plane.label} through ${pt.label}';
        return WorkAttempt.ok(
            WorkPlaneSolution(pt.point!, plane.planeNormal!, def), def);
      }

    case WorkPlaneMethod.normalToAxisThroughPoint:
      {
        final line =
            refs.firstWhere((r) => r.hasLine, orElse: () => refs.first);
        if (!line.hasLine) {
          return WorkAttempt.no(
              '${refs.first.label} is not an axis, edge or line.');
        }
        if (refs.length < 2) return WorkAttempt.more(workPlanePrompt(m, 1));
        final pt = refs.firstWhere(
            (r) => !identical(r, line) && r.hasPoint,
            orElse: () => refs.last);
        if (!pt.hasPoint || identical(pt, line)) {
          return WorkAttempt.no('Select a point for the plane to pass '
              'through.');
        }
        final def = 'Normal to ${line.label} through ${pt.label}';
        return WorkAttempt.ok(
            WorkPlaneSolution(pt.point!, line.lineDir!, def), def);
      }

    case WorkPlaneMethod.threePoints:
      {
        for (final r in refs) {
          if (!r.hasPoint) {
            return WorkAttempt.no('${r.label} does not give a point.');
          }
        }
        if (refs.length < 3) {
          return WorkAttempt.more(workPlanePrompt(m, refs.length));
        }
        return _threePointPlane(refs[0], refs[1], refs[2]);
      }

    case WorkPlaneMethod.twoCoplanarEdges:
      {
        for (final r in refs) {
          if (!r.hasLine) {
            return WorkAttempt.no('${r.label} is not an edge or line.');
          }
        }
        if (refs.length < 2) return WorkAttempt.more(workPlanePrompt(m, 1));
        return _twoEdgePlane(refs[0], refs[1]);
      }

    case WorkPlaneMethod.tangentToSurfaceThroughPoint:
    case WorkPlaneMethod.tangentToSurfaceThroughEdge:
    case WorkPlaneMethod.tangentToSurfaceParallelToPlane:
      {
        final cyl = refs.firstWhere((r) => r.radius != null,
            orElse: () => refs.first);
        if (cyl.radius == null || !cyl.hasLine) {
          return WorkAttempt.no('${refs.first.label} is not a cylindrical '
              'face — a tangent plane needs one.');
        }
        if (refs.length < 2) return WorkAttempt.more(workPlanePrompt(m, 1));
        final other =
            refs.firstWhere((r) => !identical(r, cyl), orElse: () => refs.last);
        if (m == WorkPlaneMethod.tangentToSurfaceThroughEdge) {
          return _tangentThroughEdge(cyl, other);
        }
        if (m == WorkPlaneMethod.tangentToSurfaceParallelToPlane) {
          return _tangentParallelToPlane(cyl, other);
        }
        return _tangentThroughPoint(cyl, other);
      }
  }
}

// ---------------------------------------------------------------------------
// M224 — tangent planes
// ---------------------------------------------------------------------------
//
// A tangent plane of a cylinder always has its normal PERPENDICULAR to the
// axis, so every one of them is fixed by a single angle around it. That is
// what makes these three methods the same problem three times: find the
// admissible angles, then choose between them with the side the user picked.

/// The part of [v] perpendicular to the unit direction [axis].
Vec3 _radial(Vec3 v, Vec3 axis) => v - axis * v.dot(axis);

/// The tangent plane of [cyl] whose outward normal is the unit [m]: it touches
/// at axis + m*r, taken at the axial position of [along].
WorkPlaneSolution _tangentAt(WorkRef cyl, Vec3 m, Vec3 along, String def) {
  final a = cyl.lineAt!, d = cyl.lineDir!;
  final base = a + d * (along - a).dot(d);
  return WorkPlaneSolution(base + m * cyl.radius!, m, def);
}

/// Which of [cands] the user meant, by the point the ray hit. Null when the
/// pick carried no hit — the caller then refuses rather than guessing.
Vec3? _sideChosen(WorkRef cyl, List<Vec3> cands) {
  final hit = cyl.hitAt;
  if (hit == null) return null;
  final h = _radial(hit - cyl.lineAt!, cyl.lineDir!);
  if (h.length < 1e-12) return null;
  final hn = h.normalized();
  Vec3? best;
  var bestDot = -2.0, runnerUp = -2.0;
  for (final c in cands) {
    final dot = c.dot(hn);
    if (dot > bestDot) {
      runnerUp = bestDot;
      bestDot = dot;
      best = c;
    } else if (dot > runnerUp) {
      runnerUp = dot;
    }
  }
  // A TIE is not an answer. Tapping the cylinder straight towards the point
  // lands exactly between the two tangent lines, and both score the same — the
  // pick genuinely carries no side then, so the caller asks again rather than
  // tossing a coin (M158: ranking is not acceptance).
  if (best == null || (bestDot - runnerUp).abs() < 1e-9) return null;
  return best;
}

WorkAttempt<WorkPlaneSolution> _tangentThroughPoint(WorkRef cyl, WorkRef pt) {
  if (!pt.hasPoint) {
    return WorkAttempt.no('${pt.label} does not give a point.');
  }
  final d = cyl.lineDir!, r = cyl.radius!;
  final w = _radial(pt.point! - cyl.lineAt!, d);
  final h = w.length;
  if (h < r - 1e-9) {
    return WorkAttempt.no('${pt.label} is inside ${cyl.label} — no tangent '
        'plane passes through it.');
  }
  final def = 'Tangent to ${cyl.label} through ${pt.label}';
  if (h <= r + 1e-9) {
    // The point is ON the cylinder: one tangent plane, no side to choose.
    return WorkAttempt.ok(
        _tangentAt(cyl, w.normalized(), pt.point!, def), def);
  }
  // Two of them, at +/- acos(r/h) around the axis from the point's own
  // direction. Both are correct; only the user knows which side they meant.
  final wn = w.normalized();
  final side = wn.cross(d).normalized(); // the other axis of the radial plane
  final cos = r / h, sin = math.sqrt(1 - cos * cos);
  final cands = [
    (wn * cos + side * sin).normalized(),
    (wn * cos - side * sin).normalized(),
  ];
  final m = _sideChosen(cyl, cands);
  if (m == null) {
    return WorkAttempt.no('Two planes are tangent to ${cyl.label} through '
        '${pt.label} — tap the face on the side the plane should go.');
  }
  return WorkAttempt.ok(_tangentAt(cyl, m, pt.point!, def), def);
}

WorkAttempt<WorkPlaneSolution> _tangentThroughEdge(WorkRef cyl, WorkRef edge) {
  if (!edge.hasLine) {
    return WorkAttempt.no('${edge.label} is not an edge or line.');
  }
  final d = cyl.lineDir!, r = cyl.radius!;
  if (edge.lineDir!.cross(d).length > 1e-6) {
    return WorkAttempt.no('${edge.label} is not parallel to the axis of '
        '${cyl.label}.');
  }
  final w = _radial(edge.lineAt! - cyl.lineAt!, d);
  final h = w.length;
  if ((h - r).abs() > 1e-6) {
    // An edge OFF the surface has two tangent planes through it as well, but
    // an edge that is not on the cylinder is far more likely a mis-pick than a
    // request, so this says so instead of choosing.
    return WorkAttempt.no('${edge.label} does not lie on ${cyl.label} — it is '
        '${(h - r).abs().toStringAsFixed(3)} mm off it.');
  }
  final def = 'Tangent to ${cyl.label} through ${edge.label}';
  return WorkAttempt.ok(
      _tangentAt(cyl, w.normalized(), edge.lineAt!, def), def);
}

WorkAttempt<WorkPlaneSolution> _tangentParallelToPlane(
    WorkRef cyl, WorkRef plane) {
  if (!plane.hasPlane) {
    return WorkAttempt.no('${plane.label} is not a plane or planar face.');
  }
  final d = cyl.lineDir!;
  final n = plane.planeNormal!;
  // A tangent plane's normal is perpendicular to the axis, so a plane whose
  // normal is not can never have a tangent parallel to it.
  final along = n.dot(d).abs();
  if (along > 1e-6) {
    return WorkAttempt.no('${plane.label} is not parallel to the axis of '
        '${cyl.label} — no tangent plane is parallel to it.');
  }
  final def = 'Tangent to ${cyl.label}, parallel to ${plane.label}';
  final m = _sideChosen(cyl, [n, n * -1.0]);
  if (m == null) {
    return WorkAttempt.no('Two planes are tangent to ${cyl.label} parallel to '
        '${plane.label} — tap the face on the side the plane should go.');
  }
  return WorkAttempt.ok(
      _tangentAt(cyl, m, cyl.hitAt ?? cyl.lineAt!, def), def);
}

WorkAttempt<WorkPlaneSolution> _threePointPlane(WorkRef a, WorkRef b, WorkRef c) {
  final n = (b.point! - a.point!).cross(c.point! - a.point!);
  if (n.length < 1e-12) {
    // Collinear (or two of them in the same place): an infinity of planes
    // contains them, which is not an answer. Say which, and by how much, the
    // way every other refusal in this file does.
    return WorkAttempt.no('${a.label}, ${b.label} and ${c.label} are in a '
        'line — three points must not be collinear.');
  }
  final def = 'Through ${a.label}, ${b.label} and ${c.label}';
  return WorkAttempt.ok(
      WorkPlaneSolution(a.point!, n.normalized(), def), def);
}

WorkAttempt<WorkPlaneSolution> _twoEdgePlane(WorkRef a, WorkRef b) {
  final d1 = a.lineDir!, d2 = b.lineDir!;
  final between = b.lineAt! - a.lineAt!;
  final cross = d1.cross(d2);
  if (cross.length < 1e-9) {
    // Parallel: the plane is the one containing both, so its normal is
    // perpendicular to the shared direction and to the gap between them.
    final n = d1.cross(between);
    if (n.length < 1e-9) {
      return WorkAttempt.no('${a.label} and ${b.label} are the same line — '
          'a plane needs two distinct edges.');
    }
    final def = 'Through ${a.label} and ${b.label}';
    return WorkAttempt.ok(
        WorkPlaneSolution(a.lineAt!, n.normalized(), def), def);
  }
  // Not parallel: they must MEET, or there is no plane containing both. The
  // triple product is the volume of the box they span, i.e. their gap times
  // the area of the direction parallelogram.
  final gap = between.dot(cross) / cross.length;
  if (gap.abs() > 1e-6) {
    return WorkAttempt.no('${a.label} and ${b.label} are skew — they miss '
        'each other by ${gap.abs().toStringAsFixed(3)} mm.');
  }
  final def = 'Through ${a.label} and ${b.label}';
  return WorkAttempt.ok(
      WorkPlaneSolution(a.lineAt!, cross.normalized(), def), def);
}
