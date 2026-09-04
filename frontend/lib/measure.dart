// M371 — MEASURE. The geometry, and nothing else.
//
// Deliberately free of Flutter widgets, AppState and the kernel, for the same
// reason work_features.dart is: deciding WHAT a pair of picks measures is
// arithmetic, and arithmetic should be testable without a device, a camera or
// a widget tree. The viewports supply picks (measure_pick.dart), this file
// decides what they mean, app_state holds the session and the panel draws it.
//
// ---------------------------------------------------------------------------
// What Inventor's Measure actually does (researched 2026-09, Autodesk help
// "To Measure Distance, Length, Angle, Loop, or Area in Models or Drawings",
// the 2018 "Measure Enhancements" release note, and the Inventor blog post
// that introduced the panel)
// ---------------------------------------------------------------------------
//
// Inventor used to have four commands — Distance, Angle, Loop, Area — and
// 2018 replaced all four with ONE, driven by an information-rich modeless
// panel. The behaviours that matter, and which of them this file implements:
//
//   * ONE selection reports SEVERAL values at once. "Each selection displays
//     rich information with a single click. For example, when you select a
//     cylindrical face, the diameter, area, and total loop length display."
//     This is the single most important thing to copy, and it is why
//     [MeasureReading] carries a LIST of values rather than one number: a tap
//     on a hole should answer every question you could have had about it.
//
//   * TWO selections report a distance or an angle, chosen from what the two
//     picks ARE — never asked for up front. Two parallel faces give a
//     distance; two faces that meet give an angle; two skew edges give both.
//
//   * The distance has THREE readings you can toggle between: Minimum
//     Distance, Center to Center and Maximum Distance. They are genuinely
//     different questions about the same pair, which is why [MeasureReading]
//     reports the one you asked for and lists the others as available.
//
//   * Values can be SUMMED. "You can add the values of several linear, area,
//     volume, and/or angle measurements to calculate a total measurement for
//     each measurement type." — see [MeasureTotals].
//
//   * Dual units and precision live in the panel and the result re-renders
//     when either changes, so nothing here formats to a fixed shape: the
//     numbers come out as doubles in MILLIMETRES and RADIANS and the display
//     layer decides how to write them.
//
//   * One value or all of them can be copied to the clipboard.
//
// NOT copied, and why:
//
//   * MASS. Inventor reports it for a component because its material carries
//     a density. This app's materials are appearance only (materials.dart says
//     so in its first line), so a mass here would be a number multiplied by a
//     density nobody chose. Volume is reported instead, which is the half of
//     it the model actually knows.
//
//   * Selection PRIORITY (Component / Part / Faces and Edges). The pickers
//     answer with the smallest thing under the finger and offer the body as a
//     fallback; on a touch screen a priority combo box is a mode to get stuck
//     in. [MeasureRefKind.body] still exists so that a deliberate body pick
//     measures the body.
//
// ---------------------------------------------------------------------------
// The shape of the answer
// ---------------------------------------------------------------------------
//
// Everything in this file is in MILLIMETRES and RADIANS, and every function
// is pure. Strings appear in exactly one place — [measureRoleLabel] and
// [measureRefLabel] at the bottom — and they read [L.current] the way
// work_features.dart does, because a toast raised from business logic has no
// BuildContext and should never grow one.
//
// The 2D sketcher measures through the SAME code as the 3D part: a sketch
// point (x, y) enters as Vec3(x, y, 0). Distances, angles and areas are
// identical in that embedding, so there is one implementation of "the
// distance between two circles" rather than a flat one and a solid one that
// can disagree.
import 'dart:math' as math;

import 'l10n/fmt.dart';
import 'l10n/l.dart';
import 'part_model.dart' show Vec3;

/// The current strings. See the file header: no BuildContext lives here.
AppL10n get _t => L.current;

// ===========================================================================
// what a pick IS
// ===========================================================================

/// The kind of thing that was picked.
///
/// This is a discriminator, not the geometry: the geometry lives in
/// [MeasureRef]'s carrier fields, and the solvers read those. What the kind
/// decides is the WORDING ("Zylindrische Fläche") and the handful of places
/// where two picks with identical carriers still mean different things — a
/// circular edge and a cylindrical face both give a centre, an axis and a
/// radius, but only the edge has a length.
enum MeasureRefKind {
  /// A B-Rep vertex, a sketch point, a work point, the origin centre point,
  /// or a snapped endpoint/midpoint/centre/quadrant.
  point,

  /// A straight edge or a sketch line: finite, with two ends.
  line,

  /// An INFINITE line — an origin axis, a work axis, a cylinder's axis of
  /// revolution once it has been reduced to one.
  axis,

  /// A full circular edge or sketch circle.
  circle,

  /// A circular edge or sketch arc that does not close.
  arc,

  /// An elliptical edge or a sketch ellipse.
  ellipse,

  /// A spline, a polyline or any curve with no analytic record: it has a
  /// length and (when closed) an area, and nothing else.
  curve,

  /// A planar face, an origin plane or a work plane.
  plane,

  cylinder,
  cone,
  sphere,
  torus,

  /// A whole solid body.
  body,

  /// A whole assembly component (one or more bodies under one placement).
  component,
}

/// What a tap is allowed to answer with — Inventor's selection priority.
///
/// Inventor's Measure carries a Component / Part / Faces and Edges combo box
/// and defaults to the last. This is the same idea with the documents this app
/// has, and it lives HERE rather than beside the pickers that read it because
/// the session has to remember the choice and the session is in this file: one
/// enum that both halves name, instead of two that can drift.
enum MeasurePriority {
  /// A face, an edge or a vertex. Inventor's default, and this one's.
  entity,

  /// The whole solid body under the finger: volume, surface area, extents.
  body,

  /// The whole component under the finger. Assembly only.
  component,
}

/// Everything a picked entity can be measured as.
///
/// Modelled on [WorkRef] and for the same reason: a pick is not "a face" or
/// "an edge", it is the set of primitives it can stand in for, and a solver
/// that switched on the pick's TYPE would need a case per pair of types. A
/// circular edge is a point (its centre) AND a line (its axis) AND a plane
/// (the plane it lies in) AND a curve with a length — and which of those
/// matters depends entirely on what else was picked.
///
/// What this adds over [WorkRef] is the INTRINSIC quantities: a work axis
/// only ever needed to say where it was, a measurement has to say how long,
/// how big and how much.
class MeasureRef {
  const MeasureRef._({
    required this.kind,
    this.owner,
    this.point,
    this.a,
    this.b,
    this.lineAt,
    this.lineDir,
    this.planeAt,
    this.planeNormal,
    this.planeIsOriented = false,
    this.axisAt,
    this.axisDir,
    this.radius,
    this.minorRadius,
    this.sweep,
    this.length,
    this.area,
    this.volume,
    this.perimeter,
    this.boxLo,
    this.boxHi,
    this.hitAt,
    this.samples = const [],
    this.mesh,
    this.closed = false,
    this.shape,
  });

  final MeasureRefKind kind;

  /// Which component / body this came from, for the panel's subtitle and for
  /// the "same thing picked twice" guard. Null in a part with one body and in
  /// the 2D sketcher, where there is nothing to disambiguate.
  final String? owner;

  // ---- carriers -----------------------------------------------------------

  /// The one point this pick stands for: a vertex, a centre, an edge's
  /// midpoint. Null when the pick has no single meaningful point (a cylinder
  /// does not, which is exactly why Inventor's Center to Center refuses one).
  final Vec3? point;

  /// The ENDS, when the pick is a finite segment. Both null or both set.
  final Vec3? a, b;

  /// A point on the (possibly infinite) line, and its unit direction. Set for
  /// [MeasureRefKind.line] as well, where it duplicates [a]/[b] — the solvers
  /// that only care about direction then need no special case.
  final Vec3? lineAt, lineDir;

  /// A point on the plane and its unit normal.
  final Vec3? planeAt, planeNormal;

  /// True when [planeNormal] is a face's OUTWARD normal rather than an
  /// arbitrary orientation.
  ///
  /// This is the whole of the plane-angle ambiguity in one bool. Two faces of
  /// a 30° wedge have outward normals 150° apart and a dihedral of 30°; two
  /// faces of a 150° wedge have normals 30° apart and a dihedral of 150°. The
  /// angle between the two PLANES cannot tell them apart — `acos|n1·n2|`
  /// answers 30° for both — but the outward normals can: the dihedral is
  /// `180° − angle(n1, n2)`. A work plane's normal points wherever its
  /// construction happened to leave it, so it gets the unsigned answer and
  /// says so. See [_planeAngle].
  final bool planeIsOriented;

  /// The axis of revolution of a cylinder, cone, torus or circular edge.
  /// Separate from [lineAt]/[lineDir] because a circular EDGE offers both a
  /// curve and an axis, and they are not the same line.
  final Vec3? axisAt, axisDir;

  /// Circle/cylinder/sphere radius, cone reference radius, torus MAJOR
  /// radius, ellipse MAJOR radius.
  final double? radius;

  /// Ellipse minor radius. (A torus's minor radius is not in the kernel's
  /// surface record, so a torus leaves this null rather than guessing.)
  final double? minorRadius;

  /// Included angle of an arc, in radians. Null for a full circle.
  final double? sweep;

  // ---- intrinsics ---------------------------------------------------------

  /// Curve length: exact for a line, a circle and an arc; the tessellated
  /// polyline length for a spline, which is within the display deflection.
  final double? length;

  /// Face area, or the area enclosed by a closed sketch curve.
  final double? area;

  /// Solid volume.
  final double? volume;

  /// Total length of the loops bounding a face — Inventor's "total loop
  /// length".
  final double? perimeter;

  /// Axis-aligned bounds of a body or component.
  final Vec3? boxLo, boxHi;

  /// Where the ray actually landed. Used for the annotation's leader and for
  /// the on-surface reading of a cylinder, never for the value itself.
  final Vec3? hitAt;

  /// The pick's polyline, world space. Kept for two things and nothing else:
  /// drawing the highlight, and the minimum-distance solver, which walks it.
  /// Empty when the pick is not a curve.
  final List<Vec3> samples;

  /// True when [samples] closes on itself.
  final bool closed;

  /// The pick's tessellation, for a body or a component.
  ///
  /// Only these two kinds carry one, and only because their closest approach
  /// has no closed form — see [nearestBetweenMeshes]. Everything else in this
  /// class is analytic, and a mesh hanging off a face would be an invitation
  /// to answer a question the surface record already answers exactly.
  final MeasureMesh? mesh;

  /// What this pick LOOKS like, when tracing [samples] is not enough (M374).
  ///
  /// A face has no polyline and no closed form for its outline, so before
  /// this it highlighted as a nine-point ring at the spot the finger landed —
  /// which is not a highlight of the face, it is a highlight of the tap. The
  /// picker now hands over the face's own triangles and its boundary loops,
  /// and the overlay washes the whole face the way the sketch-plane
  /// prehighlight already does.
  ///
  /// PURELY VISUAL. No solver reads it, and none may: every question this
  /// class answers about a face is answered exactly by the surface record,
  /// and letting the tessellation into the arithmetic would replace an exact
  /// answer with a deflection-dependent one. [samples] is the field that is
  /// both drawn and measured; this one is only drawn.
  final MeasureShape? shape;

  /// This pick with [shape] attached.
  ///
  /// A copy rather than a parameter on all fourteen factories: the shape is
  /// gathered from the mesh, the factories take analytic records, and
  /// threading a drawing-only argument through every one of them would put it
  /// where a solver could reach for it.
  MeasureRef withShape(MeasureShape? s) => MeasureRef._(
        kind: kind,
        owner: owner,
        point: point,
        a: a,
        b: b,
        lineAt: lineAt,
        lineDir: lineDir,
        planeAt: planeAt,
        planeNormal: planeNormal,
        planeIsOriented: planeIsOriented,
        axisAt: axisAt,
        axisDir: axisDir,
        radius: radius,
        minorRadius: minorRadius,
        sweep: sweep,
        length: length,
        area: area,
        volume: volume,
        perimeter: perimeter,
        boxLo: boxLo,
        boxHi: boxHi,
        hitAt: hitAt,
        samples: samples,
        mesh: mesh,
        closed: closed,
        shape: s,
      );

  // ---- constructors -------------------------------------------------------

  /// A vertex, a sketch point, a work point, a snapped midpoint or centre.
  factory MeasureRef.point(Vec3 p, {String? owner}) =>
      MeasureRef._(kind: MeasureRefKind.point, point: p, owner: owner);

  /// A straight edge or a sketch line.
  factory MeasureRef.segment(Vec3 a, Vec3 b, {String? owner, Vec3? hitAt}) {
    final d = b - a;
    final len = d.length;
    return MeasureRef._(
      kind: MeasureRefKind.line,
      owner: owner,
      a: a,
      b: b,
      // The MIDPOINT, which is what makes "Center to Center" between two
      // edges mean what Inventor means by it.
      point: (a + b) * 0.5,
      lineAt: a,
      lineDir: len < 1e-12 ? const Vec3(1, 0, 0) : d * (1 / len),
      length: len,
      samples: [a, b],
      hitAt: hitAt,
    );
  }

  /// An INFINITE line: an origin axis, a work axis.
  factory MeasureRef.axis(Vec3 at, Vec3 dir, {String? owner}) => MeasureRef._(
        kind: MeasureRefKind.axis,
        owner: owner,
        lineAt: at,
        lineDir: dir.normalized(),
        axisAt: at,
        axisDir: dir.normalized(),
      );

  /// A full circular edge or a sketch circle.
  ///
  /// Offers its centre, its axis, the plane it lies in, its radius and its
  /// circumference — every one of which Inventor reaches through it.
  factory MeasureRef.circle(Vec3 centre, Vec3 axis, double r,
      {String? owner, List<Vec3> samples = const [], Vec3? hitAt}) {
    final n = axis.normalized();
    return MeasureRef._(
      kind: MeasureRefKind.circle,
      owner: owner,
      point: centre,
      axisAt: centre,
      axisDir: n,
      planeAt: centre,
      planeNormal: n,
      radius: r,
      length: 2 * math.pi * r,
      area: math.pi * r * r,
      samples: samples,
      closed: true,
      hitAt: hitAt,
    );
  }

  /// A circular edge or sketch arc that does not close. [sweep] is the
  /// included angle in radians.
  factory MeasureRef.arc(Vec3 centre, Vec3 axis, double r, double sweep,
      {String? owner, List<Vec3> samples = const [], Vec3? hitAt}) {
    final n = axis.normalized();
    return MeasureRef._(
      kind: MeasureRefKind.arc,
      owner: owner,
      // An arc's POINT is its centre, not its midpoint: that is the thing you
      // dimension a hole pattern from, and it is what a fillet's arc means.
      point: centre,
      axisAt: centre,
      axisDir: n,
      planeAt: centre,
      planeNormal: n,
      radius: r,
      sweep: sweep,
      length: r * sweep.abs(),
      samples: samples,
      hitAt: hitAt,
    );
  }

  /// An elliptical edge or a sketch ellipse. [length] is the tessellated
  /// perimeter when one is known, else Ramanujan's approximation.
  factory MeasureRef.ellipse(Vec3 centre, Vec3 axis, double major, double minor,
      {String? owner,
      double? length,
      List<Vec3> samples = const [],
      Vec3? hitAt}) {
    final n = axis.normalized();
    return MeasureRef._(
      kind: MeasureRefKind.ellipse,
      owner: owner,
      point: centre,
      axisAt: centre,
      axisDir: n,
      planeAt: centre,
      planeNormal: n,
      radius: major,
      minorRadius: minor,
      length: length ?? ellipsePerimeter(major, minor),
      area: math.pi * major * minor,
      samples: samples,
      closed: true,
      hitAt: hitAt,
    );
  }

  /// A spline, a polyline, or any curve with no analytic record.
  ///
  /// [samples] is the curve as it is drawn, so its length is the length the
  /// user can see; [area] is only meaningful (and only supplied) when the
  /// curve closes.
  factory MeasureRef.curve(List<Vec3> samples,
      {String? owner, bool closed = false, Vec3? planeNormal, Vec3? hitAt}) {
    final len = polylineLength(samples);
    return MeasureRef._(
      kind: MeasureRefKind.curve,
      owner: owner,
      a: samples.isEmpty ? null : samples.first,
      b: samples.isEmpty ? null : samples.last,
      // A closed curve's point is its centroid; an open one's is its middle.
      point: samples.isEmpty
          ? null
          : (closed ? _centroid(samples) : polylineMidpoint(samples)),
      length: len,
      area: closed && planeNormal != null
          ? planarLoopArea(samples, planeNormal)
          : null,
      planeAt: closed && planeNormal != null && samples.isNotEmpty
          ? samples.first
          : null,
      planeNormal: closed ? planeNormal : null,
      samples: samples,
      closed: closed,
      hitAt: hitAt,
    );
  }

  /// A planar face, an origin plane or a work plane.
  ///
  /// [oriented] must be true only when [normal] is a face's OUTWARD normal —
  /// see [planeIsOriented], which is the whole of the dihedral ambiguity.
  factory MeasureRef.plane(Vec3 at, Vec3 normal,
          {String? owner,
          bool oriented = false,
          double? area,
          double? perimeter,
          Vec3? hitAt}) =>
      MeasureRef._(
        kind: MeasureRefKind.plane,
        owner: owner,
        planeAt: at,
        planeNormal: normal.normalized(),
        planeIsOriented: oriented,
        area: area,
        perimeter: perimeter,
        hitAt: hitAt,
      );

  /// A cylindrical face. [height] is the extent along the axis, which is what
  /// makes a tap on a hole answer "how deep" as well as "how wide".
  factory MeasureRef.cylinder(Vec3 axisAt, Vec3 axisDir, double r,
          {String? owner,
          double? height,
          double? area,
          double? perimeter,
          Vec3? hitAt}) =>
      MeasureRef._(
        kind: MeasureRefKind.cylinder,
        owner: owner,
        axisAt: axisAt,
        axisDir: axisDir.normalized(),
        lineAt: axisAt,
        lineDir: axisDir.normalized(),
        radius: r,
        length: height,
        area: area,
        perimeter: perimeter,
        hitAt: hitAt,
      );

  /// A conical face. The kernel's surface record carries the axis and a
  /// REFERENCE radius but not the half-angle, so that is all this claims.
  factory MeasureRef.cone(Vec3 axisAt, Vec3 axisDir,
          {String? owner,
          double? radius,
          double? area,
          double? perimeter,
          Vec3? hitAt}) =>
      MeasureRef._(
        kind: MeasureRefKind.cone,
        owner: owner,
        axisAt: axisAt,
        axisDir: axisDir.normalized(),
        lineAt: axisAt,
        lineDir: axisDir.normalized(),
        radius: radius,
        area: area,
        perimeter: perimeter,
        hitAt: hitAt,
      );

  factory MeasureRef.sphere(Vec3 centre,
          {String? owner,
          double? radius,
          double? area,
          double? perimeter,
          Vec3? hitAt}) =>
      MeasureRef._(
        kind: MeasureRefKind.sphere,
        owner: owner,
        point: centre,
        radius: radius,
        area: area,
        perimeter: perimeter,
        hitAt: hitAt,
      );

  factory MeasureRef.torus(Vec3 centre, Vec3 axis,
          {String? owner,
          double? majorRadius,
          double? area,
          double? perimeter,
          Vec3? hitAt}) =>
      MeasureRef._(
        kind: MeasureRefKind.torus,
        owner: owner,
        point: centre,
        axisAt: centre,
        axisDir: axis.normalized(),
        planeAt: centre,
        // A torus's midplane is a real plane through its centre, and it is
        // the one a "distance to the torus" wants.
        planeNormal: axis.normalized(),
        radius: majorRadius,
        area: area,
        perimeter: perimeter,
        hitAt: hitAt,
      );

  /// A whole solid body, or a whole assembly component.
  factory MeasureRef.solid(
    Vec3 lo,
    Vec3 hi, {
    required bool component,
    String? owner,
    double? volume,
    double? area,
    MeasureMesh? mesh,
    Vec3? hitAt,
  }) =>
      MeasureRef._(
        kind: component ? MeasureRefKind.component : MeasureRefKind.body,
        owner: owner,
        point: (lo + hi) * 0.5,
        boxLo: lo,
        boxHi: hi,
        volume: volume,
        area: area,
        mesh: mesh,
        hitAt: hitAt,
      );

  // ---- what this pick can answer -----------------------------------------

  bool get hasPoint => point != null;
  bool get hasLine => lineAt != null && lineDir != null;
  bool get hasSegment => a != null && b != null;
  bool get hasPlane => planeAt != null && planeNormal != null;
  bool get hasAxis => axisAt != null && axisDir != null;
  bool get hasRadius => radius != null && radius! > 1e-12;

  /// True for the picks that stand for a round thing — the ones whose
  /// "distance" is naturally measured to a centre or an axis rather than to a
  /// surface.
  bool get isRound =>
      kind == MeasureRefKind.circle ||
      kind == MeasureRefKind.arc ||
      kind == MeasureRefKind.cylinder ||
      kind == MeasureRefKind.sphere ||
      kind == MeasureRefKind.torus;

  /// True for a pick that has a finite extent — the precondition for a
  /// Maximum Distance reading.
  ///
  /// Stated as the four kinds that are NOT bounded rather than as the ten
  /// that are: an axis, a plane, a cylinder and a cone all run to infinity,
  /// and everything else in the enum has ends. Written the other way round it
  /// grew a hole the moment a plain POINT was asked — a point is as bounded
  /// as geometry gets, and it carries neither samples, nor ends, nor a box.
  bool get isBounded =>
      kind != MeasureRefKind.axis &&
      kind != MeasureRefKind.plane &&
      kind != MeasureRefKind.cylinder &&
      kind != MeasureRefKind.cone;

  /// Signed plane constant: `normal · x == planeD` for every x on the plane.
  double get planeD => planeAt!.dot(planeNormal!);

  /// True when [o] is the SAME piece of geometry, picked again.
  ///
  /// What it is for: tapping a face that is already in the selection takes it
  /// back out, which is how every selection in this app and in Inventor
  /// behaves and is the only way to undo a mis-tap without restarting the
  /// measurement.
  ///
  /// Compared on the defining numbers rather than on identity, because the
  /// two picks are built by separate runs of the picker and are never the
  /// same object. The tolerance is absolute and tight: two picks of one face
  /// agree bit for bit (they read the same surface record), and 1e-7 mm is
  /// far below anything two DIFFERENT features of one model sit apart.
  bool sameAs(MeasureRef o, {double tol = 1e-7}) {
    if (kind != o.kind || owner != o.owner) return false;
    bool near(Vec3? a, Vec3? b) {
      if (a == null || b == null) return a == null && b == null;
      return (a - b).length <= tol;
    }

    bool sameNum(double? a, double? b) {
      if (a == null || b == null) return a == null && b == null;
      return (a - b).abs() <= tol;
    }

    return near(point, o.point) &&
        near(a, o.a) &&
        near(b, o.b) &&
        near(lineAt, o.lineAt) &&
        near(lineDir, o.lineDir) &&
        near(planeAt, o.planeAt) &&
        near(planeNormal, o.planeNormal) &&
        near(axisAt, o.axisAt) &&
        near(axisDir, o.axisDir) &&
        sameNum(radius, o.radius);
  }

  /// The points this pick's EXTREMES live at, for Maximum Distance and for
  /// the bounding-box fallbacks. Empty when the pick is unbounded.
  List<Vec3> get extremePoints {
    if (samples.isNotEmpty) return samples;
    if (hasSegment) return [a!, b!];
    final lo = boxLo, hi = boxHi;
    if (lo != null && hi != null) {
      return [
        for (final x in [lo.x, hi.x])
          for (final y in [lo.y, hi.y])
            for (final z in [lo.z, hi.z]) Vec3(x, y, z)
      ];
    }
    if (isRound && hasRadius && hasAxis) {
      // Four points round the rim is enough for a maximum: the extreme of a
      // circle against any other point set is on the rim, and the rim's own
      // extent is captured by two opposed pairs.
      final n = axisDir!;
      final u = _anyPerp(n), v = n.cross(u).normalized();
      return [
        axisAt! + u * radius!,
        axisAt! - u * radius!,
        axisAt! + v * radius!,
        axisAt! - v * radius!,
      ];
    }
    if (hasPoint) return [point!];
    return const [];
  }
}

// ===========================================================================
// what comes back
// ===========================================================================

/// The physical dimension of a measured value. Decides which unit the display
/// layer writes after the number, and which running total it joins.
enum MeasureUnitKind { length, angle, area, volume }

/// One measured quantity. The ROLE is what it means; the unit follows from it.
///
/// Enum-and-double rather than a formatted string, deliberately: the panel's
/// precision and dual-unit controls re-render the same reading, and a reading
/// that had already been turned into "12,50 mm" could not be re-rendered at
/// four decimals or in inches without parsing its own output back.
enum MeasureRole {
  // --- intrinsic, one pick ---
  length,
  arcLength,
  radius,
  diameter,
  circumference,
  includedAngle,
  majorRadius,
  minorRadius,
  area,
  perimeter,
  volume,
  height,
  surfaceArea,
  positionX,
  positionY,
  positionZ,
  extentX,
  extentY,
  extentZ,

  // --- two picks ---
  distance,
  centreDistance,
  maximumDistance,
  deltaX,
  deltaY,
  deltaZ,
  angle,

  /// The other angle at the same crossing (180° − [angle]).
  ///
  /// Reported alongside a non-right angle because the angle between two
  /// PLANES is genuinely two numbers and a panel that shows one of them
  /// without saying so is the classic way a CAD measurement lies. See
  /// [MeasureRef.planeIsOriented].
  supplementAngle,

  /// Distance from a point or an axis to a round thing's SURFACE, as opposed
  /// to its centre — "wie weit ist es bis zur Bohrungswand".
  surfaceDistance,
}

MeasureUnitKind measureRoleUnit(MeasureRole r) {
  switch (r) {
    case MeasureRole.includedAngle:
    case MeasureRole.angle:
    case MeasureRole.supplementAngle:
      return MeasureUnitKind.angle;
    case MeasureRole.area:
    case MeasureRole.surfaceArea:
      return MeasureUnitKind.area;
    case MeasureRole.volume:
      return MeasureUnitKind.volume;
    default:
      return MeasureUnitKind.length;
  }
}

/// One row of the panel: a role and a number, in mm or radians.
class MeasureValue {
  const MeasureValue(this.role, this.value, {this.approximate = false});

  final MeasureRole role;

  /// Millimetres, square millimetres, cubic millimetres or RADIANS, by
  /// [measureRoleUnit]. Never degrees — the display layer converts.
  final double value;

  /// True when the number came from the tessellation rather than the
  /// analytic geometry (a spline's length, a curved face's area). The panel
  /// marks these with a "≈", because a measurement that is quietly
  /// approximate is worse than one that says so.
  final bool approximate;

  MeasureUnitKind get unit => measureRoleUnit(role);

  @override
  String toString() => '${role.name}=$value${approximate ? '~' : ''}';
}

/// Which of Inventor's three distance questions a reading answers.
enum MeasureDistanceMode {
  /// The closest approach of the two picks. The default, and Inventor's.
  minimum,

  /// Between the two picks' representative points — centre to centre for two
  /// holes, midpoint to midpoint for two edges.
  centre,

  /// The furthest apart the two picks get. Only defined when both are
  /// bounded.
  maximum,
}

/// What the viewport draws over the model to show what was measured.
enum MeasureMarkerKind {
  /// A dimension line between [MeasureMarker.a] and [MeasureMarker.b].
  span,

  /// An angle between two arms meeting at an apex.
  angle,

  /// A single highlighted point.
  point,

  /// A radius or diameter line across a round pick.
  radial,
}

class MeasureMarker {
  const MeasureMarker.span(Vec3 this.a, Vec3 this.b)
      : kind = MeasureMarkerKind.span,
        apex = null,
        armA = null,
        armB = null;

  const MeasureMarker.point(Vec3 this.a)
      : kind = MeasureMarkerKind.point,
        b = null,
        apex = null,
        armA = null,
        armB = null;

  const MeasureMarker.radial(Vec3 this.a, Vec3 this.b)
      : kind = MeasureMarkerKind.radial,
        apex = null,
        armA = null,
        armB = null;

  const MeasureMarker.angle(Vec3 this.apex, Vec3 this.armA, Vec3 this.armB)
      : kind = MeasureMarkerKind.angle,
        a = null,
        b = null;

  final MeasureMarkerKind kind;
  final Vec3? a, b;
  final Vec3? apex, armA, armB;
}

/// The answer: what was measured, every number it produced, and what to draw.
class MeasureReading {
  const MeasureReading({
    required this.refs,
    required this.values,
    this.marker,
    this.mode,
    this.modes = const [],
  });

  /// The picks this reading came from, in pick order. The panel titles itself
  /// from their kinds ("Fläche → Zylindrische Fläche").
  final List<MeasureRef> refs;

  /// Every measured quantity, PRIMARY FIRST. Never empty — a solver with
  /// nothing to say returns null instead.
  final List<MeasureValue> values;

  final MeasureMarker? marker;

  /// Which distance question this answered, when it was a distance at all.
  final MeasureDistanceMode? mode;

  /// The distance questions this pair can answer, so the panel can offer only
  /// the toggles that mean something. Empty for a one-pick reading.
  final List<MeasureDistanceMode> modes;

  MeasureValue get primary => values.first;

  /// The value for [role], or null.
  MeasureValue? valueOf(MeasureRole role) {
    for (final v in values) {
      if (v.role == role) return v;
    }
    return null;
  }

  @override
  String toString() => 'MeasureReading(${values.join(", ")})';
}

// ===========================================================================
// the entry point
// ===========================================================================

/// The reading for [refs], or null when they measure nothing.
///
/// One pick reports that pick's intrinsics; two report the relation between
/// them; three POINTS report the angle at the middle one, which is the only
/// three-pick measurement Inventor has and the only one that is unambiguous.
/// Anything else is a pick list the session should have trimmed.
MeasureReading? measure(List<MeasureRef> refs,
    {MeasureDistanceMode mode = MeasureDistanceMode.minimum}) {
  if (refs.isEmpty) return null;
  if (refs.length == 1) return measureSingle(refs.first);
  if (refs.length == 2) return measurePair(refs[0], refs[1], mode: mode);
  if (refs.length == 3 && refs.every((r) => r.kind == MeasureRefKind.point)) {
    return measureAngleAtVertex(refs[0], refs[1], refs[2]);
  }
  return measurePair(refs[refs.length - 2], refs.last, mode: mode);
}

// ===========================================================================
// one pick
// ===========================================================================

/// Everything one pick knows about itself, primary value first.
///
/// This is the function that makes the tool feel like Inventor's: a tap on a
/// hole answers diameter AND radius AND depth AND area, because the question
/// you actually had was one of those and asking you to say which first would
/// cost a mode.
MeasureReading? measureSingle(MeasureRef r) {
  final v = <MeasureValue>[];
  MeasureMarker? marker;

  switch (r.kind) {
    case MeasureRefKind.point:
      final p = r.point!;
      v.addAll([
        MeasureValue(MeasureRole.positionX, p.x),
        MeasureValue(MeasureRole.positionY, p.y),
        MeasureValue(MeasureRole.positionZ, p.z),
      ]);
      marker = MeasureMarker.point(p);
      break;

    case MeasureRefKind.line:
      final a = r.a!, b = r.b!;
      final d = b - a;
      v.add(MeasureValue(MeasureRole.length, r.length ?? d.length));
      v.addAll([
        MeasureValue(MeasureRole.deltaX, d.x.abs()),
        MeasureValue(MeasureRole.deltaY, d.y.abs()),
        MeasureValue(MeasureRole.deltaZ, d.z.abs()),
      ]);
      marker = MeasureMarker.span(a, b);
      break;

    case MeasureRefKind.axis:
      // An infinite line has no length and no ends. Nothing to report on its
      // own; it is a perfectly good HALF of a pair, so the session prompts
      // for a second pick rather than saying "no".
      return null;

    case MeasureRefKind.circle:
      final rad = r.radius ?? 0;
      v.addAll([
        MeasureValue(MeasureRole.diameter, 2 * rad),
        MeasureValue(MeasureRole.radius, rad),
        MeasureValue(MeasureRole.circumference, r.length ?? 2 * math.pi * rad),
        if (r.area != null) MeasureValue(MeasureRole.area, r.area!),
      ]);
      _addPosition(v, r.point);
      marker = _radialMarker(r);
      break;

    case MeasureRefKind.arc:
      final rad = r.radius ?? 0;
      v.addAll([
        MeasureValue(MeasureRole.arcLength, r.length ?? 0),
        MeasureValue(MeasureRole.radius, rad),
        MeasureValue(MeasureRole.diameter, 2 * rad),
        if (r.sweep != null)
          MeasureValue(MeasureRole.includedAngle, r.sweep!.abs()),
      ]);
      _addPosition(v, r.point);
      marker = _radialMarker(r);
      break;

    case MeasureRefKind.ellipse:
      v.addAll([
        MeasureValue(MeasureRole.circumference, r.length ?? 0,
            approximate: true),
        if (r.radius != null) MeasureValue(MeasureRole.majorRadius, r.radius!),
        if (r.minorRadius != null)
          MeasureValue(MeasureRole.minorRadius, r.minorRadius!),
        if (r.area != null) MeasureValue(MeasureRole.area, r.area!),
      ]);
      _addPosition(v, r.point);
      break;

    case MeasureRefKind.curve:
      v.add(MeasureValue(MeasureRole.length, r.length ?? 0,
          approximate: true));
      if (r.area != null) {
        v.add(MeasureValue(MeasureRole.area, r.area!, approximate: true));
      }
      if (r.samples.length >= 2 && !r.closed) {
        final d = r.samples.last - r.samples.first;
        v.addAll([
          MeasureValue(MeasureRole.deltaX, d.x.abs()),
          MeasureValue(MeasureRole.deltaY, d.y.abs()),
          MeasureValue(MeasureRole.deltaZ, d.z.abs()),
        ]);
        marker = MeasureMarker.span(r.samples.first, r.samples.last);
      }
      break;

    case MeasureRefKind.plane:
      if (r.area != null) {
        v.add(MeasureValue(MeasureRole.area, r.area!));
      }
      if (r.perimeter != null) {
        v.add(MeasureValue(MeasureRole.perimeter, r.perimeter!,
            approximate: true));
      }
      // A work plane or an origin plane has neither. It is still half of a
      // pair, so say nothing rather than something wrong.
      if (v.isEmpty) return null;
      break;

    case MeasureRefKind.cylinder:
      final rad = r.radius ?? 0;
      v.addAll([
        MeasureValue(MeasureRole.diameter, 2 * rad),
        MeasureValue(MeasureRole.radius, rad),
        if (r.length != null) MeasureValue(MeasureRole.height, r.length!),
        if (r.area != null) MeasureValue(MeasureRole.area, r.area!,
            approximate: true),
        if (r.perimeter != null)
          MeasureValue(MeasureRole.perimeter, r.perimeter!, approximate: true),
      ]);
      marker = _cylinderMarker(r);
      break;

    case MeasureRefKind.cone:
      v.addAll([
        if (r.radius != null && r.radius! > 1e-12) ...[
          MeasureValue(MeasureRole.diameter, 2 * r.radius!),
          MeasureValue(MeasureRole.radius, r.radius!),
        ],
        if (r.area != null)
          MeasureValue(MeasureRole.area, r.area!, approximate: true),
        if (r.perimeter != null)
          MeasureValue(MeasureRole.perimeter, r.perimeter!, approximate: true),
      ]);
      if (v.isEmpty) return null;
      break;

    case MeasureRefKind.sphere:
      final rad = r.radius ?? 0;
      v.addAll([
        MeasureValue(MeasureRole.diameter, 2 * rad),
        MeasureValue(MeasureRole.radius, rad),
        if (r.area != null)
          MeasureValue(MeasureRole.area, r.area!, approximate: true),
      ]);
      _addPosition(v, r.point);
      break;

    case MeasureRefKind.torus:
      final rad = r.radius ?? 0;
      v.addAll([
        if (rad > 1e-12) ...[
          MeasureValue(MeasureRole.diameter, 2 * rad),
          MeasureValue(MeasureRole.majorRadius, rad),
        ],
        if (r.area != null)
          MeasureValue(MeasureRole.area, r.area!, approximate: true),
      ]);
      _addPosition(v, r.point);
      if (v.isEmpty) return null;
      break;

    case MeasureRefKind.body:
    case MeasureRefKind.component:
      if (r.volume != null) {
        v.add(MeasureValue(MeasureRole.volume, r.volume!));
      }
      if (r.area != null) {
        v.add(MeasureValue(MeasureRole.surfaceArea, r.area!,
            approximate: true));
      }
      final lo = r.boxLo, hi = r.boxHi;
      if (lo != null && hi != null) {
        v.addAll([
          MeasureValue(MeasureRole.extentX, (hi.x - lo.x).abs()),
          MeasureValue(MeasureRole.extentY, (hi.y - lo.y).abs()),
          MeasureValue(MeasureRole.extentZ, (hi.z - lo.z).abs()),
        ]);
      }
      if (v.isEmpty) return null;
      break;
  }

  if (v.isEmpty) return null;
  return MeasureReading(refs: [r], values: v, marker: marker);
}

void _addPosition(List<MeasureValue> v, Vec3? p) {
  if (p == null) return;
  v.addAll([
    MeasureValue(MeasureRole.positionX, p.x),
    MeasureValue(MeasureRole.positionY, p.y),
    MeasureValue(MeasureRole.positionZ, p.z),
  ]);
}

/// The diameter line across a circle, arc or sphere — the picture Inventor
/// draws when it reports a diameter.
MeasureMarker? _radialMarker(MeasureRef r) {
  if (!r.hasRadius || !r.hasAxis) return null;
  final u = _anyPerp(r.axisDir!);
  return MeasureMarker.radial(
      r.axisAt! - u * r.radius!, r.axisAt! + u * r.radius!);
}

/// The diameter line across a cylinder, drawn THROUGH the point the ray hit
/// so it lands on the part of the barrel the user is looking at rather than
/// at whatever end the kernel's axis point happens to sit on.
MeasureMarker? _cylinderMarker(MeasureRef r) {
  if (!r.hasRadius || !r.hasAxis) return null;
  final at = r.axisAt!, dir = r.axisDir!;
  final hit = r.hitAt;
  final centre =
      hit == null ? at : at + dir * (hit - at).dot(dir);
  var u = hit == null ? _anyPerp(dir) : _perpComponent(hit - centre, dir);
  if (u.length < 1e-9) u = _anyPerp(dir);
  u = u.normalized();
  return MeasureMarker.radial(centre - u * r.radius!, centre + u * r.radius!);
}

// ===========================================================================
// two picks
// ===========================================================================

/// The relation between two picks: a distance, an angle, or both.
///
/// The order of the cases below is the whole design. It runs from the most
/// specific pair to the least, so that "two holes" is answered as two holes
/// (centre distance, axis angle) rather than as "two surfaces that happen to
/// have points on them" — which is what a table keyed on carrier types alone
/// would have produced.
MeasureReading? measurePair(MeasureRef p, MeasureRef q,
    {MeasureDistanceMode mode = MeasureDistanceMode.minimum}) {
  // ---- angles first, where an angle is the only honest answer -------------
  //
  // Two planes that are not parallel have NO distance: every value between
  // zero and infinity occurs somewhere on them. Reporting the gap at the
  // point you happened to tap would be a number that changes when you tap
  // again, which is worse than no number at all.
  //
  // The guards read [_isPlaneLike], not [MeasureRef.hasPlane]. A circular
  // edge carries a plane — it is flat, and work_features reaches "the plane
  // of this hole" through exactly that — but "two holes at an angle" is a
  // question about their AXES and their distance, not about the two infinite
  // planes they happen to lie in. Sending a circle down this branch reported
  // an angle where the user had asked how far apart two bolt holes were.
  if (_isPlaneLike(p) &&
      _isPlaneLike(q) &&
      !_parallel(p.planeNormal!, q.planeNormal!)) {
    return _planeAngle(p, q);
  }
  if (_isLineLike(p) && _isPlaneLike(q) && _lineMeetsPlaneAtAnAngle(p, q)) {
    return _linePlaneAngle(p, q);
  }
  if (_isPlaneLike(p) && _isLineLike(q) && _lineMeetsPlaneAtAnAngle(q, p)) {
    return _linePlaneAngle(q, p);
  }
  if (_isLineLike(p) && _isLineLike(q) && !_parallel(p.lineDir!, q.lineDir!)) {
    return _lineLine(p, q, mode);
  }

  // ---- distances ---------------------------------------------------------
  return _distance(p, q, mode);
}

/// True for a pick whose primary meaning is a direction: an edge, an axis, a
/// cylinder or a cone. NOT a circular edge — a circle's axis is a real line
/// but the circle itself is a curve, and "the angle between two holes" means
/// the angle between their axes only when neither is coplanar with the other.
bool _isLineLike(MeasureRef r) =>
    (r.kind == MeasureRefKind.line ||
        r.kind == MeasureRefKind.axis ||
        r.kind == MeasureRefKind.cylinder ||
        r.kind == MeasureRefKind.cone) &&
    r.hasLine;

bool _parallel(Vec3 a, Vec3 b, {double tol = 1e-7}) =>
    a.normalized().cross(b.normalized()).length <= tol;

/// True when [line] crosses [plane] at an angle that is worth reporting —
/// i.e. neither parallel to it nor square to it.
///
/// Both excluded cases have a DISTANCE, and the distance is what was being
/// asked. A shaft lying alongside a wall is parallel to it: answering "0°"
/// instead of "26 mm" is technically true and useless. A hole square to a
/// face is at 90°, which nobody taps a measure tool to find out; the depth
/// under it is.
bool _lineMeetsPlaneAtAnAngle(MeasureRef line, MeasureRef plane) {
  final d = line.lineDir!, n = plane.planeNormal!;
  if (_parallel(d, n)) return false; // square to it
  return d.normalized().dot(n.normalized()).abs() > 1e-7; // not alongside it
}

// ---------------------------------------------------------------------------
// angles
// ---------------------------------------------------------------------------

/// The angle between two planes.
///
/// See [MeasureRef.planeIsOriented] for why the answer depends on where the
/// normals came from. Two ORIENTED faces give the dihedral you would put a
/// protractor into — 30° for a 30° wedge, 150° for a 150° one. Two planes
/// whose normals are arbitrary give the unsigned angle in [0°, 90°], because
/// that is the only thing they can honestly say.
///
/// The supplement rides along in both cases (unless the angle is a right
/// angle, where it is the same number) so the panel never has to be believed
/// on faith.
MeasureReading _planeAngle(MeasureRef p, MeasureRef q) {
  final n1 = p.planeNormal!, n2 = q.planeNormal!;
  final raw = _angleBetween(n1, n2);
  final oriented = p.planeIsOriented && q.planeIsOriented;
  final angle = oriented ? math.pi - raw : _acute(raw);
  final supplement = math.pi - angle;
  final apexInfo = _planeAngleArms(p, q);
  return MeasureReading(
    refs: [p, q],
    values: [
      MeasureValue(MeasureRole.angle, angle),
      if ((angle - math.pi / 2).abs() > 1e-9)
        MeasureValue(MeasureRole.supplementAngle, supplement),
    ],
    marker: apexInfo,
  );
}

/// The arms to draw for a plane-plane angle: a point on the line where the
/// two planes meet, and one direction in each plane, both perpendicular to
/// that line. That is the picture a protractor makes, and it is the only
/// pair of arms whose angle IS the dihedral.
MeasureMarker? _planeAngleArms(MeasureRef p, MeasureRef q) {
  final n1 = p.planeNormal!, n2 = q.planeNormal!;
  final dir = n1.cross(n2);
  if (dir.length < 1e-12) return null;
  final apex = _planeIntersectionPoint(
      p.planeAt!, n1, q.planeAt!, n2, p.hitAt ?? q.hitAt);
  if (apex == null) return null;
  final e = dir.normalized();
  // In-plane, perpendicular to the shared line, pointing AT the tap where
  // there was one, so the arc lands on the corner the user is looking at.
  Vec3 arm(Vec3 n, Vec3? towards) {
    var d = e.cross(n).normalized();
    if (towards != null && (towards - apex).dot(d) < 0) d = d * -1;
    return d;
  }

  return MeasureMarker.angle(
      apex, arm(n1, p.hitAt), arm(n2, q.hitAt));
}

/// The angle between a line and a plane: 90° minus the angle between the
/// line and the plane's normal, in [0°, 90°]. Zero when they are parallel,
/// which is the case the distance branch takes instead.
MeasureReading _linePlaneAngle(MeasureRef line, MeasureRef plane) {
  final d = line.lineDir!, n = plane.planeNormal!;
  final angle = (math.pi / 2 - _acute(_angleBetween(d, n))).abs();
  final hit = linePlanePoint(
      line.lineAt!, d, n, plane.planeAt!.dot(n));
  MeasureMarker? marker;
  if (hit != null) {
    final inPlane = _perpComponent(d, n);
    if (inPlane.length > 1e-9) {
      final reach = _markerReach(line, plane);
      marker = MeasureMarker.angle(
          hit, _towards(d, line, hit) * reach, inPlane.normalized() * reach);
    }
  }
  return MeasureReading(
    refs: [line, plane],
    values: [
      MeasureValue(MeasureRole.angle, angle),
      if ((angle - math.pi / 2).abs() > 1e-9 && angle > 1e-9)
        MeasureValue(MeasureRole.supplementAngle, math.pi - angle),
    ],
    marker: marker,
  );
}

/// Two non-parallel lines: the angle between them and the distance, in the
/// order that answers what was asked.
///
/// WHICH GOES FIRST. Two lines that are COPLANAR meet somewhere — at the
/// corner you tapped, or just past the fillet that rounded it off — and the
/// angle is the whole question. Two SKEW lines never meet, and the thing you
/// wanted from two holes drilled at ninety degrees to one another is how far
/// apart they are; that they are at ninety degrees is worth saying second,
/// not first. Coplanarity is tested on the INFINITE lines, so a V-groove
/// whose edges stop short of the vertex still reads as an angle.
///
/// WHICH ANGLE. The INCLUDED one when the two segments share a vertex, which
/// is what you want when you tap two edges of a corner: the arms point away
/// from the shared point and the answer is the corner's own angle, in
/// [0°, 180°]. Otherwise there is no vertex to measure from and the honest
/// answer is the acute angle between the two infinite lines.
MeasureReading _lineLine(MeasureRef p, MeasureRef q, MeasureDistanceMode mode) {
  final shared = _sharedVertex(p, q);
  final reach = _markerReach(p, q);
  double angle;
  MeasureMarker marker;
  if (shared != null) {
    final da = _awayFrom(p, shared), db = _awayFrom(q, shared);
    angle = _angleBetween(da, db);
    marker = MeasureMarker.angle(shared, da * reach, db * reach);
  } else {
    angle = _acute(_angleBetween(p.lineDir!, q.lineDir!));
    final (ca, cb) = _closestBetweenLines(p, q);
    final apex = (ca + cb) * 0.5;
    marker = MeasureMarker.angle(
        apex,
        _towards(p.lineDir!, p, apex) * reach,
        _towards(q.lineDir!, q, apex) * reach);
  }

  final (a, b) = _closestPoints(p, q, MeasureDistanceMode.minimum);
  final gap = (b - a).length;

  // Do the two infinite lines meet? Measured on the lines rather than on the
  // segments, and scaled by the geometry so that a 0.001 mm slop on a
  // thousand-millimetre beam still counts as "they cross".
  final coplanar = _infiniteLineGap(p, q) <= 1e-7 * math.max(1.0, reach);
  final angleFirst = coplanar || shared != null;

  final angleRows = <MeasureValue>[
    MeasureValue(MeasureRole.angle, angle),
    if ((angle - math.pi / 2).abs() > 1e-9 && angle > 1e-9)
      MeasureValue(MeasureRole.supplementAngle, math.pi - angle),
  ];
  // The gap is information either way round: on two lines that meet it reads
  // zero, which is the panel saying they really do intersect rather than
  // missing by a hair.
  final gapRow = MeasureValue(MeasureRole.distance, gap);

  return MeasureReading(
    refs: [p, q],
    values: angleFirst ? [...angleRows, gapRow] : [gapRow, ...angleRows],
    marker: angleFirst
        ? marker
        : (gap > 1e-12 ? MeasureMarker.span(a, b) : marker),
    mode: MeasureDistanceMode.minimum,
    modes: _availableModes(p, q),
  );
}

/// The closest approach of two picks' INFINITE lines — zero exactly when they
/// are coplanar. Deliberately not the segment answer: two edges of a mitred
/// corner stop short of their crossing and are still coplanar.
double _infiniteLineGap(MeasureRef p, MeasureRef q) {
  final n = p.lineDir!.cross(q.lineDir!);
  final len = n.length;
  if (len < 1e-12) return 0; // parallel: they are coplanar by definition
  return ((q.lineAt! - p.lineAt!).dot(n) / len).abs();
}

/// The angle at [vertex] between the rays to [x] and [y] — Inventor's
/// three-point angle, and the only unambiguous three-pick measurement.
MeasureReading? measureAngleAtVertex(
    MeasureRef x, MeasureRef vertex, MeasureRef y) {
  final v = vertex.point, a = x.point, b = y.point;
  if (v == null || a == null || b == null) return null;
  final da = a - v, db = b - v;
  if (da.length < 1e-12 || db.length < 1e-12) return null;
  final angle = _angleBetween(da, db);
  return MeasureReading(
    refs: [x, vertex, y],
    values: [
      MeasureValue(MeasureRole.angle, angle),
      MeasureValue(MeasureRole.distance, da.length),
      MeasureValue(MeasureRole.centreDistance, db.length),
    ],
    marker: MeasureMarker.angle(v, da, db),
  );
}

// ---------------------------------------------------------------------------
// distances
// ---------------------------------------------------------------------------

/// The distance between two picks under [mode], with the other modes listed.
MeasureReading? _distance(MeasureRef p, MeasureRef q, MeasureDistanceMode mode) {
  final modes = _availableModes(p, q);
  final use = modes.contains(mode) ? mode : modes.first;
  final (a, b) = _closestPoints(p, q, use);
  final d = b - a;
  final dist = d.length;

  final values = <MeasureValue>[
    MeasureValue(
        use == MeasureDistanceMode.maximum
            ? MeasureRole.maximumDistance
            : use == MeasureDistanceMode.centre
                ? MeasureRole.centreDistance
                : MeasureRole.distance,
        dist,
        approximate: _approximateDistance(p, q, use)),
    MeasureValue(MeasureRole.deltaX, d.x.abs()),
    MeasureValue(MeasureRole.deltaY, d.y.abs()),
    MeasureValue(MeasureRole.deltaZ, d.z.abs()),
  ];

  // A round pick asked about its SURFACE as well as its centre: tapping a
  // hole and a face should say both how far the axis is and how far the wall
  // is, because either can be the number you came for.
  final surface = _surfaceDistance(p, q, use);
  if (surface != null) {
    values.add(MeasureValue(MeasureRole.surfaceDistance, surface));
  }
  // The angle rides along with every distance that has one.
  //
  // Two picks that reached this branch are parallel (or one of them has no
  // direction at all), so the angle is usually zero — and saying "0,0°" is
  // exactly how the panel answers "are these two faces really parallel, or
  // 0,02° off?", which is one of the two questions a measurement is actually
  // asked. Two holes at an angle land here as well, because their DISTANCE
  // is the headline and their axis angle is the useful second number.
  final angle = _secondaryAngle(p, q);
  if (angle != null) values.add(MeasureValue(MeasureRole.angle, angle));

  return MeasureReading(
    refs: [p, q],
    values: values,
    marker: dist > 1e-12
        ? MeasureMarker.span(a, b)
        : MeasureMarker.point(a),
    mode: use,
    modes: modes,
  );
}

/// Which distance questions this pair can answer.
///
/// Minimum always. Centre only when both picks have a representative point —
/// a cylinder has none, which is why Inventor's Center to Center greys out on
/// one. Maximum only when both are bounded: the furthest point of an infinite
/// axis is not a place.
List<MeasureDistanceMode> _availableModes(MeasureRef p, MeasureRef q) => [
      MeasureDistanceMode.minimum,
      if (p.hasPoint && q.hasPoint) MeasureDistanceMode.centre,
      if (p.isBounded && q.isBounded) MeasureDistanceMode.maximum,
    ];

/// True when the closest approach was found by walking a TESSELLATION rather
/// than solved in closed form — a spline, a body, a component.
bool _approximateDistance(MeasureRef p, MeasureRef q, MeasureDistanceMode m) {
  if (m == MeasureDistanceMode.centre) return false;
  bool tess(MeasureRef r) =>
      r.kind == MeasureRefKind.curve ||
      r.kind == MeasureRefKind.body ||
      r.kind == MeasureRefKind.component;
  return tess(p) || tess(q);
}

/// The two points the reading spans, under [mode].
(Vec3, Vec3) _closestPoints(MeasureRef p, MeasureRef q, MeasureDistanceMode m) {
  switch (m) {
    case MeasureDistanceMode.centre:
      return (p.point ?? _anyPointOf(p), q.point ?? _anyPointOf(q));
    case MeasureDistanceMode.maximum:
      return _farthestPoints(p, q);
    case MeasureDistanceMode.minimum:
      return _nearestPoints(p, q);
  }
}

/// The closest approach of two picks, in closed form wherever the pair has
/// one and by walking the tessellation where it does not.
///
/// Ordered from the most specific pair down, exactly like [measurePair], and
/// for the same reason: two coaxial circles have an analytic answer that a
/// polyline walk would only approximate.
(Vec3, Vec3) _nearestPoints(MeasureRef p, MeasureRef q) {
  // -- point against anything ----------------------------------------------
  if (p.kind == MeasureRefKind.point) {
    final on = _closestOn(q, p.point!);
    return (p.point!, on);
  }
  if (q.kind == MeasureRefKind.point) {
    final on = _closestOn(p, q.point!);
    return (on, q.point!);
  }

  // -- plane against a parallel plane ---------------------------------------
  if (p.hasPlane &&
      q.hasPlane &&
      _parallel(p.planeNormal!, q.planeNormal!) &&
      _isPlaneLike(p) &&
      _isPlaneLike(q)) {
    // Measured along the normal, and anchored at the tap where there was one
    // so the dimension line lands on the part rather than off in space.
    final n = p.planeNormal!;
    final from = p.hitAt ?? p.planeAt!;
    final to = from + n * ((q.planeAt! - from).dot(n));
    return (from, to);
  }

  // -- line-like against line-like ------------------------------------------
  if (_isLineLike(p) && _isLineLike(q)) {
    var (ca, cb) = _closestBetweenLines(p, q);
    // A cylinder is its axis PLUS a radius: back the answer off both barrels
    // so the gap between two shafts is the gap you could put a feeler gauge
    // into, not the distance between their centrelines.
    (ca, cb) = _shrinkByRadius(p, q, ca, cb);
    return (ca, cb);
  }

  // -- a plane against a line-like ------------------------------------------
  if (p.hasPlane && _isLineLike(q) && _isPlaneLike(p)) {
    final (b, a) = _linePlaneNearest(q, p);
    return (a, b);
  }
  if (q.hasPlane && _isLineLike(p) && _isPlaneLike(q)) {
    return _linePlaneNearest(p, q);
  }

  // -- two tessellated solids ------------------------------------------------
  final pm = p.mesh, qm = q.mesh;
  if (pm != null && qm != null) return nearestBetweenMeshes(pm, qm);
  // A solid against a PLANE is solved rather than anchored: see
  // MeasureMesh.closestToPlane for why the vertex scan is the exact answer.
  if (pm != null && _isPlaneLike(q)) {
    final on = pm.closestToPlane(q.planeAt!, q.planeNormal!);
    return (on, _closestOn(q, on));
  }
  if (qm != null && _isPlaneLike(p)) {
    final on = qm.closestToPlane(p.planeAt!, p.planeNormal!);
    return (_closestOn(p, on), on);
  }
  if (pm != null && q.hasPoint) return (pm.closestTo(q.point!), q.point!);
  if (qm != null && p.hasPoint) return (p.point!, qm.closestTo(p.point!));
  if (pm != null) {
    final anchor = q.hitAt ?? q.point ?? _anyPointOf(q);
    final on = pm.closestTo(anchor);
    return (on, _closestOn(q, on));
  }
  if (qm != null) {
    final anchor = p.hitAt ?? p.point ?? _anyPointOf(p);
    final on = qm.closestTo(anchor);
    return (_closestOn(p, on), on);
  }

  // -- anything with samples -------------------------------------------------
  final ps = _sampleSet(p), qs = _sampleSet(q);
  if (ps.isNotEmpty && qs.isNotEmpty) {
    return _nearestBetweenPolylines(ps, qs);
  }
  if (ps.isNotEmpty && q.hasPoint) {
    return (_nearestOnPolyline(ps, q.point!), q.point!);
  }
  if (qs.isNotEmpty && p.hasPoint) {
    return (p.point!, _nearestOnPolyline(qs, p.point!));
  }

  // -- last resort: the representative points --------------------------------
  return (p.point ?? _anyPointOf(p), q.point ?? _anyPointOf(q));
}

/// True for a pick whose plane is the thing being measured to — a planar
/// face, a work plane, a torus midplane. A CIRCLE has a plane too, but a
/// distance to a circle means a distance to the curve, not to its plane.
bool _isPlaneLike(MeasureRef r) =>
    r.kind == MeasureRefKind.plane || r.kind == MeasureRefKind.torus;

/// The point on [r] closest to [x].
Vec3 _closestOn(MeasureRef r, Vec3 x) {
  switch (r.kind) {
    case MeasureRefKind.point:
      return r.point!;
    case MeasureRefKind.plane:
      final n = r.planeNormal!;
      return x - n * ((x - r.planeAt!).dot(n));
    case MeasureRefKind.line:
      return _closestOnSegment3(x, r.a!, r.b!);
    case MeasureRefKind.axis:
      return _closestOnLine(x, r.lineAt!, r.lineDir!);
    case MeasureRefKind.cylinder:
    case MeasureRefKind.cone:
      final onAxis = _closestOnLine(x, r.lineAt!, r.lineDir!);
      final rad = r.radius;
      if (rad == null || rad <= 1e-12) return onAxis;
      var out = x - onAxis;
      if (out.length < 1e-12) return onAxis;
      return onAxis + out.normalized() * rad;
    case MeasureRefKind.sphere:
      final c = r.point!;
      final rad = r.radius;
      if (rad == null || rad <= 1e-12) return c;
      final out = x - c;
      if (out.length < 1e-12) return c;
      return c + out.normalized() * rad;
    case MeasureRefKind.circle:
    case MeasureRefKind.arc:
    case MeasureRefKind.ellipse:
      if (r.samples.isNotEmpty) return _nearestOnPolyline(r.samples, x);
      return _closestOnCircle(x, r.axisAt!, r.axisDir!, r.radius ?? 0);
    case MeasureRefKind.torus:
      return r.point!;
    case MeasureRefKind.body:
    case MeasureRefKind.component:
      // The mesh, not the box: "how far is this vertex from that part" must
      // answer with the part's SURFACE, and a bounding-box centre would be
      // wrong by half the model.
      final m = r.mesh;
      if (m != null) return m.closestTo(x);
      return r.point ?? x;
    case MeasureRefKind.curve:
      if (r.samples.isNotEmpty) return _nearestOnPolyline(r.samples, x);
      return r.point ?? x;
  }
}

/// The point on the circle of [radius] about [centre] with axis [n] that is
/// closest to [x]. Closed form: project into the circle's plane, then push
/// out to the rim. Degenerates to a quadrant point when [x] is on the axis,
/// where every rim point is equally close.
Vec3 _closestOnCircle(Vec3 x, Vec3 centre, Vec3 n, double radius) {
  final radial = _perpComponent(x - centre, n);
  if (radial.length < 1e-12) {
    return centre + _anyPerp(n) * radius;
  }
  return centre + radial.normalized() * radius;
}

/// The closest approach of two line-like picks, as points on each.
///
/// Segments are clamped to their ends; axes and cylinders are not. Parallel
/// lines have a whole family of closest pairs, and the one chosen is anchored
/// at whichever pick was tapped, so the dimension line is drawn where the
/// user is looking.
(Vec3, Vec3) _closestBetweenLines(MeasureRef p, MeasureRef q) {
  final pa = p.lineAt!, pd = p.lineDir!;
  final qa = q.lineAt!, qd = q.lineDir!;
  final w0 = pa - qa;
  final b = pd.dot(qd);
  final d = pd.dot(w0), e = qd.dot(w0);
  final den = 1 - b * b;
  double s, t;
  if (den.abs() < 1e-12) {
    // Parallel: the closest pairs are a whole family, so ANCHOR on the tap
    // (or on p's own middle) and drop a perpendicular from there. That is
    // what puts the dimension line where the user is looking instead of at
    // whatever end the kernel's line record starts from.
    final anchor = p.hitAt ?? (p.hasSegment ? p.point! : pa);
    s = (anchor - pa).dot(pd);
    t = (pa + pd * s - qa).dot(qd);
  } else {
    s = (b * e - d) / den;
    t = (e - b * d) / den;
  }
  if (p.hasSegment) s = s.clamp(0.0, (p.b! - p.a!).length);
  if (q.hasSegment) t = t.clamp(0.0, (q.b! - q.a!).length);
  final anchored = (pa + pd * s, qa + qd * t);

  // Two SEGMENTS have an exact answer, and the anchored one above is not it
  // whenever the clamp bit: two collinear edges 15 mm apart end to end were
  // reported 20 mm apart, because the perpendicular foot from p's midpoint
  // landed outside q and clamping it moved the wrong one of the two points.
  // Take whichever candidate is actually closer — the anchored pair still
  // wins on the overlapping-parallel case it was written for, where the two
  // are equal and it draws better.
  if (p.hasSegment && q.hasSegment) {
    final exact = _closestBetweenSegments(p.a!, p.b!, q.a!, q.b!);
    if ((exact.$2 - exact.$1).length <
        (anchored.$2 - anchored.$1).length - 1e-12) {
      return exact;
    }
  }
  return anchored;
}

/// Back two axis points off by their picks' radii, along the line between
/// them, so the distance between two shafts or two holes is measured wall to
/// wall. A pick with no radius is left where it is.
(Vec3, Vec3) _shrinkByRadius(
    MeasureRef p, MeasureRef q, Vec3 ca, Vec3 cb) {
  final rp = p.kind == MeasureRefKind.cylinder ? (p.radius ?? 0) : 0.0;
  final rq = q.kind == MeasureRefKind.cylinder ? (q.radius ?? 0) : 0.0;
  if (rp <= 1e-12 && rq <= 1e-12) return (ca, cb);
  final v = cb - ca;
  final len = v.length;
  // Nested or intersecting barrels: the walls overlap, and pretending
  // otherwise would report a negative gap as a positive one. Leave the axis
  // answer, which is still true and is what centreDistance would have said.
  if (len < 1e-12 || rp + rq >= len) return (ca, cb);
  final u = v * (1 / len);
  return (ca + u * rp, cb - u * rq);
}

/// The closest points between a line-like pick and a plane-like one, as
/// (on the line, on the plane).
(Vec3, Vec3) _linePlaneNearest(MeasureRef line, MeasureRef plane) {
  final n = plane.planeNormal!, d = line.lineDir!;
  if (!_parallel(d, n)) {
    final hit = linePlanePoint(line.lineAt!, d, n, plane.planeAt!.dot(n));
    if (hit != null && !line.hasSegment) return (hit, hit);
    if (hit != null && line.hasSegment) {
      // The infinite line meets the plane; the SEGMENT might not.
      final s = (hit - line.a!).dot(d);
      final len = (line.b! - line.a!).length;
      if (s >= 0 && s <= len) return (hit, hit);
    }
  }
  // Parallel, or a segment that stops short: measure from the near end.
  final from = line.hasSegment
      ? _nearestEndToPlane(line, plane)
      : (line.hitAt ?? line.lineAt!);
  final onPlane = from - n * ((from - plane.planeAt!).dot(n));
  // A cylinder against a plane is measured from its BARREL, not its axis.
  if (line.kind == MeasureRefKind.cylinder && (line.radius ?? 0) > 1e-12) {
    final toward = onPlane - from;
    if (toward.length > 1e-12) {
      final radial = _perpComponent(toward, line.lineDir!);
      if (radial.length > 1e-12) {
        final wall = from + radial.normalized() * line.radius!;
        final onPlane2 = wall - n * ((wall - plane.planeAt!).dot(n));
        return (wall, onPlane2);
      }
    }
  }
  return (from, onPlane);
}

Vec3 _nearestEndToPlane(MeasureRef line, MeasureRef plane) {
  final n = plane.planeNormal!, d = plane.planeAt!.dot(n);
  final da = (line.a!.dot(n) - d).abs(), db = (line.b!.dot(n) - d).abs();
  return da <= db ? line.a! : line.b!;
}

/// The distance from one pick's SURFACE to the other, when one of them is
/// round and the headline number was measured to its centre. Null when the
/// headline already is the surface distance.
double? _surfaceDistance(MeasureRef p, MeasureRef q, MeasureDistanceMode m) {
  if (m != MeasureDistanceMode.centre) return null;
  final rp = p.isRound ? (p.radius ?? 0) : 0.0;
  final rq = q.isRound ? (q.radius ?? 0) : 0.0;
  if (rp <= 1e-12 && rq <= 1e-12) return null;
  final (a, b) = _closestPoints(p, q, MeasureDistanceMode.centre);
  final gap = (b - a).length - rp - rq;
  return gap.abs();
}

/// The angle worth reporting ALONGSIDE a distance, or null when neither pick
/// carries a direction.
///
/// Line against line is the angle between them; line against plane is the
/// angle to the SURFACE (90° minus the angle to the normal); plane against
/// plane is the angle between them. All folded into [0°, 90°]: this is the
/// secondary row, and the [_planeAngle] branch above is where the oriented
/// dihedral and its supplement get said properly.
double? _secondaryAngle(MeasureRef p, MeasureRef q) {
  // A round pick is read as its PLANE here, not as its axis. The two carry the
  // same information, but "this edge is 30 degrees to the plane of that bore"
  // is the sentence a machinist says, and "60 degrees to its axis" is the same
  // fact written so that it has to be converted before it can be used.
  //
  // Only a LINE-LIKE pick offers a direction, for the same reason: a circular
  // edge has an axis, but nobody measures an angle TO a hole's axis.
  Vec3? dirOf(MeasureRef r) => _isLineLike(r) ? r.lineDir : null;
  Vec3? normalOf(MeasureRef r) => r.hasPlane ? r.planeNormal : null;
  final dp = dirOf(p), dq = dirOf(q);
  final np = normalOf(p), nq = normalOf(q);
  // Two directions: the angle between the lines.
  if (dp != null && dq != null) return _acute(_angleBetween(dp, dq));
  // A direction and a plane: the angle to the SURFACE, which is ninety
  // degrees less the angle to its normal.
  if (dp != null && nq != null) {
    return (math.pi / 2 - _acute(_angleBetween(dp, nq))).abs();
  }
  if (dq != null && np != null) {
    return (math.pi / 2 - _acute(_angleBetween(dq, np))).abs();
  }
  // Two planes: the angle between them, unsigned. The ORIENTED dihedral and
  // its supplement are said properly in [_planeAngle], which is the branch a
  // non-parallel pair of faces takes instead of this one.
  if (np != null && nq != null) return _acute(_angleBetween(np, nq));
  return null;
}

/// The two points that are furthest apart. Both picks must be bounded, which
/// [_availableModes] has already checked.
(Vec3, Vec3) _farthestPoints(MeasureRef p, MeasureRef q) {
  final ps = p.extremePoints, qs = q.extremePoints;
  if (ps.isEmpty || qs.isEmpty) {
    return (p.point ?? _anyPointOf(p), q.point ?? _anyPointOf(q));
  }
  var best = -1.0;
  var out = (ps.first, qs.first);
  for (final a in ps) {
    for (final b in qs) {
      final d = (b - a).length;
      if (d > best) {
        best = d;
        out = (a, b);
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// polyline distance — the fallback that makes "everything" true
// ---------------------------------------------------------------------------

/// The polyline a pick can be walked as, for the cases with no closed form.
///
/// A round pick that arrived without one gets a rim SYNTHESISED here rather
/// than falling back to its centre. The picker supplies real samples wherever
/// it has them (a tessellated edge follows the model exactly); this is the
/// floor under that, so "the distance from this line to that circle" is the
/// distance to the CURVE even when the pick came from an analytic record with
/// no polyline attached.
List<Vec3> _sampleSet(MeasureRef r) {
  if (r.samples.isNotEmpty) return r.samples;
  // A FULL circle or ellipse can be reconstructed from its record alone. An
  // ARC cannot — the record here carries the swept angle but not where the
  // sweep starts, so a synthesised arc would sit at an arbitrary bearing and
  // be worse than no samples at all. An arc therefore relies on the picker,
  // which does have the tessellation, and falls back to its centre when it
  // does not.
  final closed = r.kind == MeasureRefKind.circle ||
      r.kind == MeasureRefKind.ellipse;
  if (closed && r.hasAxis && r.hasRadius) return _rimSamples(r);
  return const [];
}

/// How many segments a synthesised rim gets. 72 puts the chord 0.06 % inside
/// the true circle, which is finer than the display tessellation the real
/// samples come from and far finer than any reading is shown to.
const int _kRimSegments = 72;

List<Vec3> _rimSamples(MeasureRef r) {
  final n = r.axisDir!, c = r.axisAt!;
  final major = r.radius ?? 0;
  final minor = r.minorRadius ?? major;
  final u = _anyPerp(n), v = n.cross(u).normalized();
  return [
    for (var i = 0; i <= _kRimSegments; i++)
      c +
          u * (major * math.cos(2 * math.pi * i / _kRimSegments)) +
          v * (minor * math.sin(2 * math.pi * i / _kRimSegments))
  ];
}

/// The point on the polyline [pts] closest to [x].
Vec3 _nearestOnPolyline(List<Vec3> pts, Vec3 x) {
  if (pts.isEmpty) return x;
  if (pts.length == 1) return pts.first;
  var best = pts.first;
  var bestD = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final c = _closestOnSegment3(x, pts[i], pts[i + 1]);
    final d = (c - x).length;
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best;
}

/// The closest approach between two polylines, as a point on each.
///
/// Θ(n·m) with a cheap early-out: a segment pair whose ENDPOINTS are already
/// further apart than the current best plus both segments' lengths cannot
/// contain a closer pair, and on real geometry that prunes almost everything.
/// The pickers cap how many samples a pick carries (see measure_pick.dart),
/// so the worst case is bounded by construction rather than by hope.
(Vec3, Vec3) _nearestBetweenPolylines(List<Vec3> p, List<Vec3> q) {
  if (p.length == 1 && q.length == 1) return (p.first, q.first);
  if (p.length == 1) return (p.first, _nearestOnPolyline(q, p.first));
  if (q.length == 1) return (_nearestOnPolyline(p, q.first), q.first);
  var best = double.infinity;
  var out = (p.first, q.first);
  for (var i = 0; i + 1 < p.length; i++) {
    final a0 = p[i], a1 = p[i + 1];
    final aLen = (a1 - a0).length;
    for (var j = 0; j + 1 < q.length; j++) {
      final b0 = q[j], b1 = q[j + 1];
      if ((b0 - a0).length - aLen - (b1 - b0).length > best) continue;
      final (ca, cb) = _closestBetweenSegments(a0, a1, b0, b1);
      final d = (cb - ca).length;
      if (d < best) {
        best = d;
        out = (ca, cb);
      }
    }
  }
  return out;
}

/// The closest pair of points on two SEGMENTS. The standard clamped solution
/// (Ericson, Real-Time Collision Detection §5.1.9), which handles the
/// parallel and degenerate cases without a special branch per case.
(Vec3, Vec3) _closestBetweenSegments(Vec3 p1, Vec3 q1, Vec3 p2, Vec3 q2) {
  final d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
  final a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r);
  const eps = 1e-18;
  double s, t;
  if (a <= eps && e <= eps) return (p1, p2);
  if (a <= eps) {
    s = 0;
    t = (f / e).clamp(0.0, 1.0);
  } else {
    final c = d1.dot(r);
    if (e <= eps) {
      t = 0;
      s = (-c / a).clamp(0.0, 1.0);
    } else {
      final b = d1.dot(d2);
      final den = a * e - b * b;
      s = den.abs() > eps ? ((b * f - c * e) / den).clamp(0.0, 1.0) : 0.0;
      t = (b * s + f) / e;
      if (t < 0) {
        t = 0;
        s = (-c / a).clamp(0.0, 1.0);
      } else if (t > 1) {
        t = 1;
        s = ((b - c) / a).clamp(0.0, 1.0);
      }
    }
  }
  return (p1 + d1 * s, p2 + d2 * t);
}

// ===========================================================================
// what a pick looks like
// ===========================================================================

/// The drawable form of a pick that is a SURFACE rather than a curve (M374).
///
/// Two lists, because a face highlight is two marks and they answer different
/// questions. The wash over [patch] says WHICH face — it is the only mark that
/// distinguishes the top of a plate from the bottom when both project to the
/// same outline. The stroke along [loops] says WHERE IT ENDS — a wash alone
/// bleeds into its neighbours at a shallow angle, and on a cylinder it is the
/// rims that tell you the bore was picked and not the boss around it.
///
/// Both are WORLD space and already reduced to what a canvas takes: the
/// painter projects and draws, and does no geometry of its own.
class MeasureShape {
  const MeasureShape({this.patch = const [], this.loops = const []});

  /// The surface, corner-major: three [Vec3] per triangle.
  final List<Vec3> patch;

  /// The boundary, as one polyline per loop. A face with a hole in it has
  /// two; a face the tessellation left open has none, and the wash alone
  /// still reads.
  final List<List<Vec3>> loops;

  bool get isEmpty => patch.isEmpty && loops.isEmpty;
  int get triangleCount => patch.length ~/ 3;
}

// ===========================================================================
// solids — the one pair with no closed form
// ===========================================================================

/// A solid's tessellation, reduced to what a distance needs.
///
/// Deliberately a plain value type over [Vec3] rather than the kernel's
/// `OcctMeshData`: this file must stay loadable without the FFI layer, and
/// the mesh is the only thing a body-to-body distance actually reads.
/// measure_pick.dart builds one; the tests build one by hand.
class MeasureMesh {
  MeasureMesh(this.triangles, this.curves, this.lo, this.hi)
      : assert(triangles.length % 3 == 0,
            'triangles is corner-major: three Vec3 per face');

  /// Triangle corners, THREE PER TRIANGLE, in world coordinates.
  final List<Vec3> triangles;

  /// The B-Rep display edges as polylines. Carried separately because the
  /// closest pair of two solids is often edge-to-edge (two blocks meeting at
  /// a corner), and a vertex-to-triangle search alone would miss it.
  final List<List<Vec3>> curves;

  /// Axis-aligned bounds.
  final Vec3 lo, hi;

  int get triangleCount => triangles.length ~/ 3;

  /// The point of this mesh closest to the plane `n·v = d`.
  ///
  /// EXACT, and cheaply so: the distance to a plane is linear, and a linear
  /// function over a triangle attains its extremes at the corners — so the
  /// nearest point of a triangulated body to a plane is always one of its
  /// vertices, and a scan of the corner list is the whole answer.
  ///
  /// Worth having its own method rather than falling back to [closestTo] on
  /// some anchor: "how far is this bracket from that wall" is the commonest
  /// measurement in an assembly, and an anchored answer would find the point
  /// nearest WHERE YOU TAPPED rather than the point nearest the wall.
  Vec3 closestToPlane(Vec3 at, Vec3 n) {
    final u = n.normalized();
    final d = at.dot(u);
    var best = (lo + hi) * 0.5;
    var bestD = double.infinity;
    for (final v in triangles) {
      final gap = (v.dot(u) - d).abs();
      if (gap < bestD) {
        bestD = gap;
        best = v;
      }
    }
    return bestD.isFinite ? best : (lo + hi) * 0.5;
  }

  /// The point of this mesh closest to [x].
  Vec3 closestTo(Vec3 x) {
    var best = x;
    var bestD = double.infinity;
    for (var t = 0; t + 2 < triangles.length; t += 3) {
      final c = closestOnTriangle(
          x, triangles[t], triangles[t + 1], triangles[t + 2]);
      final d = (c - x).length;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    if (bestD.isFinite) return best;
    // A mesh with no triangles (a fake, a body that failed to tessellate)
    // still has a box, and its centre is a better answer than the query
    // point itself.
    return (lo + hi) * 0.5;
  }
}

/// How many point-to-triangle tests a body-to-body distance may spend.
///
/// The search below is Θ(v·t) before pruning, and a refined iPad part reaches
/// tens of thousands of each — so the budget is what stops a measurement from
/// becoming a freeze. It is generous (a modern core does a few million of
/// these in well under a frame's worth of a tap's latency) and the pruning
/// normally keeps the real count two orders of magnitude below it, because
/// only the triangles facing the other solid survive the box test.
const int _kMeshDistanceBudget = 3000000;

/// The closest approach of two tessellated solids, as a point on each.
///
/// Three passes, and all three are needed for the answer to be right:
///
///   * every vertex of A against the triangles of B, and the mirror. This is
///     the pair that a plate hovering over a bigger plate produces — the
///     closest points are a corner of one against the FACE of the other, and
///     no edge-based search finds it.
///   * every display edge of A against every display edge of B. This is the
///     pair two blocks meeting at a corner produce, where neither closest
///     point is a vertex.
///
/// Pruning is by bounding box: a triangle whose box is already further from
/// the query point than the best so far cannot beat it. That is what keeps
/// the cost proportional to the FACING surfaces rather than to the models.
///
/// Exact when the closest features are vertex-face or edge-edge, which covers
/// every pair of flat-faced solids. On two curved surfaces it is the
/// tessellation's answer, which is why every reading built on it is marked
/// approximate (see [_approximateDistance]).
(Vec3, Vec3) nearestBetweenMeshes(MeasureMesh a, MeasureMesh b) {
  var best = double.infinity;
  var out = ((a.lo + a.hi) * 0.5, (b.lo + b.hi) * 0.5);
  var budget = _kMeshDistanceBudget;

  void offer(Vec3 pa, Vec3 pb) {
    final d = (pb - pa).length;
    if (d < best) {
      best = d;
      out = (pa, pb);
    }
  }

  /// Vertices of [from] against triangles of [to]. [swap] keeps the returned
  /// pair in (a, b) order whichever way round the pass ran.
  void vertexPass(MeasureMesh from, MeasureMesh to, {required bool swap}) {
    for (var i = 0; i < from.triangles.length; i++) {
      final v = from.triangles[i];
      // The whole of `to` is at least this far away; no triangle of it can
      // beat the current best, so the inner loop is skipped entirely.
      if (_boxDistance(v, to.lo, to.hi) >= best) continue;
      for (var t = 0; t + 2 < to.triangles.length; t += 3) {
        if (budget-- <= 0) return;
        final t0 = to.triangles[t], t1 = to.triangles[t + 1],
            t2 = to.triangles[t + 2];
        if (_triangleFartherThan(v, t0, t1, t2, best)) continue;
        final c = closestOnTriangle(v, t0, t1, t2);
        if (swap) {
          offer(c, v);
        } else {
          offer(v, c);
        }
      }
    }
  }

  vertexPass(a, b, swap: false);
  vertexPass(b, a, swap: true);

  for (final ca in a.curves) {
    for (var i = 0; i + 1 < ca.length; i++) {
      final a0 = ca[i], a1 = ca[i + 1];
      if (_boxDistance(a0, b.lo, b.hi) - (a1 - a0).length >= best) continue;
      for (final cb in b.curves) {
        for (var j = 0; j + 1 < cb.length; j++) {
          if (budget-- <= 0) return out;
          final (pa, pb) =
              _closestBetweenSegments(a0, a1, cb[j], cb[j + 1]);
          offer(pa, pb);
        }
      }
    }
  }
  return out;
}

/// Distance from [p] to the axis-aligned box [lo]..[hi]; zero inside it.
double _boxDistance(Vec3 p, Vec3 lo, Vec3 hi) {
  double axis(double v, double a, double b) =>
      v < a ? a - v : (v > b ? v - b : 0.0);
  final dx = axis(p.x, lo.x, hi.x);
  final dy = axis(p.y, lo.y, hi.y);
  final dz = axis(p.z, lo.z, hi.z);
  return math.sqrt(dx * dx + dy * dy + dz * dz);
}

/// True when [p] cannot be within [best] of triangle [a][b][c], by its
/// bounding box. Three min/max per axis is far cheaper than the barycentric
/// projection it saves.
bool _triangleFartherThan(Vec3 p, Vec3 a, Vec3 b, Vec3 c, double best) {
  if (!best.isFinite) return false;
  final lo = Vec3(math.min(a.x, math.min(b.x, c.x)),
      math.min(a.y, math.min(b.y, c.y)), math.min(a.z, math.min(b.z, c.z)));
  final hi = Vec3(math.max(a.x, math.max(b.x, c.x)),
      math.max(a.y, math.max(b.y, c.y)), math.max(a.z, math.max(b.z, c.z)));
  return _boxDistance(p, lo, hi) >= best;
}

/// The point of triangle [a][b][c] closest to [p].
///
/// The region-based solution (Ericson, Real-Time Collision Detection §5.1.5):
/// it classifies [p] into one of the seven Voronoi regions of the triangle
/// and answers from that region directly, so it is branch-heavy but has no
/// square roots and no iteration.
Vec3 closestOnTriangle(Vec3 p, Vec3 a, Vec3 b, Vec3 c) {
  final ab = b - a, ac = c - a, ap = p - a;
  final d1 = ab.dot(ap), d2 = ac.dot(ap);
  if (d1 <= 0 && d2 <= 0) return a;

  final bp = p - b;
  final d3 = ab.dot(bp), d4 = ac.dot(bp);
  if (d3 >= 0 && d4 <= d3) return b;

  final vc = d1 * d4 - d3 * d2;
  if (vc <= 0 && d1 >= 0 && d3 <= 0) {
    final den = d1 - d3;
    return a + ab * (den.abs() < 1e-18 ? 0.0 : d1 / den);
  }

  final cp = p - c;
  final d5 = ab.dot(cp), d6 = ac.dot(cp);
  if (d6 >= 0 && d5 <= d6) return c;

  final vb = d5 * d2 - d1 * d6;
  if (vb <= 0 && d2 >= 0 && d6 <= 0) {
    final den = d2 - d6;
    return a + ac * (den.abs() < 1e-18 ? 0.0 : d2 / den);
  }

  final va = d3 * d6 - d5 * d4;
  if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
    final den = (d4 - d3) + (d5 - d6);
    final w = den.abs() < 1e-18 ? 0.0 : (d4 - d3) / den;
    return b + (c - b) * w;
  }

  final den = va + vb + vc;
  if (den.abs() < 1e-18) return a;
  return a + ab * (vb / den) + ac * (vc / den);
}

// ===========================================================================
// running totals — Inventor's "add the values of several measurements"
// ===========================================================================

/// A sum per unit kind, plus how many readings went into each.
///
/// Inventor lets you accumulate "several linear, area, volume, and/or angle
/// measurements to calculate a total measurement for each measurement type".
/// Four independent accumulators, because adding an area to a length is not
/// a number.
class MeasureTotals {
  const MeasureTotals([this.sums = const {}, this.counts = const {}]);

  final Map<MeasureUnitKind, double> sums;
  final Map<MeasureUnitKind, int> counts;

  bool get isEmpty => sums.isEmpty;

  /// This total plus [r]'s PRIMARY value. Only the primary: a reading of a
  /// cylinder carries a diameter, a radius, a height and an area, and adding
  /// all four to their respective totals would make "the total length" mean
  /// nothing.
  MeasureTotals plus(MeasureReading r) {
    final v = r.primary;
    final s = Map<MeasureUnitKind, double>.from(sums);
    final c = Map<MeasureUnitKind, int>.from(counts);
    s[v.unit] = (s[v.unit] ?? 0) + v.value;
    c[v.unit] = (c[v.unit] ?? 0) + 1;
    return MeasureTotals(s, c);
  }

  double? total(MeasureUnitKind k) => sums[k];
  int count(MeasureUnitKind k) => counts[k] ?? 0;
}

// ===========================================================================
// units and formatting
// ===========================================================================

/// The unit a measurement is WRITTEN in. The model is always millimetres;
/// this only decides the display, which is what makes Inventor's dual-unit
/// row a formatting choice rather than a document change.
enum MeasureUnitSystem {
  millimetre,
  centimetre,
  metre,
  inch,
  foot,
}

/// How many millimetres one of [u] is.
double measureUnitScale(MeasureUnitSystem u) {
  switch (u) {
    case MeasureUnitSystem.millimetre:
      return 1;
    case MeasureUnitSystem.centimetre:
      return 10;
    case MeasureUnitSystem.metre:
      return 1000;
    case MeasureUnitSystem.inch:
      return 25.4;
    case MeasureUnitSystem.foot:
      return 304.8;
  }
}

/// The SI/imperial symbol, which is the same word in German and English —
/// DIN 1301 spells "mm" exactly as the SI brochure does, so this is not an
/// ARB string. Area and volume take the exponent from [kind].
String measureUnitSymbol(MeasureUnitSystem u, MeasureUnitKind kind) {
  if (kind == MeasureUnitKind.angle) return '°';
  const base = {
    MeasureUnitSystem.millimetre: 'mm',
    MeasureUnitSystem.centimetre: 'cm',
    MeasureUnitSystem.metre: 'm',
    MeasureUnitSystem.inch: 'in',
    MeasureUnitSystem.foot: 'ft',
  };
  final s = base[u]!;
  switch (kind) {
    case MeasureUnitKind.area:
      return '$s²';
    case MeasureUnitKind.volume:
      return '$s³';
    default:
      return s;
  }
}

/// [v] — millimetres, square millimetres, cubic millimetres or radians —
/// converted into [u]. Angles always come out in DEGREES, which is the only
/// unit any of this app's other readouts use.
double measureConvert(double v, MeasureUnitKind kind, MeasureUnitSystem u) {
  switch (kind) {
    case MeasureUnitKind.angle:
      return v * 180 / math.pi;
    case MeasureUnitKind.length:
      return v / measureUnitScale(u);
    case MeasureUnitKind.area:
      return v / math.pow(measureUnitScale(u), 2);
    case MeasureUnitKind.volume:
      return v / math.pow(measureUnitScale(u), 3);
  }
}

// ===========================================================================
// words
// ===========================================================================

/// What the panel calls one measured quantity.
String measureRoleLabel(MeasureRole r) {
  final t = _t;
  switch (r) {
    case MeasureRole.length:
      return t.measureLength;
    case MeasureRole.arcLength:
      return t.measureArcLength;
    case MeasureRole.radius:
      return t.measureRadius;
    case MeasureRole.diameter:
      return t.measureDiameter;
    case MeasureRole.circumference:
      return t.measureCircumference;
    case MeasureRole.includedAngle:
      return t.measureIncludedAngle;
    case MeasureRole.majorRadius:
      return t.measureMajorRadius;
    case MeasureRole.minorRadius:
      return t.measureMinorRadius;
    case MeasureRole.area:
      return t.measureArea;
    case MeasureRole.perimeter:
      return t.measurePerimeter;
    case MeasureRole.volume:
      return t.measureVolume;
    case MeasureRole.height:
      return t.measureHeight;
    case MeasureRole.surfaceArea:
      return t.measureSurfaceArea;
    case MeasureRole.positionX:
      return t.measurePositionX;
    case MeasureRole.positionY:
      return t.measurePositionY;
    case MeasureRole.positionZ:
      return t.measurePositionZ;
    case MeasureRole.extentX:
      return t.measureExtentX;
    case MeasureRole.extentY:
      return t.measureExtentY;
    case MeasureRole.extentZ:
      return t.measureExtentZ;
    case MeasureRole.distance:
      return t.measureDistance;
    case MeasureRole.centreDistance:
      return t.measureCentreDistance;
    case MeasureRole.maximumDistance:
      return t.measureMaximumDistance;
    case MeasureRole.deltaX:
      return t.measureDeltaX;
    case MeasureRole.deltaY:
      return t.measureDeltaY;
    case MeasureRole.deltaZ:
      return t.measureDeltaZ;
    case MeasureRole.angle:
      return t.measureAngle;
    case MeasureRole.supplementAngle:
      return t.measureSupplementAngle;
    case MeasureRole.surfaceDistance:
      return t.measureSurfaceDistance;
  }
}

/// What the panel calls one PICK — "Kante", "Zylindrische Fläche".
String measureRefLabel(MeasureRefKind k) {
  final t = _t;
  switch (k) {
    case MeasureRefKind.point:
      return t.measureRefPoint;
    case MeasureRefKind.line:
      return t.measureRefEdge;
    case MeasureRefKind.axis:
      return t.measureRefAxis;
    case MeasureRefKind.circle:
      return t.measureRefCircle;
    case MeasureRefKind.arc:
      return t.measureRefArc;
    case MeasureRefKind.ellipse:
      return t.measureRefEllipse;
    case MeasureRefKind.curve:
      return t.measureRefCurve;
    case MeasureRefKind.plane:
      return t.measureRefFace;
    case MeasureRefKind.cylinder:
      return t.measureRefCylinder;
    case MeasureRefKind.cone:
      return t.measureRefCone;
    case MeasureRefKind.sphere:
      return t.measureRefSphere;
    case MeasureRefKind.torus:
      return t.measureRefTorus;
    case MeasureRefKind.body:
      return t.measureRefBody;
    case MeasureRefKind.component:
      return t.measureRefComponent;
  }
}

/// What the panel calls one distance question.
String measureModeLabel(MeasureDistanceMode m) {
  final t = _t;
  switch (m) {
    case MeasureDistanceMode.minimum:
      return t.measureModeMinimum;
    case MeasureDistanceMode.centre:
      return t.measureModeCentre;
    case MeasureDistanceMode.maximum:
      return t.measureModeMaximum;
  }
}

// ===========================================================================
// arithmetic
// ===========================================================================

/// Total length of a polyline.
double polylineLength(List<Vec3> pts) {
  var total = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    total += (pts[i + 1] - pts[i]).length;
  }
  return total;
}

/// The point half way ALONG a polyline by arc length — not the middle index,
/// which on a tessellated arc sits nowhere near the middle of the curve.
Vec3 polylineMidpoint(List<Vec3> pts) {
  if (pts.isEmpty) return Vec3.zero;
  if (pts.length == 1) return pts.first;
  final half = polylineLength(pts) / 2;
  var walked = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    final seg = (pts[i + 1] - pts[i]).length;
    if (walked + seg >= half) {
      final t = seg < 1e-15 ? 0.0 : (half - walked) / seg;
      return pts[i] + (pts[i + 1] - pts[i]) * t;
    }
    walked += seg;
  }
  return pts.last;
}

/// The area enclosed by a CLOSED planar loop, by the vector form of the
/// shoelace formula: `|½ Σ (pᵢ × pᵢ₊₁) · n|`. Works in any plane, which is
/// what a 3D face loop needs, and reduces to the flat shoelace when n is z.
double planarLoopArea(List<Vec3> pts, Vec3 n) {
  if (pts.length < 3) return 0;
  var acc = Vec3.zero;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    acc = acc + a.cross(b);
  }
  return (acc.dot(n.normalized()) * 0.5).abs();
}

/// Ramanujan's second approximation to an ellipse's perimeter. Exact to
/// better than one part in 10⁹ for every aspect ratio a sketch can hold,
/// which is far tighter than the tessellation it replaces.
double ellipsePerimeter(double a, double b) {
  if (a <= 0 || b <= 0) return 0;
  final h = math.pow(a - b, 2) / math.pow(a + b, 2);
  return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h)));
}

/// The point where the line `at + t·dir` meets the plane `n·x = d`, or null
/// when they are parallel.
Vec3? linePlanePoint(Vec3 at, Vec3 dir, Vec3 n, double d) {
  final den = dir.dot(n);
  if (den.abs() < 1e-12) return null;
  return at + dir * ((d - at.dot(n)) / den);
}

/// A point on the line where two planes meet — the one nearest [near] when
/// one is given, so the angle arc is drawn at the corner the user tapped
/// rather than wherever the closed form happens to land.
Vec3? _planeIntersectionPoint(
    Vec3 a1, Vec3 n1, Vec3 a2, Vec3 n2, Vec3? near) {
  final dir = n1.cross(n2);
  final len2 = dir.dot(dir);
  if (len2 < 1e-18) return null;
  final d1 = a1.dot(n1), d2 = a2.dot(n2);
  final p = (n2.cross(dir) * d1 + dir.cross(n1) * d2) * (1 / len2);
  if (near == null) return p;
  final e = dir * (1 / math.sqrt(len2));
  return p + e * ((near - p).dot(e));
}

/// The angle between two vectors, in [0, π]. Uses atan2 of the cross and dot
/// magnitudes rather than acos of the dot: acos loses every digit it has near
/// 0° and 180°, which is precisely where a measurement is asked whether two
/// faces are parallel.
double _angleBetween(Vec3 a, Vec3 b) {
  final x = a.normalized(), y = b.normalized();
  return math.atan2(x.cross(y).length, x.dot(y));
}

/// [a] folded into [0, π/2].
double _acute(double a) => a > math.pi / 2 ? math.pi - a : a;

/// The component of [v] perpendicular to the unit [axis].
Vec3 _perpComponent(Vec3 v, Vec3 axis) {
  final n = axis.normalized();
  return v - n * v.dot(n);
}

/// Any unit vector perpendicular to [v]. Cross against whichever world axis
/// [v] is least aligned with, so the result never degenerates.
Vec3 _anyPerp(Vec3 v) {
  final n = v.normalized();
  final ax = n.x.abs(), ay = n.y.abs(), az = n.z.abs();
  final other = (ax <= ay && ax <= az)
      ? const Vec3(1, 0, 0)
      : (ay <= az ? const Vec3(0, 1, 0) : const Vec3(0, 0, 1));
  return n.cross(other).normalized();
}

Vec3 _closestOnLine(Vec3 x, Vec3 at, Vec3 dir) {
  final d = dir.normalized();
  return at + d * ((x - at).dot(d));
}

Vec3 _closestOnSegment3(Vec3 x, Vec3 a, Vec3 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 < 1e-18) return a;
  final t = ((x - a).dot(ab) / len2).clamp(0.0, 1.0);
  return a + ab * t;
}

Vec3 _centroid(List<Vec3> pts) {
  if (pts.isEmpty) return Vec3.zero;
  var acc = Vec3.zero;
  for (final p in pts) {
    acc = acc + p;
  }
  return acc * (1 / pts.length);
}

/// Any point that stands for [r] when it has no representative one.
Vec3 _anyPointOf(MeasureRef r) =>
    r.point ?? r.hitAt ?? r.lineAt ?? r.planeAt ?? r.axisAt ?? Vec3.zero;

/// The two picks share a vertex within [tol] — the test that turns "two
/// edges" into "a corner".
Vec3? _sharedVertex(MeasureRef p, MeasureRef q, {double tol = 1e-6}) {
  if (!p.hasSegment || !q.hasSegment) return null;
  for (final a in [p.a!, p.b!]) {
    for (final b in [q.a!, q.b!]) {
      if ((a - b).length <= tol) return (a + b) * 0.5;
    }
  }
  return null;
}

/// [r]'s direction pointing AWAY from the shared vertex [v].
Vec3 _awayFrom(MeasureRef r, Vec3 v) {
  final far = (r.a! - v).length >= (r.b! - v).length ? r.a! : r.b!;
  final d = far - v;
  return d.length < 1e-12 ? r.lineDir! : d.normalized();
}

/// [d], flipped so it points from [apex] into the part of [r] that exists.
Vec3 _towards(Vec3 d, MeasureRef r, Vec3 apex) {
  if (!r.hasSegment) return d.normalized();
  final far = (r.a! - apex).length >= (r.b! - apex).length ? r.a! : r.b!;
  return (far - apex).dot(d) < 0 ? d.normalized() * -1 : d.normalized();
}

/// How long to draw an angle's arms: a fraction of the picks' own size, so
/// the arc is legible on a 2 mm chamfer and on a 2 m beam alike. The viewport
/// scales it again to keep it a constant number of points on screen; this
/// only has to be in the right ballpark for the geometry.
double _markerReach(MeasureRef p, MeasureRef q) {
  double sizeOf(MeasureRef r) {
    if (r.hasSegment) return (r.b! - r.a!).length;
    if (r.radius != null) return r.radius! * 2;
    final lo = r.boxLo, hi = r.boxHi;
    if (lo != null && hi != null) return (hi - lo).length;
    return 0;
  }

  final s = math.max(sizeOf(p), sizeOf(q));
  return s > 1e-9 ? s * 0.4 : 10.0;
}

// ===========================================================================
// the live command
// ===========================================================================

/// How many picks one measurement holds.
///
/// Two, except for the three-point angle. Inventor's Measure behaves the same
/// way: it does not accumulate a selection set, it answers about what you last
/// touched — and the running [MeasureTotals] is where "several measurements"
/// is kept, rather than in an ever-growing pick list nobody can see the end of.
const int kMeasureMaxPicks = 3;

/// Everything the Measure command is holding right now.
///
/// A plain value object with no Flutter and no AppState in it, for the same
/// reason [PatternSession] is not: the pick RULES — what a third tap does,
/// what tapping the same face twice does — are the part that can be wrong, and
/// they should be testable without a device.
class MeasureSession {
  /// What has been picked, in pick order.
  final List<MeasureRef> picks = [];

  /// The reading for [picks], recomputed on every change. Null when the picks
  /// so far measure nothing (one work plane, one origin axis).
  MeasureReading? reading;

  /// Which of Inventor's three distance questions the panel is asking.
  MeasureDistanceMode mode = MeasureDistanceMode.minimum;

  /// Inventor's selection priority. The pickers read it; nothing else does.
  MeasurePriority priority = MeasurePriority.entity;

  /// Decimal places in the panel. Inventor's own control, and it re-renders
  /// the reading rather than re-measuring it.
  int decimals = 2;

  /// The SECOND unit shown under each value, or null for none — Inventor's
  /// dual units.
  MeasureUnitSystem? dualUnit;

  /// The running per-kind sums.
  MeasureTotals totals = const MeasureTotals();

  /// What is under the pointer right now, or null (M374).
  ///
  /// Inventor calls this prehighlighting and it is not decoration: a measure
  /// tap is a COMMITMENT — it lands in the picks, changes the reading, and
  /// costs a second tap to undo — and on a face crowded with fillets there is
  /// no other way to know which of the four things under the cursor you are
  /// about to commit to. It is deliberately NOT a pick: nothing reads it but
  /// the painter, and clearing it never touches the reading.
  MeasureRef? hover;

  /// Sets [hover], and says whether anything actually changed.
  ///
  /// The guard is the whole reason this is a method. A hover event arrives on
  /// every pointer move, and repainting the viewport sixty times a second to
  /// draw the same highlight is how a prehighlight turns a smooth drag into a
  /// stutter. Something already PICKED never prehighlights either — it is
  /// fully lit already, and a dimmer mark on top of a brighter one only reads
  /// as the bright one flickering.
  bool setHover(MeasureRef? ref) {
    final next = (ref != null && picks.any((p) => p.sameAs(ref))) ? null : ref;
    if (next == null && hover == null) return false;
    if (next != null && hover != null && hover!.sameAs(next)) return false;
    hover = next;
    return true;
  }

  bool get isEmpty => picks.isEmpty;

  /// Adds [ref], or takes it away again when it is already in the list.
  ///
  /// THE RULE, and it is what makes the tool feel like Inventor's rather than
  /// like a selection dialogue:
  ///
  ///   * the same thing tapped twice is DESELECTED. One mis-tap costs one tap.
  ///   * a third pick starts a NEW measurement from that pick — except when
  ///     all three are points, which is the three-point angle and the one
  ///     three-pick reading there is.
  ///
  /// Returns true when the pick was taken (as opposed to removing one).
  bool add(MeasureRef ref) {
    // The prehighlight has done its job the moment the pick lands: whatever
    // it was pointing at is now either lit as a pick or gone from the list,
    // and either way a dim mark under a bright one is only a flicker. The
    // next pointer move re-establishes it.
    hover = null;
    for (var i = 0; i < picks.length; i++) {
      if (picks[i].sameAs(ref)) {
        picks.removeAt(i);
        recompute();
        return false;
      }
    }
    final wouldBeThreePoints = picks.length == 2 &&
        ref.kind == MeasureRefKind.point &&
        picks.every((p) => p.kind == MeasureRefKind.point);
    if (picks.length >= kMeasureMaxPicks ||
        (picks.length >= 2 && !wouldBeThreePoints)) {
      picks
        ..clear()
        ..add(ref);
    } else {
      picks.add(ref);
    }
    recompute();
    return true;
  }

  void removeAt(int i) {
    if (i < 0 || i >= picks.length) return;
    picks.removeAt(i);
    recompute();
  }

  void clearPicks() {
    picks.clear();
    hover = null;
    reading = null;
  }

  /// Re-solves [reading] from the current picks and mode.
  void recompute() {
    reading = measure(picks, mode: mode);
  }

  /// Banks the current reading's primary value in its kind's running total,
  /// and CLEARS THE PICKS. Returns false when there was nothing to bank.
  ///
  /// The clearing is the half that makes summing usable. Inventor's feature is
  /// "add the values of SEVERAL measurements", i.e. measure, add, measure,
  /// add — and without the clear the second measurement is not a measurement
  /// at all: the next tap lands beside the first pick and the pair is read as
  /// a distance between them, so a run of lengths silently becomes a run of
  /// gaps. Restart would fix it, at the cost of a second tap between every
  /// pair of measurements, forever.
  ///
  /// The TOTALS survive [clearPicks], which is the other half of the same
  /// rule — see there.
  bool addToTotals() {
    final r = reading;
    if (r == null) return false;
    totals = totals.plus(r);
    clearPicks();
    return true;
  }

  void clearTotals() => totals = const MeasureTotals();
}

// ===========================================================================
// writing a value down
// ===========================================================================

/// One value as the panel writes it: the number in [unit], then the symbol.
///
/// Angles get no space before the degree sign and lengths do, which is what
/// both languages' typography asks for and what [Fmt] already does for every
/// other number in the app. The decimal mark follows the UI language, so the
/// same reading is "12,50 mm" in German and "12.50 mm" in English.
String measureFormat(MeasureValue v,
    {int decimals = 2,
    MeasureUnitSystem unit = MeasureUnitSystem.millimetre}) {
  final n = measureConvert(v.value, v.unit, unit);
  final symbol = measureUnitSymbol(unit, v.unit);
  final body = Fmt.fixed(n, decimals);
  return v.unit == MeasureUnitKind.angle ? '$body$symbol' : '$body $symbol';
}

/// A whole reading as plain text, one value per line — what "Copy all" puts on
/// the clipboard.
String measureReadingText(MeasureReading r,
    {int decimals = 2,
    MeasureUnitSystem unit = MeasureUnitSystem.millimetre}) {
  return [
    for (final v in r.values)
      '${measureRoleLabel(v.role)}: '
          '${v.approximate ? '≈ ' : ''}'
          '${measureFormat(v, decimals: decimals, unit: unit)}',
  ].join('\n');
}
