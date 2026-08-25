// M242 — assembly RELATIONSHIPS: Inventor's Place Constraint, as a model.
//
// This file is the vocabulary. It holds no solver (asm_solver.dart), no UI
// (widgets/constraint_dialog.dart) and no picking (widgets/viewport_assembly)
// — only what a constraint IS, so all three can be written against one
// definition and a document can be written and read back.
//
// THE THREE FAMILIES, and why they are one type here.
//
// Inventor puts them on three tabs of one dialog, and they are genuinely
// different animals:
//
//   ASSEMBLY     Mate, Angle, Tangent, Insert, Symmetry. These POSITION
//                components: they are equations the solver drives to zero,
//                and they remove degrees of freedom.
//   MOTION       Rotation, Rotation-Translation. These do NOT position
//                anything. Autodesk is explicit that motion constraints
//                "operate only on open degrees of freedom" and cannot
//                conflict with assembly constraints — a gear ratio is applied
//                while you DRAG, never solved. See asm_solver's drive pass.
//   TRANSITIONAL A face kept tangent to a contiguous SET of faces on another
//                part — a cam and its follower. It positions like an assembly
//                constraint, but WHICH face it is tangent to is chosen afresh
//                on every solve, because sliding from one face to the next is
//                the entire point of it.
//
// One type, because everything outside the solver treats them alike: they are
// rows in the Relationships folder, they are saved together, they are named
// in one sequence, they are suppressed and deleted the same way, and one
// dialog creates all of them.
//
// WHAT A SELECTION REMEMBERS, and why it is in LOCAL coordinates.
//
// A pick happens in world space — the user taps a face on screen. What gets
// stored is that face reduced to its geometry ([AsmGeom]) expressed in the
// SOURCE PART's own coordinates. That is the difference between a constraint
// and a one-off snap: the moment the component moves, a world-space reference
// would still be pointing at where the face used to be.
import 'dart:math' as math;

import 'part_model.dart';
import 'work_features.dart' show WorkRefSource;

/// What a selection reduced to. Mirrors the part side's WorkRef, which turns
/// a tap into "a point, a line or a plane" — but stored rather than consumed,
/// and without the label plumbing a work feature's `def` sentence needs.
enum AsmGeomKind {
  /// A planar face, an origin plane or a work plane: a point and an OUTWARD
  /// normal.
  plane,

  /// A linear edge, an origin axis, or the axis of a cylinder / cone: a point
  /// and a direction. A cylinder also carries its [AsmGeom.radius].
  axis,

  /// A vertex, a work point, the centre of a sphere, or an edge midpoint.
  point,
}

/// One piece of geometry, in whichever frame the holder says.
class AsmGeom {
  const AsmGeom(this.kind, this.at, this.dir, {this.radius = 0, this.source});

  const AsmGeom.plane(Vec3 at, Vec3 n, {this.source = WorkRefSource.plane})
      : kind = AsmGeomKind.plane,
        this.at = at,
        dir = n,
        radius = 0;

  const AsmGeom.axis(Vec3 at, Vec3 d,
      {this.radius = 0, this.source = WorkRefSource.axis})
      : kind = AsmGeomKind.axis,
        this.at = at,
        dir = d;

  const AsmGeom.point(Vec3 at, {this.source = WorkRefSource.vertex})
      : kind = AsmGeomKind.point,
        this.at = at,
        dir = Vec3.zero,
        radius = 0;

  final AsmGeomKind kind;

  /// A point on the plane / on the axis, or the point itself.
  final Vec3 at;

  /// The plane's outward normal or the axis direction. Zero for a point.
  final Vec3 dir;

  /// A cylindrical face's radius. Zero when the pick carries none — which is
  /// what makes Tangent refuse a plain planar pick rather than silently
  /// treating it as a zero-radius cylinder.
  final double radius;

  /// M247 — WHAT the pick was, not merely what it reduces to.
  ///
  /// [kind] is the reduction a CONSTRAINT needs, and it is deliberately
  /// lossy: a circular edge, a cylindrical face and a straight edge are all
  /// [AsmGeomKind.axis], because Insert and Mate treat them alike. A WORK
  /// FEATURE cannot: "Through Center of Circular Edge" must refuse a
  /// cylinder, "Center Point of Sphere" must refuse a plane, and a tangent
  /// plane needs to know it is holding a cylinder. So the pick's own kind
  /// travels alongside the reduction.
  ///
  /// Reusing [WorkRefSource] rather than declaring a second enum: this class
  /// already says it mirrors WorkRef, and two enums for one fact is two
  /// chances for them to disagree.
  ///
  /// Null on a reference written before M247 — a document, not a defect. See
  /// `asm_work_features.workRefOf` for the per-kind fallback that reads one.
  final WorkRefSource? source;

  bool get isPlane => kind == AsmGeomKind.plane;
  bool get isAxis => kind == AsmGeomKind.axis;
  bool get isPoint => kind == AsmGeomKind.point;

  /// True when this came from a cylindrical face, i.e. an axis WITH a radius.
  bool get isCylinder => isAxis && radius > 1e-9;

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'at': [at.x, at.y, at.z],
        'dir': [dir.x, dir.y, dir.z],
        if (radius != 0) 'r': radius,
        // M247 — omitted when there is none, so a constraint written before
        // this existed and one written after are byte-identical.
        if (source != null) 'src': source!.name,
      };

  static AsmGeom? fromJson(Object? j) {
    if (j is! Map) return null;
    Vec3 v(Object? o) {
      if (o is! List || o.length < 3) return Vec3.zero;
      double n(int i) => (o[i] as num?)?.toDouble() ?? 0;
      return Vec3(n(0), n(1), n(2));
    }

    final k = AsmGeomKind.values
        .where((e) => e.name == j['k'])
        .firstOrNull;
    if (k == null) return null;
    return AsmGeom(k, v(j['at']), v(j['dir']),
        radius: (j['r'] as num?)?.toDouble() ?? 0,
        source: WorkRefSource.values
            .where((e) => e.name == j['src'])
            .firstOrNull);
  }
}

/// One selection: which component, and what on it.
class AsmRef {
  const AsmRef(this.occurrence, this.geom, this.label,
      {this.anchor = Vec3.zero, this.extent = 0, this.feature});

  /// The occurrence id ("Bracket:1"). The ASSEMBLY's origin geometry — its
  /// own planes and axes — uses [kAssemblyOrigin], because a constraint to
  /// the assembly's XY plane is a perfectly ordinary thing to want and it
  /// belongs to no component.
  final String occurrence;

  /// In the source part's own coordinates (or world, for [kAssemblyOrigin]).
  final AsmGeom geom;

  /// What to call it in the browser and the dialog — "Face", "Cylindrical
  /// Face", "Circular Edge", "XY Plane". Display only.
  final String label;

  /// WHERE ON THE COMPONENT the user actually touched, in the same frame as
  /// [geom]. Display only, and it exists because [geom] alone cannot say.
  ///
  /// A plane's own point is whatever OCCT chose for it — `pl.Location()`,
  /// which for a face made by an extrusion is the SKETCH ORIGIN and is very
  /// often nowhere near the face, frequently the world origin. Drawing the
  /// highlight there put it in mid-air beside the model. A cylinder is the
  /// same: `cy.Location()` is a point on the axis, not on the band you
  /// tapped.
  ///
  /// Neither is a bug in the record — any point on a plane defines that
  /// plane, and the solver is right to use it. But a HIGHLIGHT has to appear
  /// where the user pointed, so the tapped point is remembered alongside.
  /// Saved with the constraint, so re-opening a document highlights the same
  /// place.
  ///
  /// It is the MIDDLE of what was picked, not the pixel that was touched: a
  /// tap near the corner of a face means the face, and a highlight centred on
  /// the corner hangs half of itself off the part.
  final Vec3 anchor;

  /// How big the thing picked actually is — half the diagonal of a face, the
  /// half-length of an edge. Display only, and zero when the pick could not
  /// say (the assembly's own origin geometry, or a document written before
  /// this existed), in which case the marker falls back to the component's
  /// extent.
  ///
  /// Without it a marker is sized to the whole component, so picking one
  /// small face of a large part draws a patch far bigger than the face and
  /// the highlight stops meaning "this one".
  final double extent;

  /// M247 — the ASSEMBLY WORK FEATURE this names, e.g. `wp:3`, or null.
  ///
  /// The assembly's own work planes, axes and points sit under
  /// [kAssemblyOrigin] like its origin geometry, and are unlike it in one way
  /// that matters: they MOVE. An assembly work plane is re-solved from its
  /// inputs after every solve (see asm_work_features.dart), so a reference
  /// that baked its frame the way an origin reference does would be naming
  /// where the plane used to be — the exact failure [geom]'s local frame
  /// exists to prevent for components.
  ///
  /// So the id travels instead of the geometry, and [worldGeomOf] resolves it
  /// against the model on every read. [geom] is still filled in with the
  /// frame at pick time: it is what a document opened with the feature
  /// missing falls back to, and what keeps every reader that has no
  /// AssemblyModel to hand working unchanged.
  final String? feature;

  bool get isAssemblyOrigin => occurrence == kAssemblyOrigin;

  /// True when this names an assembly work feature rather than a component or
  /// the assembly's fixed origin.
  bool get isWorkFeature => feature != null;

  Map<String, dynamic> toJson() => {
        'occ': occurrence,
        'geom': geom.toJson(),
        'label': label,
        'at': [anchor.x, anchor.y, anchor.z],
        if (extent > 0) 'ext': extent,
        if (feature != null) 'wf': feature,
      };

  static AsmRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final occ = j['occ'] as String?;
    final g = AsmGeom.fromJson(j['geom']);
    if (occ == null || g == null) return null;
    // A document written before the anchor existed falls back to the
    // geometry's own point, which is exactly where the highlight used to be
    // drawn: no worse than it was, and every constraint made since is right.
    final a = j['at'];
    return AsmRef(occ, g, j['label'] as String? ?? '',
        anchor: a is List && a.length >= 3
            ? Vec3((a[0] as num?)?.toDouble() ?? 0,
                (a[1] as num?)?.toDouble() ?? 0, (a[2] as num?)?.toDouble() ?? 0)
            : g.at,
        extent: (j['ext'] as num?)?.toDouble() ?? 0,
        feature: j['wf'] as String?);
  }
}

/// The occurrence id standing for the ASSEMBLY ITSELF — its origin planes,
/// axes and centre point. Never a real occurrence id: those are
/// "<part>:<n>" and this carries no colon by design.
const String kAssemblyOrigin = ' asm';

/// Inventor's constraint types, across all three tabs.
enum AsmKind {
  // ---- Assembly tab -------------------------------------------------------
  mate,
  angle,
  tangent,
  insert,
  symmetry,
  // ---- Motion tab ---------------------------------------------------------
  rotation,
  rotationTranslation,
  // ---- Transitional tab ---------------------------------------------------
  transitional,
}

/// Which tab of the Place Constraint dialog a kind lives on.
enum AsmTab { assembly, motion, transitional, constraintSet }

AsmTab tabOf(AsmKind k) => switch (k) {
      AsmKind.mate ||
      AsmKind.angle ||
      AsmKind.tangent ||
      AsmKind.insert ||
      AsmKind.symmetry =>
        AsmTab.assembly,
      AsmKind.rotation || AsmKind.rotationTranslation => AsmTab.motion,
      AsmKind.transitional => AsmTab.transitional,
    };

const List<AsmKind> kAssemblyKinds = [
  AsmKind.mate,
  AsmKind.angle,
  AsmKind.tangent,
  AsmKind.insert,
  AsmKind.symmetry,
];

const List<AsmKind> kMotionKinds = [
  AsmKind.rotation,
  AsmKind.rotationTranslation,
];

/// The solution buttons a kind offers, in Inventor's own order — the row of
/// icons in the dialog's Solution group is exactly this list.
///
/// Every kind has at least one, so the group is never empty and the index
/// stored on a constraint is always meaningful.
enum AsmSolution {
  // Mate
  mate,
  flush,
  // Angle
  directedAngle,
  undirectedAngle,
  explicitVector,
  // Tangent
  inside,
  outside,
  // Insert
  opposed,
  aligned,
  // Symmetry
  symmetric,
  asymmetric,
  // Motion
  forward,
  reverse,
  // Transitional has none of its own.
  none,
}

List<AsmSolution> solutionsFor(AsmKind k) => switch (k) {
      AsmKind.mate => const [AsmSolution.mate, AsmSolution.flush],
      AsmKind.angle => const [
          AsmSolution.directedAngle,
          AsmSolution.undirectedAngle,
          AsmSolution.explicitVector,
        ],
      AsmKind.tangent => const [AsmSolution.inside, AsmSolution.outside],
      AsmKind.insert => const [AsmSolution.opposed, AsmSolution.aligned],
      AsmKind.symmetry => const [AsmSolution.symmetric, AsmSolution.asymmetric],
      AsmKind.rotation ||
      AsmKind.rotationTranslation =>
        const [AsmSolution.forward, AsmSolution.reverse],
      AsmKind.transitional => const [AsmSolution.none],
    };

/// How many selections a kind takes.
///
/// Three is not a quirk of two commands, it is the dialog's third pick button
/// appearing: Angle's Explicit Reference Vector needs a direction for the
/// cross product, and Symmetry needs the plane to be symmetric ABOUT.
int selectionCountFor(AsmKind k, AsmSolution s) {
  if (k == AsmKind.symmetry) return 3;
  if (k == AsmKind.angle && s == AsmSolution.explicitVector) return 3;
  return 2;
}

/// What the numeric field means for a kind — it is not always a distance,
/// and the dialog's label changes with it exactly as Inventor's does.
enum AsmValueKind {
  /// Millimetres between the two selections. Mate, Tangent, Insert.
  offset,

  /// Degrees. Angle.
  angle,

  /// Rotation ratio, dimensionless. Motion > Rotation.
  ratio,

  /// Millimetres the second selection travels per full turn of the first.
  /// Motion > Rotation-Translation.
  distancePerTurn,

  /// Transitional takes no value.
  none,
}

AsmValueKind valueKindOf(AsmKind k) => switch (k) {
      AsmKind.mate || AsmKind.tangent || AsmKind.insert => AsmValueKind.offset,
      AsmKind.angle => AsmValueKind.angle,
      AsmKind.symmetry => AsmValueKind.none,
      AsmKind.rotation => AsmValueKind.ratio,
      AsmKind.rotationTranslation => AsmValueKind.distancePerTurn,
      AsmKind.transitional => AsmValueKind.none,
    };

/// One relationship in the assembly.
class AsmConstraint {
  AsmConstraint({
    required this.name,
    required this.kind,
    required this.solution,
    required this.a,
    required this.b,
    this.c,
    this.value = 0,
    this.suppressed = false,
  });

  /// "Mate:1", "Insert:2" — Inventor's naming, and unique in the document.
  String name;
  AsmKind kind;
  AsmSolution solution;
  AsmRef a;
  AsmRef b;

  /// The third selection: Angle's explicit reference vector, or Symmetry's
  /// plane of symmetry. Null for every other kind.
  AsmRef? c;

  /// Offset in mm, angle in degrees, ratio, or mm per turn — see
  /// [valueKindOf].
  double value;

  bool suppressed;

  /// Why this constraint could not be met, or null when it is healthy.
  ///
  /// Inventor calls an unmet constraint SICK and gives it its own glyph, its
  /// own browser marking and a Show Sick command. Runtime only: a document
  /// records what the user asked for, never the solver's opinion of it on
  /// some earlier launch.
  String? error;

  bool get isSick => error != null;

  /// True for the kinds that are EQUATIONS the solver drives to zero. The
  /// motion kinds are not: they are applied while dragging (see the file
  /// header), so a solve must skip them or it would fight the drag.
  bool get isPositional =>
      kind != AsmKind.rotation && kind != AsmKind.rotationTranslation;

  /// Every occurrence this constraint touches, ignoring the assembly origin.
  Iterable<String> get occurrences sync* {
    for (final r in [a, b, if (c != null) c!]) {
      if (!r.isAssemblyOrigin) yield r.occurrence;
    }
  }

  bool touches(String occurrenceId) => occurrences.contains(occurrenceId);

  AsmConstraint copy() => AsmConstraint(
        name: name,
        kind: kind,
        solution: solution,
        a: a,
        b: b,
        c: c,
        value: value,
        suppressed: suppressed,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'sol': solution.name,
        'a': a.toJson(),
        'b': b.toJson(),
        if (c != null) 'c': c!.toJson(),
        'value': value,
        if (suppressed) 'suppressed': true,
      };

  static AsmConstraint? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = AsmKind.values.where((e) => e.name == j['kind']).firstOrNull;
    final a = AsmRef.fromJson(j['a']);
    final b = AsmRef.fromJson(j['b']);
    if (kind == null || a == null || b == null) return null;
    final sol = AsmSolution.values.where((e) => e.name == j['sol']).firstOrNull;
    return AsmConstraint(
      name: j['name'] as String? ?? kind.name,
      kind: kind,
      // A solution that is not one of THIS kind's is not merely unknown, it is
      // wrong: it would send the solver down another branch entirely. Fall
      // back to the kind's first, which is Inventor's default.
      solution: (sol != null && solutionsFor(kind).contains(sol))
          ? sol
          : solutionsFor(kind).first,
      a: a,
      b: b,
      c: AsmRef.fromJson(j['c']),
      value: (j['value'] as num?)?.toDouble() ?? 0,
      suppressed: j['suppressed'] == true,
    );
  }
}

/// The next free name for a constraint of [kind], counting the way Inventor
/// counts: "Mate:1", then "Mate:2".
String nextConstraintName(Iterable<AsmConstraint> existing, AsmKind kind) {
  final base = constraintBaseName(kind);
  var n = 1;
  while (existing.any((c) => c.name == '$base:$n')) {
    n++;
  }
  return '$base:$n';
}

/// The English stem a constraint's name is built from. NOT localised, and
/// that is deliberate: the name is written into the document and shown in the
/// browser, so translating it would make a German-authored assembly read
/// differently when opened in English — the same rule the part's feature
/// names follow ("Extrusion1", "Fillet1").
String constraintBaseName(AsmKind kind) => switch (kind) {
      AsmKind.mate => 'Mate',
      AsmKind.angle => 'Angle',
      AsmKind.tangent => 'Tangent',
      AsmKind.insert => 'Insert',
      AsmKind.symmetry => 'Symmetry',
      AsmKind.rotation => 'Rotation',
      AsmKind.rotationTranslation => 'RotationTranslation',
      AsmKind.transitional => 'Transitional',
    };

// ---------------------------------------------------------------------------
// What a pair of picks CAN be constrained by
// ---------------------------------------------------------------------------

/// Whether [kind] can act on this pair of geometries.
///
/// Inventor greys out — or refuses with a message — a combination it cannot
/// solve, and knowing this BEFORE the solver runs is what lets the dialog say
/// so instead of producing a constraint that is born sick. The rules are the
/// documented ones:
///
///   Mate       any two of plane / axis / point.
///   Angle      two directions, so plane or axis on both sides.
///   Tangent    needs a RADIUS on at least one side: a cylinder against a
///              plane or against another cylinder. Two planes have no
///              tangency, which is exactly why Inventor rejects them.
///   Insert     two circular edges or cylinders — an axis on both sides.
///   Symmetry   two of anything, plus a plane to be symmetric about.
///   Motion     two axes (two shafts, or a shaft and a rack).
bool kindAccepts(AsmKind kind, AsmGeom a, AsmGeom b) => switch (kind) {
      AsmKind.mate => true,
      AsmKind.angle => !a.isPoint && !b.isPoint,
      AsmKind.tangent => (a.isCylinder && (b.isPlane || b.isCylinder)) ||
          (b.isCylinder && a.isPlane),
      AsmKind.insert => a.isAxis && b.isAxis,
      AsmKind.symmetry => true,
      AsmKind.rotation ||
      AsmKind.rotationTranslation =>
        a.isAxis && b.isAxis,
      AsmKind.transitional =>
        (a.isCylinder || a.isPlane) && (b.isCylinder || b.isPlane),
    };

/// Why [kind] cannot act on this pair, as a key the l10n layer turns into a
/// sentence. Null when it can.
///
/// A key rather than a string because this file has no business holding UI
/// text, and the dialog shows the reason where Inventor shows its own.
String? rejectionFor(AsmKind kind, AsmGeom a, AsmGeom b) {
  if (kindAccepts(kind, a, b)) return null;
  return switch (kind) {
    AsmKind.tangent => 'tangentNeedsRound',
    AsmKind.insert => 'insertNeedsAxes',
    AsmKind.angle => 'angleNeedsDirections',
    AsmKind.rotation ||
    AsmKind.rotationTranslation =>
      'motionNeedsAxes',
    _ => 'cannotConstrain',
  };
}

/// The angle in DEGREES between two directions, in [0, 180].
double angleBetweenDeg(Vec3 a, Vec3 b) {
  final na = a.normalized(), nb = b.normalized();
  if (na.length < 0.5 || nb.length < 0.5) return 0;
  return math.acos(na.dot(nb).clamp(-1.0, 1.0)) * 180 / math.pi;
}
