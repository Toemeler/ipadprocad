// Prototype — 3D part documents (M56).
//
// A PART is a document that CONTAINS 2D sketches (each on one of the three
// origin work planes) and parametric FEATURES computed from them by the OCCT
// kernel. The 2D sketcher is reused UNCHANGED for the child sketches — the
// part layer only adds: the plane frames that place a sketch in 3D, profile
// REGION detection over the finished sketch (Inventor's pickable profiles),
// the Extrude feature (distance/direction/taper, holes included) and the
// kernel bridge that turns it into a world-space B-Rep + display mesh.
//
// Honesty rule (M55): there is NO Dart fallback for B-Rep. Without the
// linked OCCT kernel a feature stores its parameters but reports
// "no 3D kernel" instead of faking a solid. Tests inject a [PartKernel]
// fake to exercise the state machinery on host.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'app_state.dart' show SketchModel;
import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'log.dart';
import 'perf.dart';
import 'snap.dart' show sampleEntity;
import 'spline.dart' show splineCurveFor, splineArcChain, polyPoints;
import 'text_geometry.dart' show textContours, textLayerOf;
import 'pick_math.dart';
import 'tools.dart' show ExprParser;

// ---------------------------------------------------------------------------
// minimal 3D vector (no new dependencies)
// ---------------------------------------------------------------------------
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 normalized() {
    final l = length;
    return l < 1e-12 ? this : Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() => '($x,$y,$z)';
}

// ---------------------------------------------------------------------------
// origin work planes — frames match the approved HTML dummy's camera
// conventions exactly (Y-up world; see Part3D.orientToPlane in the mock):
// facing a plane head-on shows the sketch exactly as it was drawn
// (sketch +u = screen right, +v = screen up), and u × v = normal so every
// frame is a proper right-handed rotation (accepted by occt_transform).
/// Rodrigues rotation of [v] about the UNIT axis [k] by [a] radians.
///
/// One implementation, used by the trackball orbit (PartCamera) and by the
/// revolve placement (PlaneFrame.mat34Rotated). They had drifted into two
/// copies of the same formula in this very file.
Vec3 rotateAboutAxis(Vec3 v, Vec3 k, double a) {
  if (a == 0) return v;
  final c = math.cos(a), sn = math.sin(a);
  return v * c + k.cross(v) * sn + k * (k.dot(v) * (1 - c));
}

/// Extent of the axis-aligned box [lo]..[hi] projected onto [dir]: (lo, hi)
/// as distances along that direction from the world origin.
///
/// Picks the extreme corner per axis by the sign of [dir] — two dot products
/// instead of walking all eight corners. Used by the origin-axis span (M83)
/// and by Through All (M132).
(double, double) boxSpanAlong(Vec3 lo, Vec3 hi, Vec3 dir) {
  final a = Vec3(dir.x >= 0 ? lo.x : hi.x, dir.y >= 0 ? lo.y : hi.y,
      dir.z >= 0 ? lo.z : hi.z);
  final b = Vec3(dir.x >= 0 ? hi.x : lo.x, dir.y >= 0 ? hi.y : lo.y,
      dir.z >= 0 ? hi.z : lo.z);
  return (a.dot(dir), b.dot(dir));
}

// ---------------------------------------------------------------------------
class PlaneFrame {
  final String key; // 'xy' | 'yz' | 'xz' | 'face'
  final Vec3 u, v, n;

  /// World point of the sketch origin. Zero for the three origin planes; a
  /// point ON the picked face for sketches on solid faces (M58).
  final Vec3 origin;
  const PlaneFrame(this.key, this.u, this.v, this.n, [this.origin = Vec3.zero]);

  Vec3 toWorld(Offset p, [double w = 0]) =>
      origin + u * p.dx + v * p.dy + n * w;

  /// Sketch-plane coordinates of world point [w].
  Offset toSketch(Vec3 w) => Offset((w - origin).dot(u), (w - origin).dot(v));

  /// Row-major 3x4 rigid placement for [occt_transform]: columns u,v,n,
  /// translation = origin + normal * [zOffset] (where the extrusion starts).
  List<double> mat34(double zOffset) => [
        u.x, v.x, n.x, origin.x + n.x * zOffset, //
        u.y, v.y, n.y, origin.y + n.y * zOffset, //
        u.z, v.z, n.z, origin.z + n.z * zOffset, //
      ];

  /// [mat34] pre-composed with a rotation of [angleDeg] about the SKETCH-space
  /// axis through (px, py) along (dx, dy).
  ///
  /// This is how a revolve honours Inventor's Flipped / Symmetric /
  /// Asymmetric directions. The shim always sweeps in the positive direction
  /// starting at the profile, so "start half a turn back" is expressed by
  /// rotating the finished solid backwards — the rotational twin of the z
  /// offset [mat34] already applies for a linear extrude. Doing it in the
  /// placement keeps the kernel call itself direction-free, which is why
  /// neither path can ever produce a mirrored solid.
  List<double> mat34Rotated(
      double px, double py, double dx, double dy, double angleDeg) {
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-12 || angleDeg.abs() < 1e-12) return mat34(0);
    final k = Vec3(dx / len, dy / len, 0);
    final t = angleDeg * math.pi / 180.0;
    // Column j of (M3 * R3) is M3 applied to R3's column j, and R3's column j
    // is the rotated basis vector — so the whole matrix falls out of three
    // calls to the shared Rodrigues helper, with no second copy of the
    // formula to keep in step.
    Vec3 col(Vec3 e) {
      final r = rotateAboutAxis(e, k, t);
      return u * r.x + v * r.y + n * r.z;
    }

    final cx = col(const Vec3(1, 0, 0));
    final cy = col(const Vec3(0, 1, 0));
    final cz = col(const Vec3(0, 0, 1));
    // Rotation about a LINE, not the origin: p -> R(p - a) + a.
    final a = Vec3(px, py, 0);
    final tr = a - rotateAboutAxis(a, k, t);
    final off = u * tr.x + v * tr.y + n * tr.z;
    return [
      cx.x, cy.x, cz.x, origin.x + off.x, //
      cx.y, cy.y, cz.y, origin.y + off.y, //
      cx.z, cy.z, cz.z, origin.z + off.z, //
    ];
  }

  List<double> frameJson() => [
        u.x, u.y, u.z, v.x, v.y, v.z, //
        n.x, n.y, n.z, origin.x, origin.y, origin.z,
      ];

  static PlaneFrame? fromFrameJson(List? j) {
    if (j == null || j.length != 12) return null;
    final d = [for (final v in j) (v as num).toDouble()];
    return PlaneFrame('face', Vec3(d[0], d[1], d[2]), Vec3(d[3], d[4], d[5]),
        Vec3(d[6], d[7], d[8]), Vec3(d[9], d[10], d[11]));
  }
}

/// Frame for a sketch on a planar solid face: n = the face normal, u/v a
/// right-handed basis (u x v = n), origin = the plane's point closest to the
/// world origin (small, stable sketch coordinates — Inventor-like).
PlaneFrame faceFrame(Vec3 hit, Vec3 normal) {
  final n = normal.normalized();
  var up = n.y.abs() > 0.9 ? const Vec3(0, 0, 1) : const Vec3(0, 1, 0);
  final u = up.cross(n).normalized();
  final v = n.cross(u).normalized();
  final origin = n * n.dot(hit); // closest point of the plane to (0,0,0)
  return PlaneFrame('face', u, v, n, origin);
}

/// M223 — the frame of a work plane built from picks: [at] lies on it, [n] is
/// its normal, and u/v come from [faceFrame] — the app's ONE rule for turning
/// a normal into a sketch basis. The origin is [at] itself rather than the
/// plane's closest point to the world origin: for a plane through three picked
/// points, "where is its origin" has an answer the user chose.
PlaneFrame workPlaneFrameAt(Vec3 at, Vec3 n) {
  final f = faceFrame(at, n);
  return PlaneFrame(kWorkPlaneKey, f.u, f.v, f.n, at);
}

const kPlaneKeys = ['yz', 'xz', 'xy'];

/// M151 — key carried by every user-created work plane's frame.
///
/// Deliberately NOT one of [kPlaneKeys]: a work plane behaves like a picked
/// solid face rather than like an origin plane. A sketch placed on one stores
/// the frame outright (the `face` slot of ChildSketch), so it keeps working
/// when the plane later moves, and nothing that switches the three origin
/// planes on and off can touch it.
const String kWorkPlaneKey = 'work';

/// Resolves a plane pick key — an origin key or a work plane's `wp:N` id — to
/// its frame. Null when the key names nothing on this part.
///
/// M215 — deliberately still PLANES only. A work axis (`wa:N`) and a work
/// point (`wpt:N`) are pickable too, but they are not frames and a caller that
/// wanted a plane must not silently get something else.
PlaneFrame? frameForPlaneKey(PartModel p, String key) {
  if (kPlaneKeys.contains(key)) return planeFrame(key);
  for (final w in p.workPlanes) {
    if (w.id == key) return w.frame;
  }
  return null;
}

/// How a work plane was defined. Two kinds for now, both parametric only in
/// the sense that the DEFINITION is recorded; the frame is baked at creation.
/// M223 — [constructed] covers every method that is BUILT FROM PICKS and
/// carries no editable number: three points, two coplanar edges, normal to an
/// axis, parallel through a point, the midplane of a torus. They differ only
/// in the sentence they record, which is what `def` is for; what they share is
/// that nothing about them can be re-typed afterwards. `fromJson` falls back
/// to [offset] for a name it does not know, so adding this is safe for
/// documents written before it.
enum WorkPlaneKind { offset, midplane, constructed, angle }

/// A plane offset from [base] along its own normal by [d] mm.
///
/// The u/v axes are inherited so a sketch on the offset plane has the same
/// orientation as one on the base — an offset plane that silently rotated its
/// sketch axes would be worse than useless.
PlaneFrame offsetPlaneFrame(PlaneFrame base, double d) => PlaneFrame(
    kWorkPlaneKey, base.u, base.v, base.n, base.origin + base.n * d);

/// M229 — [base] rotated by [deg] about the line ([axisAt], [axisDir]).
///
/// Rodrigues on the whole frame, not just the normal: u and v have to come
/// along or a sketch on the result would be twisted relative to the plane it
/// was angled from — the same reason [offsetPlaneFrame] inherits its axes.
/// The origin is a point ON the axis, because that is the one line the two
/// planes share and the only origin that keeps the angle visible.
PlaneFrame anglePlaneFrame(
    PlaneFrame base, Vec3 axisAt, Vec3 axisDir, double deg) {
  final d = axisDir.normalized();
  final r = deg * math.pi / 180;
  final c = math.cos(r), sn = math.sin(r);
  Vec3 rot(Vec3 v) =>
      v * c + d.cross(v) * sn + d * (d.dot(v) * (1 - c));
  return PlaneFrame(kWorkPlaneKey, rot(base.u).normalized(),
      rot(base.v).normalized(), rot(base.n).normalized(), axisAt);
}

/// The plane halfway between [a] and [b], or null when they are not parallel.
///
/// Anti-parallel counts as parallel: two opposite faces of a block are the
/// commonest midplane input there is, and their normals point away from each
/// other. Non-parallel input returns null rather than guessing — an angled
/// bisector is a different feature and pretending otherwise would put a plane
/// somewhere the user did not ask for.
PlaneFrame? midPlaneFrame(PlaneFrame a, PlaneFrame b, {double tol = 1e-6}) {
  final d = a.n.dot(b.n);
  if ((d.abs() - 1).abs() > tol) return null;
  final n = a.n;
  // Signed distances of both planes along the SHARED normal, so the midpoint
  // is a real point on the resulting plane.
  final mid = (a.origin.dot(n) + b.origin.dot(n)) / 2;
  return PlaneFrame(kWorkPlaneKey, a.u, a.v, n, n * mid);
}

/// A user-created work plane. The frame is baked at creation; [def] is what
/// the browser and the toast show, so the user can tell two planes apart.
class WorkPlane {
  final String name;
  final int seq;
  final WorkPlaneKind kind;
  String def;
  PlaneFrame frame;
  bool visible;

  /// M162 — the plane this one was offset FROM, and by how much.
  ///
  /// Kept so an offset plane can be RE-OFFSET after the fact, the way every
  /// other number in the document can be edited. Without them the distance was
  /// baked into [frame] at creation and gone: `workPlaneOffset` was never
  /// assigned from anywhere either, so every offset plane in every document is
  /// exactly 10 mm (visible in a real file as "Offset 10.00 mm from face").
  ///
  /// Null on a midplane, and on any offset plane written before M162 — those
  /// keep the frame they were saved with rather than being recomputed from a
  /// base nobody recorded.
  PlaneFrame? base;
  double? offset;

  /// M229 — the edge an [WorkPlaneKind.angle] plane pivots about, and by how
  /// much. Stored for the same reason [base]/[offset] are: without them the
  /// angle is baked into the frame at creation and the one number the user
  /// actually thinks in is gone.
  Vec3? axisAt;
  Vec3? axisDir;
  double? angle;

  WorkPlane(this.name, this.seq, this.kind, this.def, this.frame,
      {this.visible = true,
      this.base,
      this.offset,
      this.axisAt,
      this.axisDir,
      this.angle});

  /// Whether [setOffset] can move this plane.
  bool get offsetEditable => kind == WorkPlaneKind.offset && base != null;

  /// M229 — the angle twin of [offsetEditable].
  bool get angleEditable =>
      kind == WorkPlaneKind.angle &&
      base != null &&
      axisAt != null &&
      axisDir != null;

  /// True when the plane carries ONE number the value field can edit — mm for
  /// an offset, degrees for an angle. The field asks this rather than the kind,
  /// so a third editable kind lands in one place.
  bool get valueEditable => offsetEditable || angleEditable;

  /// The unit of that number, for the field's suffix and its scrub steps.
  String get valueUnit => kind == WorkPlaneKind.angle ? 'deg' : 'mm';

  double? get value => kind == WorkPlaneKind.angle ? angle : offset;

  /// M229 — re-angle an existing plane, the twin of [setOffset].
  bool setAngle(double deg, {String? baseLabel}) {
    final b = base, at = axisAt, dir = axisDir;
    if (!angleEditable || b == null || at == null || dir == null) return false;
    if (!deg.isFinite) return false;
    angle = deg;
    frame = anglePlaneFrame(b, at, dir, deg);
    def = '${deg.toStringAsFixed(2)} deg from ${baseLabel ?? _defSource()}';
    return true;
  }

  /// Re-offsets the plane from its recorded base. Returns false when this
  /// plane has no base to measure from.
  bool setOffset(double d, {String? baseLabel}) {
    final b = base;
    if (kind != WorkPlaneKind.offset || b == null || !d.isFinite) return false;
    offset = d;
    frame = offsetPlaneFrame(b, d);
    def = 'Offset ${d.toStringAsFixed(2)} mm from ${baseLabel ?? _defSource()}';
    return true;
  }

  /// The trailing "from X" of the current [def], so re-offsetting keeps
  /// naming the same source without the caller having to remember it.
  String _defSource() {
    const marker = ' from ';
    final i = def.lastIndexOf(marker);
    return i < 0 ? 'plane' : def.substring(i + marker.length);
  }

  /// Stable id used by hover and picking, e.g. `wp:3`.
  String get id => 'wp:$seq';

  static List<double> _v(Vec3 a) => [a.x, a.y, a.z];
  static Vec3 _p(dynamic l) {
    final a = (l as List).cast<num>();
    return Vec3(a[0].toDouble(), a[1].toDouble(), a[2].toDouble());
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'seq': seq,
        'kind': kind.name,
        'def': def,
        'visible': visible,
        'o': _v(frame.origin),
        'u': _v(frame.u),
        'v': _v(frame.v),
        'n': _v(frame.n),
        // M162 — only written when there IS one, so a midplane's file is
        // unchanged and an old document stays byte-identical until edited.
        if (base != null) ...{
          'bo': _v(base!.origin),
          'bu': _v(base!.u),
          'bv': _v(base!.v),
          'bn': _v(base!.n),
          if (offset != null) 'd': offset,
        },
        // M229 — the pivot of an angle plane, written only when there is one.
        if (axisAt != null && axisDir != null) ...{
          'aa': _v(axisAt!),
          'ad': _v(axisDir!),
          'ang': angle,
        },
      };

  static WorkPlane? fromJson(Map<String, dynamic> m) {
    try {
      return WorkPlane(
        m['name'] as String? ?? 'Work Plane',
        (m['seq'] as num?)?.toInt() ?? 0,
        WorkPlaneKind.values.firstWhere((k) => k.name == m['kind'],
            orElse: () => WorkPlaneKind.offset),
        m['def'] as String? ?? '',
        PlaneFrame(kWorkPlaneKey, _p(m['u']), _p(m['v']), _p(m['n']),
            _p(m['o'])),
        visible: m['visible'] as bool? ?? true,
        // M162 — absent on a midplane and on anything written before M162;
        // those keep the frame they were saved with and are not re-offsettable.
        base: m['bo'] == null
            ? null
            : PlaneFrame(kWorkPlaneKey, _p(m['bu']), _p(m['bv']), _p(m['bn']),
                _p(m['bo'])),
        offset: (m['d'] as num?)?.toDouble(),
        axisAt: m['aa'] == null ? null : _p(m['aa']),
        axisDir: m['ad'] == null ? null : _p(m['ad']),
        angle: (m['ang'] as num?)?.toDouble(),
      );
    } catch (_) {
      // A corrupt entry must not take the whole part down with it.
      return null;
    }
  }
}

/// M215 — a user-created work axis.
///
/// Baked at creation, exactly like [WorkPlane]: `at`/`dir` are world-space and
/// do not follow the geometry they were derived from. That is a real
/// difference from Inventor, where work features are parametric, and it is
/// stated here rather than implied — [def] records what it was built from so
/// the browser can say so, but nothing re-derives it.
class WorkAxis {
  final String name;
  final int seq;

  /// A point on the axis, and its UNIT direction. The direction's SIGN is
  /// meaningful: "Through Two Points" runs first to second, and an axis used
  /// as a revolve axis or a pattern direction inherits that choice.
  Vec3 at, dir;

  /// What it was made from, e.g. "Intersection of Front Face and XY Plane".
  String def;
  bool visible;

  WorkAxis(this.name, this.seq, this.def, this.at, this.dir,
      {this.visible = true});

  /// Stable id used by hover, picking and the browser, e.g. `wa:3`.
  String get id => 'wa:$seq';

  /// Reverses the axis. Inventor has no "flip work axis" command, but this
  /// app's axis carries a sign that matters downstream (revolve direction),
  /// and re-picking two points in the other order to change it would be an
  /// absurd amount of work for a minus sign.
  void flip() => dir = dir * -1;

  Map<String, dynamic> toJson() => {
        'name': name,
        'seq': seq,
        'def': def,
        'visible': visible,
        'at': [at.x, at.y, at.z],
        'dir': [dir.x, dir.y, dir.z],
      };

  static WorkAxis? fromJson(Map<String, dynamic> m) {
    try {
      final a = (m['at'] as List).cast<num>();
      final d = (m['dir'] as List).cast<num>();
      final dir = Vec3(d[0].toDouble(), d[1].toDouble(), d[2].toDouble());
      // A zero direction is not an axis. Dropping the entry loses one row;
      // keeping it would put a NaN into every span and highlight that ever
      // touches it.
      if (dir.length < 1e-9) return null;
      return WorkAxis(
        m['name'] as String? ?? 'Work Axis',
        (m['seq'] as num?)?.toInt() ?? 0,
        m['def'] as String? ?? '',
        Vec3(a[0].toDouble(), a[1].toDouble(), a[2].toDouble()),
        dir.normalized(),
        visible: m['visible'] as bool? ?? true,
      );
    } catch (_) {
      // A corrupt entry must not take the whole part down with it — same
      // policy as WorkPlane.fromJson.
      return null;
    }
  }
}

/// M215 — a user-created work point. Baked at creation, as [WorkAxis] is.
class WorkPoint {
  final String name;
  final int seq;
  Vec3 at;
  String def;
  bool visible;

  /// Inventor's Grounded Point: a point that is deliberately fixed in space
  /// rather than attached to geometry. Here EVERY work feature is baked, so
  /// this changes nothing about the arithmetic — it is recorded because the
  /// user asked for a grounded point and the browser should say that is what
  /// they got, instead of quietly relabelling it.
  final bool grounded;

  WorkPoint(this.name, this.seq, this.def, this.at,
      {this.visible = true, this.grounded = false});

  /// Stable id used by hover, picking and the browser, e.g. `wpt:3`.
  String get id => 'wpt:$seq';

  Map<String, dynamic> toJson() => {
        'name': name,
        'seq': seq,
        'def': def,
        'visible': visible,
        'at': [at.x, at.y, at.z],
        if (grounded) 'grounded': true,
      };

  static WorkPoint? fromJson(Map<String, dynamic> m) {
    try {
      final a = (m['at'] as List).cast<num>();
      return WorkPoint(
        m['name'] as String? ?? 'Work Point',
        (m['seq'] as num?)?.toInt() ?? 0,
        m['def'] as String? ?? '',
        Vec3(a[0].toDouble(), a[1].toDouble(), a[2].toDouble()),
        visible: m['visible'] as bool? ?? true,
        grounded: m['grounded'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

PlaneFrame planeFrame(String key) {
  switch (key) {
    case 'yz':
      return const PlaneFrame(
          'yz', Vec3(0, 0, -1), Vec3(0, 1, 0), Vec3(1, 0, 0));
    case 'xz':
      return const PlaneFrame(
          'xz', Vec3(1, 0, 0), Vec3(0, 0, -1), Vec3(0, 1, 0));
    default:
      return const PlaneFrame(
          'xy', Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1));
  }
}

String planeLabel(String key) => key == 'yz'
    ? 'YZ Plane'
    : key == 'xz'
        ? 'XZ Plane'
        : 'XY Plane';

/// Camera (az, pol) that faces [key] head-on — same numbers as the mock's
/// orientToPlane (xz uses a hair above 0 so the camera up vector stays sane).
(double, double) planeCameraTarget(String key) {
  if (key == 'yz') return (math.pi / 2, math.pi / 2);
  if (key == 'xz') return (0, 0.001);
  return (0, math.pi / 2);
}

/// Orbit camera of the 3D part viewport, persisted per part. Same model as
/// the mock: turntable az/pol about the origin, orthographic half-height
/// [halfH] (zoom), frustum pan offset [ox]/[oy]. 1 world unit = 1 mm.
class PartCamera {
  double az, pol, halfH, ox, oy;

  /// Rotation about the view direction, radians (M80).
  ///
  /// az/pol alone cannot express every orientation: the basis is derived by
  /// crossing the view direction with world up, which pins the roll. A sketch
  /// on a TILTED face needs its own u/v to land on screen x/y, and that
  /// generally differs from the derived basis by a roll. Without this the
  /// model appears rotated inside the sketch plane. 0 for every camera that
  /// existed before, so orbiting is unchanged.
  double roll;

  PartCamera(
      {this.az = math.pi / 4,
      this.pol = 0.955,
      this.halfH = 27,
      this.ox = 0,
      this.oy = 0,
      this.roll = 0});

  /// Aims straight down [fr]'s normal with [fr]'s own axes mapped to screen
  /// x/y, matching how Viewport2D.map() draws that sketch. [zoom] and [pan]
  /// come from the 2D editor, which stays the single source of navigation.
  static PartCamera forSketch(PlaneFrame fr, Size size, Offset pan, double zoom) {
    final n = fr.n;
    final pol = math.acos(n.y.clamp(-1.0, 1.0));
    final az = math.atan2(n.x, n.z);
    // roll = signed angle from the derived right vector to the frame's u,
    // measured about the view direction.
    final sDer = rightFor(az);
    final uDer = sDer.cross(n * -1).normalized();
    final roll = math.atan2(fr.u.dot(uDer), fr.u.dot(sDer));
    return PartCamera(
      az: az,
      pol: pol,
      halfH: clampHalfH(size.height / (2 * (zoom <= 0 ? 1 : zoom))),
      ox: fr.origin.dot(fr.u) + pan.dx,
      oy: fr.origin.dot(fr.v) + pan.dy,
      roll: roll,
    );
  }

  /// Interpolates between two cameras for the sketch-entry animation (M88).
  ///
  /// [t] runs 0..1. Angles are interpolated on the SHORT way round — plain
  /// lerp on az would spin the model most of a turn whenever the two happen to
  /// straddle +/-pi, which is common because az comes from atan2. halfH is
  /// interpolated geometrically, since zoom is multiplicative: the linear
  /// midpoint between 27 and 2700 is 1363, which is visually almost the whole
  /// way there, while the geometric one (270) is the true halfway.
  static PartCamera lerp(PartCamera a, PartCamera b, double t) {
    final k = t.clamp(0.0, 1.0);
    double ang(double x, double y) {
      var d = y - x;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      return x + d * k;
    }

    double geo(double x, double y) =>
        (x > 0 && y > 0) ? x * math.pow(y / x, k) : x + (y - x) * k;

    return PartCamera(
      az: ang(a.az, b.az),
      pol: a.pol + (b.pol - a.pol) * k,
      halfH: clampHalfH(geo(a.halfH, b.halfH)),
      ox: a.ox + (b.ox - a.ox) * k,
      oy: a.oy + (b.oy - a.oy) * k,
      roll: ang(a.roll, b.roll),
    );
  }

  /// Camera right vector, as a closed form in the AZIMUTH alone.
  ///
  /// M89 — this used to be `normalize(fwd x (0,1,0))` with a fallback for when
  /// that got short. Two problems, and they caused both reported symptoms:
  ///
  ///  * The fallback `fwd x (0,0,1)` points somewhere unrelated to the limit
  ///    the approach was heading for, so the swing SNAPPED at the end.
  ///  * More fundamentally, the basis cannot be recovered from the DIRECTION
  ///    at all near a pole: at pol = 0, dir = (0,1,0) whatever the azimuth
  ///    was, so az is simply not in there any more.
  ///
  /// Writing the cross product out with dir = (sin p sin a, cos p, sin p cos a)
  /// gives fwd x (0,1,0) = (sin p cos a, 0, -sin p sin a), whose normalisation
  /// is (cos a, 0, -sin a) for EVERY pol — sin p cancels. So the azimuth is the
  /// only input needed, there is no degenerate case, and it is continuous
  /// everywhere. Derive it from az, never from dir.
  ///
  /// Cam3 (part_render.dart) and the Swift placeCamera() must use this same
  /// form: the roll is measured against this basis and applied to theirs, so
  /// any disagreement shows up as a rotated or mirrored sketch.
  static Vec3 rightFor(double az) =>
      Vec3(math.cos(az), 0, -math.sin(az));

  /// The camera's own right vector, i.e. [rightFor] turned by [roll].
  Vec3 get right {
    final s0 = rightFor(az), u0 = s0.cross(dir * -1).normalized();
    if (roll == 0) return s0;
    return (s0 * math.cos(roll) + u0 * math.sin(roll)).normalized();
  }

  /// The camera's own up vector.
  Vec3 get up => right.cross(dir * -1).normalized();

  /// Rodrigues rotation of [v] about the unit axis [k] by [a] radians.
  /// Thin alias for the shared [rotateAboutAxis]; kept so the orbit code
  /// below reads unchanged.
  static Vec3 _rotate(Vec3 v, Vec3 k, double a) => rotateAboutAxis(v, k, a);

  /// TRACKBALL orbit (M90) — rotates about the SCREEN axes, which is what
  /// Inventor's Free Orbit and Blender's trackball do: [yaw] about the
  /// camera's own up, [pitch] about its own right.
  ///
  /// The old orbit added straight onto az/pol, a TURNTABLE, and had to clamp
  /// pol away from the poles because the basis was derived from the view
  /// direction and degenerated there. That clamp is why the view could never
  /// look straight down, let alone continue past it. Rotating the basis itself
  /// has no preferred up and no degenerate case, so it runs 360 degrees in
  /// every direction.
  ///
  /// Three degrees of freedom are needed to express the result, which is
  /// exactly what az/pol/roll became in M89 — a two-angle camera could not
  /// have represented a trackball at all.
  void orbitScreen(double yaw, double pitch) {
    var d = dir;
    var r = right;
    final u = up;
    // yaw first, about the current up
    d = _rotate(d, u, yaw);
    r = _rotate(r, u, yaw);
    // then pitch about the NEW right, so the two compose like a real ball
    d = _rotate(d, r, pitch).normalized();
    setBasis(d, r);
  }

  /// Rewrites az/pol/roll so the camera looks along [d] with [r] to the right.
  ///
  /// At a pole az is arbitrary (atan2(0,0)), and that is fine: roll is measured
  /// against rightFor(az) and the renderer rebuilds from the SAME az, so the
  /// pair stays consistent. That is precisely what a two-angle camera could
  /// not do.
  void setBasis(Vec3 d, Vec3 r) {
    final dn = d.normalized();
    // re-orthogonalise: drift accumulates over hundreds of drag events
    final rn = (r - dn * r.dot(dn)).normalized();
    pol = math.acos(dn.y.clamp(-1.0, 1.0));
    az = math.atan2(dn.x, dn.z);
    final s0 = rightFor(az);
    final u0 = s0.cross(dn * -1).normalized();
    roll = math.atan2(rn.dot(u0), rn.dot(s0));
  }

  // Practically-endless orthographic zoom (halfH = half the visible height in
  // mm). Not literally infinite: outside this band the ortho projection loses
  // precision, so we cap far beyond any real part (0.1µm .. 20km of view).
  static const double minHalfH = 1e-4;
  static const double maxHalfH = 1e7;
  static double clampHalfH(double h) =>
      h.isFinite ? h.clamp(minHalfH, maxHalfH).toDouble() : 27.0;

  Vec3 get dir => Vec3(math.sin(pol) * math.sin(az), math.cos(pol),
      math.sin(pol) * math.cos(az));

  void home() {
    az = math.pi / 4;
    pol = 0.955;
    halfH = 27;
    ox = 0;
    oy = 0;
  }

  /// Face the camera along an arbitrary plane normal (sketch on a face).
  void orientToDir(Vec3 n) {
    final d = n.normalized();
    // M90 — no pole clamp any more; the basis is continuous, so looking
    // exactly straight down is a normal state. At a pole the azimuth carries
    // no information, so the previous one is kept: the top view then keeps the
    // rotation you approached it from, which is what the old code did too.
    if (d.y.abs() < 0.999) az = math.atan2(d.x, d.z);
    setBasis(d, rightFor(az));
    ox = 0;
    oy = 0;
    halfH = 27;
  }

  /// Faces [fr] with [fr]'s own u on screen x — the same orientation
  /// [forSketch] will use. [flip] looks from the far side instead.
  ///
  /// M211 — [orientToDir] takes a DIRECTION, so it can only aim the camera; it
  /// has nothing to say about the roll and leaves it wherever the derived
  /// basis for the current azimuth happens to put it. That is fine for a view
  /// command, and wrong for picking a sketch plane, because the sketch camera
  /// is not free: [forSketch] pins screen x to the frame's u. The two then
  /// disagree by whatever the orbit left behind, and the swing into the sketch
  /// spins the model by that angle.
  ///
  /// On the device (bug20260805T230205) it was half a turn. The user picked
  /// the bottom face, n=(-0.0,-1.0,-0.0), from an orbit at az≈-2.44. At a pole
  /// [orientToDir] keeps that azimuth and rolls to match it, giving a right
  /// vector of ≈(-0.77, 0, 0.64); the frame's u is (1, 0, 0). The sketch
  /// opened with the part turned around — "the sketch shows the wrong side of
  /// the selected face" — and the slot the user had picked on the right was
  /// now on the left.
  ///
  /// Orienting to the FRAME instead of to the normal makes entering a sketch a
  /// pure zoom, which is what M88's swing was for.
  void orientToFrame(PlaneFrame fr, {bool flip = false}) {
    setBasis(flip ? fr.n * -1 : fr.n, fr.u);
    ox = 0;
    oy = 0;
    halfH = 27;
  }

  void orientToPlane(String key) {
    final (a, p) = planeCameraTarget(key);
    az = a;
    pol = p;
    ox = 0;
    oy = 0;
    halfH = 27;
  }

  Map<String, dynamic> toJson() =>
      {'az': az, 'pol': pol, 'h': halfH, 'ox': ox, 'oy': oy};
  void loadJson(Map<String, dynamic> j) {
    az = (j['az'] as num?)?.toDouble() ?? az;
    pol = (j['pol'] as num?)?.toDouble() ?? pol;
    halfH = (j['h'] as num?)?.toDouble() ?? halfH;
    ox = (j['ox'] as num?)?.toDouble() ?? ox;
    oy = (j['oy'] as num?)?.toDouble() ?? oy;
  }
}

// ---------------------------------------------------------------------------
// profile detection — Inventor's pickable regions over a finished sketch
// ---------------------------------------------------------------------------

/// One closed boundary in sketch coordinates. [pts] runs counter-clockwise
/// and does NOT repeat the first point. [ents] are the contributing entity
/// indices (for highlight).
class ProfileLoop {
  final int id;
  final List<Offset> pts;
  final double area; // > 0 (CCW)
  final Offset centroid;
  final Set<int> ents;
  const ProfileLoop(this.id, this.pts, this.area, this.centroid, this.ents);
}

/// A pickable profile: an outer loop plus the loops DIRECTLY inside it
/// (its holes) — clicking between a rectangle and the circle inside it
/// selects the ring, exactly like Inventor.
class ProfileRegion {
  final ProfileLoop outer;
  final List<ProfileLoop> holes;
  const ProfileRegion(this.outer, this.holes);
}

double _signedArea(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a / 2;
}

Offset _centroidOf(List<Offset> p) {
  // area-weighted polygon centroid (falls back to the mean when degenerate)
  final a = _signedArea(p);
  if (a.abs() < 1e-12) {
    var s = Offset.zero;
    for (final q in p) {
      s += q;
    }
    return s / p.length.toDouble();
  }
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    final w = p[i].dx * p[j].dy - p[j].dx * p[i].dy;
    cx += (p[i].dx + p[j].dx) * w;
    cy += (p[i].dy + p[j].dy) * w;
  }
  return Offset(cx / (6 * a), cy / (6 * a));
}

bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// The slice of a sketch the profile finders read. Passed instead of the whole
/// [SketchModel] so the SAME code can count loops on an arbitrary candidate
/// geometry list — the M182 projection guard needs exactly that (does this
/// update open a loop a feature builds on?) without mutating the live sketch.
class ProfileInput {
  final List<Geo> geometry;
  final List<String> layers;
  final Set<String> hidden;
  final int eosAfter;

  ProfileInput(this.geometry, this.layers, this.hidden, this.eosAfter);

  factory ProfileInput.of(SketchModel s) =>
      ProfileInput(s.geometry, s.layers, s.hiddenLayers, s.eosAfter);
}

/// True when profile geometry [g] participates in profiles: drawn on a live,
/// visible layer, not construction/centerline format (Inventor's rule).
bool _profileGeo(ProfileInput pi, Geo g) {
  if (g.isConstruction || g.isCenterline) return false;
  if (pi.hidden.contains(g.layer)) return false;
  final li = pi.layers.indexOf(g.layer);
  if (li >= 0 && li >= pi.eosAfter) return false; // below End of Sketch
  return true;
}

/// Sampled point chain of an entity for profile purposes: exact endpoints,
/// curved pieces finely sampled (arc/circle 96 around a full turn, splines
/// via the app's own curve sampler). Returns (points, closed).
(List<Offset>, bool) _profileChain(Geo g) {
  switch (g.type) {
    case Geo.line:
      return (
        [Offset(g.data[0], g.data[1]), Offset(g.data[2], g.data[3])],
        false
      );
    case Geo.circle:
      final pts = sampleEntity(g, arcSamples: 96);
      pts.removeLast(); // sampleEntity repeats the first point when closed
      return (pts, true);
    case Geo.arc:
      return (sampleEntity(g, arcSamples: 48), false);
    case Geo.polyline:
      final closedFlag = g.data[0] != 0;
      if (g.spline != Geo.straight) {
        // The ARC-CHAIN form, not the display curve: arcFitLoop turns points
        // that lie on true arcs into exact bulges, so the prism gets
        // near-tangent cylindrical faces instead of a fan of flat strips with
        // a crease at every one. That decimation is wrong for everything else
        // (see splineCurveFor) and right here.
        final pts = List<Offset>.of(splineArcChain(g));
        if (g.spline == Geo.ellipseTag) {
          if ((pts.first - pts.last).distance < 1e-9) pts.removeLast();
          return (pts, true);
        }
        final closed = closedFlag ||
            (pts.length > 2 && (pts.first - pts.last).distance < 1e-9);
        if (closed && (pts.first - pts.last).distance < 1e-9) {
          pts.removeLast();
        }
        return (pts, closed);
      }
      final pts = polyPoints(g);
      return (List<Offset>.of(pts), closedFlag);
    default:
      return (const [], false);
  }
}

class _HalfEdge {
  final int curve; // index into the open-curve list
  final bool fwd;
  int from = -1, to = -1;
  double angle = 0; // departure direction at [from]
  int twin = -1;
  bool used = false;
  _HalfEdge(this.curve, this.fwd);
}

/// All closed profile loops of [s]: standalone closed curves plus every
/// bounded face of the planar graph formed by endpoint-connected open
/// curves (this is what turns the four M34 rectangle lines into one loop,
/// and a rectangle with a diagonal into two triangles). Endpoints must
/// actually coincide (tolerance 1e-6 mm) — coincident-constrained sketches
/// do; crossings without a shared endpoint are NOT split (like a sketch
/// without the intersection point in Inventor). Dangling ends are pruned.
/// Drops consecutive coincident vertices of a loop (tolerance [tol] mm) and
/// any trailing vertex that coincides with the first, so the loop never
/// contains a zero-length edge. This matters because a closed
/// INTERPOLATION spline samples its last point EXACTLY on its start (a closed
/// Catmull-Rom segment ends at t=1 on p[0]) while the sampler also appends
/// p[0] — leaving a degenerate closing edge that the OCCT wire builder rejects
/// (chord < 1e-12), which is why closed fit-splines could not be extruded.
/// Cleaning the loop at the source fixes both the extrude and the on-screen
/// region/area/highlight, and is a no-op on line/arc/circle loops (their
/// vertices are already distinct). [tol] is far below sketch scale so distinct
/// geometry is never merged.
List<Offset> dedupeClosedLoop(List<Offset> p, [double tol = 1e-7]) {
  if (p.length < 2) return p;
  final out = <Offset>[];
  for (final q in p) {
    if (out.isEmpty || (out.last - q).distance > tol) out.add(q);
  }
  while (out.length > 1 && (out.first - out.last).distance <= tol) {
    out.removeLast();
  }
  return out;
}

/// Planar ARRANGEMENT of the sketch's profile curves.
///
/// Every segment is split at every crossing, dangling ends are pruned, and the
/// minimal cycles of the resulting planar graph are the selectable faces. This
/// is what lets merely CROSSING lines bound a region, the way Inventor behaves.
/// The previous loop finder only closed a loop when entities met at shared
/// ENDPOINTS, so an X of two lines — or a rectangle cut by a diagonal — yielded
/// no profile at all, and a sketch holding several areas offered nothing to
/// pick.
///
/// Disjoint closed shapes come out exactly as before (a circle inside a
/// rectangle still gives the two loops), so nesting in [regionsFrom] is
/// unchanged for them.
///
/// Public entry point: the arrangement of [s]'s closed loops. Kept on
/// [SketchModel] for the profile tests and any external caller; the M182
/// profile-input variant below is what the recompute paths use so they can run
/// the same finder over a candidate geometry list without a live sketch.
List<ProfileLoop> arrangementLoops(SketchModel s) =>
    _arrangementLoops(ProfileInput.of(s));

/// The same arrangement over a [ProfileInput] (any geometry list + the
/// sketch's layer/visibility rules), so the projection guard can count loops
/// on a CANDIDATE geometry without touching the live sketch.
List<ProfileLoop> _arrangementLoops(ProfileInput pi) {
  const tol = 1e-6;

  // ---- 1. every profile curve as straight segments -------------------------
  final segA = <Offset>[], segB = <Offset>[], segE = <int>[];
  for (var i = 0; i < pi.geometry.length; i++) {
    final g = pi.geometry[i];
    if (!_profileGeo(pi, g)) continue;
    final (pts, closed) = _profileChain(g);
    if (pts.length < 2) continue;
    for (var k = 0; k + 1 < pts.length; k++) {
      segA.add(pts[k]);
      segB.add(pts[k + 1]);
      segE.add(i);
    }
    if (closed && (pts.first - pts.last).distance > tol) {
      segA.add(pts.last);
      segB.add(pts.first);
      segE.add(i);
    }
  }
  if (segA.isEmpty) return const [];

  // ---- 2. split parameters from pairwise crossings -------------------------
  final cuts = List<List<double>>.generate(segA.length, (_) => <double>[]);
  for (var i = 0; i < segA.length; i++) {
    final a = segA[i], b = segB[i];
    final rx = b.dx - a.dx, ry = b.dy - a.dy;
    for (var j = i + 1; j < segA.length; j++) {
      final c = segA[j], d = segB[j];
      final sx = d.dx - c.dx, sy = d.dy - c.dy;
      final den = rx * sy - ry * sx;
      if (den.abs() < 1e-12) continue; // parallel — shared endpoints cover it
      final t = ((c.dx - a.dx) * sy - (c.dy - a.dy) * sx) / den;
      final u = ((c.dx - a.dx) * ry - (c.dy - a.dy) * rx) / den;
      if (t < -tol || t > 1 + tol || u < -tol || u > 1 + tol) continue;
      if (t > tol && t < 1 - tol) cuts[i].add(t);
      if (u > tol && u < 1 - tol) cuts[j].add(u);
    }
  }

  // ---- 3. node pool, snapping coincident points ---------------------------
  final nodePt = <Offset>[];
  final grid = <int, List<int>>{};
  int cell(double v) => (v / 1e-5).floor();
  int nodeOf(Offset p) {
    final cx = cell(p.dx), cy = cell(p.dy);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final n in grid[Object.hash(cx + dx, cy + dy)] ?? const <int>[]) {
          if ((nodePt[n] - p).distance <= 1e-6) return n;
        }
      }
    }
    nodePt.add(p);
    (grid[Object.hash(cx, cy)] ??= <int>[]).add(nodePt.length - 1);
    return nodePt.length - 1;
  }

  // ---- 4. undirected graph of the split segments --------------------------
  final adj = <int, Set<int>>{};
  final edgeEnt = <int, int>{};
  int key(int u, int v) => u < v ? u * 1000003 + v : v * 1000003 + u;
  for (var i = 0; i < segA.length; i++) {
    final ts = <double>[0, 1, ...cuts[i]]..sort();
    final a = segA[i], b = segB[i];
    for (var k = 0; k + 1 < ts.length; k++) {
      if (ts[k + 1] - ts[k] < tol) continue;
      Offset at(double t) =>
          Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      final u = nodeOf(at(ts[k])), v = nodeOf(at(ts[k + 1]));
      if (u == v) continue;
      (adj[u] ??= <int>{}).add(v);
      (adj[v] ??= <int>{}).add(u);
      edgeEnt[key(u, v)] = segE[i];
    }
  }

  // ---- 5. prune dangling ends: they cannot bound a face -------------------
  var pruned = true;
  while (pruned) {
    pruned = false;
    for (final n in adj.keys.toList()) {
      if ((adj[n]?.length ?? 0) >= 2) continue;
      for (final m in adj[n] ?? const <int>{}) {
        adj[m]?.remove(n);
      }
      adj.remove(n);
      pruned = true;
    }
  }
  if (adj.isEmpty) return const [];

  // ---- 6. faces = minimal cycles of the planar graph ----------------------
  double ang(int from, int to) {
    final d = nodePt[to] - nodePt[from];
    return math.atan2(d.dy, d.dx);
  }

  final around = <int, List<int>>{};
  for (final n in adj.keys) {
    around[n] = adj[n]!.toList()
      ..sort((x, y) => ang(n, x).compareTo(ang(n, y)));
  }
  // Leaving v having arrived from u, take the neighbour just BEFORE u in the
  // counter-clockwise order — the sharpest clockwise turn. That walks each
  // face with its interior on one side, so every bounded face closes as its
  // own minimal cycle and the unbounded one comes back with the opposite sign.
  int nextNode(int u, int v) {
    final l = around[v]!;
    final i = l.indexOf(u);
    return l[(i - 1 + l.length) % l.length];
  }

  final loops = <ProfileLoop>[];
  final used = <int>{};
  var nextId = 0;
  for (final u0 in adj.keys) {
    for (final v0 in adj[u0]!) {
      if (!used.add(u0 * 1000003 + v0)) continue;
      final cyc = <int>[];
      final ents = <int>{};
      var a = u0, b = v0;
      while (true) {
        cyc.add(a);
        ents.add(edgeEnt[key(a, b)] ?? -1);
        final c = nextNode(a, b);
        a = b;
        b = c;
        if (a == u0 && b == v0) break;
        used.add(a * 1000003 + b);
        if (cyc.length > 200000) return const []; // malformed — bail out
      }
      if (cyc.length < 3) continue;
      final pts = [for (final n in cyc) nodePt[n]];
      final ar = _signedArea(pts);
      // Negative area is the UNBOUNDED face of this component: not a profile.
      if (ar <= 1e-9) continue;
      loops.add(ProfileLoop(
          nextId++, pts, ar, _centroidOf(pts), ents..removeWhere((e) => e < 0)));
    }
  }
  return loops;
}

/// M220 — the sketch's TEXTS as profile loops.
///
/// A glyph contour is already a closed loop, so it does not go through the
/// planar arrangement: it needs nothing from it (there is no chaining to do
/// and no crossing to split) and it would pay dearly for it — the arrangement
/// is quadratic in the number of segments, and one line of text is a couple
/// of thousand. Text is therefore its own profile, exactly as in Inventor: it
/// does not cut regions out of the geometry it happens to sit on, and the
/// geometry does not cut regions out of it.
///
/// The layer rules are the ones every profile obeys — a text on a hidden
/// layer, or on one rolled back below the End of Sketch, is not a profile.
/// [ents] is empty on purpose: these loops belong to no entity INDEX, because
/// a text is not in `geometry` (see text_geometry.dart). Nothing reads a
/// loop's ents but the highlight, which simply lights nothing up for a text.
List<ProfileLoop> textLoops(SketchModel s, {int firstId = 0}) {
  final out = <ProfileLoop>[];
  var id = firstId;
  for (final t in s.texts) {
    final layer = textLayerOf(t);
    if (s.hiddenLayers.contains(layer)) continue;
    final li = s.layers.indexOf(layer);
    if (li >= 0 && li >= s.eosAfter) continue;
    for (final c in textContours(s, t)) {
      final pts = dedupeClosedLoop(c);
      if (pts.length < 3) continue;
      final a = _signedArea(pts);
      if (a.abs() < 1e-9) continue; // a hairline contour is not a face
      final ccw = a > 0 ? pts : pts.reversed.toList();
      out.add(
          ProfileLoop(id++, ccw, a.abs(), _centroidOf(ccw), const <int>{}));
    }
  }
  return out;
}

List<ProfileLoop> profileLoops(SketchModel s) {
  final all = Perf.span(
      'sketch.profileLoops', () => _profileLoops(ProfileInput.of(s)));
  final kept = dropDuplicateLoops(all);
  // M164 — a sketch quietly gaining a loop is how the zero-thickness ring
  // appeared (M156/M163), and it was only ever visible because EXTRUDE
  // happened to log its loops. Say it at the source, and say when a duplicate
  // was dropped. Throttled: this runs on every hit-test and paint.
  // Throttled on BOTH branches: this is a hot path (every hit-test, every
  // paint), and a persistently-dropped duplicate would otherwise log on every
  // single call. A dropped duplicate is worth hearing about sooner, not more
  // often.
  if (Log.every('loops.${s.name}', kept.length != all.length ? 500 : 5000)) {
    Log.i(
        'loops',
        '"${s.name}": ${kept.length} loop(s)'
            '${kept.length != all.length
                ? "  (${all.length - kept.length} DUPLICATE dropped)" : ""}'
            '${kept.isEmpty ? "" : "  areas=[${kept.map((l) =>
                l.area.toStringAsFixed(2)).join(", ")}]"}');
  }
  if (s.texts.isEmpty) return kept;
  // M220 — text loops carry on the same id sequence, because a duplicate id
  // would make two loops the same loop to [regionsFrom]'s nesting map.
  var next = 0;
  for (final l in kept) {
    if (l.id >= next) next = l.id + 1;
  }
  return [...kept, ...textLoops(s, firstId: next)];
}

/// How many closed loops [in] yields — the cheap shape of the profile
/// question. M182 — the projection guard uses this to refuse an update that
/// would open a loop a feature builds on: it runs the same arrangement code as
/// [profileLoops] but over an arbitrary candidate geometry list, silently.
int profileLoopCount(ProfileInput pi) => _profileLoops(pi).length;

/// M182 — the projection CLOSURE GUARD.
///
/// A projection sync re-derives `projSolid` segments from the current model.
/// If the body changed a lot (or the fold broke), a segment inside a closed
/// profile can move enough to OPEN the loop — which is how the device session
/// ended in "no closed profile in Sketch5/6" and the whole second solid died.
/// This refuses such an update for a sketch a feature builds on: when the
/// candidate list [gs] drops a closed loop that [orig] had, every segment that
/// moved is frozen in place (tagged [Geo.projBroken], keeping its old curve —
/// Inventor's "converted to fixed curves" for a reference whose parent is
/// gone) instead of being pushed. Returns the list to push (possibly frozen).
List<Geo> freezeProjectionUpdatesThatBreakLoops(List<Geo> orig, List<Geo> gs,
    List<String> layers, Set<String> hidden, int eosAfter) {
  final before =
      profileLoopCount(ProfileInput(orig, layers, hidden, eosAfter));
  if (before == 0) return gs; // nothing a feature depends on: allow
  final after = profileLoopCount(ProfileInput(gs, layers, hidden, eosAfter));
  if (after >= before) return gs; // nothing closed was lost: allow
  Log.w(
      'project',
      'projection sync would drop a closed loop a feature builds on '
          '($before -> $after) — freezing the moved segments instead of '
          'pushing broken geometry');
  for (var i = 0; i < gs.length; i++) {
    if (i < orig.length && !_projectionGeoEquals(gs[i], orig[i])) {
      gs[i] = orig[i].withProj(Geo.projBroken, -1);
    }
  }
  return gs;
}

/// Whether two entities are the same curve for the projection guard — same
/// kind, same spline style, same data. (The guard must know which segments a
/// projection sync actually moved before it freezes them.)
bool _projectionGeoEquals(Geo a, Geo b) {
  if (a.type != b.type || a.spline != b.spline) return false;
  if (a.data.length != b.data.length) return false;
  for (var i = 0; i < a.data.length; i++) {
    if ((a.data[i] - b.data[i]).abs() > 1e-9) return false;
  }
  return true;
}

/// Wall thickness, in mm, below which the gap between two loops is not a
/// feature but the same boundary counted twice. 20 um: thinner than anything
/// that can be manufactured, meshed or even seen, and forty times narrower
/// than the thinnest wall in the reported failure that must SURVIVE.
const double kMinWallThickness = 0.02;

/// M156 — removes a loop that merely REPEATS another one.
///
/// A sketch legitimately holds two coincident curves: Project Geometry brings
/// the model edge in, and the user draws over it (constrained equal and
/// concentric, so the solver keeps them on top of each other). The arrangement
/// is then perfectly right to report two loops — but the region between them
/// is a ring microns wide, and extruding it produces the zero-thickness shell
/// that showed up on the device instead of a solid cylinder.
///
/// The two do not stay bit-identical: they are tessellated separately and the
/// projection re-derives from the model on every rebuild, so the pair drifts
/// apart by a fraction of the sag of their own polygons (measured on the
/// device: areas 176.588 and 176.120 for the same Ø15 circle). Comparing for
/// equality would never catch it; comparing the ENCLOSED AREA does, because a
/// duplicate encloses the same area whatever its sampling.
///
/// Only a loop nested inside its twin is dropped, so a genuine thin ring drawn
/// as two separate circles is untouched as long as it is thicker than
/// [kDuplicateLoopArea] — and one thinner than that could not be meshed or
/// manufactured anyway.
List<ProfileLoop> dropDuplicateLoops(List<ProfileLoop> loops) {
  if (loops.length < 2) return loops;
  final drop = <int>{};
  for (final inner in loops) {
    if (drop.contains(inner.id)) continue;
    for (final outer in loops) {
      if (identical(inner, outer) || drop.contains(outer.id)) continue;
      if (inner.area >= outer.area) continue; // only ever drop the inner twin
      if (!_sameBoundary(inner, outer)) continue;
      drop.add(inner.id);
      break;
    }
  }
  if (drop.isEmpty) return loops;
  return [
    for (final l in loops)
      if (!drop.contains(l.id)) l
  ];
}

/// Whether [inner] and [outer] are the same boundary sampled twice, rather
/// than a genuine loop nested in another.
///
/// Deliberately NOT built on [_loopInside]: that votes with three sample
/// points, which is exactly the test that cannot resolve two boundaries a few
/// microns apart — a duplicate lands partly inside and partly outside its
/// twin's polygon, so the vote is a coin toss. Everything here is a measured
/// separation instead.
bool _sameBoundary(ProfileLoop inner, ProfileLoop outer) {
  // 1. Mean wall thickness: the area between the two loops, spread along the
  //    perimeter that encloses it. This is the physical quantity that decides
  //    whether the gap is a feature — it does not care about the sampling.
  final perim = _perimeterOf(inner.pts);
  if (perim <= 0) return false;
  if ((outer.area - inner.area) / perim >= kMinWallThickness) return false;
  // 2. Same place. Two equal circles side by side also enclose equal areas.
  if ((outer.centroid - inner.centroid).distance >= kMinWallThickness) {
    return false;
  }
  // 3. Same shape. Equal area and centre still admit a square and a circle;
  //    their radial extents about the shared centre do not match. This also
  //    catches a loop that coincides over most of its run and departs
  //    somewhere — the maximum has to agree, not just the average.
  final c = outer.centroid;
  final (iMin, iMax) = _radialExtent(inner.pts, c);
  final (oMin, oMax) = _radialExtent(outer.pts, c);
  return (oMin - iMin).abs() < kMinWallThickness &&
      (oMax - iMax).abs() < kMinWallThickness;
}

double _perimeterOf(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    s += (p[(i + 1) % p.length] - p[i]).distance;
  }
  return s;
}

(double, double) _radialExtent(List<Offset> p, Offset c) {
  var lo = double.infinity, hi = 0.0;
  for (final q in p) {
    final d = (q - c).distance;
    if (d < lo) lo = d;
    if (d > hi) hi = d;
  }
  return (lo, hi);
}

List<ProfileLoop> _profileLoops(ProfileInput pi) {
  // The arrangement subsumes the endpoint-chaining finder below and adds
  // crossings; the old path stays as a fallback so a bail-out can never leave
  // the sketch with no profile at all.
  final arranged = _arrangementLoops(pi);
  if (arranged.isNotEmpty) return arranged;
  const tol = 1e-6;
  final loops = <ProfileLoop>[];
  var nextId = 0;

  void addLoop(List<Offset> raw0, Set<int> ents) {
    final raw = dedupeClosedLoop(raw0);
    if (raw.length < 3) return;
    final a = _signedArea(raw);
    if (a.abs() < 1e-6) return; // degenerate sliver
    final pts = a > 0 ? raw : raw.reversed.toList();
    loops.add(ProfileLoop(
        nextId++, pts, a.abs(), _centroidOf(pts), Set<int>.of(ents)));
  }

  // 1. split entities into standalone closed loops and open chains
  final chains = <(List<Offset>, int)>[]; // (points, entity index)
  for (var i = 0; i < pi.geometry.length; i++) {
    final g = pi.geometry[i];
    if (!_profileGeo(pi, g)) continue;
    final (pts, closed) = _profileChain(g);
    if (pts.length < 2) continue;
    if (closed) {
      addLoop(pts, {i});
    } else if ((pts.first - pts.last).distance < tol && pts.length > 3) {
      // an open entity whose ends meet IS a loop already
      addLoop(pts.sublist(0, pts.length - 1), {i});
    } else {
      chains.add((pts, i));
    }
  }
  if (chains.isEmpty) return loops;

  // 2. nodes by quantised endpoints
  final nodeIx = <String, int>{};
  final nodePos = <Offset>[];
  int nodeOf(Offset p) {
    final k = '${(p.dx / tol).round()}_${(p.dy / tol).round()}';
    return nodeIx.putIfAbsent(k, () {
      nodePos.add(p);
      return nodePos.length - 1;
    });
  }

  // 3. two half-edges per chain
  final hes = <_HalfEdge>[];
  for (var c = 0; c < chains.length; c++) {
    final pts = chains[c].$1;
    final f = _HalfEdge(c, true)
      ..from = nodeOf(pts.first)
      ..to = nodeOf(pts.last)
      ..angle = math.atan2(pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);
    final r = _HalfEdge(c, false)
      ..from = f.to
      ..to = f.from
      ..angle = math.atan2(pts[pts.length - 2].dy - pts.last.dy,
          pts[pts.length - 2].dx - pts.last.dx);
    f.twin = hes.length + 1;
    r.twin = hes.length;
    hes.add(f);
    hes.add(r);
  }

  // 4. prune dangling chains (degree-1 nodes) so spurs never poison a face
  final degree = List<int>.filled(nodePos.length, 0);
  final alive = List<bool>.filled(chains.length, true);
  for (var c = 0; c < chains.length; c++) {
    degree[hes[2 * c].from]++;
    degree[hes[2 * c].to]++;
  }
  var pruned = true;
  while (pruned) {
    pruned = false;
    for (var c = 0; c < chains.length; c++) {
      if (!alive[c]) continue;
      final a = hes[2 * c].from, b = hes[2 * c].to;
      if (degree[a] == 1 || degree[b] == 1) {
        alive[c] = false;
        degree[a]--;
        degree[b]--;
        pruned = true;
      }
    }
  }

  // 5. outgoing half-edges per node, sorted counter-clockwise by angle
  final out = List<List<int>>.generate(nodePos.length, (_) => []);
  for (var h = 0; h < hes.length; h++) {
    if (!alive[hes[h].curve]) continue;
    out[hes[h].from].add(h);
  }
  for (final l in out) {
    l.sort((a, b) => hes[a].angle.compareTo(hes[b].angle));
  }

  // 6. face tracing: arriving at a node, continue with the next half-edge
  // CLOCKWISE from the arrival's twin — interiors end up on the left, so
  // bounded faces come out counter-clockwise (positive area) and the one
  // unbounded face clockwise (filtered by the area sign in addLoop).
  for (var start = 0; start < hes.length; start++) {
    if (hes[start].used || !alive[hes[start].curve]) continue;
    final cycle = <int>[];
    var h = start;
    var guard = 0;
    while (guard++ <= hes.length) {
      hes[h].used = true;
      cycle.add(h);
      final n = hes[h].to;
      final list = out[n];
      final i = list.indexOf(hes[h].twin);
      if (i < 0 || list.isEmpty) {
        cycle.clear();
        break;
      }
      h = list[(i - 1 + list.length) % list.length];
      if (h == start) break;
      if (hes[h].used) {
        cycle.clear();
        break;
      }
    }
    if (cycle.isEmpty || guard > hes.length) continue;
    // stitch the polygon from the traversed chains
    final poly = <Offset>[];
    final ents = <int>{};
    for (final hi in cycle) {
      final he = hes[hi];
      final src = chains[he.curve].$1;
      final pts = he.fwd ? src : src.reversed.toList();
      ents.add(chains[he.curve].$2);
      for (var k = poly.isEmpty ? 0 : 1; k < pts.length; k++) {
        poly.add(pts[k]);
      }
    }
    if (poly.length > 1 && (poly.first - poly.last).distance < tol) {
      poly.removeLast();
    }
    // only keep counter-clockwise faces — the clockwise trace is the
    // unbounded outside
    if (_signedArea(poly) > 1e-6) addLoop(poly, ents);
  }
  return loops;
}

/// A point strictly inside [l] (works for concave loops too): the centroid
/// when it is inside, otherwise the midpoint of the fattest interior span.
Offset interiorPointOf(ProfileLoop l) {
  if (pointInPolygon(l.centroid, l.pts)) return l.centroid;
  for (var i = 0; i < l.pts.length; i++) {
    final a = l.pts[i], b = l.pts[(i + 1) % l.pts.length];
    final mid = (a + b) / 2;
    final d = b - a;
    final nrm = Offset(-d.dy, d.dx) / (d.distance + 1e-12);
    for (final eps in [0.01, 0.1, 1.0]) {
      final p = mid + nrm * eps;
      if (pointInPolygon(p, l.pts)) return p;
    }
  }
  return l.centroid;
}

/// A point inside the region's MATERIAL — inside its outer loop and outside
/// every hole. This is what IDENTIFIES a selected region (M221).
///
/// [interiorPointOf] answers for one loop and knows nothing of the holes cut
/// out of it. For a ring — a circle, or a rectangle, with a concentric loop
/// inside it — its answer is the centre, which is exactly the spot the HOLE
/// occupies and exactly the spot the disc in that hole reports as its own.
/// The ring and the disc then carry the SAME anchor, and nothing downstream
/// can tell them apart: picking the disc reads as re-picking the ring (so the
/// second one can never be added), the highlight paints the wrong one, and
/// [resolveProfiles] matches whichever of the two it happens to meet first.
/// That is the reported "I cant select the inner circle to also extrude".
Offset regionAnchor(ProfileRegion r) {
  final c = interiorPointOf(r.outer);
  if (!r.holes.any((h) => pointInPolygon(c, h.pts))) return c;
  // The centre is in a hole. Cut the region with horizontal lines, take the
  // middle of each piece of material on them, and keep the one that sits
  // FARTHEST from every boundary.
  //
  // Not the widest piece, which is the obvious rule and is wrong: a row that
  // runs TANGENT to a hole crosses it zero times, so the hole does not split
  // that row at all and the span looks like the whole chord — while its
  // midpoint sits exactly on the hole's extreme vertex. That is how the first
  // version of this put a ring's anchor precisely on the boundary of its own
  // hole (a Ø30 ring around a Ø10 hole answered `(0, 5)`), and a point on a
  // boundary is the one point whose inside/outside answer the next
  // tessellation may well reverse. Clearance says what the anchor is FOR.
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in r.outer.pts) {
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  if (!(maxY > minY)) return c;
  final loops = [r.outer, ...r.holes];
  Offset? best;
  var bestClear = -1.0; // squared
  const rows = 9;
  for (var k = 1; k < rows; k++) {
    final y = minY + (maxY - minY) * k / rows;
    final xs = <double>[];
    for (final loop in loops) {
      final pts = loop.pts;
      for (var i = 0; i < pts.length; i++) {
        final a = pts[i], b = pts[(i + 1) % pts.length];
        if ((a.dy > y) == (b.dy > y)) continue;
        xs.add(a.dx + (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i++) {
      final mid = Offset((xs[i] + xs[i + 1]) / 2, y);
      if (!pointInPolygon(mid, r.outer.pts)) continue;
      if (r.holes.any((h) => pointInPolygon(mid, h.pts))) continue;
      var clear = double.infinity;
      for (final loop in loops) {
        final d = _distSqToLoop(mid, loop.pts);
        if (d < clear) clear = d;
      }
      if (clear > bestClear) {
        bestClear = clear;
        best = mid;
      }
    }
  }
  return best ?? c;
}

/// Squared distance from [p] to the closed polyline [pts] (its EDGES, not its
/// vertices — a coarse polygon has long ones).
double _distSqToLoop(Offset p, List<Offset> pts) {
  var best = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final v = b - a, w = p - a;
    final len2 = v.dx * v.dx + v.dy * v.dy;
    var t = len2 <= 0 ? 0.0 : (w.dx * v.dx + w.dy * v.dy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final d = w - v * t;
    final d2 = d.dx * d.dx + d.dy * d.dy;
    if (d2 < best) best = d2;
  }
  return best;
}

/// The region a stored selection points at, or null if there are none.
///
/// Nearest anchor — but a region whose AREA still matches the selection beats
/// a nearer one that does not. A document written before M221 stored the outer
/// LOOP's interior point, so a ring's anchor sits in the middle of its own
/// hole: the disc living there is zero away from it and would otherwise steal
/// the selection the first time the part is rebuilt. [resolveProfiles] writes
/// the new anchor back, so each document migrates on its next rebuild and the
/// area only has to carry it across that one hop.
ProfileRegion? regionForSel(List<ProfileRegion> regions, ProfileSel sel) {
  final anchor = Offset(sel.ax, sel.ay);
  ProfileRegion? best;
  var bestFar = 2, bestD = double.infinity;
  for (final r in regions) {
    final rel = sel.area.abs() < 1e-12
        ? 1.0
        : (r.outer.area - sel.area).abs() / sel.area.abs();
    final far = rel <= 0.05 ? 0 : 1;
    final d = (regionAnchor(r) - anchor).distance;
    if (far < bestFar || (far == bestFar && d < bestD)) {
      bestFar = far;
      bestD = d;
      best = r;
    }
  }
  return best;
}

bool _loopInside(ProfileLoop inner, ProfileLoop outer) {
  if (inner.area >= outer.area) return false;
  var votes = 0;
  final samples = [
    interiorPointOf(inner),
    inner.pts.first,
    inner.pts[inner.pts.length ~/ 2],
  ];
  for (final p in samples) {
    if (pointInPolygon(p, outer.pts)) votes++;
  }
  return votes >= 2;
}

/// Top-level pickable regions: each is an outer loop plus its DIRECT child
/// loops as holes. A loop that is nested inside another is that loop's HOLE
/// and is NOT returned as its own region — so a rectangle-with-a-circle is a
/// SINGLE region (the circle is its hole), which auto-selects and extrudes
/// with the hole cut, exactly like Inventor. (Odd nesting depth = solid,
/// even = hole: a shape inside a hole becomes its own region again.)
List<ProfileRegion> regionsFrom(List<ProfileLoop> loops) {
  final parent = <int, int>{}; // loop id -> immediate parent loop id
  final depth = <int, int>{}; // nesting depth (0 = top level)
  for (final l in loops) {
    ProfileLoop? best;
    for (final o in loops) {
      if (o.id == l.id || !_loopInside(l, o)) continue;
      if (best == null || o.area < best.area) best = o;
    }
    if (best != null) parent[l.id] = best.id;
  }
  int depthOf(int id) {
    final cached = depth[id];
    if (cached != null) return cached;
    final p = parent[id];
    final dpt = p == null ? 0 : depthOf(p) + 1;
    depth[id] = dpt;
    return dpt;
  }

  // EVERY loop is a selectable face, with its immediate children as holes.
  // A circle inside a rectangle therefore offers both the ring AND the disc,
  // which is what Inventor does — previously odd-depth loops were treated as
  // holes only and could never be picked. depthOf still runs: it is what makes
  // a loop's own children (and not its grandchildren) its holes.
  depthOf(loops.isEmpty ? 0 : loops.first.id);
  return [
    for (final l in loops)
      ProfileRegion(l, [
        for (final c in loops)
          if (parent[c.id] == l.id) c
      ]),
  ];
}

/// The region under a tap at sketch point [p], Inventor-style: the smallest
/// region whose FILLED material (outer loop minus its holes) contains the
/// point. Tapping inside a hole selects no region there (unless a nested
/// island fills it).
ProfileRegion? regionAt(List<ProfileRegion> regions, Offset p) {
  ProfileRegion? best;
  for (final r in regions) {
    if (!pointInPolygon(p, r.outer.pts)) continue;
    // inside the outer, but a hole cuts this spot out -> not this region
    if (r.holes.any((h) => pointInPolygon(p, h.pts))) continue;
    if (best == null || r.outer.area < best.outer.area) best = r;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Extrude feature
// ---------------------------------------------------------------------------
enum ExtrudeDirection { defaultDir, flipped, symmetric, asymmetric }

String extrudeDirName(ExtrudeDirection d) => switch (d) {
      ExtrudeDirection.defaultDir => 'default',
      ExtrudeDirection.flipped => 'flipped',
      ExtrudeDirection.symmetric => 'symmetric',
      ExtrudeDirection.asymmetric => 'asymmetric',
    };

ExtrudeDirection extrudeDirFrom(String s) => switch (s) {
      'flipped' => ExtrudeDirection.flipped,
      'symmetric' => ExtrudeDirection.symmetric,
      'asymmetric' => ExtrudeDirection.asymmetric,
      _ => ExtrudeDirection.defaultDir,
    };

/// Inventor's distance semantics as (total height, start offset along the
/// plane normal): default grows +normal from the plane; flipped grows
/// -normal; symmetric splits Distance A half/half; asymmetric goes A up
/// and B down. The shim always extrudes +Z, the offset rides in the
/// placement transform — no mirroring, valid solids, correct normals.
(double, double) extrudeSpan(ExtrudeDirection d, double a, double b) =>
    switch (d) {
      ExtrudeDirection.defaultDir => (a, 0.0),
      ExtrudeDirection.flipped => (a, -a),
      ExtrudeDirection.symmetric => (a, -a / 2),
      ExtrudeDirection.asymmetric => (a + b, -b),
    };

/// A picked profile, stored re-attachably: the outer loop's interior anchor
/// point and area at pick time. On recompute the nearest current region is
/// re-matched (and the anchor updated); a lost profile marks the feature
/// with an honest error instead of guessing.
class ProfileSel {
  double ax, ay, area;
  ProfileSel(this.ax, this.ay, this.area);
  Map<String, dynamic> toJson() => {'x': ax, 'y': ay, 'a': area};
  static ProfileSel fromJson(Map<String, dynamic> j) => ProfileSel(
      (j['x'] as num).toDouble(),
      (j['y'] as num).toDouble(),
      (j['a'] as num).toDouble());
}

// ---------------------------------------------------------------------------
// M131 — feature polymorphism
// ---------------------------------------------------------------------------

/// Inventor's termination options, shared by Extrude and Revolve.
///
/// [distance] is the typed value (Angle A for a revolve). The other three
/// resolve against the MODEL at recompute time, which is why they carry no
/// number of their own:
///   [toNext]     — stop on the next face met in the extrude direction. Not
///                  offered for a base feature: with nothing built yet there
///                  is no next face, exactly as Inventor greys it out.
///   [toFace]     — stop on a picked face (see [FaceSel]).
///   [throughAll] — pass through the entire body.
enum FeatureExtent { distance, toNext, toFace, throughAll }

String featureExtentName(FeatureExtent e) => switch (e) {
      FeatureExtent.toNext => 'toNext',
      FeatureExtent.toFace => 'toFace',
      FeatureExtent.throughAll => 'throughAll',
      FeatureExtent.distance => 'distance',
    };

FeatureExtent featureExtentFrom(String? s) => switch (s) {
      'toNext' => FeatureExtent.toNext,
      'toFace' => FeatureExtent.toFace,
      'throughAll' => FeatureExtent.throughAll,
      _ => FeatureExtent.distance,
    };

/// A picked TERMINATION face, stored re-attachably as a point on the face plus
/// its outward normal — the same "remember the geometry, re-find the index"
/// contract as [ProfileSel] and [EdgeSel], because OCCT face indices are not
/// stable across a rebuild either.
class FaceSel {
  double px, py, pz, nx, ny, nz;
  FaceSel(this.px, this.py, this.pz, this.nx, this.ny, this.nz);
  Map<String, dynamic> toJson() =>
      {'p': [px, py, pz], 'n': [nx, ny, nz]};
  static FaceSel? fromJson(Map<String, dynamic> j) {
    final p = (j['p'] as List?)?.cast<num>(), n = (j['n'] as List?)?.cast<num>();
    if (p == null || n == null || p.length != 3 || n.length != 3) return null;
    return FaceSel(p[0].toDouble(), p[1].toDouble(), p[2].toDouble(),
        n[0].toDouble(), n[1].toDouble(), n[2].toDouble());
  }
}

/// A picked EDGE, stored the way a fillet has to store it: by geometry, never
/// by index.
///
/// OCCT renumbers every edge on every rebuild, so persisting "edge 7" would
/// move the fillet to a different edge the moment anything upstream changes —
/// the classic topological-naming failure. What does survive a rebuild is
/// where the edge IS: its arc-length midpoint, its length, its curve type and
/// radius. [bestMatch] re-finds the index from those.
///
/// This mirrors [ProfileSel] exactly, which already solves the same problem
/// for profiles (interior anchor + area, re-matched to the nearest region).
class EdgeSel {
  double mx, my, mz; // arc-length midpoint at pick time, WORLD coords
  double length;
  int kind; // 1 line, 2 circle, 3 ellipse, 4 other
  double radius;

  EdgeSel(this.mx, this.my, this.mz, this.length, this.kind, this.radius);

  Map<String, dynamic> toJson() =>
      {'m': [mx, my, mz], 'l': length, 'k': kind, 'r': radius};

  static EdgeSel? fromJson(Map<String, dynamic> j) {
    final m = (j['m'] as List?)?.cast<num>();
    if (m == null || m.length != 3) return null;
    return EdgeSel(
        m[0].toDouble(),
        m[1].toDouble(),
        m[2].toDouble(),
        (j['l'] as num?)?.toDouble() ?? 0,
        (j['k'] as num?)?.toInt() ?? 0,
        (j['r'] as num?)?.toDouble() ?? 0);
  }

  /// Distance between this fingerprint and a live edge. Lower is better;
  /// [double.infinity] means "cannot be this edge".
  ///
  /// Position dominates, because that is what the user actually pointed at.
  /// Length is a weak tiebreaker only — a fillet legitimately changes the
  /// length of its own neighbours, so a hard length match would lose the edge
  /// on exactly the edits where keeping it matters most. A TYPE change is
  /// disqualifying: a line that became an arc is not the same edge any more.
  double score(OcctEdgeInfo e, {double ox = 0, double oy = 0, double oz = 0}) {
    if (!e.filletable) return double.infinity;
    if (kind != 0 && e.kind != 0 && kind != e.kind) return double.infinity;
    final dx = e.mx - mx - ox, dy = e.my - my - oy, dz = e.mz - mz - oz;
    final d = math.sqrt(dx * dx + dy * dy + dz * dz);
    var s = d;
    // M152 — RADIUS. It was stored from the beginning and never read, which
    // is how a chamfer picked on the inner rim of a boss came back after
    // recompute sitting on the outer rim of the cylinder underneath it. Two
    // concentric circles have midpoints only (R - r) apart, so position alone
    // cannot tell them apart. Radius is the one thing that separates them.
    //
    // Not disqualifying: a chamfer on a neighbouring edge legitimately shrinks
    // the circle it belongs to, and a hard match would lose the edge on
    // exactly the edits where keeping it matters most.
    final curved = radius > 1e-9 && e.radius > 1e-9;
    if (curved) s += 1.5 * (e.radius - radius).abs();
    // M183 — SIZE vs EXTENT, charged once each.
    //
    // Length used to be a flat 0.05 nudge, so a 29 % length change cost a
    // quarter of the tolerance and a fillet stored against a 17.96 mm edge
    // re-matched onto a 12.80 mm one — same radius, same midpoint — and the
    // body silently changed shape.
    //
    // Raising the weight alone would be wrong, because on a circle radius and
    // circumference are the SAME fact and charging both bills a shrinking rim
    // twice, at 2*pi amplification. What length adds over radius on a curved
    // edge is how much of the circle this edge actually spans: same radius,
    // two thirds the length, means an arc where a full turn used to be, which
    // is a different edge however well the midpoint agrees. So compare the
    // swept angle, converted back to millimetres so it is commensurate with
    // everything else. On a line there is no radius and length IS the size.
    final dLen = curved
        ? ((e.length / e.radius) - (length / radius)).abs() * radius
        : (e.length - length).abs();
    s += 0.5 * dLen;
    return s;
  }

  /// The live edge this selection now refers to, or null when it is gone.
  /// [tol] is in model units and scales with the edge: a 200 mm edge may
  /// legitimately shift further than a 2 mm one.
  /// How far this selection is allowed to have moved. Scales with the edge's
  /// own SIZE, and for a circle that is its radius, not its circumference.
  double get tol {
    final scale = (kind == 2 || kind == 3) && radius > 0 ? radius : length.abs();
    return 0.25 * (scale + 1.0);
  }

  OcctEdgeInfo? bestMatch(List<OcctEdgeInfo> edges,
      {double ox = 0, double oy = 0, double oz = 0}) {
    OcctEdgeInfo? best;
    var bestScore = double.infinity;
    var runnerUp = double.infinity;
    for (final e in edges) {
      final s = score(e, ox: ox, oy: oy, oz: oz);
      if (s < bestScore) {
        runnerUp = bestScore;
        bestScore = s;
        best = e;
      } else if (s < runnerUp) {
        runnerUp = s;
      }
    }
    if (best == null) return null;
    // M152 — the tolerance scales with the edge's SIZE, and for a circle that
    // is its radius, not its circumference. A 30 mm boss rim is 188 mm long,
    // which used to buy it a 47 mm search radius — wide enough to swallow
    // most of the part. Radius gives ~8 mm, which is what "this edge may have
    // shifted a little" actually means.
    final tol = this.tol;
    if (bestScore > tol) return null;
    // M158 — AMBIGUITY. Two candidates whose scores sit within one tolerance
    // of each other are a coin toss, and the coin decides which edge a chamfer
    // lands on: this is how one picked on the inner rim of a boss came back on
    // the outer rim of the cylinder underneath. Report the selection LOST
    // instead of guessing. Losing a chamfer is recoverable and obvious;
    // silently moving one is neither — the author of M152 said exactly that
    // and then let the guess stand.
    //
    // Weighting radius more heavily cannot substitute for this. It changes
    // WHICH candidate wins, never whether the winner was meaningfully better
    // than the next one, and it is the second question that decides whether
    // the answer can be trusted.
    if (!runnerUp.isInfinite && runnerUp - bestScore < tol) return null;
    return best;
  }

  /// Re-anchor onto the edge we just matched, so the fingerprint tracks the
  /// model instead of drifting further from it with every rebuild.
  void reanchor(OcctEdgeInfo e) {
    mx = e.mx;
    my = e.my;
    mz = e.mz;
    length = e.length;
    kind = e.kind;
    radius = e.radius;
  }
}

/// A picked SKETCH CURVE — a sweep path, or a loft rail.
///
/// Stored by geometry for the same reason [EdgeSel] is: a sketch index moves
/// the instant anything is added to or deleted from the sketch, so persisting
/// "curve 4" quietly re-points the sweep at a different line. The endpoints
/// and length are what survive an edit.
class CurveSel {
  String sketchName;
  int geoIndex; // a HINT, re-validated against the fingerprint below
  double x0, y0, x1, y1; // endpoints in sketch coordinates
  double length;

  CurveSel(this.sketchName, this.geoIndex, this.x0, this.y0, this.x1, this.y1,
      this.length);

  Map<String, dynamic> toJson() => {
        'sketch': sketchName,
        'geo': geoIndex,
        'p': [x0, y0, x1, y1],
        'l': length,
      };

  static CurveSel? fromJson(Map<String, dynamic> j) {
    final p = (j['p'] as List?)?.cast<num>();
    if (p == null || p.length != 4) return null;
    return CurveSel(
        j['sketch'] as String? ?? '',
        (j['geo'] as num?)?.toInt() ?? -1,
        p[0].toDouble(),
        p[1].toDouble(),
        p[2].toDouble(),
        p[3].toDouble(),
        (j['l'] as num?)?.toDouble() ?? 0);
  }

  /// How far [pts] is from this fingerprint; infinite when it cannot be it.
  /// Endpoint-based and direction-agnostic, since a curve redrawn the other
  /// way round is still the same path.
  double score(List<Offset> pts) {
    if (pts.length < 2) return double.infinity;
    final a = pts.first, b = pts.last;
    final fwd = (a - Offset(x0, y0)).distance + (b - Offset(x1, y1)).distance;
    final rev = (a - Offset(x1, y1)).distance + (b - Offset(x0, y0)).distance;
    return fwd < rev ? fwd : rev;
  }
}

/// Everything the timeline, the browser, the End-of-Part marker and the
/// boolean fold need from a feature, whatever kind it is.
///
/// Before M131 the feature list was `List<ExtrudeFeature>` and every one of
/// those subsystems reached straight into extrude-specific fields. Revolve,
/// Fillet and Chamfer could not exist until this base did.
abstract class PartFeature {
  PartFeature({
    required this.name,
    required this.bodyName,
    this.visible = true,
    this.output = 'join',
  });

  String name; // Extrusion1, Revolution1, Fillet1, ...
  String bodyName; // Solid1, ...
  bool visible;

  /// Inventor's Output boolean: 'join' | 'cut' | 'intersect' | 'new'.
  /// Body-modifying features (fillet, chamfer) ignore it — see [modifiesBody].
  String output;

  /// M91 — position on the browser timeline, shared with [ChildSketch.seq].
  int seq = 0;

  // ---- runtime, never serialised ----
  KernelSolid? solid;

  /// M213 — the surfaces THIS feature contributed to its body, captured by
  /// the fold at the one moment they exist on their own: after the feature
  /// built and before the boolean folds it away. What makes "click a face,
  /// select the feature that made it" possible at all — see [attributeFaces].
  List<FaceSurface> ownSurfaces = const [];
  String? computeError;
  bool consumedByJoin = false;
  bool rolledBack = false;

  /// Input signature [solid] was last built from; null = must rebuild.
  String? builtSig;

  /// Discriminator written to JSON and used by the browser for icons.
  String get kind;

  /// Human label for a new feature of this kind ("Extrusion", "Fillet", ...).
  String get typeLabel;

  /// The sketch this feature consumes, or '' when it does not consume one.
  String get sketchName => '';

  /// EVERY sketch this feature depends on.
  ///
  /// Extrude and revolve have one; a sweep also depends on the sketch its PATH
  /// lives in, and a loft on one per section. The rebuild signature hashes all
  /// of them — hashing only [sketchName] meant editing a loft's second section
  /// or a sweep's path left the cached solid in place and nothing moved.
  List<String> get sketchNames =>
      sketchName.isEmpty ? const [] : [sketchName];

  /// M227 — OTHER bodies this feature reads, by name.
  ///
  /// Empty for everything that only ever touches its own chain, which is
  /// everything except Combine. The fold mixes these bodies' rebuild keys into
  /// this feature's own, because a feature that consumes another body has to
  /// rebuild when THAT body changes — and nothing else in the key can see it.
  List<String> get inputBodies => const [];

  /// True for features built FROM a sketch (extrude, revolve). False for
  /// features that MODIFY an existing body (fillet, chamfer) — those need an
  /// upstream solid as input and fail honestly without one, whereas a
  /// sketch-based feature can be a base feature.
  bool get modifiesBody => false;

  /// This feature's own contribution to the rebuild key. The upstream chain
  /// hash is prepended by [recomputeAllFeatures], so subclasses only describe
  /// THEMSELVES — anything reachable upstream is already covered.
  String ownSig();

  Map<String, dynamic> toJson();

  /// Common fields every subclass writes. Subclasses spread this and add
  /// their own, so a new field is never forgotten in one of four places.
  Map<String, dynamic> baseJson() => {
        'kind': kind,
        'name': name,
        'seq': seq,
        'body': bodyName,
        'visible': visible,
        'output': output,
      };

  void readBaseJson(Map<String, dynamic> j) {
    seq = (j['seq'] as num?)?.toInt() ?? 0;
  }

  void disposeSolid() {
    solid?.dispose();
    solid = null;
    builtSig = null;
    // The surfaces described the solid that just went away. Keeping them
    // would let a feature that failed to rebuild go on claiming faces of the
    // body it is no longer part of.
    ownSurfaces = const [];
  }

  /// Dispatching loader. An unknown 'kind' returns null and the caller drops
  /// the entry rather than inventing a feature — a file from a newer build
  /// should lose a feature loudly, not silently become a different part.
  static PartFeature? fromJson(Map<String, dynamic> j) {
    switch (j['kind'] as String? ?? 'extrude') {
      case 'extrude':
        return ExtrudeFeature.fromJson(j);
      case 'revolve':
        return RevolveFeature.fromJson(j);
      case 'fillet':
        return FilletFeature.fromJson(j);
      case 'chamfer':
        return ChamferFeature.fromJson(j);
      case 'deleteface':
        return DeleteFaceFeature.fromJson(j);
      case 'direct':
        return DirectEditFeature.fromJson(j);
      case 'sweep':
        return SweepFeature.fromJson(j);
      case 'loft':
        return LoftFeature.fromJson(j);
      case 'coil':
        return CoilFeature.fromJson(j);
      case 'pattern':
        return PatternFeature.fromJson(j);
      case 'hole':
        return HoleFeature.fromJson(j);
      case 'combine':
        return CombineFeature.fromJson(j);
      case 'split':
        return SplitFeature.fromJson(j);
      default:
        return null;
    }
  }
}

/// M225 — where one hole goes: a point in the SKETCH's own (u,v).
///
/// Stored as coordinates and re-matched to a sketch point on every rebuild,
/// exactly as [ProfileSel] is re-matched to a region: an index into the
/// sketch's entity list moves the moment anything is inserted, and a hole that
/// silently walks to another point is worse than one that fails.
class HolePlace {
  double x, y;
  HolePlace(this.x, this.y);
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  static HolePlace fromJson(Map<String, dynamic> j) => HolePlace(
      (j['x'] as num?)?.toDouble() ?? 0, (j['y'] as num?)?.toDouble() ?? 0);
}

/// M228 — Inventor's **Modify > Split**, in the half this architecture can
/// carry honestly: **Trim Solid**.
///
/// Inventor's Split does three things: split a FACE with a curve, split a body
/// into TWO bodies, and trim a body away on one side of a plane. The middle
/// one is not a footnote to the other two — a feature that produces a SECOND
/// body has no place in the fold, which maps one feature to one solid and
/// folds it into one chain. Building it would mean teaching the timeline that
/// a feature can spawn a body, and that is its own milestone.
///
/// So this is the trim: everything on one side of [frame] goes away. [flip]
/// chooses the side, because which half you meant is not derivable from a
/// plane — a plane has two sides and no opinion.
class SplitFeature extends PartFeature {
  /// The cutting plane, stored OUTRIGHT rather than as a key. A work plane can
  /// move and an origin key cannot say "the face I picked"; a sketch on a face
  /// stores its frame for exactly this reason (M58).
  PlaneFrame frame;

  /// What the plane was called when it was picked — for the browser sentence.
  String label;

  /// Keep the material on the +normal side instead of the -normal side.
  bool flip;

  SplitFeature({
    required super.name,
    required super.bodyName,
    required this.frame,
    this.label = 'Plane',
    this.flip = false,
    super.visible,
  }) : super(output: 'cut');

  @override
  String get kind => 'split';
  @override
  String get typeLabel => 'Split';

  @override
  bool get modifiesBody => true;

  @override
  String ownSig() {
    final o = frame.origin, n = frame.n;
    return 'sp|${o.x},${o.y},${o.z}|${n.x},${n.y},${n.z}|$flip';
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'frame': frame.frameJson(),
        'label': label,
        'flip': flip,
      };

  static SplitFeature fromJson(Map<String, dynamic> j) {
    final fr = PlaneFrame.fromFrameJson(j['frame'] as List?);
    final f = SplitFeature(
      name: j['name'] as String? ?? 'Split',
      bodyName: j['body'] as String? ?? 'Solid1',
      // A split with no plane cannot be rebuilt, and says so at recompute
      // rather than being dropped on load: losing a feature silently is how a
      // part comes back different (M111's rule for imports, same reasoning).
      frame: fr ?? planeFrame('xy'),
      label: j['label'] as String? ?? 'Plane',
      flip: j['flip'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

/// M227 — Inventor's **Modify > Combine**: a boolean between solid BODIES.
///
/// The one Inventor operation that works on bodies rather than on profiles or
/// edges. Extrude has carried Join/Cut/Intersect since M62, but only against
/// the body its own profile builds into — there was no way to say "take this
/// body away from that one" once both existed.
///
/// The base is [bodyName], as for every other feature; [tools] are the bodies
/// consumed. They are named rather than indexed for the same reason a profile
/// is anchored rather than indexed: a body list re-orders the moment one is
/// deleted.
class CombineFeature extends PartFeature {
  final List<String> tools;

  /// 'join' | 'cut' | 'intersect' — Inventor's three, and the same words the
  /// extrude Output uses, so [combineSolids] serves both.
  String op;

  /// Inventor's "Keep Toolbody": the tool survives as its own body instead of
  /// being folded away.
  bool keepTool;

  CombineFeature({
    required super.name,
    required super.bodyName,
    required this.tools,
    this.op = 'cut',
    this.keepTool = false,
    super.visible,
  }) : super(output: 'cut');

  @override
  String get kind => 'combine';
  @override
  String get typeLabel => 'Combine';

  /// It consumes the body that reaches it and hands on the result.
  @override
  bool get modifiesBody => true;

  @override
  List<String> get inputBodies => tools;

  @override
  String ownSig() => 'cb|$op|$keepTool|${tools.join(",")}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'tools': tools,
        'op': op,
        'keepTool': keepTool,
      };

  static CombineFeature fromJson(Map<String, dynamic> j) {
    final f = CombineFeature(
      name: j['name'] as String? ?? 'Combine',
      bodyName: j['body'] as String? ?? 'Solid1',
      tools: [
        for (final t in (j['tools'] as List? ?? const [])) t.toString()
      ],
      op: j['op'] as String? ?? 'cut',
      keepTool: j['keepTool'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

/// M226 — Inventor's four hole shapes.
///
/// [spotface] is geometrically a [counterbore] and is kept apart anyway,
/// because it is a different INTENT and the browser should say which one was
/// asked for: a counterbore sinks a head, a spotface just flattens a boss so a
/// washer sits square. Inventor draws them the same way and dimensions them
/// differently, and quietly relabelling one as the other is the kind of small
/// lie that survives into a drawing.
enum HoleType { simple, counterbore, spotface, countersink }

String holeTypeLabel(HoleType t) => switch (t) {
      HoleType.simple => 'Simple',
      HoleType.counterbore => 'Counterbore',
      HoleType.spotface => 'Spotface',
      HoleType.countersink => 'Countersink',
    };

String holeTypeName(HoleType t) => t.name;

/// Short label for the panel's four-way switch. Not the first N characters of
/// [holeTypeLabel]: Counterbore and Countersink share their first six, and two
/// buttons reading the same word is not a choice.
String holeTypeShort(HoleType t) => switch (t) {
      HoleType.simple => 'Simple',
      HoleType.counterbore => "C'bore",
      HoleType.spotface => 'Spot',
      HoleType.countersink => "C'sink",
    };

HoleType holeTypeFrom(String? s) => switch (s) {
      'counterbore' => HoleType.counterbore,
      'spotface' => HoleType.spotface,
      'countersink' => HoleType.countersink,
      _ => HoleType.simple,
    };

/// Inventor's **Modify > Hole**, first cut: simple drilled holes on sketch
/// points.
///
/// It is a BODY-MODIFYING feature and not an extrusion with `output: 'cut'`,
/// even though a cut extrusion is how it reaches the kernel. Inventor treats a
/// hole as its own feature for good reasons this app shares: it can never be a
/// base feature (there must be material to drill), its browser row and its
/// edit dialog are about a hole rather than about a profile, and the profile
/// it cuts with is DERIVED from a diameter rather than drawn — nothing in the
/// sketch has to be a circle, and a user who moves a point moves the hole.
///
/// What this first cut deliberately does NOT do, rather than half-doing it:
/// counterbore, countersink and spotface (each is a stepped or conical profile
/// and a second set of numbers), tapped and clearance holes (a thread table),
/// the drill-point angle at the bottom (a cone, so a revolve rather than an
/// extrusion), and the linear/concentric placements (this one places on sketch
/// POINTS, which is Inventor's "From Sketch"). Every one of them is a real
/// feature, not a footnote.
class HoleFeature extends PartFeature {
  @override
  final String sketchName;
  final List<HolePlace> places;
  double dia, depth;
  String exprDia, exprDepth;

  /// M226 — the shape at the mouth of the hole.
  HoleType type;

  /// Counterbore / spotface: the wider, flat-bottomed pocket at the top.
  double cbDia, cbDepth;
  String exprCbDia, exprCbDepth;

  /// Countersink: the cone at the top. [csAngle] is Inventor's INCLUDED angle
  /// (90 deg by default, which is what a 90 deg countersunk screw needs).
  double csDia, csAngle;
  String exprCsDia, exprCsAngle;

  /// Only [FeatureExtent.distance] and [FeatureExtent.throughAll] are honoured;
  /// To Next / To Face need a face reference the panel does not offer yet and
  /// are refused rather than silently treated as a distance.
  FeatureExtent extent;

  /// Drill along +n instead of the default -n. The default is "into the
  /// material": a sketch's normal faces the viewer, so a hole goes away from
  /// it.
  bool flip;

  HoleFeature({
    required super.name,
    required super.bodyName,
    required this.sketchName,
    required this.places,
    this.dia = 6,
    this.depth = 10,
    this.exprDia = '6 mm',
    this.exprDepth = '10 mm',
    this.extent = FeatureExtent.distance,
    this.flip = false,
    this.type = HoleType.simple,
    this.cbDia = 11,
    this.cbDepth = 6,
    this.exprCbDia = '11 mm',
    this.exprCbDepth = '6 mm',
    this.csDia = 12,
    this.csAngle = 90,
    this.exprCsDia = '12 mm',
    this.exprCsAngle = '90 deg',
    super.visible,
  }) : super(output: 'cut');

  @override
  String get kind => 'hole';
  @override
  String get typeLabel => 'Hole';

  /// A hole needs something to drill: it consumes the body it lands in and can
  /// never be a base feature.
  @override
  bool get modifiesBody => true;

  @override
  String ownSig() => 'ho|$sketchName|$dia,$depth,'
      '${featureExtentName(extent)},$flip|${type.name},'
      '$cbDia,$cbDepth,$csDia,$csAngle|'
      '${places.map((p) => '${p.x}:${p.y}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'sketch': sketchName,
        'places': [for (final p in places) p.toJson()],
        'dia': dia,
        'depth': depth,
        'exprDia': exprDia,
        'exprDepth': exprDepth,
        'extent': featureExtentName(extent),
        'flip': flip,
        'type': holeTypeName(type),
        'cbDia': cbDia,
        'cbDepth': cbDepth,
        'exprCbDia': exprCbDia,
        'exprCbDepth': exprCbDepth,
        'csDia': csDia,
        'csAngle': csAngle,
        'exprCsDia': exprCsDia,
        'exprCsAngle': exprCsAngle,
      };

  static HoleFeature fromJson(Map<String, dynamic> j) {
    final f = HoleFeature(
      name: j['name'] as String? ?? 'Hole',
      bodyName: j['body'] as String? ?? 'Solid1',
      sketchName: j['sketch'] as String? ?? '',
      places: [
        for (final p in (j['places'] as List? ?? const []))
          HolePlace.fromJson((p as Map).cast<String, dynamic>())
      ],
      dia: (j['dia'] as num?)?.toDouble() ?? 6,
      depth: (j['depth'] as num?)?.toDouble() ?? 10,
      exprDia: j['exprDia'] as String? ?? '6 mm',
      exprDepth: j['exprDepth'] as String? ?? '10 mm',
      extent: featureExtentFrom(j['extent'] as String? ?? 'distance'),
      flip: j['flip'] as bool? ?? false,
      type: holeTypeFrom(j['type'] as String?),
      cbDia: (j['cbDia'] as num?)?.toDouble() ?? 11,
      cbDepth: (j['cbDepth'] as num?)?.toDouble() ?? 6,
      exprCbDia: j['exprCbDia'] as String? ?? '11 mm',
      exprCbDepth: j['exprCbDepth'] as String? ?? '6 mm',
      csDia: (j['csDia'] as num?)?.toDouble() ?? 12,
      csAngle: (j['csAngle'] as num?)?.toDouble() ?? 90,
      exprCsDia: j['exprCsDia'] as String? ?? '12 mm',
      exprCsAngle: j['exprCsAngle'] as String? ?? '90 deg',
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

class ExtrudeFeature extends PartFeature {
  @override
  final String sketchName;
  final List<ProfileSel> profiles;
  ExtrudeDirection direction;
  double distanceA, distanceB, taperDeg;
  String exprA, exprB, exprTaper; // what the user typed (redisplayed on edit)
  bool iMate, matchShape;

  /// M132 — Inventor's Extents. [distanceA] is only consulted for
  /// [FeatureExtent.distance]; the others resolve against the model.
  FeatureExtent extent;
  FaceSel? extentFace; // set iff extent == toFace

  /// M111 — an IMPORTED body (STEP). It has no sketch and no profiles, so the
  /// feature recompute must leave it alone: rebuilding it from inputs that do
  /// not exist would delete the geometry the user just imported. Persisted,
  /// together with [importPath], so it survives reopening the part.
  bool imported = false;

  /// Where the imported STEP lives, relative to the part folder. The B-Rep
  /// itself is not serialised — the file IS the source of truth, and
  /// re-reading it on open is both simpler and lossless.
  String? importPath;

  ExtrudeFeature({
    required super.name,
    required super.bodyName,
    required this.sketchName,
    required this.profiles,
    this.direction = ExtrudeDirection.defaultDir,
    this.distanceA = 5,
    this.distanceB = 5,
    this.taperDeg = 0,
    this.exprA = '5 mm',
    this.exprB = '5 mm',
    this.exprTaper = '0.00 deg',
    this.iMate = false,
    this.matchShape = true,
    this.extent = FeatureExtent.distance,
    this.extentFace,
    super.visible,
    super.output,
  });

  @override
  String get kind => 'extrude';
  @override
  String get typeLabel => 'Extrusion';

  @override
  String ownSig() => 'ex|$sketchName|$distanceA,$distanceB,$taperDeg,'
      '${extrudeDirName(direction)},${featureExtentName(extent)},'
      '$iMate,$matchShape|'
      '${profiles.map((p) => '${p.ax}:${p.ay}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        if (imported) 'imported': true,
        if (importPath != null) 'importPath': importPath,
        'sketch': sketchName,
        'profiles': [for (final p in profiles) p.toJson()],
        'dir': extrudeDirName(direction),
        'a': distanceA,
        'b': distanceB,
        'taper': taperDeg,
        'exprA': exprA,
        'exprB': exprB,
        'exprTaper': exprTaper,
        'imate': iMate,
        'match': matchShape,
        'extent': featureExtentName(extent),
        if (extentFace != null) 'extentFace': extentFace!.toJson(),
      };

  static ExtrudeFeature fromJson(Map<String, dynamic> j) {
    final f = ExtrudeFeature(
      name: j['name'] as String? ?? 'Extrusion',
      bodyName: j['body'] as String? ?? 'Solid1',
      sketchName: j['sketch'] as String? ?? '',
      profiles: [
        for (final p in (j['profiles'] as List? ?? const []))
          ProfileSel.fromJson((p as Map).cast<String, dynamic>())
      ],
      direction: extrudeDirFrom(j['dir'] as String? ?? 'default'),
      distanceA: (j['a'] as num?)?.toDouble() ?? 5,
      distanceB: (j['b'] as num?)?.toDouble() ?? 5,
      taperDeg: (j['taper'] as num?)?.toDouble() ?? 0,
      exprA: j['exprA'] as String? ?? '5 mm',
      exprB: j['exprB'] as String? ?? '5 mm',
      exprTaper: j['exprTaper'] as String? ?? '0.00 deg',
      iMate: j['imate'] as bool? ?? false,
      matchShape: j['match'] as bool? ?? true,
      // Pre-M132 files have no 'extent' and were all plain distances, so the
      // default reproduces them exactly.
      extent: featureExtentFrom(j['extent'] as String?),
      extentFace: j['extentFace'] == null
          ? null
          : FaceSel.fromJson((j['extentFace'] as Map).cast<String, dynamic>()),
      visible: j['visible'] as bool? ?? true,
      output: j['output'] as String? ?? 'join',
    );
    f.readBaseJson(j);
    // M111 — an imported body carries no sketch inputs; these two say so.
    f.imported = j['imported'] as bool? ?? false;
    f.importPath = j['importPath'] as String?;
    return f;
  }
}

/// Inventor's Revolve: a profile swept about an axis lying in its own plane.
///
/// The axis is stored in SKETCH coordinates as a point plus a direction, not
/// as a reference to the sketch entity that produced it. A construction line
/// can be deleted or re-drawn; the geometry it defined is what the feature
/// actually depends on, and storing that keeps the revolve alive exactly as
/// [ProfileSel] keeps a profile alive.
class RevolveFeature extends PartFeature {
  @override
  final String sketchName;
  final List<ProfileSel> profiles;

  double axPx, axPy, axDx, axDy; // axis in sketch coords
  ExtrudeDirection direction; // reuses Inventor's four direction modes
  double angleA, angleB;
  String exprA, exprB;
  bool full; // Inventor's "Full" — a complete 360 turn
  FeatureExtent extent;
  FaceSel? extentFace;

  RevolveFeature({
    required super.name,
    required super.bodyName,
    required this.sketchName,
    required this.profiles,
    this.axPx = 0,
    this.axPy = 0,
    this.axDx = 0,
    this.axDy = 1,
    this.direction = ExtrudeDirection.defaultDir,
    this.angleA = 360,
    this.angleB = 0,
    this.exprA = '360.00 deg',
    this.exprB = '0.00 deg',
    this.full = true,
    this.extent = FeatureExtent.distance,
    this.extentFace,
    super.visible,
    super.output,
  });

  @override
  String get kind => 'revolve';
  @override
  String get typeLabel => 'Revolution';

  /// Total sweep actually handed to the kernel. Inventor's Full wins over the
  /// typed angle; Symmetric splits Angle A; Asymmetric adds A and B.
  double get sweepDeg {
    if (full) return 360.0;
    final t = switch (direction) {
      ExtrudeDirection.asymmetric => angleA + angleB,
      _ => angleA,
    };
    return t.clamp(0.0, 360.0);
  }

  /// Where the sweep STARTS, as an angle offset from the profile plane —
  /// the rotational twin of [extrudeSpan]'s start offset.
  double get startOffsetDeg {
    if (full) return 0.0;
    return switch (direction) {
      ExtrudeDirection.defaultDir => 0.0,
      ExtrudeDirection.flipped => -sweepDeg,
      ExtrudeDirection.symmetric => -sweepDeg / 2,
      ExtrudeDirection.asymmetric => -angleB,
    };
  }

  @override
  String ownSig() => 'rv|$sketchName|$angleA,$angleB,$full,'
      '${extrudeDirName(direction)},${featureExtentName(extent)}|'
      '$axPx,$axPy,$axDx,$axDy|'
      '${profiles.map((p) => '${p.ax}:${p.ay}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'sketch': sketchName,
        'profiles': [for (final p in profiles) p.toJson()],
        'ax': [axPx, axPy, axDx, axDy],
        'dir': extrudeDirName(direction),
        'angA': angleA,
        'angB': angleB,
        'exprA': exprA,
        'exprB': exprB,
        'full': full,
        'extent': featureExtentName(extent),
        if (extentFace != null) 'extentFace': extentFace!.toJson(),
      };

  static RevolveFeature fromJson(Map<String, dynamic> j) {
    final ax = (j['ax'] as List?)?.cast<num>();
    final f = RevolveFeature(
      name: j['name'] as String? ?? 'Revolution',
      bodyName: j['body'] as String? ?? 'Solid1',
      sketchName: j['sketch'] as String? ?? '',
      profiles: [
        for (final p in (j['profiles'] as List? ?? const []))
          ProfileSel.fromJson((p as Map).cast<String, dynamic>())
      ],
      axPx: (ax != null && ax.length == 4) ? ax[0].toDouble() : 0,
      axPy: (ax != null && ax.length == 4) ? ax[1].toDouble() : 0,
      axDx: (ax != null && ax.length == 4) ? ax[2].toDouble() : 0,
      axDy: (ax != null && ax.length == 4) ? ax[3].toDouble() : 1,
      direction: extrudeDirFrom(j['dir'] as String? ?? 'default'),
      angleA: (j['angA'] as num?)?.toDouble() ?? 360,
      angleB: (j['angB'] as num?)?.toDouble() ?? 0,
      exprA: j['exprA'] as String? ?? '360.00 deg',
      exprB: j['exprB'] as String? ?? '0.00 deg',
      full: j['full'] as bool? ?? true,
      extent: featureExtentFrom(j['extent'] as String?),
      extentFace: j['extentFace'] == null
          ? null
          : FaceSel.fromJson((j['extentFace'] as Map).cast<String, dynamic>()),
      visible: j['visible'] as bool? ?? true,
      output: j['output'] as String? ?? 'join',
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Inventor's Sweep: a profile driven along a path curve.
class SweepFeature extends PartFeature {
  @override
  final String sketchName;
  final List<ProfileSel> profiles;
  CurveSel? path;

  /// 0 Follow Path, 1 Fixed, 2 Follow Path and Guide — Inventor's three
  /// Orientation buttons.
  int orientation;
  double taperDeg, twistDeg;
  String exprTaper, exprTwist;

  /// S11 — the KERNEL ARGUMENTS [solid] was last swept from. Runtime only,
  /// never serialised.
  ///
  /// [PartFeature.builtSig] is the chain-aware key, and only
  /// [recomputeAllFeatures] maintains it: a feature built through the
  /// single-feature entry point [recomputeFeature] leaves it null, so the next
  /// fold always rebuilds. On a sweep that costs whatever the sweep costs, and in
  /// the field capture that was 103 seconds — the third of three identical
  /// runs.
  ///
  /// This key is narrower on purpose. It is the resolved argument list handed
  /// to the kernel, so it says exactly the thing the guard needs: identical
  /// arguments, identical output. It deliberately does NOT include the boolean
  /// base, because [_recomputeSweep] does not take one — the fold happens
  /// outside this function and is unaffected by reusing the swept solid.
  String? sweptFrom;

  SweepFeature({
    required super.name,
    required super.bodyName,
    required this.sketchName,
    required this.profiles,
    this.path,
    this.orientation = 0,
    this.taperDeg = 0,
    this.twistDeg = 0,
    this.exprTaper = '0 deg',
    this.exprTwist = '0 deg',
    super.visible,
    super.output,
  });

  @override
  List<String> get sketchNames => [
        if (sketchName.isNotEmpty) sketchName,
        if (path != null && path!.sketchName.isNotEmpty) path!.sketchName,
      ];

  @override
  String get kind => 'sweep';
  @override
  String get typeLabel => 'Sweep';

  /// Clears [sweptFrom] with the solid it described. Without this a disposed
  /// solid would still look "already swept" and the guard would return true
  /// with nothing built.
  @override
  void disposeSolid() {
    sweptFrom = null;
    super.disposeSolid();
  }

  @override
  String ownSig() => 'sw|$sketchName|$orientation,$taperDeg,$twistDeg|'
      '${path == null ? "-" : "${path!.sketchName}:${path!.x0},${path!.y0},"
          "${path!.x1},${path!.y1}"}|'
      '${profiles.map((p) => '${p.ax}:${p.ay}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'sketch': sketchName,
        'profiles': [for (final p in profiles) p.toJson()],
        if (path != null) 'path': path!.toJson(),
        'orient': orientation,
        'taper': taperDeg,
        'twist': twistDeg,
        'exprTaper': exprTaper,
        'exprTwist': exprTwist,
      };

  static SweepFeature fromJson(Map<String, dynamic> j) {
    final f = SweepFeature(
      name: j['name'] as String? ?? 'Sweep',
      bodyName: j['body'] as String? ?? 'Solid1',
      sketchName: j['sketch'] as String? ?? '',
      profiles: [
        for (final p in (j['profiles'] as List? ?? const []))
          ProfileSel.fromJson((p as Map).cast<String, dynamic>())
      ],
      path: j['path'] == null
          ? null
          : CurveSel.fromJson((j['path'] as Map).cast<String, dynamic>()),
      orientation: (j['orient'] as num?)?.toInt() ?? 0,
      taperDeg: (j['taper'] as num?)?.toDouble() ?? 0,
      twistDeg: (j['twist'] as num?)?.toDouble() ?? 0,
      exprTaper: j['exprTaper'] as String? ?? '0 deg',
      exprTwist: j['exprTwist'] as String? ?? '0 deg',
      visible: j['visible'] as bool? ?? true,
      output: j['output'] as String? ?? 'join',
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Inventor's Loft: a run through two or more sections.
///
/// Each section is a profile in ITS OWN sketch, so unlike extrude and revolve
/// this feature is not tied to one sketch — [sectionSketches] runs parallel to
/// [sections].
class LoftFeature extends PartFeature {
  final List<String> sectionSketches;
  final List<ProfileSel> sections;
  bool solidOutput, ruled, closedLoop, mergeTangent;

  LoftFeature({
    required super.name,
    required super.bodyName,
    required this.sectionSketches,
    required this.sections,
    this.solidOutput = true,
    this.ruled = false,
    this.closedLoop = false,
    this.mergeTangent = false,
    super.visible,
    super.output,
  });

  @override
  String get kind => 'loft';
  @override
  String get typeLabel => 'Loft';

  /// A loft spans several sketches, so there is no single one it depends on.
  /// The signature below names them all instead.
  @override
  String get sketchName => '';

  @override
  List<String> get sketchNames =>
      sectionSketches.where((n) => n.isNotEmpty).toSet().toList();

  @override
  String ownSig() => 'lo|${sectionSketches.join(",")}|'
      '$solidOutput,$ruled,$closedLoop,$mergeTangent|'
      '${sections.map((p) => '${p.ax}:${p.ay}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'sketches': sectionSketches,
        'sections': [for (final p in sections) p.toJson()],
        'solid': solidOutput,
        'ruled': ruled,
        'closed': closedLoop,
        'mergeTangent': mergeTangent,
      };

  static LoftFeature fromJson(Map<String, dynamic> j) {
    final secs = [
      for (final p in (j['sections'] as List? ?? const []))
        ProfileSel.fromJson((p as Map).cast<String, dynamic>())
    ];
    final sks = [
      for (final n in (j['sketches'] as List? ?? const [])) n as String
    ];
    // Keep the two lists the same length: every downstream loop pairs them.
    while (sks.length < secs.length) {
      sks.add(sks.isEmpty ? '' : sks.last);
    }
    final f = LoftFeature(
      name: j['name'] as String? ?? 'Loft',
      bodyName: j['body'] as String? ?? 'Solid1',
      sectionSketches: sks.sublist(0, secs.length),
      sections: secs,
      solidOutput: j['solid'] as bool? ?? true,
      ruled: j['ruled'] as bool? ?? false,
      closedLoop: j['closed'] as bool? ?? false,
      mergeTangent: j['mergeTangent'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
      output: j['output'] as String? ?? 'join',
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Inventor's Coil: a profile driven along a helix about an axis.
class CoilFeature extends PartFeature {
  @override
  final String sketchName;
  final List<ProfileSel> profiles;

  /// Axis in SKETCH coordinates, like [RevolveFeature] and for the same
  /// reason: the line that defined it may be deleted or redrawn.
  double axPx, axPy, axDx, axDy;

  /// Inventor's Method: 0 Revolution and Height, 1 Pitch and Revolution,
  /// 2 Pitch and Height, 3 Spiral. All four resolve to a revolutions/height
  /// pair, which is what the kernel takes — see [resolved].
  int method;
  double revolutions, height, pitch, taperDeg;
  String exprRevolutions, exprHeight, exprPitch, exprTaper;
  bool clockwise, closeStart, closeEnd;

  CoilFeature({
    required super.name,
    required super.bodyName,
    required this.sketchName,
    required this.profiles,
    this.axPx = 0,
    this.axPy = 0,
    this.axDx = 0,
    this.axDy = 1,
    this.method = 0,
    this.revolutions = 5,
    this.height = 8,
    this.pitch = 2,
    this.taperDeg = 0,
    this.exprRevolutions = '5 ul',
    this.exprHeight = '8 mm',
    this.exprPitch = '2 mm',
    this.exprTaper = '0.00 deg',
    this.clockwise = false,
    this.closeStart = false,
    this.closeEnd = false,
    super.visible,
    super.output,
  });

  @override
  String get kind => 'coil';
  @override
  String get typeLabel => 'Coil';

  /// The (revolutions, height) pair the kernel actually needs.
  ///
  /// Inventor offers four ways to say the same helix; converting here means
  /// the shim takes one form and the panel can offer all four without the
  /// arithmetic being duplicated at the call site.
  (double, double) get resolved => switch (method) {
        1 => (revolutions, pitch * revolutions), // pitch + revolutions
        2 => (pitch <= 0 ? 0 : height / pitch, height), // pitch + height
        3 => (revolutions, 0.0), // spiral: flat, no rise
        _ => (revolutions, height), // revolutions + height
      };

  @override
  String ownSig() => 'co|$sketchName|$method,$revolutions,$height,$pitch,'
      '$taperDeg,$clockwise,$closeStart,$closeEnd|'
      '$axPx,$axPy,$axDx,$axDy|'
      '${profiles.map((p) => '${p.ax}:${p.ay}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'sketch': sketchName,
        'profiles': [for (final p in profiles) p.toJson()],
        'ax': [axPx, axPy, axDx, axDy],
        'method': method,
        'rev': revolutions,
        'h': height,
        'pitch': pitch,
        'taper': taperDeg,
        'exprRev': exprRevolutions,
        'exprH': exprHeight,
        'exprPitch': exprPitch,
        'exprTaper': exprTaper,
        'cw': clockwise,
        'cs': closeStart,
        'ce': closeEnd,
      };

  static CoilFeature fromJson(Map<String, dynamic> j) {
    final ax = (j['ax'] as List?)?.cast<num>();
    final f = CoilFeature(
      name: j['name'] as String? ?? 'Coil',
      bodyName: j['body'] as String? ?? 'Solid1',
      sketchName: j['sketch'] as String? ?? '',
      profiles: [
        for (final p in (j['profiles'] as List? ?? const []))
          ProfileSel.fromJson((p as Map).cast<String, dynamic>())
      ],
      axPx: (ax != null && ax.length == 4) ? ax[0].toDouble() : 0,
      axPy: (ax != null && ax.length == 4) ? ax[1].toDouble() : 0,
      axDx: (ax != null && ax.length == 4) ? ax[2].toDouble() : 0,
      axDy: (ax != null && ax.length == 4) ? ax[3].toDouble() : 1,
      method: (j['method'] as num?)?.toInt() ?? 0,
      revolutions: (j['rev'] as num?)?.toDouble() ?? 5,
      height: (j['h'] as num?)?.toDouble() ?? 8,
      pitch: (j['pitch'] as num?)?.toDouble() ?? 2,
      taperDeg: (j['taper'] as num?)?.toDouble() ?? 0,
      exprRevolutions: j['exprRev'] as String? ?? '5 ul',
      exprHeight: j['exprH'] as String? ?? '8 mm',
      exprPitch: j['exprPitch'] as String? ?? '2 mm',
      exprTaper: j['exprTaper'] as String? ?? '0.00 deg',
      clockwise: j['cw'] as bool? ?? false,
      closeStart: j['cs'] as bool? ?? false,
      closeEnd: j['ce'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
      output: j['output'] as String? ?? 'join',
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Base for the two features that MODIFY an existing body instead of adding
/// one. They consume no sketch, they cannot be a base feature, and the fold
/// feeds them the accumulated solid of their body as input.
/// M217 — a picked FACE, stored as geometry so it survives a rebuild.
///
/// The face twin of [EdgeSel], and for the same reason: a topological index is
/// meaningless across a rebuild (add a feature upstream and every index
/// shifts), so what a feature stores has to be something the face IS, not
/// where it happened to sit in a list.
///
/// The anchor is the face's mesh CENTROID rather than the surface's Location:
/// two coplanar faces of the same body share a Location and would be
/// indistinguishable, while their centroids are metres apart. Area and surface
/// type are the tie-breakers, and a TYPE change is disqualifying — a planar
/// face that became cylindrical is not the same face any more, which is
/// exactly the rule [EdgeSel] applies to a line that became an arc.
class FacePick {
  double cx, cy, cz; // mesh centroid, WORLD
  double nx, ny, nz; // outward unit normal there
  double area;
  int kind; // kFacePlane / kFaceCylinder / ... (part_render constants)

  FacePick(this.cx, this.cy, this.cz, this.nx, this.ny, this.nz, this.area,
      this.kind);

  Vec3 get centre => Vec3(cx, cy, cz);
  Vec3 get normal => Vec3(nx, ny, nz);

  Map<String, dynamic> toJson() =>
      {'c': [cx, cy, cz], 'n': [nx, ny, nz], 'a': area, 'k': kind};

  static FacePick? fromJson(Map<String, dynamic> j) {
    final c = (j['c'] as List?)?.cast<num>();
    final n = (j['n'] as List?)?.cast<num>();
    if (c == null || c.length != 3 || n == null || n.length != 3) return null;
    return FacePick(
        c[0].toDouble(),
        c[1].toDouble(),
        c[2].toDouble(),
        n[0].toDouble(),
        n[1].toDouble(),
        n[2].toDouble(),
        (j['a'] as num?)?.toDouble() ?? 0,
        (j['k'] as num?)?.toInt() ?? 0);
  }

  /// Distance between this fingerprint and a live face; [double.infinity]
  /// means "cannot be this face".
  ///
  /// Position dominates, because that is what the user pointed at. Area is a
  /// weak tiebreaker only — a Direct Edit legitimately changes the area of the
  /// faces around the one it moved, so a hard area match would lose exactly
  /// the faces that matter most on a second edit.
  double distanceTo(FaceRef live) {
    if (live.kind != kind) return double.infinity;
    // A face whose normal flipped is a different face, not a moved one.
    if (normal.dot(live.normal) < 0.2) return double.infinity;
    final d = (live.centre - centre).length;
    final aRel = area <= 0 || live.area <= 0
        ? 0.0
        : (live.area - area).abs() / (area + live.area);
    return d + aRel * 2.0;
  }
}

/// A LIVE face of a computed solid: what [FacePick] is re-matched against.
class FaceRef {
  /// 1-based TOPOLOGICAL index — what the kernel operations name.
  final int topoIndex;

  /// Index into the mesh's face list — what picking produces.
  final int meshIndex;

  final Vec3 centre, normal;
  final double area;
  final int kind;
  const FaceRef(this.topoIndex, this.meshIndex, this.centre, this.normal,
      this.area, this.kind);
}

/// Every live face of [mesh], with the centroid/area/normal a [FacePick] needs.
///
/// Computed from the TRIANGLES rather than the surface record because a
/// centroid and an area are properties of the trimmed face, and the surface
/// record describes the untrimmed surface it lies on.
List<FaceRef> facesOf(OcctMeshData mesh) {
  final n = mesh.faceCount;
  if (n <= 0 || mesh.triFaces.isEmpty) return const [];
  final cx = List<double>.filled(n, 0), cy = List<double>.filled(n, 0);
  final cz = List<double>.filled(n, 0), ar = List<double>.filled(n, 0);
  for (var t = 0; t + 2 < mesh.indices.length; t += 3) {
    final f = t ~/ 3;
    if (f >= mesh.triFaces.length) break;
    final fi = mesh.triFaces[f];
    if (fi < 0 || fi >= n) continue;
    final i0 = mesh.indices[t] * 3,
        i1 = mesh.indices[t + 1] * 3,
        i2 = mesh.indices[t + 2] * 3;
    final a = Vec3(mesh.positions[i0], mesh.positions[i0 + 1],
        mesh.positions[i0 + 2]);
    final b = Vec3(mesh.positions[i1], mesh.positions[i1 + 1],
        mesh.positions[i1 + 2]);
    final c = Vec3(mesh.positions[i2], mesh.positions[i2 + 1],
        mesh.positions[i2 + 2]);
    // Area-WEIGHTED centroid: a face triangulated into one huge and twenty
    // slivers has its centre where the material is, not where the vertices
    // happen to crowd.
    final w = (b - a).cross(c - a).length * 0.5;
    if (w <= 0) continue;
    ar[fi] += w;
    cx[fi] += (a.x + b.x + c.x) / 3 * w;
    cy[fi] += (a.y + b.y + c.y) / 3 * w;
    cz[fi] += (a.z + b.z + c.z) / 3 * w;
  }
  final out = <FaceRef>[];
  for (var f = 0; f < n; f++) {
    if (ar[f] <= 0) continue;
    final rec = 15 * f;
    if (rec + 7 > mesh.faceInfos.length) continue;
    final topo = mesh.topoFaceId(f);
    out.add(FaceRef(
        topo,
        f,
        Vec3(cx[f] / ar[f], cy[f] / ar[f], cz[f] / ar[f]),
        Vec3(mesh.faceInfos[rec + 4], mesh.faceInfos[rec + 5],
                mesh.faceInfos[rec + 6])
            .normalized(),
        ar[f],
        mesh.faceInfos[rec].round()));
  }
  return out;
}

/// Centre of [mesh]'s bounding box, or the origin for an empty mesh.
///
/// Direct > Scale needs a fixed point, and the box centre is the one that
/// keeps the body where it is: scaling about the world origin would fling a
/// part modelled off-origin across the scene, which reads as the command
/// having moved it rather than resized it.
Vec3 meshCentreOf(OcctMeshData mesh) {
  if (mesh.positions.length < 3) return Vec3.zero;
  var lox = mesh.positions[0], loy = mesh.positions[1], loz = mesh.positions[2];
  var hix = lox, hiy = loy, hiz = loz;
  for (var i = 0; i + 2 < mesh.positions.length; i += 3) {
    final x = mesh.positions[i], y = mesh.positions[i + 1];
    final z = mesh.positions[i + 2];
    if (x < lox) lox = x;
    if (y < loy) loy = y;
    if (z < loz) loz = z;
    if (x > hix) hix = x;
    if (y > hiy) hiy = y;
    if (z > hiz) hiz = z;
  }
  return Vec3((lox + hix) / 2, (loy + hiy) / 2, (loz + hiz) / 2);
}

/// The live face each selection now refers to, in order. A selection that no
/// longer matches is DROPPED and counted — the rule [BodyModifyFeature]
/// already applies to edges: a Direct Edit whose face set partly survives
/// keeps editing the rest rather than failing whole.
(List<int> topoIds, int lost) resolveFaces(
    List<FacePick> sels, List<FaceRef> live) {
  final ids = <int>[];
  final taken = <int>{};
  var lost = 0;
  for (final sel in sels) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < live.length; i++) {
      if (taken.contains(i) || live[i].topoIndex < 1) continue;
      final d = sel.distanceTo(live[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best < 0 || !bestD.isFinite) {
      lost++;
      continue;
    }
    taken.add(best);
    ids.add(live[best].topoIndex);
    // Re-anchor, so the next rebuild measures from where the face IS now
    // rather than from where it was first picked.
    final f = live[best];
    sel
      ..cx = f.centre.x
      ..cy = f.centre.y
      ..cz = f.centre.z
      ..nx = f.normal.x
      ..ny = f.normal.y
      ..nz = f.normal.z
      ..area = f.area;
  }
  return (ids, lost);
}


/// M217 — which face edit is open.
enum FaceEditKind { delete, move, size, scale }

String faceEditLabel(FaceEditKind k) => switch (k) {
      FaceEditKind.delete => 'Delete Face',
      FaceEditKind.move => 'Move Faces',
      FaceEditKind.size => 'Size Faces',
      FaceEditKind.scale => 'Scale Body',
    };

/// M217 — the open Delete Face / Direct Edit session.
///
/// One type for both commands, the way [EdgeFeatureSession] serves fillet and
/// chamfer: they collect the same thing (a face set on one body) and differ
/// only in what they do with it.
class FaceEditSession {
  FaceEditSession(this.kind);
  final FaceEditKind kind;

  /// The picked faces, as re-findable fingerprints, and the MESH indices they
  /// came from. The mesh indices are display state only — they drive the
  /// highlight and let a second tap deselect — and are deliberately not what
  /// the feature stores, because they do not survive a rebuild.
  final List<FacePick> faces = [];
  final List<int> meshIndices = [];

  /// Move/Size: the delta in mm. Size is offered along the first picked face's
  /// own normal, Move in free direction; both end up here.
  double dx = 0, dy = 0, dz = 0;

  /// Scale: the uniform factor.
  double factor = 1;

  bool get isScale => kind == FaceEditKind.scale;
  String get label => faceEditLabel(kind);
}

/// M217 — a feature that operates on picked FACES of the body it sits on.
///
/// The face-side sibling of [BodyModifyFeature]. Not a subclass of it: that
/// one's whole contract is a `List<EdgeSel>` and its edge re-matching, and
/// bolting faces onto it would leave every fillet carrying an empty face list
/// and every Direct Edit an empty edge list.
abstract class FaceModifyFeature extends PartFeature {
  FaceModifyFeature({
    required super.name,
    required super.bodyName,
    required this.faces,
    super.visible,
  }) : super(output: 'modify');

  final List<FacePick> faces;

  @override
  bool get modifiesBody => true;

  /// How many selections the last rebuild could not find. Reported, never
  /// silent — a Direct Edit quietly applying to three of four picked faces is
  /// a wrong part that looks right.
  int lostFaces = 0;
}

/// M217 — Inventor's Delete Face (with Heal).
class DeleteFaceFeature extends FaceModifyFeature {
  DeleteFaceFeature({
    required super.name,
    required super.bodyName,
    required super.faces,
    super.visible,
  });

  @override
  String get kind => 'deleteface';
  @override
  String get typeLabel => 'Delete Face';

  @override
  String ownSig() =>
      'df|${faces.map((f) => '${f.cx},${f.cy},${f.cz}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'faces': [for (final f in faces) f.toJson()],
      };

  static DeleteFaceFeature fromJson(Map<String, dynamic> j) {
    final fs = <FacePick>[];
    for (final e in (j['faces'] as List? ?? const [])) {
      final f = FacePick.fromJson((e as Map).cast<String, dynamic>());
      if (f != null) fs.add(f);
    }
    final f = DeleteFaceFeature(
      name: j['name'] as String? ?? 'Delete Face',
      bodyName: j['body'] as String? ?? 'Solid1',
      faces: fs,
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Which Direct Edit operation a [DirectEditFeature] performs.
///
/// Inventor's Direct panel offers Move, Size, Scale, Rotate and Delete. Delete
/// is [DeleteFaceFeature] (it is the same command as Delete Face, which is why
/// Inventor's own Delete Face and Direct > Delete produce the same feature).
/// Rotate is absent, deliberately — see [DirectEditFeature].
enum DirectOp { move, size, scale }

/// M217 — Inventor's Direct Edit.
///
/// [DirectOp.move] and [DirectOp.size] are the same kernel call and differ
/// only in how the UI offers the direction: Move takes a free direction, Size
/// pushes along the face's own normal. Keeping them one feature means a part
/// that was sized cannot rebuild differently from one that was moved by the
/// same vector, because they ARE the same edit.
///
/// ROTATE IS NOT HERE. Rotating a face means sliding its surface and
/// re-trimming its neighbours — a BRepTools_Modification subclass whose
/// failure modes only appear on real shapes. Shipping it unverified would be
/// exactly the dead-looking-alive control this milestone's ribbon pass
/// removed, so it is absent and the ribbon says so.
class DirectEditFeature extends FaceModifyFeature {
  DirectEditFeature({
    required super.name,
    required super.bodyName,
    required super.faces,
    required this.op,
    required this.dx,
    required this.dy,
    required this.dz,
    this.factor = 1,
    super.visible,
  });

  final DirectOp op;

  /// Move/Size: the delta, in mm, world axes.
  double dx, dy, dz;

  /// Scale: the uniform factor about the body's bounding-box centre.
  double factor;

  Vec3 get delta => Vec3(dx, dy, dz);

  @override
  String get kind => 'direct';
  @override
  String get typeLabel => switch (op) {
        DirectOp.move => 'Move Faces',
        DirectOp.size => 'Size Faces',
        DirectOp.scale => 'Scale Body',
      };

  @override
  String ownSig() => 'de|${op.name}|$dx,$dy,$dz|$factor|'
      '${faces.map((f) => '${f.cx},${f.cy},${f.cz}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'op': op.name,
        'd': [dx, dy, dz],
        if (op == DirectOp.scale) 'f': factor,
        'faces': [for (final f in faces) f.toJson()],
      };

  static DirectEditFeature fromJson(Map<String, dynamic> j) {
    final fs = <FacePick>[];
    for (final e in (j['faces'] as List? ?? const [])) {
      final f = FacePick.fromJson((e as Map).cast<String, dynamic>());
      if (f != null) fs.add(f);
    }
    final d = (j['d'] as List?)?.cast<num>();
    final f = DirectEditFeature(
      name: j['name'] as String? ?? 'Direct',
      bodyName: j['body'] as String? ?? 'Solid1',
      faces: fs,
      op: DirectOp.values.firstWhere((o) => o.name == j['op'],
          orElse: () => DirectOp.move),
      dx: d != null && d.length == 3 ? d[0].toDouble() : 0,
      dy: d != null && d.length == 3 ? d[1].toDouble() : 0,
      dz: d != null && d.length == 3 ? d[2].toDouble() : 0,
      factor: (j['f'] as num?)?.toDouble() ?? 1,
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

abstract class BodyModifyFeature extends PartFeature {
  BodyModifyFeature({
    required super.name,
    required super.bodyName,
    required this.edges,
    super.visible,
  }) : super(output: 'modify');

  /// The picked edges, stored as geometry so they survive a rebuild.
  final List<EdgeSel> edges;

  @override
  bool get modifiesBody => true;

  /// Resolve every stored selection against the live edge list. Returns the
  /// topological indices in the same order, and re-anchors the fingerprints.
  /// A selection that no longer matches is DROPPED from the result and
  /// reported through [lostEdges] — Inventor's behaviour for a fillet whose
  /// edge set partly survives is to keep filleting the rest.
  /// Returns the resolved topological ids, the INDEX INTO [edges] each one
  /// came from, and how many selections were lost.
  ///
  /// The source indices matter: a fillet's radii are parallel to [edges], so
  /// after selections are dropped the caller has to know which original entry
  /// each surviving id belongs to. Re-deriving that by calling [bestMatch]
  /// again would be both wasteful and WRONG — this pass reanchors the
  /// fingerprints and enforces one-live-edge-per-selection through [taken],
  /// neither of which a second independent pass reproduces.
  (List<int>, List<int>, int) resolveEdges(List<OcctEdgeInfo> live) {
    // Phase 1 — every selection against the model where it last saw itself.
    // An edge nothing upstream disturbed resolves here.
    final hit = List<OcctEdgeInfo?>.filled(edges.length, null);
    final taken = <int>{};
    for (var i = 0; i < edges.length; i++) {
      final m = edges[i].bestMatch(live);
      if (m != null && taken.add(m.index)) hit[i] = m;
    }

    // Phase 2 — M183. Whatever is left may not be GONE; the body it sits on
    // may simply have moved. Making a wall 2 mm taller translates every edge
    // above it by 2 mm, which is further than a fingerprint is allowed to
    // drift, so on the device a chamfer with both its edges on a raised boss
    // reported "none of the selected edges exist any more" and the feature
    // died — for an edit that did not remove either edge.
    //
    // The fix is to let a selection be re-found at a DISPLACEMENT, but only
    // one the feature can justify from its own evidence. See [_offsetPool].
    final missing = <int>[
      for (var i = 0; i < edges.length; i++)
        if (hit[i] == null) i
    ];
    if (missing.isNotEmpty) {
      for (final o in _offsetPool(live, hit, missing)) {
        for (final i in missing) {
          if (hit[i] != null) continue;
          final m = edges[i].bestMatch(live, ox: o.$1, oy: o.$2, oz: o.$3);
          if (m != null && taken.add(m.index)) hit[i] = m;
        }
      }
    }

    // Phase 3 — report and re-anchor.
    final ids = <int>[];
    final src = <int>[];
    var lost = 0;
    for (var i = 0; i < edges.length; i++) {
      final sel = edges[i];
      final m = hit[i];
      // M164 — say what each stored selection resolved to. A chamfer landing
      // on the wrong edge, or silently vanishing, is invisible in the log
      // without this: only "edges=2" was ever printed, which says nothing
      // about WHICH two. The `want` line is the fingerprint as picked, `got`
      // is the live edge it matched.
      final want = 'r=${sel.radius.toStringAsFixed(4)} '
          'l=${sel.length.toStringAsFixed(3)} k=${sel.kind} '
          'm=(${sel.mx.toStringAsFixed(3)},${sel.my.toStringAsFixed(3)},'
          '${sel.mz.toStringAsFixed(3)})';
      if (m == null) {
        Log.w(
            'edge',
            'sel[$i] LOST — $want; no confident match among ${live.length} '
                'live edges (gone, or two candidates too alike to choose)');
        lost++;
        continue;
      }
      final moved = (m.mx - sel.mx).abs() +
          (m.my - sel.my).abs() +
          (m.mz - sel.mz).abs();
      Log.i(
          'edge',
          'sel[$i] -> edge ${m.index}  $want  got r=${m.radius.toStringAsFixed(4)} '
              'l=${m.length.toStringAsFixed(3)} k=${m.kind}'
              '${moved > 1e-9 ? "  MOVED by ${moved.toStringAsFixed(4)} mm" : ""}');
      sel.reanchor(m);
      ids.add(m.index);
      src.add(i);
    }
    if (lost > 0) {
      Log.w('edge',
          '${edges.length - lost}/${edges.length} selections resolved, $lost lost');
    }
    return (ids, src, lost);
  }

  /// Displacements this feature is entitled to re-find its lost edges at.
  ///
  /// A free offset would explain anything: pick any live edge, subtract, and
  /// the selection "matches" perfectly. That is precisely the silent walk M158
  /// exists to prevent, so an offset is only usable when the feature can
  /// CORROBORATE it, and there are exactly two ways it can:
  ///
  ///  - a sibling selection resolved at that displacement on its own. The
  ///    edges of one fillet usually sit on the same lump of material, so a
  ///    sibling that demonstrably travelled 2 mm is real evidence about where
  ///    this one went. Siblings are tried independently, so a feature spanning
  ///    a part that moved and a part that did not still resolves both halves.
  ///
  ///  - with nothing resolved at all, a displacement that independently
  ///    explains TWO different lost selections. One selection agreeing with
  ///    itself is not evidence; two selections agreeing is.
  ///
  /// Offsets are returned nearest-first, so the smallest displacement that
  /// accounts for the model wins. The zero offset is never included — phase 1
  /// already tried it.
  List<(double, double, double)> _offsetPool(List<OcctEdgeInfo> live,
      List<OcctEdgeInfo?> hit, List<int> missing) {
    final pool = <(double, double, double)>[];
    void add(double x, double y, double z) {
      if (x.abs() + y.abs() + z.abs() < 1e-9) return;
      for (final p in pool) {
        if ((p.$1 - x).abs() + (p.$2 - y).abs() + (p.$3 - z).abs() < 1e-6) {
          return;
        }
      }
      pool.add((x, y, z));
    }

    for (var i = 0; i < edges.length; i++) {
      final m = hit[i];
      if (m != null) add(m.mx - edges[i].mx, m.my - edges[i].my,
          m.mz - edges[i].mz);
    }

    if (pool.isEmpty && missing.length >= 2) {
      // Nothing resolved, so the whole feature moved together or not at all.
      // Every (lost selection, plausible live edge) pairing proposes the
      // displacement that would explain it; a proposal that also explains a
      // DIFFERENT lost selection is the one to trust.
      // Distinct proposals only: many pairings land on the same displacement,
      // and scoring one costs a full match pass per lost selection.
      final proposals = <(double, double, double)>[];
      for (final i in missing) {
        final sel = edges[i];
        for (final e in live) {
          final ox = e.mx - sel.mx, oy = e.my - sel.my, oz = e.mz - sel.mz;
          if (ox.abs() + oy.abs() + oz.abs() < 1e-9) continue;
          if (!sel.score(e, ox: ox, oy: oy, oz: oz).isFinite) {
            continue; // type or length says this can never be that edge
          }
          var seen = false;
          for (final q in proposals) {
            if ((q.$1 - ox).abs() + (q.$2 - oy).abs() + (q.$3 - oz).abs() <
                1e-6) {
              seen = true;
              break;
            }
          }
          if (!seen) proposals.add((ox, oy, oz));
          if (proposals.length >= 64) break;
        }
        if (proposals.length >= 64) break;
      }
      for (final p in proposals) {
        var support = 0;
        for (final j in missing) {
          if (edges[j].bestMatch(live, ox: p.$1, oy: p.$2, oz: p.$3) != null) {
            support++;
          }
        }
        if (support >= 2) add(p.$1, p.$2, p.$3);
      }
    }

    pool.sort((a, b) {
      double n((double, double, double) v) =>
          v.$1 * v.$1 + v.$2 * v.$2 + v.$3 * v.$3;
      return n(a).compareTo(n(b));
    });
    return pool;
  }
}

/// Inventor's 3D Model > Modify > Fillet, constant radius.
///
/// One feature carries MANY edges with possibly DIFFERENT radii, which is
/// exactly what Inventor means by several edge sets inside a single fillet
/// feature — "all fillets and rounds that you create in a single operation
/// become a single feature".
class FilletFeature extends BodyModifyFeature {
  final List<double> radii; // parallel to [edges]

  /// M144 — END radius per edge, for Inventor's VARIABLE-radius fillet. An
  /// entry of 0 (or a missing one) means that edge is constant, so a plain
  /// fillet stores nothing extra and old files load unchanged.
  final List<double> radii2;

  String exprRadius; // what the user typed for the shared default
  bool allFillets, allRounds; // Inventor's Select Mode toggles

  FilletFeature({
    required super.name,
    required super.bodyName,
    required super.edges,
    required this.radii,
    this.radii2 = const [],
    this.exprRadius = '2 mm',
    this.allFillets = false,
    this.allRounds = false,
    super.visible,
  });

  @override
  String get kind => 'fillet';
  @override
  String get typeLabel => 'Fillet';

  @override
  String ownSig() => 'fi|${radii.join(',')}|${radii2.join(',')}|'
      '$allFillets,$allRounds|'
      '${edges.map((e) => '${e.mx},${e.my},${e.mz}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'edges': [for (final e in edges) e.toJson()],
        'radii': radii,
        if (radii2.any((r) => r > 0)) 'radii2': radii2,
        'exprRadius': exprRadius,
        'allFillets': allFillets,
        'allRounds': allRounds,
      };

  static FilletFeature fromJson(Map<String, dynamic> j) {
    final es = <EdgeSel>[];
    for (final e in (j['edges'] as List? ?? const [])) {
      final s = EdgeSel.fromJson((e as Map).cast<String, dynamic>());
      if (s != null) es.add(s);
    }
    final rs = [
      for (final r in (j['radii'] as List? ?? const [])) (r as num).toDouble()
    ];
    // Keep the two lists the same length no matter what the file says: every
    // downstream loop indexes them together.
    while (rs.length < es.length) {
      rs.add(rs.isEmpty ? 2.0 : rs.last);
    }
    final f = FilletFeature(
      name: j['name'] as String? ?? 'Fillet',
      bodyName: j['body'] as String? ?? 'Solid1',
      edges: es,
      radii: rs.sublist(0, es.length),
      radii2: [
        for (final r in (j['radii2'] as List? ?? const []))
          (r as num).toDouble()
      ],
      exprRadius: j['exprRadius'] as String? ?? '2 mm',
      allFillets: j['allFillets'] as bool? ?? false,
      allRounds: j['allRounds'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Inventor's 3D Model > Modify > Chamfer, with all three methods:
/// 0 = equal distance, 1 = two distances, 2 = distance and angle.
class ChamferFeature extends BodyModifyFeature {
  int mode;
  double distance1, distance2, angleDeg;
  String exprD1, exprD2, exprAngle;
  bool flip; // swaps which adjacent face distance1 is measured on
  bool edgeChain; // Inventor's "All Tangentially Connected Edges"

  ChamferFeature({
    required super.name,
    required super.bodyName,
    required super.edges,
    this.mode = 0,
    this.distance1 = 1,
    this.distance2 = 1,
    this.angleDeg = 45,
    this.exprD1 = '1 mm',
    this.exprD2 = '1 mm',
    this.exprAngle = '45.00 deg',
    this.flip = false,
    this.edgeChain = true,
    super.visible,
  });

  @override
  String get kind => 'chamfer';
  @override
  String get typeLabel => 'Chamfer';

  /// Distances as the shim wants them, with Flip already applied. Flip is a
  /// pure presentation swap for mode 1 and the complementary angle for
  /// mode 2, so the kernel never needs to know the toggle exists.
  (double, double, double) get kernelParams => switch (mode) {
        1 => flip
            ? (distance2, distance1, 0.0)
            : (distance1, distance2, 0.0),
        2 => (distance1, 0.0, flip ? 90.0 - angleDeg : angleDeg),
        _ => (distance1, 0.0, 0.0),
      };

  @override
  String ownSig() => 'ch|$mode,$distance1,$distance2,$angleDeg,$flip,'
      '$edgeChain|${edges.map((e) => '${e.mx},${e.my},${e.mz}').join(';')}';

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'edges': [for (final e in edges) e.toJson()],
        'mode': mode,
        'd1': distance1,
        'd2': distance2,
        'ang': angleDeg,
        'exprD1': exprD1,
        'exprD2': exprD2,
        'exprAngle': exprAngle,
        'flip': flip,
        'chain': edgeChain,
      };

  static ChamferFeature fromJson(Map<String, dynamic> j) {
    final es = <EdgeSel>[];
    for (final e in (j['edges'] as List? ?? const [])) {
      final s = EdgeSel.fromJson((e as Map).cast<String, dynamic>());
      if (s != null) es.add(s);
    }
    final f = ChamferFeature(
      name: j['name'] as String? ?? 'Chamfer',
      bodyName: j['body'] as String? ?? 'Solid1',
      edges: es,
      mode: (j['mode'] as num?)?.toInt() ?? 0,
      distance1: (j['d1'] as num?)?.toDouble() ?? 1,
      distance2: (j['d2'] as num?)?.toDouble() ?? 1,
      angleDeg: (j['ang'] as num?)?.toDouble() ?? 45,
      exprD1: j['exprD1'] as String? ?? '1 mm',
      exprD2: j['exprD2'] as String? ?? '1 mm',
      exprAngle: j['exprAngle'] as String? ?? '45.00 deg',
      flip: j['flip'] as bool? ?? false,
      edgeChain: j['chain'] as bool? ?? true,
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

// ---------------------------------------------------------------------------
// M212 — patterns in the PART: Rectangular, Circular, Sketch Driven, Mirror
// ---------------------------------------------------------------------------
//
// One feature class for all four, exactly as Inventor keeps one pattern
// concept with four placement rules. What differs between them is only WHERE
// the occurrences go; everything after that — which features are copied, how
// each copy is combined into the body, which occurrences are suppressed, and
// whether copies are identical or re-terminated — is shared, and four classes
// would have been four places to keep that in step.

/// Which placement rule a [PatternFeature] uses.
enum PatternKind { rectangular, circular, sketchDriven, mirror }

String patternKindName(PatternKind k) => switch (k) {
      PatternKind.rectangular => 'rect',
      PatternKind.circular => 'circ',
      PatternKind.sketchDriven => 'sketch',
      PatternKind.mirror => 'mirror',
    };

PatternKind patternKindFrom(String? s) => switch (s) {
      'circ' => PatternKind.circular,
      'sketch' => PatternKind.sketchDriven,
      'mirror' => PatternKind.mirror,
      _ => PatternKind.rectangular,
    };

/// The command name Inventor puts at the top of the panel.
String patternKindLabel(PatternKind k) => switch (k) {
      PatternKind.rectangular => 'Rectangular Pattern',
      PatternKind.circular => 'Circular Pattern',
      PatternKind.sketchDriven => 'Sketch Driven Pattern',
      PatternKind.mirror => 'Mirror',
    };

/// The type label a new feature of this kind gets in the browser.
String patternTypeLabel(PatternKind k) => switch (k) {
      PatternKind.rectangular => 'RectangularPattern',
      PatternKind.circular => 'CircularPattern',
      PatternKind.sketchDriven => 'SketchDrivenPattern',
      PatternKind.mirror => 'Mirror',
    };

/// Inventor's Distribution. The typed value is either the step BETWEEN
/// neighbouring occurrences ([spacing], Inventor's "Spacing"; "Incremental"
/// on a circular pattern) or the TOTAL span the occurrences fill ([distance],
/// Inventor's "Distance"; "Fitted" on a circular pattern).
///
/// Fitted is the one to use when the design may change, because the pattern
/// then re-divides the same total rather than growing out of its boundary —
/// which is precisely Inventor's own advice.
/// [curveLength] is Inventor's third option and only exists for a direction
/// that is a CURVE: the occurrences are fitted to the length of that curve,
/// so the pattern re-divides itself when the curve is redrawn. It behaves as
/// [distance] on a straight direction, where there is no curve to fit to.
enum PatternDistribution { spacing, distance, curveLength }

String patternDistName(PatternDistribution d) => switch (d) {
      PatternDistribution.distance => 'distance',
      PatternDistribution.curveLength => 'curve',
      PatternDistribution.spacing => 'spacing',
    };

PatternDistribution patternDistFrom(String? s) => switch (s) {
      'distance' => PatternDistribution.distance,
      'curve' => PatternDistribution.curveLength,
      _ => PatternDistribution.spacing,
    };

/// Inventor's circular Orientation: [rotational] turns each occurrence with
/// the axis (the usual bolt-circle look), [fixed] carries it around the axis
/// while keeping the parent's orientation.
enum PatternOrient { rotational, fixed }

/// Inventor's Creation Method (the old dialog's "Compute").
///
/// [identical] replicates the RESULT of the original feature — one tool
/// solid, placed n times. It is what Inventor recommends and what every
/// pattern here does unless told otherwise.
///
/// [adjust] rebuilds each occurrence at its own place, so a termination
/// ("To Next", "To <face>", "Through All") is resolved against the body
/// WHERE THAT OCCURRENCE LANDS. On a stepped part that is the difference
/// between a row of holes that all stop at the first step and a row that each
/// break through their own wall. Only the two feature kinds that HAVE a
/// termination (extrude, revolve) can differ; for the others Adjust and
/// Identical are the same solid, and this build does not pretend otherwise.
enum PatternCompute { identical, adjust }

String patternComputeName(PatternCompute c) =>
    c == PatternCompute.adjust ? 'adjust' : 'identical';

PatternCompute patternComputeFrom(String? s) =>
    s == 'adjust' ? PatternCompute.adjust : PatternCompute.identical;

/// A picked DIRECTION or AXIS, stored as geometry: a point plus a direction
/// in world coordinates, with the label the panel shows.
///
/// Stored the way [RevolveFeature] stores its axis and for the same reason —
/// the edge, sketch line or origin axis that produced it can be deleted or
/// redrawn, and what the feature actually depends on is the direction it
/// defined. A reference would die with the edge; the geometry does not.
class AxisRef {
  double px, py, pz, dx, dy, dz;
  String label;
  AxisRef(this.px, this.py, this.pz, this.dx, this.dy, this.dz,
      [this.label = 'Direction']);

  Vec3 get point => Vec3(px, py, pz);
  Vec3 get dir => Vec3(dx, dy, dz);
  Vec3 get unit => dir.normalized();
  bool get valid => dir.length > 1e-9;

  AxisRef copy() => AxisRef(px, py, pz, dx, dy, dz, label);

  Map<String, dynamic> toJson() =>
      {'p': [px, py, pz], 'd': [dx, dy, dz], 'label': label};

  static AxisRef? fromJson(Map<String, dynamic> j) {
    final p = (j['p'] as List?)?.cast<num>(), d = (j['d'] as List?)?.cast<num>();
    if (p == null || d == null || p.length != 3 || d.length != 3) return null;
    return AxisRef(p[0].toDouble(), p[1].toDouble(), p[2].toDouble(),
        d[0].toDouble(), d[1].toDouble(), d[2].toDouble(),
        j['label'] as String? ?? 'Direction');
  }
}

/// A picked MIRROR PLANE — a point on it and its normal, plus a label.
///
/// Same contract as [AxisRef]: the plane is remembered as geometry, not as a
/// reference to the face or work plane that defined it.
class PlaneRef {
  double px, py, pz, nx, ny, nz;
  String label;
  PlaneRef(this.px, this.py, this.pz, this.nx, this.ny, this.nz,
      [this.label = 'Plane']);

  Vec3 get point => Vec3(px, py, pz);
  Vec3 get normal => Vec3(nx, ny, nz);
  bool get valid => normal.length > 1e-9;

  PlaneRef copy() => PlaneRef(px, py, pz, nx, ny, nz, label);

  Map<String, dynamic> toJson() =>
      {'p': [px, py, pz], 'n': [nx, ny, nz], 'label': label};

  static PlaneRef? fromJson(Map<String, dynamic> j) {
    final p = (j['p'] as List?)?.cast<num>(), n = (j['n'] as List?)?.cast<num>();
    if (p == null || n == null || p.length != 3 || n.length != 3) return null;
    return PlaneRef(p[0].toDouble(), p[1].toDouble(), p[2].toDouble(),
        n[0].toDouble(), n[1].toDouble(), n[2].toDouble(),
        j['label'] as String? ?? 'Plane');
  }
}

/// ONE occurrence of a pattern: where a copy of the patterned geometry goes.
///
/// [mat34] is a rigid placement for every kind except the mirror, which is a
/// REFLECTION and therefore not expressible as one (determinant -1; the shim
/// refuses it in `occt_transform` on purpose). A mirror occurrence carries
/// [mirror] = true instead and the plane comes from the feature.
///
/// [index] is the occurrence's position in Inventor's numbering, counting the
/// ORIGINAL as 1 — so the copies this list describes start at 2. It is what
/// the browser labels and what [PatternFeature.suppressed] addresses, and it
/// must stay stable as long as the counts do, which is why it is computed
/// from the grid indices rather than from the position in this list.
class PatternOccurrence {
  final int index;
  final List<double>? mat34;
  final bool mirror;
  const PatternOccurrence(this.index, this.mat34, {this.mirror = false});
}

/// Row-major 3x4 rigid placement of a pure translation by [d].
List<double> translationMat34(Vec3 d) => [
      1, 0, 0, d.x, //
      0, 1, 0, d.y, //
      0, 0, 1, d.z, //
    ];

/// Row-major 3x4 rigid placement of a rotation by [angleRad] about the line
/// through [p] along the UNIT axis [k].
List<double> rotationMat34(Vec3 p, Vec3 k, double angleRad) {
  final cx = rotateAboutAxis(const Vec3(1, 0, 0), k, angleRad);
  final cy = rotateAboutAxis(const Vec3(0, 1, 0), k, angleRad);
  final cz = rotateAboutAxis(const Vec3(0, 0, 1), k, angleRad);
  // Rotation about a LINE, not the origin: x -> R(x - p) + p.
  final t = p - rotateAboutAxis(p, k, angleRad);
  return [
    cx.x, cy.x, cz.x, t.x, //
    cx.y, cy.y, cz.y, t.y, //
    cx.z, cy.z, cz.z, t.z, //
  ];
}

/// True when [m] is (numerically) the identity placement — the occurrence
/// that would land exactly on the original, and must therefore not be built.
bool isIdentityMat34(List<double> m) {
  const id = [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0];
  if (m.length != 12) return false;
  for (var i = 0; i < 12; i++) {
    if ((m[i] - id[i]).abs() > 1e-9) return false;
  }
  return true;
}

/// Inventor's part-feature pattern: Rectangular, Circular, Sketch Driven and
/// Mirror in one feature.
///
/// It MODIFIES a body (like fillet and chamfer): the occurrences are combined
/// into the solid that reaches it, so the feature's own solid is the whole
/// body afterwards. The original feature is NOT one of the occurrences this
/// feature builds — it is already in that body, upstream, which is exactly
/// why Inventor calls the original "occurrence 1" and why suppressing it is a
/// different operation from suppressing a copy.
class PatternFeature extends PartFeature {
  PatternFeature({
    required super.name,
    required super.bodyName,
    required this.mode,
    this.patternSolid = false,
    List<String> sources = const [],
    this.dirA,
    this.dirB,
    this.flipA = false,
    this.flipB = false,
    this.midplaneA = false,
    this.midplaneB = false,
    this.countA = 2,
    this.countB = 2,
    this.distanceA = 25,
    this.distanceB = 25,
    this.exprCountA = '2',
    this.exprCountB = '2',
    this.exprDistanceA = '25 mm',
    this.exprDistanceB = '25 mm',
    this.distributionA = PatternDistribution.spacing,
    this.distributionB = PatternDistribution.spacing,
    this.pathA,
    this.pathB,
    this.startA = 0,
    this.startB = 0,
    Map<int, double> irregularA = const {},
    Map<int, double> irregularB = const {},
    Map<int, double> irregularC = const {},
    this.axis,
    this.flipC = false,
    this.countC = 6,
    this.angleC = 360,
    this.exprCountC = '6',
    this.exprAngleC = '360.00 deg',
    this.distributionC = PatternDistribution.distance,
    this.orientation = PatternOrient.rotational,
    this.pointSketch = '',
    this.basePicked = false,
    this.baseX = 0,
    this.baseY = 0,
    this.mirrorPlane,
    this.orientFace,
    this.removeOriginal = false,
    this.compute = PatternCompute.identical,
    Set<int> suppressed = const {},
    super.visible,
  })  : sources = [...sources],
        suppressed = {...suppressed},
        irregularA = {...irregularA},
        irregularB = {...irregularB},
        irregularC = {...irregularC},
        // Like fillet and chamfer, a pattern's Output boolean is meaningless:
        // it does not add a body, it reshapes the one that reaches it. It is
        // NOT a [BodyModifyFeature] though — that class is the EDGE-picking
        // family (resolveEdges, the displacement pool), and inheriting it
        // would also route this feature straight into _recomputeBodyModify.
        super(output: 'modify');

  /// A pattern consumes the body that reaches it and hands on the result, so
  /// it needs an upstream solid exactly the way a fillet does.
  @override
  bool get modifiesBody => true;

  PatternKind mode;

  /// Inventor's two Input Geometry modes: pattern a set of FEATURES, or
  /// pattern the whole SOLID body ("Pattern a solid").
  bool patternSolid;

  /// Feature names being patterned, in pick order. Empty in solid mode.
  final List<String> sources;

  // ---- rectangular ----
  AxisRef? dirA, dirB;
  bool flipA, flipB;

  /// Inventor's Midplane, available per direction: the occurrences are laid
  /// out on BOTH sides of the original instead of growing away from it.
  bool midplaneA, midplaneB;
  int countA, countB;
  double distanceA, distanceB;
  String exprCountA, exprCountB, exprDistanceA, exprDistanceB;
  PatternDistribution distributionA, distributionB;

  /// M213 — Inventor lets a row run along a CURVE, not only along a straight
  /// direction ("rows and columns can be lines, arcs, splines, or trimmed
  /// ellipses"). When a path is set it REPLACES the direction: the
  /// occurrences are spaced by arc length along it, and Curve Length becomes
  /// available as a distribution.
  CurveSel? pathA, pathB;

  /// Inventor's Start: how far along the path the ORIGINAL sits, in mm of
  /// arc length from the curve's first point. Meaningless without a path.
  double startA, startB;

  /// M213 — Inventor 2026's Irregular Distance / Irregular Angle: one
  /// occurrence given its own offset instead of the even step.
  ///
  /// Keyed by STEP index along that direction (1 = the first copy after the
  /// original), valued as the offset FROM THE ORIGINAL — the same quantity
  /// the even spacing produces, so an entry simply replaces it and nothing
  /// downstream has to know which occurrences are irregular.
  final Map<int, double> irregularA, irregularB, irregularC;

  // ---- circular ----
  AxisRef? axis;
  bool flipC;
  int countC;
  double angleC;
  String exprCountC, exprAngleC;
  PatternDistribution distributionC;
  PatternOrient orientation;

  // ---- sketch driven ----
  /// Sketch whose POINTS place the occurrences.
  String pointSketch;

  /// Inventor's Base Point. Unset means the patterned geometry's own centre,
  /// which is what makes "one occurrence per point" land the way you expect
  /// without picking anything.
  bool basePicked;
  double baseX, baseY; // in [pointSketch]'s coordinates

  /// M213 — Inventor's Variable Orientation: a face the occurrences FOLLOW.
  ///
  /// With it set, each copy is turned from the sketch plane's normal to the
  /// surface normal where it lands, so a pattern of bosses over a curved
  /// shell stands up out of the shell instead of leaning with the original.
  /// Stored as a point + normal like every other picked face, and sampled
  /// against the live body at build time.
  FaceSel? orientFace;

  // ---- mirror ----
  PlaneRef? mirrorPlane;

  /// Inventor's Remove Original: only the mirrored half survives. Solid mode
  /// only — removing the original of a FEATURE mirror would mean deleting a
  /// feature that is upstream of this one, which is a tree edit, not a
  /// geometry option.
  bool removeOriginal;

  // ---- shared ----
  PatternCompute compute;

  /// Occurrence numbers (Inventor's numbering, original = 1) the user has
  /// suppressed. Suppressing an occurrence is a property of the pattern, not
  /// of the copy, which is why it lives here and survives a rebuild.
  final Set<int> suppressed;

  @override
  String get kind => 'pattern';

  @override
  String get typeLabel => patternTypeLabel(mode);

  /// A sketch-driven pattern depends on the sketch holding its points, so a
  /// point moved there has to rebuild it. The others depend on no sketch of
  /// their own (their inputs are stored as geometry).
  @override
  List<String> get sketchNames {
    final out = <String>[];
    if (mode == PatternKind.sketchDriven && pointSketch.isNotEmpty) {
      out.add(pointSketch);
    }
    // A path lives in a sketch too, and redrawing that curve has to rebuild
    // the pattern that runs along it.
    for (final c in [pathA, pathB]) {
      if (c != null && c.sketchName.isNotEmpty && !out.contains(c.sketchName)) {
        out.add(c.sketchName);
      }
    }
    return out;
  }

  /// How many occurrences were actually built last time, INCLUDING the
  /// original. Runtime only — it is a result, not an input.
  ///
  /// A sketch-driven pattern is the reason it exists: its count comes from
  /// the points in a sketch, so it cannot be read off the feature, and the
  /// browser still has to be able to list the occurrences to suppress one.
  int builtOccurrences = 0;

  /// How many occurrences the pattern describes INCLUDING the original, the
  /// way Inventor counts them.
  int get occurrenceCount => switch (mode) {
        // A second direction that was never picked is not a second row.
        PatternKind.rectangular => countA.clamp(1, kPatternMaxCount) *
            (dirB == null && pathB == null
                ? 1
                : countB.clamp(1, kPatternMaxCount)),
        PatternKind.circular => countC.clamp(1, kPatternMaxCount),
        PatternKind.mirror => 2,
        PatternKind.sketchDriven => builtOccurrences,
      };

  @override
  String ownSig() {
    final b = StringBuffer('pat|${patternKindName(mode)}|')
      ..write(patternSolid ? 'solid' : sources.join(','))
      ..write('|')
      ..write(patternComputeName(compute))
      ..write('|')
      ..write(suppressed.toList()..sort())
      ..write('|');
    switch (mode) {
      case PatternKind.rectangular:
        b
          ..write(_axSig(dirA))
          ..write(',$flipA,$midplaneA,$countA,$distanceA,')
          ..write(patternDistName(distributionA))
          ..write(',${_pathSig(pathA)},$startA,${_irrSig(irregularA)}')
          ..write('|')
          ..write(_axSig(dirB))
          ..write(',$flipB,$midplaneB,$countB,$distanceB,')
          ..write(patternDistName(distributionB))
          ..write(',${_pathSig(pathB)},$startB,${_irrSig(irregularB)}')
          ..write(',${orientation.name}');
      case PatternKind.circular:
        b
          ..write(_axSig(axis))
          ..write(',$flipC,$countC,$angleC,')
          ..write(patternDistName(distributionC))
          ..write(',')
          ..write(orientation.name)
          ..write(',${_irrSig(irregularC)}');
      case PatternKind.sketchDriven:
        final of = orientFace;
        b.write('$pointSketch,$basePicked,$baseX,$baseY,'
            '${of == null ? "flat" : "${of.px},${of.py},${of.pz}"}');
      case PatternKind.mirror:
        final p = mirrorPlane;
        b
          ..write(p == null
              ? 'none'
              : '${p.px},${p.py},${p.pz},${p.nx},${p.ny},${p.nz}')
          ..write(',$removeOriginal');
    }
    return b.toString();
  }

  static String _axSig(AxisRef? a) => a == null
      ? 'none'
      : '${a.px},${a.py},${a.pz},${a.dx},${a.dy},${a.dz}';

  static String _pathSig(CurveSel? c) => c == null
      ? 'nopath'
      : '${c.sketchName}#${c.geoIndex}:${c.x0},${c.y0},${c.x1},${c.y1}';

  /// The irregular entries in a stable order — a Map's iteration order is
  /// insertion order, and two identical patterns edited in a different order
  /// must produce the same key or the cache reuses the wrong solid.
  static String _irrSig(Map<int, double> m) {
    if (m.isEmpty) return '-';
    final ks = m.keys.toList()..sort();
    return [for (final k in ks) '$k=${m[k]}'].join(';');
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'mode': patternKindName(mode),
        'solid': patternSolid,
        'sources': [...sources],
        'compute': patternComputeName(compute),
        if (suppressed.isNotEmpty) 'suppressed': (suppressed.toList()..sort()),
        if (dirA != null) 'dirA': dirA!.toJson(),
        if (dirB != null) 'dirB': dirB!.toJson(),
        'flipA': flipA,
        'flipB': flipB,
        'midA': midplaneA,
        'midB': midplaneB,
        'countA': countA,
        'countB': countB,
        'distA': distanceA,
        'distB': distanceB,
        'exprCountA': exprCountA,
        'exprCountB': exprCountB,
        'exprDistA': exprDistanceA,
        'exprDistB': exprDistanceB,
        'distribA': patternDistName(distributionA),
        'distribB': patternDistName(distributionB),
        if (pathA != null) 'pathA': pathA!.toJson(),
        if (pathB != null) 'pathB': pathB!.toJson(),
        if (startA != 0) 'startA': startA,
        if (startB != 0) 'startB': startB,
        if (irregularA.isNotEmpty) 'irrA': _irrJson(irregularA),
        if (irregularB.isNotEmpty) 'irrB': _irrJson(irregularB),
        if (irregularC.isNotEmpty) 'irrC': _irrJson(irregularC),
        if (orientFace != null) 'orientFace': orientFace!.toJson(),
        if (axis != null) 'axis': axis!.toJson(),
        'flipC': flipC,
        'countC': countC,
        'angleC': angleC,
        'exprCountC': exprCountC,
        'exprAngleC': exprAngleC,
        'distribC': patternDistName(distributionC),
        'orient': orientation.name,
        if (pointSketch.isNotEmpty) 'pointSketch': pointSketch,
        'basePicked': basePicked,
        'baseX': baseX,
        'baseY': baseY,
        if (mirrorPlane != null) 'plane': mirrorPlane!.toJson(),
        'removeOriginal': removeOriginal,
      };

  static Map<String, double> _irrJson(Map<int, double> m) {
    final ks = m.keys.toList()..sort();
    return {for (final k in ks) '$k': m[k]!};
  }

  static Map<int, double> _irrFrom(Object? j) {
    if (j is! Map) return const {};
    final out = <int, double>{};
    j.forEach((k, v) {
      final i = int.tryParse('$k');
      if (i != null && v is num) out[i] = v.toDouble();
    });
    return out;
  }

  static PatternFeature fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? sub(String k) => j[k] == null
        ? null
        : (j[k] as Map).cast<String, dynamic>();
    final a = sub('dirA'), b = sub('dirB'), ax = sub('axis'), pl = sub('plane');
    final pa = sub('pathA'), pb = sub('pathB'), of = sub('orientFace');
    final f = PatternFeature(
      name: j['name'] as String? ?? 'Pattern',
      bodyName: j['body'] as String? ?? 'Solid1',
      mode: patternKindFrom(j['mode'] as String?),
      patternSolid: j['solid'] as bool? ?? false,
      sources: [
        for (final s in (j['sources'] as List? ?? const [])) s as String
      ],
      dirA: a == null ? null : AxisRef.fromJson(a),
      dirB: b == null ? null : AxisRef.fromJson(b),
      flipA: j['flipA'] as bool? ?? false,
      flipB: j['flipB'] as bool? ?? false,
      midplaneA: j['midA'] as bool? ?? false,
      midplaneB: j['midB'] as bool? ?? false,
      countA: (j['countA'] as num?)?.toInt() ?? 2,
      countB: (j['countB'] as num?)?.toInt() ?? 2,
      distanceA: (j['distA'] as num?)?.toDouble() ?? 25,
      distanceB: (j['distB'] as num?)?.toDouble() ?? 25,
      exprCountA: j['exprCountA'] as String? ?? '2',
      exprCountB: j['exprCountB'] as String? ?? '2',
      exprDistanceA: j['exprDistA'] as String? ?? '25 mm',
      exprDistanceB: j['exprDistB'] as String? ?? '25 mm',
      distributionA: patternDistFrom(j['distribA'] as String?),
      distributionB: patternDistFrom(j['distribB'] as String?),
      pathA: pa == null ? null : CurveSel.fromJson(pa),
      pathB: pb == null ? null : CurveSel.fromJson(pb),
      startA: (j['startA'] as num?)?.toDouble() ?? 0,
      startB: (j['startB'] as num?)?.toDouble() ?? 0,
      irregularA: _irrFrom(j['irrA']),
      irregularB: _irrFrom(j['irrB']),
      irregularC: _irrFrom(j['irrC']),
      axis: ax == null ? null : AxisRef.fromJson(ax),
      flipC: j['flipC'] as bool? ?? false,
      countC: (j['countC'] as num?)?.toInt() ?? 6,
      angleC: (j['angleC'] as num?)?.toDouble() ?? 360,
      exprCountC: j['exprCountC'] as String? ?? '6',
      exprAngleC: j['exprAngleC'] as String? ?? '360.00 deg',
      // A circular pattern's typed value is a TOTAL angle by default
      // (Inventor's Fitted), which is what makes "6 at 360" mean a bolt
      // circle rather than six full turns.
      distributionC: patternDistFrom(j['distribC'] as String? ?? 'distance'),
      orientation: (j['orient'] as String?) == 'fixed'
          ? PatternOrient.fixed
          : PatternOrient.rotational,
      pointSketch: j['pointSketch'] as String? ?? '',
      basePicked: j['basePicked'] as bool? ?? false,
      baseX: (j['baseX'] as num?)?.toDouble() ?? 0,
      baseY: (j['baseY'] as num?)?.toDouble() ?? 0,
      mirrorPlane: pl == null ? null : PlaneRef.fromJson(pl),
      removeOriginal: j['removeOriginal'] as bool? ?? false,
      compute: patternComputeFrom(j['compute'] as String?),
      orientFace: of == null ? null : FaceSel.fromJson(of),
      suppressed: {
        for (final s in (j['suppressed'] as List? ?? const []))
          (s as num).toInt()
      },
      visible: j['visible'] as bool? ?? true,
    );
    f.readBaseJson(j);
    return f;
  }
}

/// Hard ceiling on occurrences per direction. Not a style choice: every
/// occurrence is a boolean against the whole body, so a slipped decimal point
/// in a count is minutes of kernel work and an app that looks hung. Inventor
/// caps patterns for the same reason.
const int kPatternMaxCount = 512;

/// The step between neighbouring occurrences.
///
/// [PatternDistribution.spacing] means the typed value IS the step;
/// [PatternDistribution.distance] means it is the TOTAL the occurrences fill
/// and the step is that divided by the gaps. A full 360° circle has as many
/// gaps as occurrences (the last one wraps onto the first), which is why it
/// divides by [count] rather than by count - 1 — without that a "6 at 360°"
/// bolt circle puts two holes in the same place.
double patternStep(double value, int count, PatternDistribution d,
    {bool wrapsFullTurn = false, double curveLength = 0}) {
  if (d == PatternDistribution.spacing) return value;
  if (count <= 1) return value;
  // Curve Length fits the occurrences to the curve that is actually there,
  // which is the point of it: redraw the curve and the pattern re-divides.
  // Without a curve it is a Distance, because there is nothing to fit to.
  final total =
      d == PatternDistribution.curveLength && curveLength > 0 ? curveLength : value;
  return wrapsFullTurn ? total / count : total / (count - 1);
}

/// [a] then [b] — the placement that applies [b] to the result of [a].
List<double> composeMat34(List<double> a, List<double> b) {
  double r(int row, int col) =>
      b[row * 4] * a[col] +
      b[row * 4 + 1] * a[4 + col] +
      b[row * 4 + 2] * a[8 + col];
  double t(int row) =>
      b[row * 4] * a[3] +
      b[row * 4 + 1] * a[7] +
      b[row * 4 + 2] * a[11] +
      b[row * 4 + 3];
  return [
    r(0, 0), r(0, 1), r(0, 2), t(0), //
    r(1, 0), r(1, 1), r(1, 2), t(1), //
    r(2, 0), r(2, 1), r(2, 2), t(2), //
  ];
}

/// WHERE every copy of a pattern goes, as pure geometry.
///
/// Deliberately free of the kernel, the model and the app: given the feature,
/// the centre of what is being patterned and (for a sketch-driven pattern)
/// the points, this is arithmetic — and arithmetic that is wrong in a corner
/// (the 360° wrap, the midplane centring, an occurrence landing back on the
/// original) is exactly what a host test can pin down and a device cannot.
///
/// [refPoint] is the centre of the patterned geometry. It only matters for a
/// circular pattern with [PatternOrient.fixed] (where the copy travels round
/// the axis without turning) and as the default base point of a sketch-driven
/// pattern.
///
/// The ORIGINAL is never in the result: it is already in the body. Any
/// occurrence whose placement comes out as the identity — the middle one of
/// an odd midplane row, a sketch point sitting on the base point — is dropped
/// for the same reason, since building it would fuse a solid onto itself.
List<PatternOccurrence> patternOccurrences(PatternFeature f,
    {Vec3 refPoint = Vec3.zero,
    List<Vec3> points = const [],
    List<Vec3> pathA = const [],
    List<Vec3> pathB = const [],
    List<Vec3> pointNormals = const []}) {
  final out = <PatternOccurrence>[];
  switch (f.mode) {
    case PatternKind.rectangular:
      // A direction is either a straight line or a CURVE the row runs along.
      // The two produce the same thing — an offset per step — so everything
      // after this point is common.
      final onPathA = f.pathA != null && pathA.length >= 2;
      final onPathB = f.pathB != null && pathB.length >= 2;
      final a = f.dirA;
      if (!onPathA && (a == null || !a.valid)) return const [];
      final ua = onPathA
          ? Vec3.zero
          : a!.unit * (f.flipA ? -1.0 : 1.0);
      final b = f.dirB;
      final hasB = onPathB || (b != null && b.valid);
      final ub = (b != null && b.valid) ? b.unit * (f.flipB ? -1.0 : 1.0) : null;
      final na = f.countA.clamp(1, kPatternMaxCount);
      final nb = hasB ? f.countB.clamp(1, kPatternMaxCount) : 1;
      final lenA = onPathA ? polylineLength(pathA) : 0.0;
      final lenB = onPathB ? polylineLength(pathB) : 0.0;
      final sa = patternStep(f.distanceA, na, f.distributionA,
          curveLength: lenA - f.startA);
      final sb = patternStep(f.distanceB, nb, f.distributionB,
          curveLength: lenB - f.startB);
      // Midplane centres the SPAN on the original: with an odd count one
      // occurrence lands on it (and is dropped as the identity), with an even
      // count the original sits between the two middle ones. That is what
      // "distributed on both sides of the original feature" describes.
      final oa = f.midplaneA ? (na - 1) / 2.0 : 0.0;
      final ob = f.midplaneB ? (nb - 1) / 2.0 : 0.0;
      // An irregular entry REPLACES the even offset of that step, so nothing
      // downstream has to know which occurrences are irregular.
      double offA(int i) => f.irregularA[i] ?? (i - oa) * sa;
      double offB(int i) => f.irregularB[i] ?? (i - ob) * sb;
      // On a path the offsets are arc lengths, so the base point and the base
      // tangent are read once and every step measured against them.
      final baseA = onPathA ? pointAtArcLength(pathA, f.startA) : null;
      final baseB = onPathB ? pointAtArcLength(pathB, f.startB) : null;
      if (onPathA && baseA == null) return const [];
      for (var ib = 0; ib < nb; ib++) {
        for (var ia = 0; ia < na; ia++) {
          List<double> m;
          if (onPathA) {
            final at = pointAtArcLength(pathA, f.startA + offA(ia));
            if (at == null) continue;
            var d = at.$1 - baseA!.$1;
            if (onPathB && baseB != null) {
              final atB = pointAtArcLength(pathB, f.startB + offB(ib));
              if (atB != null) d = d + (atB.$1 - baseB.$1);
            } else if (ub != null) {
              d = d + ub * offB(ib);
            }
            m = translationMat34(d);
            // Inventor's Orientation Method: Identical keeps the parent's
            // attitude, Direction 1 turns each copy to follow the curve.
            if (f.orientation == PatternOrient.rotational) {
              final turn = rotationBetween(baseA.$2, at.$2, at.$1);
              m = composeMat34(m, turn);
            }
          } else {
            var d = ua * offA(ia);
            if (onPathB && baseB != null) {
              final atB = pointAtArcLength(pathB, f.startB + offB(ib));
              if (atB != null) d = d + (atB.$1 - baseB.$1);
            } else if (ub != null) {
              d = d + ub * offB(ib);
            }
            m = translationMat34(d);
          }
          if (isIdentityMat34(m)) continue;
          out.add(PatternOccurrence(1 + ia + ib * na, m));
        }
      }
      return out;
    case PatternKind.circular:
      final ax = f.axis;
      if (ax == null || !ax.valid) return const [];
      final k = ax.unit * (f.flipC ? -1.0 : 1.0);
      final n = f.countC.clamp(1, kPatternMaxCount);
      final full = (f.angleC.abs() - 360).abs() < 1e-9;
      final stepDeg = patternStep(f.angleC, n, f.distributionC,
          wrapsFullTurn: full && f.distributionC == PatternDistribution.distance);
      for (var i = 1; i < n; i++) {
        final ang = (f.irregularC[i] ?? stepDeg * i) * math.pi / 180.0;
        final rot = rotationMat34(ax.point, k, ang);
        // Fixed orientation: the copy travels to where the rotation would put
        // it and keeps the parent's attitude — so the placement is the pure
        // translation from the reference point to its rotated image.
        final m = f.orientation == PatternOrient.fixed
            ? translationMat34(
                _applyMat34(rot, refPoint) - refPoint)
            : rot;
        if (isIdentityMat34(m)) continue;
        out.add(PatternOccurrence(1 + i, m));
      }
      return out;
    case PatternKind.sketchDriven:
      if (points.isEmpty) return const [];
      final base = f.basePicked ? points.first : refPoint;
      // Inventor's Variable Orientation: with a face picked, each copy is
      // turned from the surface normal AT THE ORIGINAL to the one where it
      // lands, so a boss on a curved shell stands up out of the shell.
      // [pointNormals] is parallel to [points]; an empty list is the plain
      // "Identical" orientation and every copy is a pure translation.
      final follow = f.orientFace != null &&
          pointNormals.length == points.length &&
          points.isNotEmpty;
      final n0 = follow ? pointNormals.first : Vec3.zero;
      for (var i = 0; i < points.length; i++) {
        var m = translationMat34(points[i] - base);
        if (follow && i > 0) {
          m = composeMat34(m, rotationBetween(n0, pointNormals[i], points[i]));
        }
        if (isIdentityMat34(m)) continue;
        out.add(PatternOccurrence(1 + i, m));
      }
      return out;
    case PatternKind.mirror:
      final p = f.mirrorPlane;
      if (p == null || !p.valid) return const [];
      return const [PatternOccurrence(2, null, mirror: true)];
  }
}

/// Total length of a world-space polyline.
double polylineLength(List<Vec3> pts) {
  var l = 0.0;
  for (var i = 1; i < pts.length; i++) {
    l += (pts[i] - pts[i - 1]).length;
  }
  return l;
}

/// Point and unit tangent at arc length [s] along [pts].
///
/// Beyond either end the last segment is EXTENDED rather than clamped: a
/// pattern whose count overruns its curve then keeps its spacing and walks
/// off the end (visibly wrong, and fixable by reading the number), instead of
/// silently stacking every remaining occurrence on the final point.
(Vec3, Vec3)? pointAtArcLength(List<Vec3> pts, double s) {
  if (pts.length < 2) return null;
  if (s <= 0) {
    final d = (pts[1] - pts[0]);
    if (d.length < 1e-12) return null;
    final t = d.normalized();
    return (pts[0] + t * s, t);
  }
  var acc = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final seg = pts[i] - pts[i - 1];
    final len = seg.length;
    if (len < 1e-12) continue;
    if (acc + len >= s || i == pts.length - 1) {
      final t = seg.normalized();
      return (pts[i - 1] + t * (s - acc), t);
    }
    acc += len;
  }
  return null;
}

/// Arc length of the point on [pts] nearest [q] — Inventor's Start point,
/// picked by tapping the curve.
double arcLengthNearest(List<Vec3> pts, Vec3 q) {
  var acc = 0.0, best = 0.0, bestD = double.infinity;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final seg = b - a;
    final len = seg.length;
    if (len < 1e-12) continue;
    final t = ((q - a).dot(seg) / (len * len)).clamp(0.0, 1.0);
    final d = (a + seg * t - q).length;
    if (d < bestD) {
      bestD = d;
      best = acc + t * len;
    }
    acc += len;
  }
  return best;
}

/// The rotation that takes unit [from] onto unit [to], as a 3x4 placement
/// about the point [about]. The identity when they already agree, and a
/// half-turn about any perpendicular when they oppose (the axis is
/// undetermined there, and refusing would be worse than choosing one).
List<double> rotationBetween(Vec3 from, Vec3 to, Vec3 about) {
  final a = from.normalized(), b = to.normalized();
  final d = a.dot(b).clamp(-1.0, 1.0);
  if (d > 1 - 1e-12) return translationMat34(Vec3.zero);
  var axis = a.cross(b);
  if (axis.length < 1e-9) {
    // opposite: any perpendicular will do, so take the most stable one
    final ref = a.x.abs() < 0.9 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
    axis = a.cross(ref);
  }
  return rotationMat34(about, axis.normalized(), math.acos(d));
}

/// Applies a row-major 3x4 placement to a point.
Vec3 _applyMat34(List<double> m, Vec3 p) => Vec3(
      m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3],
      m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7],
      m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11],
    );

/// The sketch frame an occurrence's copy of a feature is built in.
///
/// Only needed by [PatternCompute.adjust], which rebuilds each occurrence
/// where it lands instead of copying the finished solid. Moving the FRAME is
/// what makes the rebuild resolve "To Next" / "Through All" against the body
/// under that occurrence — the profile numbers never change, only the plane
/// they are read on.
PlaneFrame placedFrame(PlaneFrame f, List<double> m) {
  Vec3 rot(Vec3 v) => Vec3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[4] * v.x + m[5] * v.y + m[6] * v.z,
        m[8] * v.x + m[9] * v.y + m[10] * v.z,
      );
  return PlaneFrame(
      f.key, rot(f.u), rot(f.v), rot(f.n), _applyMat34(m, f.origin));
}

/// The sketch frame of a MIRRORED occurrence.
///
/// A reflection maps a right-handed frame to a left-handed one, and a
/// left-handed frame is not a placement any kernel will accept. Negating v
/// restores the handedness (u × v = n again) at the price of reading the
/// profile mirrored in v — which is why this comes with [mirrorProfilesInV]
/// and why the two must always travel together. Reflecting the frame and
/// forgetting the profile silently builds the ORIGINAL shape at the mirrored
/// place: right position, wrong part.
PlaneFrame mirroredFrame(PlaneFrame f, Vec3 planePoint, Vec3 planeNormal) {
  final n = planeNormal.normalized();
  Vec3 refl(Vec3 v) => v - n * (2 * v.dot(n));
  final o = f.origin - n * (2 * (f.origin - planePoint).dot(n));
  return PlaneFrame(f.key, refl(f.u), refl(f.v) * -1.0, refl(f.n), o);
}

// ---------------------------------------------------------------------------
// part document
// ---------------------------------------------------------------------------
/// M153 — a live planar face, reduced to the three numbers that identify it.
///
/// Centroid and area come from the display mesh rather than the B-Rep, because
/// the mesh is what we already have on the Dart side after every rebuild.
class FaceRec {
  final int id;
  final Vec3 c; // centroid
  final Vec3 n; // outward normal
  final double area;
  const FaceRec(this.id, this.c, this.n, this.area);
}

// ---------------------------------------------------------------------------
// M213 — FACE PROVENANCE: which feature made this face?
// ---------------------------------------------------------------------------
//
// Inventor lets you select a feature by clicking one of its faces in the
// graphics window. Until now this build could not: the fold leaves ONE solid
// per body, and a face of that solid knows nothing about the extrusion or
// fillet it came from. OCCT's own boolean history (Modified/Generated) is not
// exposed by the shim, and threading it through every operation would mean a
// new ABI for every kind of feature.
//
// So provenance is recovered GEOMETRICALLY, from something the fold already
// has: each feature's own solid, at the moment before it is combined away.
// A boolean trims faces, but it does not move them — the face of a result
// still lies on a surface that one of the operands brought. Matching the
// SURFACE (the infinite plane, the whole cylinder) rather than the trimmed
// patch is what makes this survive the trimming.
//
// It is a heuristic, and it says so: a face whose surface no feature claims
// is reported as unknown rather than attributed to the nearest guess.

/// The surface a mesh face lies on, plus where its triangles actually are.
///
/// [type] follows the shim's face record (0 plane, 1 cylinder, 2 cone,
/// 3 sphere, 4 torus, 5 other). Only plane and cylinder carry analytic
/// parameters there; for the rest the record is empty and only the extent is
/// available, which is why [sameSurfaceAs] falls back to containment for them.
class FaceSurface {
  final int id; // mesh face index
  final int type;
  final Vec3 p; // point on the plane / on the axis
  final Vec3 d; // plane normal / axis direction
  final double radius;
  final Vec3 lo, hi; // bounding box of this face's triangles
  final Vec3 centroid;
  final double area;

  const FaceSurface(this.id, this.type, this.p, this.d, this.radius, this.lo,
      this.hi, this.centroid, this.area);

  bool contains(Vec3 q, double tol) =>
      q.x >= lo.x - tol &&
      q.x <= hi.x + tol &&
      q.y >= lo.y - tol &&
      q.y <= hi.y + tol &&
      q.z >= lo.z - tol &&
      q.z <= hi.z + tol;

  /// Do these two faces lie on the SAME surface?
  ///
  /// Orientation is deliberately ignored: cutting a cylinder out of a block
  /// leaves a wall whose normal points into the hole, i.e. opposite to the
  /// tool's outward normal, and it is still the same cylinder. That is the
  /// whole reason a cut can be attributed at all.
  bool sameSurfaceAs(FaceSurface o, double tol) {
    if (type != o.type) return false;
    switch (type) {
      case 0:
        if (d.dot(o.d).abs() < 1 - 1e-6) return false;
        // same infinite plane: the offsets along the shared normal agree
        return (p.dot(d) - o.p.dot(d)).abs() <= tol;
      case 1:
        if (d.dot(o.d).abs() < 1 - 1e-6) return false;
        if ((radius - o.radius).abs() > tol) return false;
        // the two axis LINES must coincide, not merely be parallel
        final v = o.p - p;
        final perp = v - d * v.dot(d);
        return perp.length <= tol;
      default:
        // No analytic record from the shim for cones, spheres, tori and
        // splines. What is left is where the face IS, which is enough as long
        // as it is not dressed up as more than it is.
        return contains(o.centroid, tol) || o.contains(centroid, tol);
    }
  }
}

/// One [FaceSurface] per triangulated face of [m], or empty when the mesh
/// carries no face metadata (a test fake, a legacy mesh) — and "empty" must
/// be read as "unknown", never as "this solid has no faces".
List<FaceSurface> faceSurfaces(OcctMeshData m) {
  if (m.faceInfos.isEmpty || m.triFaces.length * 3 != m.indices.length) {
    return const [];
  }
  final n = m.faceCount;
  if (n <= 0) return const [];
  // Flat accumulators rather than lists of Vec3. This loop runs once per
  // triangle of every mesh on every rebuild, and the Vec3 form allocated
  // roughly sixteen short-lived objects per triangle — about 23 000 of them
  // for the 1436-triangle body of §8.1. The arithmetic below is the same
  // arithmetic in the same order, so the values are bit-identical to the
  // version this replaces; only the allocations are gone.
  final lo = Float64List(n * 3)..fillRange(0, n * 3, 1e30);
  final hi = Float64List(n * 3)..fillRange(0, n * 3, -1e30);
  final cen = Float64List(n * 3);
  final ar = Float64List(n);
  final pos = m.positions, idx = m.indices, tri = m.triFaces;
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final f = tri[t ~/ 3];
    if (f < 0 || f >= n) continue;
    final i0 = idx[t] * 3, i1 = idx[t + 1] * 3, i2 = idx[t + 2] * 3;
    final ax = pos[i0], ay = pos[i0 + 1], az = pos[i0 + 2];
    final bx = pos[i1], by = pos[i1 + 1], bz = pos[i1 + 2];
    final cx = pos[i2], cy = pos[i2 + 1], cz = pos[i2 + 2];
    // (b - a) cross (c - a), half its length: the triangle's area.
    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final vx = cx - ax, vy = cy - ay, vz = cz - az;
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    final w = math.sqrt(nx * nx + ny * ny + nz * nz) * 0.5;
    // Area-weighted, like planarFaceRecs: a face tessellated into one big
    // triangle and twenty slivers still reports its true centre.
    final w3 = w / 3;
    final o = f * 3;
    cen[o] = cen[o] + (ax + bx + cx) * w3;
    cen[o + 1] = cen[o + 1] + (ay + by + cy) * w3;
    cen[o + 2] = cen[o + 2] + (az + bz + cz) * w3;
    ar[f] += w;
    lo[o] = math.min(math.min(math.min(lo[o], ax), bx), cx);
    lo[o + 1] = math.min(math.min(math.min(lo[o + 1], ay), by), cy);
    lo[o + 2] = math.min(math.min(math.min(lo[o + 2], az), bz), cz);
    hi[o] = math.max(math.max(math.max(hi[o], ax), bx), cx);
    hi[o + 1] = math.max(math.max(math.max(hi[o + 1], ay), by), cy);
    hi[o + 2] = math.max(math.max(math.max(hi[o + 2], az), bz), cz);
  }
  final out = <FaceSurface>[];
  for (var f = 0; f < n; f++) {
    if (ar[f] <= 0) continue;
    final r = 15 * f;
    if (r + 15 > m.faceInfos.length) break;
    final o = f * 3;
    out.add(FaceSurface(
      f,
      m.faceInfos[r].round(),
      Vec3(m.faceInfos[r + 1], m.faceInfos[r + 2], m.faceInfos[r + 3]),
      Vec3(m.faceInfos[r + 4], m.faceInfos[r + 5], m.faceInfos[r + 6])
          .normalized(),
      m.faceInfos[r + 10],
      Vec3(lo[o], lo[o + 1], lo[o + 2]),
      Vec3(hi[o], hi[o + 1], hi[o + 2]),
      Vec3(cen[o], cen[o + 1], cen[o + 2]) * (1 / ar[f]),
      ar[f],
    ));
  }
  return out;
}

/// Tolerance for surface matching, in mm. Generous on purpose: the display
/// mesh is a coarse tessellation, so a plane's sampled points sit up to the
/// deflection off the true surface, and a provenance answer that is right
/// 99% of the time and admits the rest beats one that is silently wrong.
const double kFaceMatchTol = 0.05;

/// Cell width of the direction index [newSurfacesOf] builds over its base
/// list, and the number of cells the key's range needs at that width.
///
/// [FaceSurface.sameSurfaceAs] can only answer true when the two faces have
/// the same `type`, and for a plane (0) or a cylinder (1) only when their axes
/// are parallel to within `|d·o.d| >= 1 - 1e-6`. Both are NECESSARY conditions,
/// so an index built on them and followed by the original predicate returns
/// the identical boolean — it only skips pairs that could never have matched.
///
/// The key is `|d.x| + 2|d.y| + 4|d.z|`. Absolute values, because the match
/// deliberately ignores which way a normal points; componentwise `|.|` is
/// continuous, where flipping a normal into a canonical hemisphere is not and
/// would drop two nearly-parallel faces into distant cells.
///
/// Why probing one cell either side cannot miss a match: for unit u, v with
/// `|u·v| >= 1 - 1e-6`, and s = sign(u·v),
///
///     |u - s.v|^2 = |u|^2 + |v|^2 - 2|u·v| <= 2 - 2(1 - 1e-6) = 2e-6
///     |u - s.v|   <= 1.4143e-3
///
/// hence `||u_i| - |v_i|| <= 1.4143e-3` for each component, hence by
/// Cauchy-Schwarz
///
///     |key(u) - key(v)| <= sqrt(1 + 4 + 16) * 1.4143e-3 = 6.4808e-3
///
/// A cell at least that wide therefore holds any matching pair in the same
/// cell or in one of its neighbours. 7e-3 leaves 8 % of margin over the bound.
const double _kDirCell = 7e-3;

/// ceil(sqrt(21) / [_kDirCell]) — sqrt(21) = 4.5826 is the key's maximum.
const int _kDirCells = 655;

/// Below this many base faces the index costs more to build than the scan it
/// replaces, so [newSurfacesOf] keeps the straight loop. The answer is the
/// same either way; only the arithmetic that produces it differs.
const int _kDirIndexMin = 64;

double _dirKey(Vec3 d) => d.x.abs() + 2 * d.y.abs() + 4 * d.z.abs();

/// Whether [d] is a unit vector, which the bound above assumes.
///
/// `Vec3.normalized()` hands back its input unchanged when the length is below
/// 1e-12, so a face with a degenerate normal reaches here un-normalised. Such
/// a face can never match anything (the dot product against any unit vector is
/// far below the threshold), but rather than rely on that it is kept out of
/// the index and scanned every time. NaN fails these comparisons too, which is
/// the wanted answer for the same reason.
bool _isUnitDir(Vec3 d) {
  final q = d.dot(d);
  return q > 1 - 1e-9 && q < 1 + 1e-9;
}

/// The cell a face belongs in, or -1 for one the index cannot place: a cone,
/// sphere, torus or spline (type >= 2), which matches by bounding box and so
/// has no direction condition at all, or a degenerate normal.
int _dirCellOf(FaceSurface f) {
  if (f.type != 0 && f.type != 1) return -1;
  if (!_isUnitDir(f.d)) return -1;
  var q = (_dirKey(f.d) / _kDirCell).floor();
  if (q < 0) q = 0;
  if (q >= _kDirCells) q = _kDirCells - 1;
  return (f.type == 0 ? 0 : _kDirCells) + q;
}

/// A base face list arranged so that [anyMatch] only has to test the faces
/// that could possibly match — a counting sort into [_kDirCells] cells per
/// matchable type, plus a tail of faces the index cannot place.
///
/// Purely an accelerator: [anyMatch] returns exactly what
/// `base.any((b) => b.sameSurfaceAs(f, tol))` returns, for every input. The
/// predicate has no side effects, so short-circuiting on a different element
/// of the list cannot change the answer.
class _DirIndex {
  _DirIndex._(this._base, this._cellStart, this._order, this._loose);

  final List<FaceSurface> _base;
  final Int32List _cellStart; // 2 * _kDirCells + 1 entries: cell c is
  final Int32List _order; //     _order[_cellStart[c] .. _cellStart[c+1])
  final List<FaceSurface> _loose;

  factory _DirIndex.of(List<FaceSurface> base) {
    final n = base.length;
    final start = Int32List(2 * _kDirCells + 1);
    final cell = Int32List(n);
    final loose = <FaceSurface>[];
    var placed = 0;
    for (var i = 0; i < n; i++) {
      final c = _dirCellOf(base[i]);
      cell[i] = c;
      if (c < 0) {
        loose.add(base[i]);
        continue;
      }
      start[c + 1]++;
      placed++;
    }
    for (var c = 0; c < 2 * _kDirCells; c++) {
      start[c + 1] += start[c];
    }
    final order = Int32List(placed);
    final cursor = Int32List.fromList(start);
    for (var i = 0; i < n; i++) {
      final c = cell[i];
      if (c >= 0) order[cursor[c]++] = i;
    }
    return _DirIndex._(base, start, order, loose);
  }

  bool anyMatch(FaceSurface f, double tol) {
    // The tail first: it holds every base face the cells cannot speak for.
    for (final b in _loose) {
      if (b.sameSurfaceAs(f, tol)) return true;
    }
    final c = _dirCellOf(f);
    if (c < 0) {
      // A query the index cannot place. Its own type could only match faces
      // already in the tail, and a degenerate normal matches nothing at all —
      // but scanning everything is what makes the answer provably the same,
      // and this path is reached only by degenerate or non-analytic faces.
      for (final b in _base) {
        if (b.sameSurfaceAs(f, tol)) return true;
      }
      return false;
    }
    // The three cells are adjacent in `_order`, so one walk covers them. The
    // clamp keeps the probe inside this type's own block of cells.
    final tb = f.type == 0 ? 0 : _kDirCells;
    final q = c - tb;
    final from = tb + (q > 0 ? q - 1 : 0);
    final to = tb + (q < _kDirCells - 1 ? q + 1 : _kDirCells - 1);
    for (var k = _cellStart[from]; k < _cellStart[to + 1]; k++) {
      if (_base[_order[k]].sameSurfaceAs(f, tol)) return true;
    }
    return false;
  }
}

/// The faces of [result] that [base] did not already have — what a
/// body-modifying feature (a fillet, a pattern) actually ADDED.
///
/// Without this a fillet would claim every face of the body it modified,
/// which is worse than claiming none: clicking the front face of a block
/// would select the fillet at the far corner.
///
/// Measured quadratic — k = 1.96, R^2 = 1.0000, face count x13.9 giving time
/// x144 (§8.1) — because the plain form asks every base face about every
/// result face. [_DirIndex] cuts the pairs actually tested by about 22x on the
/// profile's fixture without changing a single answer; see its doc comment for
/// why the filter cannot drop a match. It does NOT change the exponent, which
/// stays at 2: any scalar key on the unit sphere has stationary points, and
/// cell occupancy near one grows as sqrt(n).
List<FaceSurface> newSurfacesOf(
    List<FaceSurface> result, List<FaceSurface> base) {
  if (base.isEmpty) return result;
  if (base.length < _kDirIndexMin) {
    return [
      for (final f in result)
        if (!base.any((b) => b.sameSurfaceAs(f, kFaceMatchTol))) f
    ];
  }
  final index = _DirIndex.of(base);
  return [
    for (final f in result)
      if (!index.anyMatch(f, kFaceMatchTol)) f
  ];
}

/// Which feature made each face of [solid]: face id -> feature name.
///
/// Rules, in order:
///   * a feature only claims a face lying on a surface it contributed;
///   * among several claimants, one whose own face CONTAINED that face wins
///     over one that merely shares an infinite plane;
///   * otherwise the LATEST claimant wins, because a later feature is what
///     you see: it cut or joined over the earlier one.
/// A face nobody claims is absent from the map — unknown, not guessed.
Map<int, String> attributeFaces(
    PartModel part, String bodyName, KernelSolid solid) {
  final faces = faceSurfaces(solid.mesh);
  final out = <int, String>{};
  if (faces.isEmpty) return out;
  for (final f in faces) {
    String? best;
    var bestContained = false;
    for (final g in part.features) {
      if (g.bodyName != bodyName || g.rolledBack) continue;
      for (final s in g.ownSurfaces) {
        if (!s.sameSurfaceAs(f, kFaceMatchTol)) continue;
        final contained = s.contains(f.centroid, kFaceMatchTol);
        // Later wins, but a containment beats a bare surface match even from
        // an earlier feature — that is the difference between "the same
        // infinite plane" and "this piece of material".
        if (best == null || contained || !bestContained) {
          best = g.name;
          bestContained = contained;
        }
        break;
      }
    }
    if (best != null) out[f.id] = best;
  }
  return out;
}

/// Planar faces of a mesh, with centroid and area accumulated per face id.
///
/// Triangle area weights the centroid, so a face tessellated into one big and
/// twenty slivers still reports its true centre rather than being dragged
/// toward the busy corner.
List<FaceRec> planarFaceRecs(OcctMeshData m) {
  if (m.triFaces.isEmpty || m.faceInfos.isEmpty) return const [];
  final cx = <int, Vec3>{};
  final ar = <int, double>{};
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final f = m.triFaces[t ~/ 3];
    if (f < 0 || 15 * f >= m.faceInfos.length) continue;
    // Surface type 0 = plane (occt_capi.h, per-face record). Not the
    // kFacePlane constant: it lives in part_render, which imports this file.
    if (m.faceInfos[15 * f].round() != 0) continue;
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final tri = (b - a).cross(c - a).length / 2;
    if (tri <= 0) continue;
    final mid = (a + b + c) * (1 / 3);
    cx[f] = (cx[f] ?? Vec3.zero) + mid * tri;
    ar[f] = (ar[f] ?? 0) + tri;
  }
  final out = <FaceRec>[];
  ar.forEach((f, area) {
    if (area <= 0) return;
    final n = Vec3(m.faceInfos[15 * f + 4], m.faceInfos[15 * f + 5],
            m.faceInfos[15 * f + 6])
        .normalized();
    out.add(FaceRec(f, cx[f]! * (1 / area), n, area));
  });
  return out;
}

/// M153 — which face a sketch was drawn on, so it can be found again.
///
/// The twin of [EdgeSel] (and unrelated to [FaceSel], which records the
/// to-face extent of an extrude), and it exists for the same reason: face indices are
/// not stable across a rebuild, so a sketch that stored one would follow
/// whatever face inherited the number. Until now a sketch-on-face stored only
/// its baked frame (M58) and therefore did not follow the face AT ALL —
/// change an extrusion's height and the face moved out from under the sketch.
///
/// The fingerprint is centroid + normal + area, chosen so that the one motion
/// we MUST follow is free and everything else is penalised:
///   * movement ALONG the normal is what "the extrusion got taller" looks
///     like, so it is nearly free;
///   * sideways drift is penalised, because that is a different face;
///   * AREA separates coaxial faces — the top of a boss and the top of the
///     cylinder under it share a normal and very nearly share a centroid axis,
///     which is exactly the confusion that put a chamfer on the wrong rim in
///     M152.
class SketchFaceSel {
  double cx, cy, cz;
  double nx, ny, nz;
  double area;

  SketchFaceSel(this.cx, this.cy, this.cz, this.nx, this.ny, this.nz, this.area);

  factory SketchFaceSel.of(FaceRec f) =>
      SketchFaceSel(f.c.x, f.c.y, f.c.z, f.n.x, f.n.y, f.n.z, f.area);

  Vec3 get c => Vec3(cx, cy, cz);
  Vec3 get n => Vec3(nx, ny, nz);

  Map<String, dynamic> toJson() =>
      {'c': [cx, cy, cz], 'n': [nx, ny, nz], 'a': area};

  static SketchFaceSel? fromJson(Map<String, dynamic> j) {
    final c = (j['c'] as List?)?.cast<num>();
    final n = (j['n'] as List?)?.cast<num>();
    if (c == null || c.length != 3 || n == null || n.length != 3) return null;
    return SketchFaceSel(c[0].toDouble(), c[1].toDouble(), c[2].toDouble(),
        n[0].toDouble(), n[1].toDouble(), n[2].toDouble(),
        (j['a'] as num?)?.toDouble() ?? 0);
  }

  /// Distance between this fingerprint and a live face. Lower is better.
  double score(FaceRec f) {
    // A face that turned to point elsewhere is not this face any more. Sign
    // matters: the top and the bottom of a plate are parallel and opposite.
    if (n.dot(f.n) < 0.999) return double.infinity;
    final d = f.c - c;
    final along = d.dot(f.n);
    final inPlane = (d - f.n * along).length;
    final scale = math.sqrt(math.max(area, 1e-9));
    final rel = area > 0 && f.area > 0
        ? (f.area - area).abs() / math.max(area, f.area)
        : 0.0;
    return inPlane + 2.0 * scale * rel + 0.05 * along.abs();
  }

  /// The live face this selection now refers to, or null when it is gone.
  FaceRec? bestMatch(List<FaceRec> faces) {
    FaceRec? best;
    var bestScore = double.infinity;
    for (final f in faces) {
      final s = score(f);
      if (s < bestScore) {
        bestScore = s;
        best = f;
      }
    }
    if (best == null) return null;
    // Tolerance scales with the face's own size — a 200 mm plate may drift
    // further than a 2 mm pad before it stops being the same face.
    final tol = 0.5 * (math.sqrt(math.max(area, 1e-9)) + 1.0);
    return bestScore <= tol ? best : null;
  }

  /// How far the matched face has moved ALONG its normal since the last
  /// anchor. This is the number the sketch's frame has to be shifted by, and
  /// only this one: shifting in-plane would move the drawing across the face.
  double alongTo(FaceRec f) => (f.c - c).dot(f.n);

  void reanchor(FaceRec f) {
    cx = f.c.x;
    cy = f.c.y;
    cz = f.c.z;
    nx = f.n.x;
    ny = f.n.y;
    nz = f.n.z;
    area = f.area;
  }
}

class ChildSketch {
  final SketchModel model;
  final String plane; // 'xy' | 'yz' | 'xz' | 'face'
  /// Set iff plane == 'face'. MUTABLE since M153: the frame is re-anchored
  /// onto the live face after every rebuild.
  PlaneFrame? face;

  /// Inventor semantics: a sketch stays visible in the 3D scene until a
  /// feature consumes it; consumption turns visibility OFF, and the browser
  /// eye can turn it back on (persisted).
  bool visible;

  /// M84 — Inventor's **Share Sketch**. A sketch is normally CONSUMED by the
  /// first feature that uses it and disappears under that feature in the
  /// browser; sharing is the documented escape hatch that makes it available
  /// to a second feature ("Selects a sketch already used in a feature for use
  /// in a new feature", Part Browser Reference). A shared sketch keeps its
  /// nested instance under the parent feature AND appears at the top level,
  /// which is exactly what Inventor shows.
  ///
  /// False for every sketch that existed before M84, so old documents load
  /// with today's behaviour unchanged.
  bool shared;

  /// M113 — suppressed because it sits below the End of Part marker. Derived
  /// from [PartModel.eopAfter] on every apply, never persisted — exactly like
  /// [ExtrudeFeature.rolledBack].
  bool rolledBack = false;

  /// M91 — creation order. The browser is a TIMELINE: a new sketch belongs at
  /// the bottom, under the extrusions that already exist, not in a sketches
  /// block above them. Persisted; documents from before M91 get sequence
  /// numbers on load in their old list order, so they open looking exactly as
  /// they did.
  int seq;

  /// M153 — WHICH face this sketch was drawn on, when it was drawn on one.
  ///
  /// [face] alone is the frame baked at pick time (M58) and does not survive
  /// the face moving: change an extrusion's height and the sketch stayed at
  /// the old height while its face walked off. This is the fingerprint that
  /// finds the face again after a rebuild, so the frame can be shifted to
  /// follow it. Null for origin-plane sketches, and null for sketches made
  /// before this milestone — which simply keep the old frozen behaviour
  /// instead of guessing.
  SketchFaceSel? faceRef;

  ChildSketch(this.model, this.plane,
      [this.face, this.visible = true, this.shared = false, this.seq = 0,
      this.faceRef]);
}

/// M153 — move every sketch-on-face back onto its face.
///
/// Called after each rebuild. For each sketch with a [ChildSketch.faceRef],
/// find the live face it now refers to and shift the frame ALONG THE NORMAL by
/// however far that face moved. Only along the normal: an in-plane shift would
/// slide the drawing across the face, and the whole point is that the sketch
/// keeps its 2D coordinates and simply arrives at the new height.
///
/// A face that cannot be found is left alone rather than guessed at. A sketch
/// stuck at the old height is a visible, fixable problem; a sketch silently
/// relocated onto a different face is the bug M152 just finished paying for.
int reanchorFaceSketches(PartModel part) {
  final live = <FaceRec>[];
  for (final f in part.features) {
    final sol = f.solid;
    if (sol != null) live.addAll(planarFaceRecs(sol.mesh));
  }
  if (live.isEmpty) return 0;
  var moved = 0;
  for (final cs in part.childSketches) {
    final ref = cs.faceRef;
    final fr = cs.face;
    if (ref == null || fr == null) continue;
    final m = ref.bestMatch(live);
    if (m == null) continue;
    final d = ref.alongTo(m);
    ref.reanchor(m);
    if (d.abs() < 1e-9) continue;
    cs.face = PlaneFrame(fr.key, fr.u, fr.v, fr.n, fr.origin + fr.n * d);
    moved++;
  }
  return moved;
}

/// Every feature that uses [sketchName] (Inventor's Unshare is only offered
/// while exactly ONE feature does).
List<PartFeature> consumersOf(PartModel part, String sketchName) =>
    [for (final f in part.features) if (f.sketchName == sketchName) f];

/// Whether [cs] is currently consumed by a feature — Inventor greys out
/// "Share Sketch" for an unconsumed sketch, because there is nothing to free
/// it from.
bool sketchIsConsumed(PartModel part, ChildSketch cs) =>
    firstConsumerOf(part, cs.model.name) != null;

/// Inventor's rule, verbatim: "You can unshare a sketch or feature only if a
/// single feature shares it and it is next to the feature in the browser."
/// The second half is a browser-ordering condition that our tree has no
/// equivalent for (the shared copy is always rendered directly at top level),
/// so only the single-consumer half is enforced.
bool canUnshareSketch(PartModel part, ChildSketch cs) =>
    cs.shared && consumersOf(part, cs.model.name).length == 1;

/// The first feature that consumes [sketchName], or null (Inventor nests the
/// consumed sketch under exactly this feature in the browser).
PartFeature? firstConsumerOf(PartModel part, String sketchName) {
  for (final f in part.features) {
    if (f.sketchName == sketchName) return f;
  }
  return null;
}

/// The working frame of a child sketch: its stored face frame, or the fixed
/// origin-plane frame. EVERY consumer of a sketch's plane goes through this.
PlaneFrame sketchFrameOf(ChildSketch cs) => cs.face ?? planeFrame(cs.plane);

/// End of Part "after everything". Not a row count — see [PartModel.eopAfter].
const int kEopAtEnd = 1 << 30;

class PartModel {
  final String name;
  final List<ChildSketch> childSketches = [];
  final List<PartFeature> features = [];

  /// M151 — user-created work planes, in creation order.
  final List<WorkPlane> workPlanes = [];

  /// M215 — user-created work axes and work points, in creation order.
  ///
  /// Three parallel lists rather than one heterogeneous one, for the reason
  /// the browser already documents about work planes: these are NOT
  /// [partTimeline] nodes. That list is what the End of Part marker indexes
  /// into, and a work feature is not rolled back by EOP. They are interleaved
  /// into the browser by `seq` and the marker keeps counting only the
  /// timeline's own rows.
  final List<WorkAxis> workAxes = [];
  final List<WorkPoint> workPoints = [];

  /// Every work feature's seq, for the browser's interleave.
  Iterable<int> get workFeatureSeqs => [
        for (final w in workPlanes) w.seq,
        for (final a in workAxes) a.seq,
        for (final pt in workPoints) pt.seq,
      ];

  /// Origin-item visibility (all invisible by default, like the mock).
  final Map<String, bool> vis = {
    'yz': false,
    'xz': false,
    'xy': false,
    'x': false,
    'y': false,
    'z': false,
    'cp': false,
  };
  final PartCamera camera = PartCamera();

  /// M91 — **End of Part**, the part-level twin of the sketch's End of Sketch
  /// marker: the number of FEATURES above it. Features from this index on are
  /// rolled back — not computed into the body, not drawn, greyed in the
  /// browser — which is Inventor's EOP.
  ///
  /// M113 — counted in TIMELINE NODES, not features.
  ///
  /// It used to count features, which meant a sketch had no slot at all and
  /// the marker could never stand above one. Four attempts were spent trying
  /// to fix that in the browser's row arithmetic before the obvious answer:
  /// the model had no position there to map to. Inventor rolls sketches back
  /// too, so now every browser row is a slot, slot == row, and the whole
  /// row-to-slot conversion is gone.
  /// Rows the End of Part marker sits after.
  ///
  /// [kEopAtEnd] means "after everything", and is deliberately a sentinel
  /// rather than the current row count: stored as a number, dragging the
  /// marker to the bottom and then creating a feature would leave the marker
  /// BEFORE the new feature and suppress it — so every feature made after ever
  /// touching the marker came out invisible.
  int eopAfter = kEopAtEnd;

  /// True when nothing is suppressed.
  bool get eopAtEnd => eopAfter >= partTimeline(this).length;

  /// Appends [f] and keeps the End of Part marker sane.
  ///
  /// Inventor builds what you just made: with the marker mid-list, a new
  /// feature goes in AT the marker and the marker moves past it. Appending
  /// without this left the new feature below the marker, so it was created
  /// suppressed — invisible, with no indication why. Use this rather than
  /// `features.add` for anything the user just created.
  void appendFeature(PartFeature f) {
    final wasAtEnd = eopAtEnd;
    features.add(f);
    if (wasAtEnd) {
      eopAfter = kEopAtEnd; // stays at the end
      return;
    }
    final rows = partTimeline(this);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isFeature && identical(rows[i].feature, f)) {
        eopAfter = i + 1;
        return;
      }
    }
    // Not in the timeline (should not happen); leave the marker alone rather
    // than guess a position.
  }

  /// Appends [cs] and keeps the End of Part marker sane — the sketch twin of
  /// [appendFeature].
  ///
  /// A sketch row was appended straight onto [childSketches], so with the
  /// marker at the end (the sentinel, clamped to the row count) the new row
  /// landed exactly ON the cut and was born rolled back: greyed in the
  /// browser, not drawn in 3D — while its editor had just opened. That is the
  /// "the sketch for the second extrusion is made below the EOP" report. Use
  /// this rather than `childSketches.add` for anything the user just created.
  void appendChildSketch(ChildSketch cs) {
    final wasAtEnd = eopAtEnd;
    childSketches.add(cs);
    if (wasAtEnd) {
      eopAfter = kEopAtEnd; // stays at the end
      return;
    }
    final rows = partTimeline(this);
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].isFeature && identical(rows[i].sketch, cs)) {
        eopAfter = i + 1;
        return;
      }
    }
  }

  /// Next value for [ChildSketch.seq] / [ExtrudeFeature.seq].
  int seqNext = 0;

  /// Hands out the next creation-order number.
  int nextSeq() => seqNext++;


  /// Memo for [partContentBounds] (M83). Not serialised, not part of the
  /// document — a pure cache, rebuilt on demand.
  String? extentSig;
  (Vec3, Vec3)? extentCache;
  int featureN = 0, solidN = 0;
  bool dirty = false;

  PartModel(this.name);

  /// Distinct solid bodies in creation order (Inventor's "Solid Bodies"
  /// folder). A body is the set of features sharing a bodyName; its display
  /// entry is the LAST feature that actually carries geometry for it (join
  /// chains fold into one body). Returns [(bodyName, features-of-body)].
  List<(String, List<PartFeature>)> solidBodies() {
    final order = <String>[];
    final byName = <String, List<PartFeature>>{};
    for (final f in features) {
      if (f.solid == null && f.computeError == null) continue;
      byName.putIfAbsent(f.bodyName, () {
        order.add(f.bodyName);
        return <PartFeature>[];
      }).add(f);
    }
    return [for (final n in order) (n, byName[n]!)];
  }

  /// True once the part carries real geometry. Inventor-like rule: the three
  /// origin planes are offered AUTOMATICALLY (shown + pickable) only while the
  /// part is still empty — that is the first sketch/extrusion. Afterwards you
  /// sketch on faces, and a plane is only shown when explicitly switched on in
  /// the browser (its 'vis' flag).
  bool get hasSolid => features.any((f) => f.solid != null);

  ChildSketch? sketchByName(String n) {
    for (final c in childSketches) {
      if (c.model.name == n) return c;
    }
    return null;
  }

  String nextSketchName() {
    var n = 1;
    while (sketchByName('Sketch$n') != null) {
      n++;
    }
    return 'Sketch$n';
  }

  /// M131 — Inventor numbers each feature TYPE separately (Extrusion1,
  /// Revolution1, Fillet1 can all coexist), so the name is derived from what
  /// already exists rather than from one shared counter. [featureN] is still
  /// written to the file and still drives the legacy Extrusion sequence, so
  /// documents from before M131 keep the names they were saved with.
  String nextFeatureName([String label = 'Extrusion']) {
    if (label == 'Extrusion') return 'Extrusion${++featureN}';
    var n = 1;
    while (features.any((f) => f.name == '$label$n')) {
      n++;
    }
    return '$label$n';
  }
  /// The next free body name, consuming it.
  ///
  /// M155 — goes through [peekSolidName] so it SKIPS names already in use.
  /// `'Solid${++solidN}'` trusted the counter alone, and the counter drifts:
  /// revolve/sweep/loft/coil set their body name from their own dialog and
  /// never bumped it, so a part with Solid1..Solid3 was saved with
  /// `solidN: 1`. Re-opening it and adding a body then handed out "Solid2" a
  /// second time, and two features silently drove the same body — one of the
  /// ways a part came back different after a close and re-open.
  String nextSolidName() {
    final name = peekSolidName();
    claimBodyName(name);
    return name;
  }

  /// Records that [name] is taken, so no counter ever hands it out again.
  /// Call for every body name that is set from outside (a dialog, a loaded
  /// document) rather than drawn from [nextSolidName].
  void claimBodyName(String name) {
    final m = RegExp(r'^Solid(\d+)$').firstMatch(name.trim());
    final n = m == null ? null : int.tryParse(m.group(1)!);
    if (n != null && n > solidN) solidN = n;
  }

  /// M96 — the next free body name WITHOUT consuming it.
  ///
  /// The extrude dialog needs a name to show the moment you press New Solid,
  /// and that happens on every toggle — [nextSolidName] would bump the counter
  /// each time and march the name up. It also skips names already in use, so a
  /// renamed body cannot make "New Solid" silently target an existing one.
  String peekSolidName() {
    // EVERY feature's body name counts as taken, not just [bodyNames] — that
    // one lists only bodies with a computed solid, so a body that is rolled
    // back below End of Part (M91) or simply not built yet would not be
    // skipped and "New Solid" would collide with it.
    final taken = {for (final f in features) f.bodyName};
    var n = solidN + 1;
    while (taken.contains('Solid$n')) {
      n++;
    }
    return 'Solid$n';
  }

  /// The LIVE solid bodies, in creation order — one entry per distinct body
  /// name that still owns geometry (a feature consumed by a join no longer
  /// does). Drives Inventor's Output behaviour: Join targets an existing body,
  /// and only when there is more than one does the user have to choose.
  List<String> get bodyNames {
    final out = <String>[];
    for (final f in features) {
      if (f.solid == null || f.consumedByJoin) continue;
      if (!out.contains(f.bodyName)) out.add(f.bodyName);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'type': 'part',
        'vis': vis,
        'cam': camera.toJson(),
        'sketches': [
          for (final c in childSketches)
            {
              'name': c.model.name,
              'plane': c.plane,
              'vis': c.visible,
              if (c.shared) 'shared': true,
              'seq': c.seq,
              if (c.face != null) 'frame': c.face!.frameJson(),
              // M153 — which face, so the sketch can find it again.
              if (c.faceRef != null) 'faceRef': c.faceRef!.toJson(),
            }
        ],
        'features': [for (final f in features) f.toJson()],
        // M151 — written only when there are any, so an untouched part's file
        // is byte-identical to what it was before work planes existed.
        if (workPlanes.isNotEmpty)
          'workPlanes': [for (final w in workPlanes) w.toJson()],
        // M215 — same rule: absent when there are none, so a document made
        // before work axes existed round-trips byte-identical.
        if (workAxes.isNotEmpty)
          'workAxes': [for (final a in workAxes) a.toJson()],
        if (workPoints.isNotEmpty)
          'workPoints': [for (final pt in workPoints) pt.toJson()],
        'featureN': featureN,
        'solidN': solidN,
        // M91 — timeline + End of Part. `eopAfter` is only written when the
        // marker is NOT at the end, so an untouched part's file is unchanged.
        'seqNext': seqNext,
        // M113 — 'eopNodes' counts timeline rows; the old 'eop' counted
        // features and is only READ, never written again.
        if (eopAfter < partTimeline(this).length) 'eopNodes': eopAfter,
      };

  /// Loads everything EXCEPT the child sketch models (their geometry lives
  /// in their own per-sketch files — the caller attaches them).
  void loadJson(Map<String, dynamic> j) {
    (j['vis'] as Map?)?.forEach((k, v) {
      if (vis.containsKey(k)) vis[k as String] = v == true;
    });
    final cam = j['cam'];
    if (cam is Map) camera.loadJson(cam.cast<String, dynamic>());
    featureN = (j['featureN'] as num?)?.toInt() ?? 0;
    solidN = (j['solidN'] as num?)?.toInt() ?? 0;
    for (final f in (j['features'] as List? ?? const [])) {
      final pf = PartFeature.fromJson((f as Map).cast<String, dynamic>());
      if (pf != null) features.add(pf);
    }
    // M155 — REPAIR the counters from what the document actually CONTAINS.
    // Every document written before this carries counters that drifted behind
    // their own contents (a real file: bodies Solid1..Solid3 present, saved
    // with `solidN: 1`, because revolve/coil set the body name from their own
    // dialog and never bumped it). Trusting the stored number hands the same
    // name out again on the next feature and two features silently drive one
    // body. Deriving it from the features repairs those files on open.
    for (final f in features) {
      claimBodyName(f.bodyName);
      final m = RegExp(r'^Extrusion(\d+)$').firstMatch(f.name);
      final n = m == null ? null : int.tryParse(m.group(1)!);
      if (n != null && n > featureN) featureN = n;
    }
    for (final w in (j['workPlanes'] as List? ?? const [])) {
      final wp = WorkPlane.fromJson((w as Map).cast<String, dynamic>());
      if (wp != null) workPlanes.add(wp);
    }
    for (final a in (j['workAxes'] as List? ?? const [])) {
      final wa = WorkAxis.fromJson((a as Map).cast<String, dynamic>());
      if (wa != null) workAxes.add(wa);
    }
    for (final pt in (j['workPoints'] as List? ?? const [])) {
      final wpt = WorkPoint.fromJson((pt as Map).cast<String, dynamic>());
      if (wpt != null) workPoints.add(wpt);
    }
    // M91 — creation order. A pre-M91 document has no 'seq' anywhere; the
    // sketches are numbered first and the features after, which reproduces
    // EXACTLY the old "sketches block, then features block" layout, so an old
    // part opens looking the way its author left it. Only what is made from
    // now on lands on the timeline by real creation time.
    seqNext = (j['seqNext'] as num?)?.toInt() ?? 0;
    var n = 0;
    final sj = j['sketches'] as List? ?? const [];
    for (var i = 0; i < childSketches.length; i++) {
      final m = i < sj.length ? sj[i] as Map? : null;
      childSketches[i].seq = (m?['seq'] as num?)?.toInt() ?? n;
      n = math.max(n, childSketches[i].seq + 1);
    }
    for (final f in features) {
      if (f.seq == 0) f.seq = n;
      n = math.max(n, f.seq + 1);
    }
    if (seqNext < n) seqNext = n;
    // End of Part: absent means "at the end", which is no rollback at all.
    final nodes = (j['eopNodes'] as num?)?.toInt();
    if (nodes != null) {
      // Stored as written. The sentinel decision CANNOT be made here: the
      // caller attaches the child sketches AFTER loadJson returns, so
      // `partTimeline` is currently short by every unconsumed sketch row and a
      // genuinely parked marker would look like "at the end" and silently
      // un-park. [finishLoad] makes that call once the timeline is complete.
      eopAfter = nodes;
    } else {
      // Pre-M113: the stored number counted FEATURES. Convert by walking the
      // timeline until that many features have been passed, so a rolled-back
      // part opens showing exactly what it showed before.
      final feats = (j['eop'] as num?)?.toInt();
      if (feats == null) {
        eopAfter = kEopAtEnd;
      } else {
        var seen = 0, at = 0;
        final tl = partTimeline(this);
        for (; at < tl.length && seen < feats; at++) {
          if (tl[at].isFeature) seen++;
        }
        eopAfter = at;
      }
    }
    applyEndOfPart(this);
  }

  /// M160 — completes a load once the caller has attached the child sketches.
  ///
  /// [loadJson] cannot finish the job on its own: the sketch MODELS live in
  /// their own files and are attached afterwards, so while it runs
  /// `partTimeline` is short by every unconsumed sketch row. Two things
  /// therefore have to wait for this call.
  ///
  /// First, "is the End of Part marker at the end?" — asked against the short
  /// timeline, a marker genuinely parked above the last feature looks like it
  /// covers everything, and converting it to [kEopAtEnd] silently throws the
  /// user's rollback away. Second, [applyEndOfPart] itself, which had been
  /// deciding `rolledBack` for a set of rows that did not yet include the
  /// sketches.
  ///
  /// Idempotent, so calling it twice is harmless.
  void finishLoad() {
    final rows = partTimeline(this);
    if (eopAfter != kEopAtEnd && eopAfter >= rows.length) {
      eopAfter = kEopAtEnd; // covers every row: that IS the end
    }
    applyEndOfPart(this);
    // M164 — the loaded document, stated. Every "the part was different after
    // I closed and opened it" bug so far has been visible right here: a
    // counter behind its own contents (M155), a marker in the wrong place
    // (M160). Printing it means the next one is one line, not a bisect.
    Log.block('part', 'loaded "$name"', [
      'sketches=${childSketches.length}  features=${features.length}  '
          'workPlanes=${workPlanes.length} workAxes=${workAxes.length} '
          'workPoints=${workPoints.length}',
      'counters: featureN=$featureN solidN=$solidN seqNext=$seqNext',
      'bodies: ${{for (final f in features) f.bodyName}.join(", ")}',
      'eopAfter=${eopAfter == kEopAtEnd ? "AT END" : eopAfter} '
          'of ${rows.length} rows'
          '${partIsRolledBack(this) ? "  (ROLLED BACK)" : ""}',
      for (final n in rows)
        '  row ${rows.indexOf(n)}: ${n.isFeature ? "feature" : "sketch "} '
            '${n.name}'
            '${n.isFeature ? " (${n.feature!.kind})" : ""}'
            '${(n.isFeature ? n.feature!.rolledBack : n.sketch!.rolledBack)
                ? "  [rolled back]" : ""}',
    ]);
  }

  void dispose() {
    for (final f in features) {
      f.disposeSolid();
    }
    for (final c in childSketches) {
      c.model.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// adaptive tessellation — a fixed mesh facets as you zoom in (the circle of a
// cylinder shows straight chords). These pure helpers turn the current
// orthographic zoom into a SCREEN-SPACE deflection so a curve's chord sag
// stays sub-pixel at any zoom; the 3D viewport re-meshes when it gets finer.
// ---------------------------------------------------------------------------

/// Default (coarse, fast) linear deflection for a solid's very first mesh, in
/// mm. The viewport refines this to screen resolution on the first frame.
const double kCoarseLinDeflection = 0.6;
const double kCoarseAngDeflection = 0.35;

/// Linear deflection (mm) so a curve's chord sag stays about [pxSag] device
/// pixels at the given orthographic zoom. [halfH] is the half view height in
/// mm, [viewHpx] the viewport height in device pixels. Clamped to [floor]
/// (so extreme zoom-in can't demand an unbounded mesh) and [ceil] (so a tiny,
/// far-away solid stays cheap). The floor is 2 um: the device log showed the
/// old 1e-4 floor being reached (lin=1.28e-4), i.e. a 0.1 um chord sag, which
/// no display can resolve and which cost 1 812 ms of kernel time to produce. Falls back to the coarse default on bad input.
double viewLinearDeflection(double halfH, double viewHpx,
    {double pxSag = 0.4, double floor = 2e-3, double ceil = 5.0}) {
  if (!(halfH > 0) || !(viewHpx > 0) || !halfH.isFinite) {
    return kCoarseLinDeflection;
  }
  final worldPerPx = (2 * halfH) / viewHpx;
  final d = worldPerPx * pxSag;
  return d.isFinite ? d.clamp(floor, ceil).toDouble() : kCoarseLinDeflection;
}

/// Angular deflection (rad) paired with a linear deflection [lin] — finer when
/// we ask for finer linear sag, floored so small circles still round out.
double viewAngularDeflection(double lin) =>
    (lin <= 0 ? kCoarseAngDeflection : (0.02 + 0.5 * lin))
        .clamp(0.02, 0.5)
        .toDouble();

/// Total triangles the 3D scene may carry before refinement stops asking for
/// more. A single z=20 gear measured 34 236 triangles at full screen-space
/// refinement on device (measured 50 548 on the build-39555ac log), so 120 000
/// — the first guess — never fired at all for one gear. A handful of gear-like
/// features would otherwise walk into the hundreds of thousands: the mesh only
/// ever gets FINER (see [meshNeedsRefine]), so every zoom-in ratchets the
/// scene up and nothing ever gives it back.
const int kSceneTriangleBudget = 40000;

/// [target] deflection relaxed so the scene stays near [budget] triangles.
///
/// Triangle count for curved faces grows roughly as 1/deflection, so scaling
/// the target by the overrun ratio lands close in one step. This can only make
/// the target COARSER, and because [meshNeedsRefine] refuses to coarsen an
/// existing mesh the pair simply stops refining once the budget is reached —
/// there is no oscillation, the loop just settles.
double budgetedLinDeflection(double target, int sceneTris,
    {int budget = kSceneTriangleBudget}) {
  if (budget <= 0 || !(target > 0)) return target;
  // HARD stop, not a proportional nudge. The M65 version scaled the target by
  // sceneTris/budget, but that ratio is ~1.0 exactly when the scene first
  // crosses the line, so the relaxation was negligible and refinement sailed
  // on to 78 976 triangles (device log, build 9ef0425). Once the scene is at
  // budget we ask for nothing finer at all; meshNeedsRefine then refuses and
  // the ratchet stops dead.
  if (sceneTris >= budget) return double.infinity;
  final headroom = sceneTris / budget;
  if (headroom < 0.8) return target;
  // Inside the last 20% ease off so we approach the ceiling instead of
  // slamming into it mid-gesture.
  final relaxed = target / (1.0 - headroom).clamp(0.05, 1.0);
  return relaxed.isFinite ? relaxed : target;
}

/// Most a single refinement pass may tighten the deflection.
///
/// M159 — the budget is REACTIVE: [budgetedLinDeflection] reads the triangles
/// already in the scene, so it can only stop a ratchet that has begun. It
/// cannot stop one step from overshooting, and a coil overshoots by a factor
/// of a hundred. Device log: a coil meshed at 7 536 triangles, the scene was
/// far under budget so the full target was requested, and OCCT returned
/// 1 002 412 triangles in ONE pass — 9 952 ms, and later 605 610 triangles in
/// 56 183 ms. The budget then correctly refused to go further, but the cost
/// was already paid and a million-triangle mesh was already on screen.
///
/// Triangle growth per pass is bounded instead. Halving the deflection costs
/// at most ~4x the triangles for a surface, so each pass stays cheap and the
/// existing budget check between passes stops the climb while the numbers are
/// still small — several fast remeshes rather than one catastrophic one.
const double kMaxRefineStep = 2.0;

/// [target], but no finer than one [kMaxRefineStep] beyond [current].
///
/// Coarsening requests pass through untouched: this only ever limits how much
/// FINER a single pass may ask for.
double steppedLinDeflection(double current, double target) {
  if (!(current > 0) || !current.isFinite) return target;
  final floor = current / kMaxRefineStep;
  return target < floor ? floor : target;
}

/// Whether a mesh built at [current] deflection should be re-tessellated for
/// a [target] deflection. We only ever refine FINER (never coarsen): refining
/// is monotone-safe with OCCT's incremental mesher, and a too-fine mesh is
/// still visually correct when you zoom back out — so a curve stays smooth at
/// any zoom without thrashing the kernel on the way out.
bool meshNeedsRefine(double current, double target) =>
    !(current > 0) || target < current * 0.66;

/// Segment count to approximate a circle of [radius] within linear sag [lin]
/// (chord-height formula), floored at 8 and hard-capped so an absurd zoom-in
/// can't blow up the vertex count. Shared by the display path and test fakes.
int circleSegments(double radius, double lin) {
  if (!(radius > 0) || !(lin > 0)) return 8;
  final ratio = (1 - lin / radius).clamp(-1.0, 1.0);
  final theta = 2 * math.acos(ratio); // angle subtended by one chord
  if (!(theta > 1e-9)) return 2000;
  final n = (2 * math.pi / theta).ceil();
  return n.clamp(8, 2000);
}

// ---------------------------------------------------------------------------
// arc recovery — region detection hands the kernel POLYGONIZED loops, so a
// circle would become an N-gon prism whose facet edges show as black
// verticals on the barrel. arcFitLoop detects runs of consecutive loop
// points that lie on one circle (the polygonizer emits them mathematically
// exact) and collapses each run back into a TRUE arc (DXF bulge), so the
// kernel receives exact circles/arcs/fillets and the B-Rep is smooth at any
// zoom. Lines and free-form runs pass through untouched (bulge 0).
// ---------------------------------------------------------------------------

/// Circumcenter of three points, or null when (nearly) collinear.
Offset? circumcenter(Offset a, Offset b, Offset c) {
  final d =
      2 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
  if (d.abs() < 1e-12) return null;
  final a2 = a.dx * a.dx + a.dy * a.dy;
  final b2 = b.dx * b.dx + b.dy * b.dy;
  final c2 = c.dx * c.dx + c.dy * c.dy;
  return Offset(
      (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d,
      (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d);
}

/// One output segment of [arcFitLoop]: start vertex + bulge of the edge
/// leaving it toward the next segment's start (0 = line, tan(sweep/4) else).
class LoopSeg {
  final Offset p;
  final double bulge;
  const LoopSeg(this.p, this.bulge);
}

/// Collapses circular runs of the closed polyline [pts] into arcs.
///
/// Guards (all must hold for a run):
///  * every chord subtends < ~20 deg on the fitted circle — a rectangle or
///    regular polygon whose CORNERS happen to be concyclic is NOT an arc
///    discretisation and stays straight;
///  * every run vertex lies on the fitted circle within max(1e-9, 1e-6 r);
///  * the turn direction is consistent;
///  * a run is >= 3 chords (4 vertices).
/// The loop is first rotated to start at a CORNER (a vertex that is not
/// smooth-arc interior), so no run ever wraps the seam; if no corner exists
/// and every vertex sits on ONE circle, the loop IS a circle and becomes two
/// half arcs. Conservative: anything else passes through as lines.
List<LoopSeg> arcFitLoop(List<Offset> pts) {
  final n = pts.length;
  if (n < 4) return [for (final p in pts) LoopSeg(p, 0)];
  const maxChordSweep = 0.35; // rad per chord (~20 deg)

  bool chordsOk(double r, Offset a, Offset b) =>
      (a - b).distance <= 2 * r * math.sin(maxChordSweep / 2) * (1 + 1e-9);

  // Discretised arcs have (near-)EQUAL chords; a junction pairs a tiny arc
  // chord with a long line chord. The ratio guard is what makes gaps
  // detectable at all — the sweep guard alone is scale-relative and a
  // near-collinear triple fits a huge circle that swallows any chord.
  bool ratioOk(Offset a, Offset b, Offset c) {
    final l0 = (a - b).distance, l1 = (b - c).distance;
    if (l0 <= 0 || l1 <= 0) return false;
    final q = l0 > l1 ? l0 / l1 : l1 / l0;
    return q <= 2.0;
  }

  // linked[k]: chords k and k+1 COULD belong to one arc discretisation. A
  // maximal arc run is a maximal stretch of linked chords, so a chord pair
  // with linked == false is a GAP that no run can cross.
  bool linked(int k) {
    final a = pts[k % n], b = pts[(k + 1) % n], c = pts[(k + 2) % n];
    final cc = circumcenter(a, b, c);
    if (cc == null) return false;
    if (_turnSign(a, b, c) == 0) return false;
    if (!ratioOk(a, b, c)) return false;
    final r = (b - cc).distance;
    return chordsOk(r, a, b) && chordsOk(r, b, c);
  }

  var gap = -1;
  for (var k = 0; k < n; k++) {
    if (!linked(k)) {
      gap = k;
      break;
    }
  }

  if (gap < 0) {
    // Every chord pair is arc-like: either ONE full circle, or a smooth
    // free-form loop we conservatively leave untouched.
    final c = circumcenter(pts[0], pts[1], pts[2]);
    if (c != null) {
      final r = (pts[0] - c).distance;
      final tol = math.max(1e-9, 1e-6 * r);
      var all = true;
      for (final p in pts) {
        if (((p - c).distance - r).abs() > tol) {
          all = false;
          break;
        }
      }
      if (all) {
        final ccw = _turnSign(pts[0], pts[1], pts[2]) >= 0;
        final b = ccw ? 1.0 : -1.0; // two half-turn arcs: tan(pi/4)
        final opposite = c * 2 - pts[0];
        return [
          LoopSeg(pts[0], b),
          LoopSeg(Offset(opposite.dx, opposite.dy), b),
        ];
      }
    }
    return [for (final p in pts) LoopSeg(p, 0)];
  }

  // Start the walk just after the gap: chord gap+1 can only BEGIN a run, so
  // rotation never splits an arc — even one that crossed the input seam.
  final rp = [for (var j = 0; j < n; j++) pts[(gap + 1 + j) % n]];
  Offset at(int i) => rp[i % n]; // at(n) == rp[0], the closing vertex

  final out = <LoopSeg>[];
  var i = 0;
  while (i < n) {
    var run = 0;
    Offset? c;
    if (i + 2 <= n) {
      final c0 = circumcenter(at(i), at(i + 1), at(i + 2));
      if (c0 != null) {
        final r = (at(i) - c0).distance;
        final tol = math.max(1e-9, 1e-6 * r);
        final turn0 = _turnSign(at(i), at(i + 1), at(i + 2));
        if (turn0 != 0 &&
            ratioOk(at(i), at(i + 1), at(i + 2)) &&
            chordsOk(r, at(i), at(i + 1)) &&
            chordsOk(r, at(i + 1), at(i + 2))) {
          run = 2;
          c = c0;
          var k = i + 3;
          while (k <= n &&
              ((at(k) - c0).distance - r).abs() <= tol &&
              chordsOk(r, at(k - 1), at(k)) &&
              ratioOk(at(k - 2), at(k - 1), at(k)) &&
              _turnSign(at(k - 2), at(k - 1), at(k)) == turn0) {
            run++;
            k++;
          }
        }
        if (run < 3) {
          run = 0;
          c = null;
        }
      }
    }
    if (c == null) {
      out.add(LoopSeg(at(i), 0));
      i++;
      continue;
    }
    final sweep = _runSweepR(rp, i, run, c);
    out.add(LoopSeg(at(i), math.tan(sweep / 4)));
    i += run; // == n exactly when the arc closes at the rotated seam
  }
  return out;
}

int _turnSign(Offset a, Offset b, Offset c) {
  final z = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
  return z > 0 ? 1 : (z < 0 ? -1 : 0);
}

/// Signed total sweep of [chords] chords starting at vertex [i] around
/// center [c] — summed per chord, so sweeps beyond pi work. Indices wrap.
double _runSweepR(List<Offset> pts, int i, int chords, Offset c) {
  final n = pts.length;
  var sweep = 0.0;
  for (var k = 0; k < chords; k++) {
    final a = pts[(i + k) % n] - c;
    final b = pts[(i + k + 1) % n] - c;
    sweep += math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);
  }
  return sweep;
}

/// Encodes fitted loops for the v3 kernel entry: 3 doubles per vertex
/// (x, y, bulge).
List<double> encodeLoopSegs(List<LoopSeg> segs) => [
      for (final s in segs) ...[s.p.dx, s.p.dy, s.bulge]
    ];

// ---------------------------------------------------------------------------
// kernel bridge — the ONLY seam between part features and OCCT, so host
// tests can inject a fake while the app itself never fakes a B-Rep.
// ---------------------------------------------------------------------------
class KernelSolid {
  /// Display mesh in WORLD coordinates. Mutable: the viewport swaps in a finer
  /// tessellation via [refine] as you zoom, so this always holds the mesh that
  /// should currently be drawn.
  OcctMeshData mesh;
  final double volume;

  /// World-space B-Rep handle (null in test fakes). Owned by this solid.
  final OcctShape? shape;

  /// Re-tessellate at a new deflection. On the real kernel this closes over the
  /// retained B-Rep and re-meshes it; test fakes close over a synthetic
  /// generator. Null means the mesh is static (no refinement possible).
  final OcctMeshData? Function(double lin, double ang)? _remesher;

  /// Linear deflection (mm) the current [mesh] was built at.
  double meshLin;

  KernelSolid(
    this.mesh,
    this.volume,
    this.shape, {
    OcctMeshData? Function(double lin, double ang)? remesher,
    this.meshLin = kCoarseLinDeflection,
  }) : _remesher = remesher;

  /// Replaces [mesh] with a tessellation at [lin]/[ang] when a remesher is
  /// present and succeeds. Returns true iff the mesh actually changed. Never
  /// throws — a failed refine (e.g. a disposed shape) just keeps the old mesh.
  bool refine(double lin, double ang) {
    final r = _remesher;
    if (r == null) return false;
    try {
      final m = r(lin, ang);
      if (m == null) return false;
      mesh = m;
      meshLin = lin;
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() => shape?.dispose();
}

abstract class PartKernel {
  bool get available;
  String get info;
  String get lastError;

  /// Extrudes [groups] (each = outer loop + hole loops, sketch coords) by
  /// [height] with [taperDeg] (Inventor sign), fuses multiple groups, and
  /// places the result with the rigid [mat34]. Null on failure.
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34);

  /// Boolean union of two solids (Inventor's Join). Inputs stay owned by the
  /// caller; the result is a NEW solid. Null on failure.
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b);

  /// Boolean cut [base] \ [tool] (Inventor's Cut). Inputs stay owned by the
  /// caller; the result is a NEW solid. Null on failure (incl. empty result).
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool);

  /// Boolean intersection [a] ∩ [b] (Inventor's Intersect). Inputs stay owned
  /// by the caller; the result is a NEW solid. Null on failure (incl. empty).
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b);

  // ---- M131: sweep / loft / coil ---------------------------------------
  // Concrete and null-returning for the same reason as the M131 additions
  // above: the test fakes use `implements`, and a fake that does not model
  // sweeping should say so rather than break every unrelated test.

  /// Sweeps [groups] along the world-space polyline [pathPts] (3 doubles per
  /// point), placing the profile with [mat34].
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
          List<double> pathPts,
          {int orientation = 0, double taperDeg = 0, double twistDeg = 0}) =>
      null;

  /// Lofts through [sections] (one closed loop each) placed by [mats].
  KernelSolid? loft(List<List<Offset>> sections, List<List<double>> mats,
          {bool solid = true, bool ruled = false, bool closed = false}) =>
      null;

  /// Helical sweep of [groups] about the world axis [axP]/[axD].
  KernelSolid? coil(List<List<List<Offset>>> groups, List<double> mat34,
          Vec3 axP, Vec3 axD,
          {required double revolutions,
          required double height,
          double taperDeg = 0,
          bool clockwise = false}) =>
      null;

  /// Writes the union of [solids] as STEP to [path].
  ///
  /// M214 — prefer [exportStepBodies]. This one unions, which is only ever
  /// right for a caller that already knows its solids are one body; the part
  /// export is not such a caller and used to be one by accident.
  bool exportStep(List<KernelSolid> solids, String path);

  /// M214 — writes [bodies] as STEP: one NAMED product per body, no union.
  ///
  /// [product] names the document in the file header. Concrete (not abstract)
  /// for the reason documented below on [revolve] — three test fakes
  /// `implement` this interface, and the default delegates to [exportStep] so
  /// a fake that does not model naming still behaves exactly as it did.
  bool exportStepBodies(
          List<(String, KernelSolid)> bodies, String path,
          {String product = ''}) =>
      exportStep([for (final b in bodies) b.$2], path);

  // ---- M131: revolve + body modification -------------------------------
  //
  // These are CONCRETE and fail honestly rather than abstract, deliberately.
  // Three test fakes implement PartKernel; making these abstract would break
  // all of them in one commit for machinery most of their tests never touch.
  // A fake that wants to exercise revolve or fillet overrides the one method
  // it needs, and any fake that does not simply reports "unsupported" — which
  // is the truth, and is what the feature will surface as its computeError.

  /// Revolves [groups] about the sketch-space axis through ([axPx], [axPy])
  /// along ([axDx], [axDy]) by [angleDeg], then places it with [mat34].
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
          double axPx, double axPy, double axDx, double axDy,
          List<double> mat34) =>
      null;

  /// Topological edges of [s], in the index space [filletEdges] and
  /// [chamferEdges] address. Empty when the kernel cannot enumerate them.
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => const [];

  /// Constant-radius fillet on [edgeIds] (1-based topological indices) with
  /// one radius each. Returns a NEW solid; [base] stays owned by the caller.
  ///
  /// [report], when given, receives what the kernel actually did: the edges it
  /// had to skip, and whether it had to step a hair off the asked-for radius
  /// to build at all. See [BlendReport].
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
          List<double> radii,
          {List<double> radii2 = const [], BlendReport? report}) =>
      null;

  /// Angles in degrees at which the circular path of [p] about the axis
  /// through [axP] along [axD] crosses [s]. Empty when it never does.
  List<double> revolveHits(KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p) =>
      const [];

  /// As [revolveHits], but only crossings of the face nearest [facePoint].
  List<double> revolveHitsFace(
          KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p, Vec3 facePoint) =>
      const [];

  /// Chamfer on [edgeIds] with Inventor method [mode] (0 equal distance,
  /// 1 two distances, 2 distance and angle). Returns a NEW solid.
  /// [report] carries the same after-the-fact truth as on [filletEdges].
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
          double d1, double d2, double angleDeg, {BlendReport? report}) =>
      null;

  // ---- M217: Delete Face and Direct Edit --------------------------------
  //
  // Concrete and null-returning, for the reason documented on [revolve]: the
  // test fakes `implement` this interface, and a fake that does not model
  // face surgery should say so rather than break every unrelated test.

  /// Inventor's Delete Face (Heal on): removes [faceIds] — 1-based
  /// TOPOLOGICAL face indices — and closes the wound by extending their
  /// neighbours. Returns a NEW solid; [base] stays owned by the caller.
  KernelSolid? deleteFaces(KernelSolid base, List<int> faceIds) => null;

  /// Inventor's Direct > Move/Size: slides [faceIds] by [delta].
  KernelSolid? moveFaces(KernelSolid base, List<int> faceIds, Vec3 delta) =>
      null;

  /// Inventor's Direct > Scale: uniform scale of the whole body about
  /// [centre] by [factor].
  KernelSolid? scaleSolid(KernelSolid base, Vec3 centre, double factor) =>
      null;

  /// M111 — reads a STEP file as one [KernelSolid] per SOLID, so an imported
  /// assembly becomes several bodies rather than one opaque compound. Empty
  /// list on failure or when the file holds no solids.
  List<KernelSolid> importStepSolids(String path);

  // ---- M212: the two placements a PATTERN needs -------------------------
  //
  // Concrete and null-returning for the same reason as the M131 additions
  // above: three test fakes implement PartKernel, and a fake that does not
  // model placement should say so rather than break every unrelated test.

  /// A NEW solid = [s] moved by the row-major rigid 3x4 [mat34]. [s] stays
  /// owned by the caller. This is what every pattern occurrence except a
  /// mirror is: the same tool solid, somewhere else.
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) => null;

  /// A NEW solid = [s] reflected about the plane through [planePoint] with
  /// normal [planeNormal]. Its own method rather than a matrix through
  /// [placeSolid] because a reflection is not a rigid motion — the shim
  /// refuses det -1 there deliberately, so that a wrong frame can never
  /// silently turn a solid inside out (occt_capi.h, occt_transform).
  KernelSolid? mirrorSolid(KernelSolid s, Vec3 planePoint, Vec3 planeNormal) =>
      null;
}

/// Applies Inventor's Output boolean [output] to combine [base] (the
/// accumulated body) with [tool] (this feature's fresh prism) via [kernel].
/// 'join' → union, 'cut' → subtract, 'intersect' → common; anything else
/// (incl. 'new') has no combine and returns null. Shared by the feature fold
/// and the live preview so both agree exactly.
KernelSolid? combineSolids(
    PartKernel kernel, String output, KernelSolid base, KernelSolid tool) {
  switch (output) {
    case 'cut':
      return kernel.cutSolids(base, tool);
    case 'intersect':
      return kernel.intersectSolids(base, tool);
    case 'join':
      return kernel.fuseSolids(base, tool);
    default:
      return null; // 'new' (or unknown): no boolean
  }
}

/// The real kernel over the linked OCCT shim. [available] is false on host
/// (symbols not linked) — callers report that honestly.
class OcctPartKernel implements PartKernel {
  String _errValue = '';

  /// M185 — assigning an error LOGS it.
  ///
  /// Every refusal in this class already records WHY here, and until now that
  /// string only reached the log if a feature happened to surface it as its
  /// computeError. A boolean that failed inside the fold, a sweep that could
  /// not build its path, a STEP import that read nothing — all of those set
  /// this field and then said nothing anywhere a report could see. There were
  /// forty-seven such sites and no realistic chance of every future one
  /// remembering to log; routing the assignment itself is the only version of
  /// this that stays true as the kernel grows.
  ///
  /// The shim's own message is appended when it has one, because the Dart-side
  /// sentence says which operation gave up and the OCCT sentence says why.
  set _err(String v) {
    _errValue = v;
    if (v.isEmpty) return;
    final native = _ffi?.lastError() ?? '';
    Log.w('kernel', native.isEmpty || v.contains(native) ? v : '$v | $native');
  }

  String get _err => _errValue;

  OcctFfi? get _ffi => OcctFfi.instance();

  @override
  bool get available => _ffi != null;

  @override
  String get info => _ffi?.version ?? 'occt-none';

  @override
  String get lastError => _err;

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    OcctShape? acc;
    try {
      for (final g in groups) {
        // Recover true arcs from the polygonized loops so circles reach OCCT
        // as exact cylindrical faces — no facet edges on curved walls.
        // DIAGNOSTIC: the shim treats loop 0 as the OUTER boundary and the
        // rest as holes. Measured on device, the extruded caps keep coming
        // back with exactly the CIRCLE's area for a rectangle-with-hole, and
        // identically so for both rectangle winding directions — which rules
        // out the orientation theory and points at what is handed over here.
        // So record it: loop order, point counts, signed areas and extents.
        for (var li = 0; li < g.length; li++) {
          final lp = g[li];
          var a2 = 0.0, x0 = 1e30, y0 = 1e30, x1 = -1e30, y1 = -1e30;
          for (var i = 0; i < lp.length; i++) {
            final p0 = lp[i], p1 = lp[(i + 1) % lp.length];
            a2 += p0.dx * p1.dy - p1.dx * p0.dy;
            if (p0.dx < x0) x0 = p0.dx;
            if (p0.dy < y0) y0 = p0.dy;
            if (p0.dx > x1) x1 = p0.dx;
            if (p0.dy > y1) y1 = p0.dy;
          }
          Log.i(
              'extrude',
              'loop[$li] pts=${lp.length} signedArea=${(a2 / 2).toStringAsFixed(2)} '
              'bbox=${x0.toStringAsFixed(1)},${y0.toStringAsFixed(1)}'
              '..${x1.toStringAsFixed(1)},${y1.toStringAsFixed(1)}'
              '${li == 0 ? "  <-- treated as OUTER" : "  <-- treated as hole"}');
        }
        final loops = [for (final loop in g) encodeLoopSegs(arcFitLoop(loop))];
        final part = ffi.extrudeProfileArcs(loops, height, taperDeg: taperDeg);
        if (part == null) {
          _err = ffi.lastError();
          acc?.dispose();
          return null;
        }
        if (acc == null) {
          acc = part;
        } else {
          final fused = ffi.fuse(acc, part);
          acc.dispose();
          part.dispose();
          if (fused == null) {
            _err = ffi.lastError();
            return null;
          }
          acc = fused;
        }
      }
      if (acc == null) {
        _err = 'nothing to extrude';
        return null;
      }
      final placed = acc.transformed(mat34);
      acc.dispose();
      acc = null;
      if (placed == null) {
        _err = ffi.lastError();
        return null;
      }
      // Build a coarse mesh now (fast first frame); the viewport refines it to
      // screen resolution immediately and on every zoom-in via [refine], so
      // curved edges stay smooth at any zoom.
      final mesh = placed.mesh(
          linDeflection: kCoarseLinDeflection,
          angDeflection: kCoarseAngDeflection);
      if (mesh == null) {
        _err = ffi.lastError();
        placed.dispose();
        return null;
      }
      return KernelSolid(mesh, placed.volume, placed,
          meshLin: kCoarseLinDeflection,
          remesher: (lin, ang) =>
              placed.mesh(linDeflection: lin, angDeflection: ang));
    } catch (e) {
      _err = '$e';
      acc?.dispose();
      return null;
    }
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      _boolean('fuse', a, b, (ffi, sa, sb) => ffi.fuse(sa, sb));

  @override
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool) =>
      _boolean('cut', base, tool, (ffi, sa, sb) => ffi.cut(sa, sb));

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) =>
      _boolean('intersect', a, b, (ffi, sa, sb) => ffi.common(sa, sb));

  /// Shared body of the three boolean ops: run [op] on the two operands'
  /// B-Reps, clean the same-domain faces/edges the boolean leaves behind
  /// (v4 — otherwise the seam renders spurious fragment lines, M58 device
  /// find), then build the coarse display mesh. Inputs stay owned by the
  /// caller; the result is a NEW solid.
  KernelSolid? _boolean(String what, KernelSolid a, KernelSolid b,
      OcctShape? Function(OcctFfi ffi, OcctShape sa, OcctShape sb) op) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final sa = a.shape, sb = b.shape;
    if (sa == null || sb == null) {
      _err = '$what needs kernel-backed solids';
      return null;
    }
    // M185 — the operands, so a failed boolean can be reasoned about. A bare
    // OCCT message names neither which of the three ran nor what it was
    // given, and "cut failed" with no volumes is the same dead end as "the
    // fillet broke": the interesting cases are a tool that misses the base
    // entirely, or one of the two arriving empty.
    final operands = '$what(a: vol=${a.volume.toStringAsFixed(4)}, '
        'b: vol=${b.volume.toStringAsFixed(4)})';
    final raw = op(ffi, sa, sb);
    if (raw == null) {
      _err = '$operands failed';
      return null;
    }
    final result = ffi.unify(raw) ?? raw;
    if (!identical(result, raw)) raw.dispose();
    final mesh = result.mesh(
        linDeflection: kCoarseLinDeflection,
        angDeflection: kCoarseAngDeflection);
    if (mesh == null) {
      _err = '$operands built a solid that could not be tessellated';
      result.dispose();
      return null;
    }
    // A boolean whose result is empty or unchanged is not an error to OCCT
    // but is almost always the user's bug: a cut that removed nothing, or one
    // that removed everything. Only worth a line when it actually happens.
    final v = result.volume;
    if (v <= 1e-9) {
      Log.w('kernel', '$operands produced an EMPTY solid (vol=$v)');
    } else if (what == 'cut' && (v - a.volume).abs() < 1e-9) {
      Log.w('kernel',
          '$operands removed NOTHING — the tool and the base do not overlap');
    }
    return KernelSolid(mesh, result.volume, result,
        meshLin: kCoarseLinDeflection,
        remesher: (lin, ang) =>
            result.mesh(linDeflection: lin, angDeflection: ang));
  }

  /// Mesh a freshly produced shape and wrap it, taking ownership. Shared tail
  /// of every M131 path; identical to [_boolean]'s ending minus the unify.
  KernelSolid? _wrapOwned(OcctFfi ffi, OcctShape? shape) {
    if (shape == null) {
      _err = ffi.lastError();
      return null;
    }
    final mesh = shape.mesh(
        linDeflection: kCoarseLinDeflection,
        angDeflection: kCoarseAngDeflection);
    if (mesh == null) {
      _err = ffi.lastError();
      shape.dispose();
      return null;
    }
    return KernelSolid(mesh, shape.volume, shape,
        meshLin: kCoarseLinDeflection,
        remesher: (lin, ang) =>
            shape.mesh(linDeflection: lin, angDeflection: ang));
  }

  @override
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
      double axPx, double axPy, double axDx, double axDy, List<double> mat34) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    OcctShape? acc;
    try {
      for (final g in groups) {
        final loops = [for (final loop in g) encodeLoopSegs(arcFitLoop(loop))];
        final part = ffi.revolveProfile(loops, angleDeg,
            axPx: axPx, axPy: axPy, axDx: axDx, axDy: axDy);
        if (part == null) {
          _err = ffi.lastError();
          acc?.dispose();
          return null;
        }
        if (acc == null) {
          acc = part;
        } else {
          final fused = ffi.fuse(acc, part);
          acc.dispose();
          part.dispose();
          if (fused == null) {
            _err = ffi.lastError();
            return null;
          }
          acc = fused;
        }
      }
      if (acc == null) {
        _err = 'nothing to revolve';
        return null;
      }
      final placed = acc.transformed(mat34);
      acc.dispose();
      acc = null;
      return _wrapOwned(ffi, placed);
    } catch (e) {
      _err = '$e';
      acc?.dispose();
      return null;
    }
  }

  @override
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
      List<double> pathPts,
      {int orientation = 0, double taperDeg = 0, double twistDeg = 0}) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    OcctShape? acc;
    try {
      for (final g in groups) {
        final loops = [for (final loop in g) encodeLoopSegs(arcFitLoop(loop))];
        final part = ffi.sweepProfile(loops, mat34, pathPts,
            orientation: orientation, taperDeg: taperDeg, twistDeg: twistDeg);
        if (part == null) {
          _err = ffi.lastError();
          acc?.dispose();
          return null;
        }
        if (acc == null) {
          acc = part;
        } else {
          final fused = ffi.fuse(acc, part);
          acc.dispose();
          part.dispose();
          if (fused == null) {
            _err = ffi.lastError();
            return null;
          }
          acc = fused;
        }
      }
      if (acc == null) {
        _err = 'nothing to sweep';
        return null;
      }
      final out = _wrapOwned(ffi, acc);
      if (out == null) acc.dispose();
      return out;
    } catch (e) {
      _err = '$e';
      acc?.dispose();
      return null;
    }
  }

  @override
  KernelSolid? loft(List<List<Offset>> sections, List<List<double>> mats,
      {bool solid = true, bool ruled = false, bool closed = false}) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    try {
      final enc = [for (final sec in sections) encodeLoopSegs(arcFitLoop(sec))];
      final shape = ffi.loftSections(enc, mats,
          solid: solid, ruled: ruled, closed: closed);
      if (shape == null) {
        _err = ffi.lastError();
        return null;
      }
      return _wrapOwned(ffi, shape);
    } catch (e) {
      _err = '$e';
      return null;
    }
  }

  @override
  KernelSolid? coil(List<List<List<Offset>>> groups, List<double> mat34,
      Vec3 axP, Vec3 axD,
      {required double revolutions,
      required double height,
      double taperDeg = 0,
      bool clockwise = false}) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    if (groups.isEmpty) {
      _err = 'nothing to coil';
      return null;
    }
    try {
      // One profile only: a coil sweeps ONE section along its helix, and two
      // profiles would need two helices that could not share a pitch.
      final loops = [
        for (final loop in groups.first) encodeLoopSegs(arcFitLoop(loop))
      ];
      final shape = ffi.coilProfile(
          loops, mat34, [axP.x, axP.y, axP.z], [axD.x, axD.y, axD.z],
          revolutions: revolutions,
          height: height,
          taperDeg: taperDeg,
          clockwise: clockwise);
      if (shape == null) {
        _err = ffi.lastError();
        return null;
      }
      return _wrapOwned(ffi, shape);
    } catch (e) {
      _err = '$e';
      return null;
    }
  }

  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) {
    final shape = s.shape;
    if (shape == null) {
      _err = 'edge query needs a kernel-backed solid';
      return const [];
    }
    try {
      return shape.allEdges();
    } catch (e) {
      _err = '$e';
      return const [];
    }
  }

  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
      List<double> radii,
      {List<double> radii2 = const [], BlendReport? report}) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final shape = base.shape;
    if (shape == null) {
      _err = 'fillet needs a kernel-backed solid';
      return null;
    }
    // No unify here, unlike the boolean path: OCCT's filleting algorithm
    // already emits clean topology, and running ShapeUpgrade over a fresh
    // fillet is a well-known way to lose the very faces it just built.
    return _wrapOwned(ffi,
        shape.filletEdges(edgeIds, radii, radii2: radii2, report: report));
  }

  @override
  List<double> revolveHits(KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p) {
    final shape = s.shape;
    if (shape == null) return const [];
    try {
      return shape.revolveHits(
          axP.x, axP.y, axP.z, axD.x, axD.y, axD.z, p.x, p.y, p.z);
    } catch (e) {
      _err = '$e';
      return const [];
    }
  }

  @override
  List<double> revolveHitsFace(
      KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p, Vec3 facePoint) {
    final shape = s.shape;
    if (shape == null) return const [];
    try {
      return shape.revolveHitsFace(axP.x, axP.y, axP.z, axD.x, axD.y, axD.z,
          p.x, p.y, p.z, facePoint.x, facePoint.y, facePoint.z);
    } catch (e) {
      _err = '$e';
      return const [];
    }
  }

  @override
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
      double d1, double d2, double angleDeg, {BlendReport? report}) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final shape = base.shape;
    if (shape == null) {
      _err = 'chamfer needs a kernel-backed solid';
      return null;
    }
    final n = edgeIds.length;
    return _wrapOwned(
        ffi,
        shape.chamferEdges(
          edgeIds,
          List<int>.filled(n, mode),
          List<double>.filled(n, d1),
          d2: mode == 1 ? List<double>.filled(n, d2) : const [],
          angleDeg: mode == 2 ? List<double>.filled(n, angleDeg) : const [],
          report: report,
        ));
  }

  @override
  bool exportStep(List<KernelSolid> solids, String path) =>
      exportStepBodies([for (final s in solids) ('', s)], path);

  /// M214 — the part export. One STEP product per body, named, no boolean.
  ///
  /// What this replaced, and why each part of it was wrong:
  ///
  ///   `ffi.fuse(s, s)` as a "cheap copy via self-union" — a self-union is a
  ///   FULL boolean against identical geometry. It is the most expensive way
  ///   to copy a handle that exists, it can regularise the shape into
  ///   something that is not what the user modelled, and on a part with many
  ///   faces it was simply slow.
  ///
  ///   Unioning the bodies together — two separate bodies ARE two bodies. The
  ///   union threw away that fact, and when it failed (a boolean on disjoint
  ///   solids is not free of failure modes) the whole export failed with it.
  ///   The shim now writes them side by side, which cannot fail that way.
  ///
  /// A disposed or shapeless solid is REFUSED rather than skipped: silently
  /// dropping a body means handing over a file that is missing part of the
  /// model without saying so, which is the one outcome an exporter must never
  /// have. (A test-fake solid has no shape at all, so on host this reports
  /// honestly instead of writing an empty file.)
  @override
  bool exportStepBodies(
      List<(String, KernelSolid)> bodies, String path,
      {String product = ''}) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return false;
    }
    if (bodies.isEmpty) {
      _err = 'no solids to export';
      return false;
    }
    final shapes = <OcctShape>[];
    final names = <String>[];
    for (final (name, solid) in bodies) {
      final sh = solid.shape;
      if (sh == null || sh.disposed) {
        _err = 'body "$name" has no live B-Rep to export';
        return false;
      }
      shapes.add(sh);
      names.add(name);
    }
    final doc = product.isNotEmpty
        ? product
        : (names.first.isEmpty ? 'Part' : names.first);
    final ok = ffi.exportStepNamed(shapes, names, path, doc);
    if (!ok) _err = ffi.lastError();
    return ok;
  }

  @override
  List<KernelSolid> importStepSolids(String path) {
    final ffi = OcctFfi.instance();
    if (ffi == null) {
      _err = 'no kernel';
      return const [];
    }
    try {
      final shapes = ffi.importStepSolids(path);
      final out = <KernelSolid>[];
      for (final sh in shapes) {
        final mesh = sh.mesh(
            linDeflection: kCoarseLinDeflection,
            angDeflection: kCoarseAngDeflection);
        if (mesh == null) {
          // A solid we cannot tessellate is useless on screen; drop it rather
          // than adding an invisible body the user cannot explain.
          sh.dispose();
          continue;
        }
        out.add(KernelSolid(mesh, sh.volume, sh,
            meshLin: kCoarseLinDeflection,
            remesher: (lin, ang) =>
                sh.mesh(linDeflection: lin, angDeflection: ang)));
      }
      if (out.isEmpty) _err = 'no solids in file';
      return out;
    } catch (e) {
      _err = '$e';
      return const [];
    }
  }

  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final sh = s.shape;
    if (sh == null) {
      _err = 'placing a pattern occurrence needs a kernel-backed solid';
      return null;
    }
    if (mat34.length != 12) {
      _err = 'a placement matrix has 12 numbers, got ${mat34.length}';
      return null;
    }
    return _wrapOwned(ffi, sh.transformed(mat34));
  }

  @override
  KernelSolid? mirrorSolid(KernelSolid s, Vec3 planePoint, Vec3 planeNormal) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final sh = s.shape;
    if (sh == null) {
      _err = 'mirroring needs a kernel-backed solid';
      return null;
    }
    final n = planeNormal.normalized();
    if (n.length < 0.5) {
      _err = 'the mirror plane has no normal direction';
      return null;
    }
    return _wrapOwned(
        ffi,
        sh.mirrored(
            planePoint.x, planePoint.y, planePoint.z, n.x, n.y, n.z));
  }

  // ---- M217: Delete Face and Direct Edit --------------------------------

  /// Shared preamble: a kernel, a live B-Rep and a non-empty face set. Every
  /// one of the three below needs exactly this, and each of the three getting
  /// its own copy is how they would have drifted.
  OcctShape? _facesInput(KernelSolid base, List<int> faceIds, String what) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final sh = base.shape;
    if (sh == null || sh.disposed) {
      _err = '$what needs a kernel-backed solid';
      return null;
    }
    if (faceIds.isEmpty) {
      _err = 'no faces selected';
      return null;
    }
    // A pick that could not be mapped to a topological face arrives as -1 (see
    // OcctMeshData.topoFaceId). Passing it on would delete or move whichever
    // face the kernel happened to have at a bogus index — refuse instead.
    for (final id in faceIds) {
      if (id < 1) {
        _err = 'a selected face could not be identified on the body';
        return null;
      }
    }
    return sh;
  }

  @override
  KernelSolid? deleteFaces(KernelSolid base, List<int> faceIds) {
    final sh = _facesInput(base, faceIds, 'Delete Face');
    if (sh == null) return null;
    final ffi = _ffi!;
    final out = ffi.deleteFaces(sh, faceIds);
    if (out == null) _err = ffi.lastError();
    return _wrapOwned(ffi, out);
  }

  @override
  KernelSolid? moveFaces(KernelSolid base, List<int> faceIds, Vec3 delta) {
    final sh = _facesInput(base, faceIds, 'Move Faces');
    if (sh == null) return null;
    if (delta.length < 1e-9) {
      _err = 'nothing to move — the distance is zero';
      return null;
    }
    final ffi = _ffi!;
    final out = ffi.moveFaces(sh, faceIds, delta.x, delta.y, delta.z);
    if (out == null) _err = ffi.lastError();
    return _wrapOwned(ffi, out);
  }

  @override
  KernelSolid? scaleSolid(KernelSolid base, Vec3 centre, double factor) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final sh = base.shape;
    if (sh == null || sh.disposed) {
      _err = 'Scale needs a kernel-backed solid';
      return null;
    }
    if (!(factor > 0) || !factor.isFinite) {
      _err = 'the scale factor must be greater than zero';
      return null;
    }
    final out = ffi.scaleShape(sh, centre.x, centre.y, centre.z, factor);
    if (out == null) _err = ffi.lastError();
    return _wrapOwned(ffi, out);
  }
}

/// Re-matches [profiles] against the current regions of [sketchName] and
/// returns the loop groups to hand the kernel, or an error string.
///
/// Shared by extrude and revolve: both pick profiles from a sketch the same
/// way, and duplicating this was how the two would have drifted apart.
(List<List<List<Offset>>>?, PlaneFrame?, String?) resolveProfiles(
    PartModel part, String sketchName, List<ProfileSel> profiles,
    {OccurrenceAt? at}) {
  final cs = part.sketchByName(sketchName);
  if (cs == null) return (null, null, 'sketch "$sketchName" no longer exists');
  final regions = regionsFrom(profileLoops(cs.model));
  if (regions.isEmpty) return (null, null, 'no closed profile in "$sketchName"');
  final groups = <List<List<Offset>>>[];
  for (final sel in profiles) {
    final anchor = Offset(sel.ax, sel.ay);
    final best = regionForSel(regions, sel);
    // sanity: the anchor should still sit INSIDE the matched region, or at
    // least the region should not have changed beyond recognition
    if (best == null ||
        (!pointInPolygon(anchor, best.outer.pts) &&
            (best.outer.area - sel.area).abs() > 0.5 * sel.area)) {
      return (null, null, 'a picked profile could not be found any more');
    }
    // M221 — the anchor is the region's, not its outer loop's, so a ring and
    // the disc in its hole stay two different selections. Writing it back here
    // is also what migrates a document saved before that rule.
    final ip = regionAnchor(best);
    sel.ax = ip.dx;
    sel.ay = ip.dy;
    sel.area = best.outer.area;
    groups.add([best.outer.pts, for (final h in best.holes) h.pts]);
  }
  if (groups.isEmpty) return (null, null, 'no profile selected');
  // M212 — a PATTERN occurrence built with Adjust reads the same profile on a
  // MOVED plane, so the caller may hand in the frame. [at] also decides
  // whether the profile is read mirrored, which is the only way a reflected
  // occurrence can keep a right-handed frame (see [OccurrenceAt]).
  if (at != null) {
    if (at.mirrorInV) {
      for (final g in groups) {
        for (var i = 0; i < g.length; i++) {
          g[i] = [for (final p in g[i]) Offset(p.dx, -p.dy)];
        }
      }
    }
    return (groups, at.frame, null);
  }
  return (groups, sketchFrameOf(cs), null);
}

/// Recomputes [f] against the CURRENT model state and stores the resulting
/// solid, or an honest [PartFeature.computeError] (Inventor's sick-feature
/// behaviour, minus the guessing).
///
/// [base] is the accumulated solid of this feature's body at this position.
/// A body-modifying feature (fillet, chamfer) REQUIRES it — that is its
/// input, not something to combine with afterwards.
/// [at] moves the build somewhere else — M212's Adjust pattern occurrences,
/// which are rebuilt where they land instead of copied. Null (the normal
/// case) builds the feature on its own sketch plane.
bool recomputeFeature(PartModel part, PartFeature f, PartKernel kernel,
    {KernelSolid? base, OccurrenceAt? at}) {
  // Two spans, one nested inside the other. The aggregate answers "what does a
  // feature rebuild cost"; the per-KIND one answers "which kind", and that is
  // the question an optimisation actually needs — an extrude and a loft on the
  // same part differ by more than an order of magnitude, and a single average
  // over both is a number that describes neither (M75, again).
  final ok = Perf.span(
      'kernel.feature',
      () => Perf.span('kernel.feature.${f.kind}',
          () => _recomputeFeature(part, f, kernel, base, at)));
  Perf.count('kernel.feature.${ok ? 'ok' : 'fail'}');
  // M164 — every feature rebuild, named, with its outcome. A part that comes
  // back different after a reopen is a SEQUENCE of these going wrong, and
  // until now the log showed only the ones that happened to toast.
  final tris = f.solid?.mesh.indices.length;
  Log.i(
      'feature',
      '${ok ? "ok  " : "FAIL"} ${f.name} (${f.kind}) body=${f.bodyName} '
          'op=${f.output}'
          '${base == null ? "" : " base=present"}'
          '${tris == null ? " solid=null" : " tris=${tris ~/ 3}"}'
          '${f.computeError == null ? "" : "  err=${f.computeError}"}');
  // M185 — on FAILURE, what it was built FROM.
  //
  // The line above says a feature did not build; it never said with which
  // numbers. Reading a report then meant asking for the part file just to
  // learn the height of the extrusion that failed. The parameters come from
  // the feature's own toJson, so this cannot fall behind as kinds are added,
  // and it is failure-only because the same dump on every successful rebuild
  // would be tens of lines per recompute of a healthy part.
  if (!ok) {
    try {
      Log.w('feature', '${f.name} was built from: ${jsonEncode(f.toJson())}');
    } catch (e) {
      Log.w('feature', '${f.name} parameters are not serialisable: $e');
    }
  }
  return ok;
}

bool _recomputeFeature(PartModel part, PartFeature f, PartKernel kernel,
    KernelSolid? base, [OccurrenceAt? at]) {
  // M182 — a failing recompute leaves the feature SICK, honestly, per the
  // repo's long-standing contract ("deleting the profile marks the feature
  // sick, honestly", m56): it holds no solid and reports its error. The
  // 'cannot break' guarantees live elsewhere — visibility never reaches the
  // fold, a failure poisons its own body instead of spawning a phantom, and
  // a failed pass is not settled/projection-synced or treated as good.
  // S11 — the SWEEP decides for itself whether its solid must be thrown away.
  //
  // This unconditional dispose is why the field's sweep ran three times. Every
  // path into a rebuild lands here and destroys the result before the feature
  // that owns it is ever asked whether the inputs changed, so a guard further
  // down could never fire — it would always be looking at a null solid. Only
  // recomputeAllFeatures escapes it, and only because its own builtSig check
  // sits BEFORE the call.
  //
  // Scoped to sweep deliberately. Every other kind keeps the exact behaviour
  // it had, and [_recomputeSweep] disposes on every path that does not reuse,
  // so the M182 contract above ("a failing recompute leaves the feature SICK")
  // holds unchanged for it too.
  if (f is SweepFeature) {
    f.computeError = null;
    return _recomputeSweep(part, f, kernel);
  }
  f.disposeSolid();
  f.computeError = null;
  if (f is BodyModifyFeature) return _recomputeBodyModify(f, kernel, base);
  // M217 — the face-side twin. Same contract: no base means the upstream
  // broke, and the feature goes sick honestly rather than materialising.
  if (f is FaceModifyFeature) return _recomputeFaceModify(f, kernel, base);
  if (f is PatternFeature) return _recomputePattern(part, f, kernel, base);
  if (f is HoleFeature) return _recomputeHole(part, f, kernel, base);
  if (f is CombineFeature) return _recomputeCombine(part, f, kernel, base);
  if (f is SplitFeature) return _recomputeSplit(part, f, kernel, base);
  if (f is ExtrudeFeature) return _recomputeExtrude(part, f, kernel, base, at);
  if (f is RevolveFeature) return _recomputeRevolve(part, f, kernel, base, at);
  if (f is LoftFeature) return _recomputeLoft(part, f, kernel);
  if (f is CoilFeature) return _recomputeCoil(part, f, kernel);
  f.computeError = 'unknown feature kind "${f.kind}"';
  return false;
}

/// Human label for an extent, used in error messages and tooltips.
String extentLabel(FeatureExtent e) => switch (e) {
      FeatureExtent.toNext => 'To Next',
      FeatureExtent.toFace => 'To',
      FeatureExtent.throughAll => 'Through All',
      FeatureExtent.distance => 'Distance',
    };

/// Signed extent of [solid] along [frame]'s normal, measured from the sketch
/// origin: (tMin, tMax). Null when the solid carries no B-Rep — on a test
/// fake that is the truth, and the caller reports it instead of guessing a
/// number.
(double, double)? bodySpanAlong(KernelSolid solid, PlaneFrame frame) {
  final bb = solid.shape?.bbox();
  if (bb == null || bb.length != 6) return null;
  // Deliberately this BODY's box, not partContentBounds(): Through All must
  // pass through the body it builds into, and the whole-part bounds include
  // other bodies and sketch curves, which would silently overshoot and also
  // break the "nothing lies above the sketch plane" answer.
  final (lo, hi) = boxSpanAlong(
      Vec3(bb[0], bb[1], bb[2]), Vec3(bb[3], bb[4], bb[5]), frame.n);
  // measured FROM the sketch plane
  final base = frame.origin.dot(frame.n);
  return (lo - base, hi - base);
}

/// Distance from the sketch plane to the next face of [solid] along [dir],
/// looking from every picked profile anchor. Null when nothing is hit.
///
/// The MINIMUM positive hit wins: "To Next" means the next face encountered,
/// and on a stepped block the nearest step is that face. Rays start on the
/// sketch plane, so a sketch drawn ON a face registers that face at t≈0 and
/// it is filtered out — otherwise every To Next would resolve to zero.
double? nextFaceDistance(
    KernelSolid solid, PlaneFrame frame, List<ProfileSel> profiles, Vec3 dir) {
  final shape = solid.shape;
  if (shape == null) return null;
  var best = double.infinity;
  for (final p in profiles) {
    final o = frame.toWorld(Offset(p.ax, p.ay));
    final hits = shape.rayHits(o.x, o.y, o.z, dir.x, dir.y, dir.z);
    for (final t in hits) {
      if (t > 1e-6 && t < best) best = t;
    }
  }
  return best.isFinite ? best : null;
}

/// Where the extrusion should stop for [FeatureExtent.toFace].
///
/// A planar termination face is solved analytically — that is exact at any
/// distance and needs no tessellation. Anything else (a cylinder, an
/// irregular surface) has no single termination plane, so it falls back to
/// the ray cast, which is also what Inventor's "Alternate/Minimum Solution"
/// toggles are choosing between.
double? faceDistance(KernelSolid solid, PlaneFrame frame,
    List<ProfileSel> profiles, Vec3 dir, FaceSel face) {
  final fn = Vec3(face.nx, face.ny, face.nz);
  final denom = dir.dot(fn);
  if (denom.abs() > 1e-9 && profiles.isNotEmpty) {
    final p = Vec3(face.px, face.py, face.pz);
    var best = double.infinity;
    for (final s in profiles) {
      final o = frame.toWorld(Offset(s.ax, s.ay));
      final t = (p - o).dot(fn) / denom;
      if (t > 1e-6 && t < best) best = t;
    }
    if (best.isFinite) return best;
  }
  return nextFaceDistance(solid, frame, profiles, dir);
}

/// Turns a revolve's Extents into the (sweep, startOffset) pair in DEGREES,
/// or an honest error.
///
/// The rotational twin of [resolveExtrudeSpan]. "To Next" cannot be a ray cast
/// here: a revolved profile travels on a circle, so the question is the ANGLE
/// at which it first meets material, which is what [PartKernel.revolveHits]
/// answers. The smallest positive angle across the picked profile anchors
/// wins, for the same reason the nearest hit wins for an extrude.
/// [axPy]/[axDy] override the stored axis. Only M212's mirrored pattern
/// occurrences pass them: their profile is read mirrored in v, so the axis
/// that belongs to it is mirrored in v too. Everything else leaves them null
/// and gets the feature's own axis.
(double, double, String?) resolveRevolveSweep(
    RevolveFeature f, PlaneFrame frame, KernelSolid? base, PartKernel kernel,
    {double? axPy, double? axDy}) {
  final ay = axPy ?? f.axPy, ady = axDy ?? f.axDy;
  if (f.extent == FeatureExtent.distance) {
    final sweep = f.sweepDeg;
    return (sweep, f.startOffsetDeg,
        sweep > 0 ? null : 'angle must be greater than 0');
  }
  if (base == null) {
    return (
      0,
      0,
      '${extentLabel(f.extent)} needs an existing body — '
          'a base feature has nothing to terminate against'
    );
  }
  if (f.extent == FeatureExtent.throughAll) {
    // A full turn passes through everything there is to pass through, and
    // needs no measurement at all.
    return (360.0, 0.0, null);
  }
  // The axis lives in sketch coordinates; the body does not.
  final axP = frame.toWorld(Offset(f.axPx, ay));
  final axD = frame.u * f.axDx + frame.v * ady;
  final flipped = f.direction == ExtrudeDirection.flipped;
  final face = f.extentFace;
  if (f.extent == FeatureExtent.toFace && face == null) {
    return (0, 0, 'no termination face selected');
  }
  var best = double.infinity;
  for (final s in f.profiles) {
    final p = frame.toWorld(Offset(s.ax, s.ay));
    // M144 — "To <face>" asks a DIFFERENT question from To Next: not the
    // first material met, but the angle at which the sweep reaches THAT face,
    // which it may only do after passing through others.
    final hits = face == null
        ? kernel.revolveHits(base, axP, axD, p)
        : kernel.revolveHitsFace(
            base, axP, axD, p, Vec3(face.px, face.py, face.pz));
    // Flipped sweeps the other way, so "the next face" is the nearest hit
    // going backwards — i.e. the largest angle, read as 360 minus it.
    for (final a in hits) {
      final v = flipped ? 360.0 - a : a;
      if (v > 1e-6 && v < best) best = v;
    }
  }
  if (!best.isFinite) {
    return (0, 0, 'the profile never meets the body as it revolves');
  }
  if (f.direction == ExtrudeDirection.symmetric ||
      f.direction == ExtrudeDirection.asymmetric) {
    final total = (2 * best).clamp(0.0, 360.0);
    return (total, -total / 2, null);
  }
  return (best, flipped ? -best : 0.0, null);
}

/// Turns Inventor's Extents into the (height, startOffset) pair the kernel
/// wants, or an honest error.
///
/// [base] is the body this feature builds into. Every extent except a plain
/// Distance resolves against it, which is exactly why Inventor greys those
/// options out on a base feature — there is nothing to terminate against.
(double, double, String?) resolveExtrudeSpan(
    ExtrudeFeature f, PlaneFrame frame, KernelSolid? base) {
  if (f.extent == FeatureExtent.distance) {
    final (h, z) = extrudeSpan(f.direction, f.distanceA, f.distanceB);
    return (h, z, h > 0 ? null : 'distance must be greater than 0');
  }
  if (base == null) {
    return (
      0,
      0,
      '${extentLabel(f.extent)} needs an existing body — '
          'a base feature has nothing to terminate against'
    );
  }
  final flipped = f.direction == ExtrudeDirection.flipped;
  final both = f.direction == ExtrudeDirection.symmetric ||
      f.direction == ExtrudeDirection.asymmetric;
  final dir = flipped ? frame.n * -1.0 : frame.n;

  if (f.extent == FeatureExtent.throughAll) {
    final span = bodySpanAlong(base, frame);
    if (span == null) {
      return (0, 0, 'Through All could not measure the body');
    }
    final (lo, hi) = span;
    // Overshoot both ends: a tool cap COPLANAR with a body cap is the classic
    // way to make an OCCT boolean fragile, and the overshoot costs nothing.
    final pad = 0.01 * ((hi - lo).abs() + 1.0) + 1.0;
    if (both) return (hi - lo + 2 * pad, lo - pad, null);
    if (flipped) {
      final h = -(lo - pad);
      return h > 0 ? (h, lo - pad, null) : (0, 0, 'nothing lies below the sketch plane');
    }
    final h = hi + pad;
    return h > 0 ? (h, 0.0, null) : (0, 0, 'nothing lies above the sketch plane');
  }

  final d = f.extent == FeatureExtent.toFace && f.extentFace != null
      ? faceDistance(base, frame, f.profiles, dir, f.extentFace!)
      : nextFaceDistance(base, frame, f.profiles, dir);
  if (d == null || !(d > 0)) {
    return (
      0,
      0,
      f.extent == FeatureExtent.toFace
          ? 'the termination face is not reachable from this profile'
          : 'no next face in that direction'
    );
  }
  // Symmetric/asymmetric measure the SAME resolved distance either side, the
  // way a symmetric Distance splits one typed value.
  if (both) return (2 * d, -d, null);
  return (d, flipped ? -d : 0.0, null);
}

bool _recomputeExtrude(PartModel part, ExtrudeFeature f, PartKernel kernel,
    KernelSolid? base, [OccurrenceAt? at]) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles, at: at);
  if (groups == null || frame == null) {
    f.computeError = err ?? 'profile resolution failed';
    return false;
  }
  final (height, zOff, spanErr) = resolveExtrudeSpan(f, frame, base);
  if (spanErr != null || !(height > 0)) {
    f.computeError = spanErr ?? 'distance must be greater than 0';
    return false;
  }
  final solid = kernel.extrude(groups, height, f.taperDeg, frame.mat34(zOff));
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
  return true;
}

bool _recomputeRevolve(PartModel part, RevolveFeature f, PartKernel kernel,
    KernelSolid? base, [OccurrenceAt? at]) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles, at: at);
  if (groups == null || frame == null) {
    f.computeError = err ?? 'profile resolution failed';
    return false;
  }
  if (f.axDx == 0 && f.axDy == 0) {
    f.computeError = 'no axis of revolution selected';
    return false;
  }
  // M212 — a MIRRORED occurrence reads its profile mirrored in v (see
  // [OccurrenceAt]), and the axis lives in those same sketch coordinates, so
  // it has to follow. Without this the mirrored profile would revolve about
  // a line it no longer touches.
  final mir = at != null && at.mirrorInV;
  final axPy = mir ? -f.axPy : f.axPy;
  final axDy = mir ? -f.axDy : f.axDy;
  final (sweep, startOffset, sweepErr) =
      resolveRevolveSweep(f, frame, base, kernel, axPy: axPy, axDy: axDy);
  if (sweepErr != null || !(sweep > 0)) {
    f.computeError = sweepErr ?? 'angle must be greater than 0';
    return false;
  }
  // Inventor's Symmetric/Flipped/Asymmetric rotate WHERE the sweep starts.
  // The shim always sweeps in the positive direction from the profile, so the
  // offset rides in the placement transform — the same trick extrudeSpan uses
  // for the linear case, and the reason neither path ever mirrors a solid.
  final solid = kernel.revolve(groups, sweep, f.axPx, axPy, f.axDx, axDy,
      frame.mat34Rotated(f.axPx, axPy, f.axDx, axDy, startOffset));
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
  return true;
}

/// World-space polyline of a [CurveSel], re-matched against its sketch.
///
/// The stored index is only a hint: it is checked against the fingerprint and,
/// if it no longer fits, every curve in the sketch is scored so a path
/// survives having geometry inserted before it.
(List<double>?, String?) resolvePath(PartModel part, CurveSel sel) {
  final cs = part.sketchByName(sel.sketchName);
  if (cs == null) return (null, 'the path sketch no longer exists');
  final frame = sketchFrameOf(cs);
  final geo = cs.model.geometry;
  List<Offset>? best;
  var bestScore = double.infinity;
  for (var i = 0; i < geo.length; i++) {
    final pts = sketchCurve(geo[i]);
    if (pts.length < 2) continue;
    // The hinted index wins outright when it still fits, so an unchanged
    // sketch costs one comparison rather than a full scan.
    final sc = sel.score(pts) - (i == sel.geoIndex ? 1e-6 : 0);
    if (sc < bestScore) {
      bestScore = sc;
      best = pts;
      sel.geoIndex = i;
    }
  }
  if (best == null) return (null, 'the path curve could not be found');
  final tol = 0.25 * (sel.length.abs() + 1.0);
  if (bestScore > tol) return (null, 'the path curve has changed too much');
  sel.x0 = best.first.dx;
  sel.y0 = best.first.dy;
  sel.x1 = best.last.dx;
  sel.y1 = best.last.dy;
  final out = <double>[];
  for (final p in best) {
    final w = frame.toWorld(p);
    out..add(w.x)..add(w.y)..add(w.z);
  }
  return (out, null);
}

/// S11 — the exact argument list [_recomputeSweep] hands the kernel.
///
/// Every value the swept solid depends on and nothing else. Written as digits
/// rather than hashed: a hash collision here would silently reuse the WRONG
/// solid, and a sweep is exactly the operation whose result nobody would look
/// at closely enough to notice. Full precision (a double's `toString()`
/// round-trips exactly in Dart), so two profiles differing in the last bit are
/// two different keys.
///
/// The cost is bounded by the profile size — the field's 1218-segment loop
/// produces a key of some tens of kilobytes, built in milliseconds, against a
/// sweep that took 102 seconds.
String _sweepArgSig(List<List<List<Offset>>> groups, List<double> mat34,
    List<double> pathPts, SweepFeature f) {
  final b = StringBuffer()
    ..write(f.orientation)
    ..write(',')
    ..write(f.taperDeg)
    ..write(',')
    ..write(f.twistDeg)
    ..write('|');
  for (final m in mat34) {
    b..write(m)..write(' ');
  }
  b.write('|');
  for (final p in pathPts) {
    b..write(p)..write(' ');
  }
  for (final g in groups) {
    b.write('|G');
    for (final loop in g) {
      b.write(';');
      for (final q in loop) {
        b..write(q.dx)..write(',')..write(q.dy)..write(' ');
      }
    }
  }
  return b.toString();
}

bool _recomputeSweep(PartModel part, SweepFeature f, PartKernel kernel) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles);
  if (groups == null || frame == null) {
    f.disposeSolid();
    f.computeError = err ?? 'profile resolution failed';
    return false;
  }
  final sel = f.path;
  if (sel == null) {
    f.disposeSolid();
    f.computeError = 'no path selected';
    return false;
  }
  final (pts, perr) = resolvePath(part, sel);
  if (pts == null) {
    f.disposeSolid();
    f.computeError = perr ?? 'path resolution failed';
    return false;
  }
  final mat34 = frame.mat34(0);
  // S11 — THE REBUILD GUARD.
  //
  // A user swept a 1218-segment profile and the same sweep ran three times,
  // identically: the preview, the commit, and recomputeAllFeatures folding the
  // part afterwards. All three logged tris=91646 and together they were 310.75
  // seconds, 53 % of the session. This removes the third.
  //
  // The claim it rests on is narrow and checkable: the swept solid is a pure
  // function of these arguments. resolveProfiles and resolvePath have just
  // re-read the sketches, so a changed profile, a moved path, a different
  // plane, orientation, taper or twist all produce a different key and rebuild
  // as before. The boolean base is absent from the key because it is absent
  // from the computation — the fold that consumes this solid runs outside.
  //
  // Resolution still happens on every call. It is the cheap half (reading two
  // sketches) and it is what makes the key trustworthy; skipping it would mean
  // guarding on the feature's parameters while the geometry moved underneath.
  final sig = _sweepArgSig(groups, mat34, pts, f);
  if (f.solid != null && f.sweptFrom == sig) {
    Perf.count('kernel.sweep.reuse');
    return true;
  }
  // Not reusable: the old solid goes now, exactly as the shared entry point
  // would have done, and before the new one is built so the two never coexist.
  f.disposeSolid();
  final solid = kernel.sweep(groups, mat34, pts,
      orientation: f.orientation,
      taperDeg: f.taperDeg,
      twistDeg: f.twistDeg);
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
  f.sweptFrom = sig;
  return true;
}

/// M225 — the sketch points a hole feature drills on, or an error.
///
/// Nearest point wins and the placement is rewritten to it, so moving a point
/// moves its hole. Two placements landing on ONE point is refused rather than
/// drilling the same hole twice: that is the state a deleted point leaves
/// behind, and it is exactly the confusion M217's resolveFaces refuses for
/// faces.
(List<Offset>?, String?) holeCentresFor(SketchModel sk, List<HolePlace> places) {
  if (places.isEmpty) return (null, 'no hole placed');
  // The SAME rule the sketch-driven pattern uses (M212): a tagged sketch
  // point, never a circle centre. Two definitions of "a point in this sketch"
  // is two chances for a hole and a pattern occurrence to disagree about where
  // they are.
  final pts = sketchPatternPoints(sk);
  if (pts.isEmpty) {
    return (null, 'no sketch point in "${sk.name}" to place a hole on');
  }
  final out = <Offset>[];
  final taken = <int>{};
  for (final pl in places) {
    final anchor = Offset(pl.x, pl.y);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (pts[i] - anchor).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (!taken.add(best)) {
      return (null, 'two holes resolved to the same sketch point — one of '
          'the points they were placed on is gone');
    }
    pl.x = pts[best].dx;
    pl.y = pts[best].dy;
    out.add(pts[best]);
  }
  return (out, null);
}

/// A closed polygon on the circle, in the sketch's own (u,v).
///
/// A polygon and not an arc pair because that is what the kernel path takes —
/// and it stays a true cylinder anyway: [arcFitLoop] recognises points that
/// lie on one circle and hands OCCT exact arcs. 96 points is what a DRAWN
/// circle gets on the way to a profile (`sampleEntity(g, arcSamples: 96)`), so
/// a hole is tessellated exactly like the circle a user would have drawn for
/// it — same input to arcFitLoop, same faces out of the kernel.
List<Offset> holeProfile(Offset c, double r, {int n = 96}) {
  return [
    for (var i = 0; i < n; i++)
      c + Offset(r * math.cos(2 * math.pi * i / n),
          r * math.sin(2 * math.pi * i / n))
  ];
}

bool _recomputeHole(
    PartModel part, HoleFeature f, PartKernel kernel, KernelSolid? base) {
  if (base == null) {
    f.computeError = 'a hole needs a body to drill into';
    return false;
  }
  final cs = part.sketchByName(f.sketchName);
  if (cs == null) {
    f.computeError = 'sketch "${f.sketchName}" no longer exists';
    return false;
  }
  final (centres, err) = holeCentresFor(cs.model, f.places);
  if (centres == null) {
    f.computeError = err ?? 'the hole has nowhere to go';
    return false;
  }
  final r = f.dia / 2;
  if (!(r > 0)) {
    f.computeError = 'diameter must be greater than 0';
    return false;
  }
  final frame = sketchFrameOf(cs);
  double height;
  double start; // where the tool begins, along n
  if (f.extent == FeatureExtent.throughAll) {
    // Long enough to leave the part on both sides, and STARTED outside it: a
    // tool face exactly on the body's face is the classic boolean coin toss.
    final (lo, hi) = originExtentBounds(part);
    final span = (hi - lo).length + 20.0;
    if (!span.isFinite || span <= 0) {
      f.computeError = 'the part has no extent to drill through';
      return false;
    }
    height = span;
    start = f.flip ? -1.0 : -(span - 1.0);
  } else if (f.extent == FeatureExtent.distance) {
    height = f.depth;
    if (!(height > 0)) {
      f.computeError = 'depth must be greater than 0';
      return false;
    }
    start = f.flip ? 0.0 : -height;
  } else {
    // To Next / To Face need a face reference the hole panel does not offer.
    // Saying so beats treating it as a distance and drilling the wrong depth.
    f.computeError =
        '${extentLabel(f.extent)} is not available for a hole yet';
    return false;
  }
  final groups = [
    for (final c in centres) [holeProfile(c, r)]
  ];
  final tool = kernel.extrude(groups, height, 0, frame.mat34(start));
  if (tool == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  var cut = kernel.cutSolids(base, tool);
  tool.dispose();
  if (cut == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  // M226 — the shape at the MOUTH, cut as a second tool rather than folded
  // into the first. Two cuts of simple solids is what OCCT is happiest with,
  // and it keeps the counterbore's flat bottom and the countersink's cone out
  // of the profile arithmetic entirely.
  if (f.type != HoleType.simple) {
    final (mouth, mErr) = _holeMouthTool(f, centres, r, frame, kernel);
    if (mouth == null) {
      cut.dispose();
      f.computeError = mErr ?? 'the hole mouth could not be built';
      return false;
    }
    final done = kernel.cutSolids(cut, mouth);
    mouth.dispose();
    cut.dispose();
    if (done == null) {
      f.computeError = kernel.lastError;
      return false;
    }
    cut = done;
  }
  f.solid = cut;
  return true;
}

/// M228 — the half-space tool: a slab covering everything on ONE side of
/// [frame], big enough to swallow the part.
///
/// The same box [sliceSolidAt] builds for Slice Graphics, and that is the
/// point: Slice Graphics has cut the near side away on every device session
/// since M168, so the sizing is proven. What differs is that this one is
/// PERMANENT and can be flipped.
KernelSolid? halfSpaceTool(
    PartKernel kernel, PartModel part, PlaneFrame frame, bool flip) {
  final (lo, hi) = originExtentBounds(part);
  final r = (hi - lo).length + 10.0;
  if (!r.isFinite || r <= 0) return null;
  final profile = [
    [
      [Offset(-r, -r), Offset(r, -r), Offset(r, r), Offset(-r, r)]
    ]
  ];
  // Extruding along +n covers the +side; the -side is the same box started a
  // full length back. Never both, and never zero-thickness at the plane.
  return kernel.extrude(profile, r, 0, frame.mat34(flip ? -r : 0));
}

bool _recomputeSplit(
    PartModel part, SplitFeature f, PartKernel kernel, KernelSolid? base) {
  if (base == null) {
    f.computeError = 'a split needs a body to trim';
    return false;
  }
  if (f.frame.n.length < 1e-9) {
    f.computeError = 'the splitting plane is gone';
    return false;
  }
  final tool = halfSpaceTool(kernel, part, f.frame, f.flip);
  if (tool == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  final cut = kernel.cutSolids(base, tool);
  tool.dispose();
  if (cut == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = cut;
  return true;
}

/// M227 — the live feature of [body] as of just before [before] in the
/// timeline, or null when that body has nothing built there.
///
/// "As of" is the whole point: features of the tool body that come LATER may
/// still be holding a solid from the previous pass, and folding one of those
/// in would combine with a body from the future.
PartFeature? bodyFeatureBefore(PartModel part, String body, int before) {
  PartFeature? best;
  for (final f in part.features) {
    // BEFORE is by seq, which is the timeline the browser shows and the
    // marker walks — `features` is kept in that order but is not sorted by it,
    // and the answer must be the one the user can see.
    if (f.bodyName != body || f.rolledBack || f.seq >= before) continue;
    if (f.solid == null) continue;
    if (best == null || f.seq > best.seq) best = f;
  }
  return best;
}

bool _recomputeCombine(
    PartModel part, CombineFeature f, PartKernel kernel, KernelSolid? base) {
  if (base == null) {
    f.computeError = 'a combine needs a base body';
    return false;
  }
  if (f.tools.isEmpty) {
    f.computeError = 'no tool body selected';
    return false;
  }
  var acc = base;
  var owned = false; // whether acc is ours to dispose
  for (final name in f.tools) {
    if (name == f.bodyName) {
      if (owned) acc.dispose();
      f.computeError = 'a body cannot be combined with itself';
      return false;
    }
    final src = bodyFeatureBefore(part, name, f.seq);
    if (src?.solid == null) {
      if (owned) acc.dispose();
      // A tool built LATER in the timeline is the commonest way to get here,
      // and saying "not built yet at this point" is the difference between a
      // fixable mistake and a mystery.
      f.computeError = 'body "$name" has nothing built before this feature';
      return false;
    }
    final out = combineSolids(kernel, f.op, acc, src!.solid!);
    if (out == null) {
      if (owned) acc.dispose();
      f.computeError = kernel.lastError;
      return false;
    }
    if (owned) acc.dispose();
    acc = out;
    owned = true;
    // The tool is folded away unless Inventor's Keep Toolbody says otherwise.
    // Marking it here is what makes it vanish from the viewport, the browser's
    // body list and the STEP export in one move — they all read the same
    // solid/!consumedByJoin rule (M214).
    if (!f.keepTool) src.consumedByJoin = true;
  }
  f.solid = acc;
  return true;
}

/// The counterbore / spotface pocket or the countersink cone, as ONE tool for
/// every placement.
(KernelSolid?, String?) _holeMouthTool(HoleFeature f, List<Offset> centres,
    double r, PlaneFrame frame, PartKernel kernel) {
  if (f.type == HoleType.countersink) {
    final bigR = f.csDia / 2;
    if (!(bigR > r)) {
      return (null, 'the countersink must be wider than the hole');
    }
    if (!(f.csAngle > 0) || f.csAngle >= 180) {
      return (null, 'the countersink angle must be between 0 and 180 deg');
    }
    // Included angle: the cone's half-angle is what the wall makes with the
    // axis, so the depth follows from the radius it has to open out by.
    final half = f.csAngle / 2;
    final dz = (bigR - r) / math.tan(half * math.pi / 180);
    if (!(dz > 0) || !dz.isFinite) {
      return (null, 'the countersink angle leaves it no depth');
    }
    // The shim's taper is Inventor's sign: POSITIVE flares outward along the
    // extrusion. Drilling inwards the tool runs from the small end up to the
    // face, so it flares; flipped it starts wide at the face and closes, which
    // is the same cone read the other way.
    final profileR = f.flip ? bigR : r;
    final taper = f.flip ? -half : half;
    final start = f.flip ? 0.0 : -dz;
    final groups = [
      for (final c in centres) [holeProfile(c, profileR)]
    ];
    final tool = kernel.extrude(groups, dz, taper, frame.mat34(start));
    return (tool, tool == null ? kernel.lastError : null);
  }
  // Counterbore and spotface: the same flat-bottomed pocket.
  final bigR = f.cbDia / 2;
  if (!(bigR > r)) {
    return (null, '${holeTypeLabel(f.type).toLowerCase()} must be wider than '
        'the hole');
  }
  if (!(f.cbDepth > 0)) {
    return (null, '${holeTypeLabel(f.type).toLowerCase()} depth must be '
        'greater than 0');
  }
  final groups = [
    for (final c in centres) [holeProfile(c, bigR)]
  ];
  final tool = kernel.extrude(
      groups, f.cbDepth, 0, frame.mat34(f.flip ? 0.0 : -f.cbDepth));
  return (tool, tool == null ? kernel.lastError : null);
}

bool _recomputeLoft(PartModel part, LoftFeature f, PartKernel kernel) {
  if (f.sections.length < 2) {
    f.computeError = 'a loft needs at least 2 sections';
    return false;
  }
  final wires = <List<Offset>>[];
  final mats = <List<double>>[];
  for (var i = 0; i < f.sections.length; i++) {
    // Each section lives in its OWN sketch, so profiles are resolved one at a
    // time rather than in a single pass like extrude does.
    final (groups, frame, err) = resolveProfiles(
        part, f.sectionSketches[i], [f.sections[i]]);
    if (groups == null || frame == null) {
      f.computeError = err ?? 'section ${i + 1} could not be resolved';
      return false;
    }
    // Outer loop only: a lofted section with holes would need the holes
    // lofted to matching holes in every other section, which the panel does
    // not offer and OCCT will not infer.
    wires.add(groups.first.first);
    mats.add(frame.mat34(0));
  }
  final solid = kernel.loft(wires, mats,
      solid: f.solidOutput, ruled: f.ruled, closed: f.closedLoop);
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
  return true;
}

bool _recomputeCoil(PartModel part, CoilFeature f, PartKernel kernel) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles);
  if (groups == null || frame == null) {
    f.computeError = err ?? 'profile resolution failed';
    return false;
  }
  if (f.axDx == 0 && f.axDy == 0) {
    f.computeError = 'no axis selected';
    return false;
  }
  final (revs, h) = f.resolved;
  if (!(revs > 0)) {
    f.computeError = 'revolutions must be greater than 0';
    return false;
  }
  // The axis is stored in sketch coordinates; the kernel works in world.
  final axP = frame.toWorld(Offset(f.axPx, f.axPy));
  final axD = frame.u * f.axDx + frame.v * f.axDy;
  final solid = kernel.coil(groups, frame.mat34(0), axP, axD,
      revolutions: revs,
      height: h,
      taperDeg: f.taperDeg,
      clockwise: f.clockwise);
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
  return true;
}


/// M217 — Delete Face and Direct Edit.
///
/// The whole reason this is separate from [_recomputeBodyModify]: the
/// selections are FACES, and a face is re-found by [resolveFaces] against the
/// live mesh rather than by the edge machinery.
bool _recomputeFaceModify(
    FaceModifyFeature f, PartKernel kernel, KernelSolid? base) {
  if (base == null) {
    f.computeError = 'nothing to modify — no solid before this feature';
    return false;
  }
  // Scale is the one operation with no face selection: it takes the whole
  // body, which is what Inventor's Direct > Scale does too.
  final isScale = f is DirectEditFeature && f.op == DirectOp.scale;
  if (f.faces.isEmpty && !isScale) {
    f.computeError = 'no faces selected';
    return false;
  }

  if (isScale) {
    final d = f as DirectEditFeature;
    final centre = meshCentreOf(base.mesh);
    final out = kernel.scaleSolid(base, centre, d.factor);
    if (out == null) {
      f.computeError = kernel.lastError.isEmpty
          ? 'scaling failed'
          : kernel.lastError;
      return false;
    }
    f.lostFaces = 0;
    f.solid = out;
    return true;
  }

  final live = facesOf(base.mesh);
  if (live.isEmpty) {
    f.computeError = kernel.lastError.isEmpty
        ? 'the body reports no identifiable faces — a build without face '
            'identity cannot delete or move one'
        : kernel.lastError;
    return false;
  }
  final (ids, lost) = resolveFaces(f.faces, live);
  f.lostFaces = lost;
  if (ids.isEmpty) {
    f.computeError = 'none of the selected faces exist any more';
    return false;
  }

  KernelSolid? out;
  if (f is DeleteFaceFeature) {
    out = kernel.deleteFaces(base, ids);
  } else if (f is DirectEditFeature) {
    out = kernel.moveFaces(base, ids, f.delta);
  }
  if (out == null) {
    f.computeError =
        kernel.lastError.isEmpty ? 'the edit failed' : kernel.lastError;
    return false;
  }
  f.solid = out;
  // A partial loss is not a failure — Inventor keeps editing the faces that
  // survived — but it must not be silent either. Same rule as a fillet whose
  // edge set partly survives.
  if (lost > 0) {
    Log.i('feature',
        '${f.name}: $lost of ${f.faces.length} picked faces no longer exist');
  }
  return true;
}

bool _recomputeBodyModify(
    BodyModifyFeature f, PartKernel kernel, KernelSolid? base) {
  if (base == null) {
    // Inventor greys Fillet out with nothing to fillet; a saved file can
    // still reach this if the upstream feature broke, so say so plainly.
    f.computeError = 'nothing to modify — no solid before this feature';
    return false;
  }
  if (f.edges.isEmpty) {
    f.computeError = 'no edges selected';
    return false;
  }
  final live = kernel.edgesOf(base);
  if (live.isEmpty) {
    f.computeError = kernel.lastError.isEmpty
        ? 'the body has no selectable edges'
        : kernel.lastError;
    return false;
  }
  final (ids, src, lost) = f.resolveEdges(live);
  if (ids.isEmpty) {
    f.computeError = 'none of the selected edges exist any more';
    return false;
  }
  KernelSolid? out;
  final report = BlendReport();
  var sizeLabel = '';
  if (f is FilletFeature) {
    // Straight lookup through the source indices resolveEdges reported: no
    // second matching pass, so the radii cannot drift away from the ids.
    final radii = [
      for (final i in src)
        i < f.radii.length
            ? f.radii[i]
            : (f.radii.isEmpty ? 2.0 : f.radii.last)
    ];
    // An all-zero list means every edge is constant, and the shim then skips
    // the variable-radius path entirely.
    final radii2 = f.radii2.any((r) => r > 0)
        ? [for (final i in src) i < f.radii2.length ? f.radii2[i] : 0.0]
        : const <double>[];
    sizeLabel = 'r=${radii.isEmpty ? "?" : radii.first} mm';
    out = kernel.filletEdges(base, ids, radii,
        radii2: radii2, report: report);
  } else if (f is ChamferFeature) {
    final (d1, d2, ang) = f.kernelParams;
    sizeLabel = 'd=$d1 mm';
    out = kernel.chamferEdges(base, ids, f.mode, d1, d2, ang, report: report);
  }
  if (out == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = out;
  // A partial loss is not a failure — Inventor keeps filleting the edges that
  // survived — but it must not be silent either.
  if (lost > 0) {
    Log.i('feature',
        '${f.name}: $lost of ${f.edges.length} picked edges no longer exist');
  }
  // M183 — and neither is a blend the kernel had to adjust to build. Skipped
  // edges and a nudged size are both departures from what was asked for, and
  // a CAD system that makes those quietly is one you cannot trust a dimension
  // from.
  final note = report.note(ids.length, sizeLabel);
  if (note != null) Log.i('feature', '${f.name}: $note');
  return true;
}

// ---------------------------------------------------------------------------
// M212 — building a pattern
// ---------------------------------------------------------------------------

/// Where an OCCURRENCE of a feature is rebuilt, for [PatternCompute.adjust].
///
/// [frame] is the feature's own sketch plane, moved to the occurrence.
/// [mirrorInV] says the profile must be read mirrored in v — the price of
/// keeping a reflected frame right-handed, and inseparable from it (see
/// [mirroredFrame]).
class OccurrenceAt {
  final PlaneFrame frame;
  final bool mirrorInV;
  const OccurrenceAt(this.frame, {this.mirrorInV = false});
}

/// Which SKETCH plane a feature is built on, or null when it has none.
///
/// Only the sketch-based kinds have one, and only they can be rebuilt
/// somewhere else. This is what decides whether Adjust has anything to do.
String? featureSketchOf(PartFeature f) =>
    f.sketchName.isEmpty ? null : f.sketchName;

/// The points a sketch-driven pattern places its occurrences on.
///
/// Inventor drives these patterns from sketch POINTS — the centre points a
/// sketch carries, not its curves. M209 made a point a tagged circle (the
/// QCAD core has no point entity), so that tag is what identifies one here;
/// circle centres are deliberately NOT included, or every hole in the sketch
/// would silently become a pattern position.
///
/// Returned in the sketch's own coordinates, in geometry order, so a stored
/// base point can be matched against them.
List<Offset> sketchPatternPoints(SketchModel m) {
  final out = <Offset>[];
  for (final g in m.geometry) {
    if (!g.isSketchPoint || g.data.length < 2) continue;
    out.add(Offset(g.data[0], g.data[1]));
  }
  return out;
}

/// Centre of a solid, used as the reference point of a pattern: the middle of
/// its bounding box.
///
/// The bounding box and not the centre of mass, deliberately — it is what the
/// shim already reports for free, and the reference point only ever measures
/// a DISPLACEMENT (fixed-orientation circular occurrences, the default base
/// point of a sketch-driven pattern), so the two differ by a constant that
/// cancels. Null when the solid carries no B-Rep, and the callers then say so
/// rather than pretending the part is centred on the origin.
Vec3? solidCentre(KernelSolid s) {
  final bb = s.shape?.bbox();
  if (bb == null || bb.length != 6) return null;
  return Vec3(
      (bb[0] + bb[3]) / 2, (bb[1] + bb[4]) / 2, (bb[2] + bb[5]) / 2);
}

/// Surface normal of the display mesh nearest [q], looking along [dir].
///
/// Used by a sketch-driven pattern's Variable Orientation, which has to know
/// which way the shell faces where each occurrence lands. The nearest
/// triangle by point-to-plane distance wins, restricted to triangles facing
/// against [dir] so the far side of a thin wall cannot answer for the near
/// one. Null when the mesh carries no triangles.
Vec3? meshNormalAt(OcctMeshData m, Vec3 q, Vec3 dir) {
  Vec3? best;
  var bestD = double.infinity;
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final i0 = m.indices[t] * 3,
        i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    final n = (b - a).cross(c - a);
    if (n.length < 1e-12) continue;
    final nn = n.normalized();
    if (nn.dot(dir) > 0) continue; // facing away from where we are looking
    final centre = (a + b + c) * (1 / 3);
    final d = (centre - q).length;
    if (d < bestD) {
      bestD = d;
      best = nn;
    }
  }
  return best;
}

/// One thing a pattern copies.
///
/// Two kinds, because features come in two kinds. A feature that brings its
/// own volume is copied as a SOLID and combined with the body by its own
/// boolean. A fillet or a chamfer has no volume to copy — it is a
/// modification — so what is repeated is the OPERATION: the same blend, on
/// the edges the occurrence lands on. Inventor patterns both, and a pattern
/// that silently dropped the fillet would produce sharp copies of a rounded
/// original, which is a wrong part rather than a missing one.
class _PatternTool {
  final PartFeature? source; // null in solid mode
  final KernelSolid? solid; // null for a blend
  final String output; // 'join' | 'cut' | 'intersect'
  final BodyModifyFeature? blend; // the fillet/chamfer to re-apply
  _PatternTool(this.source, this.solid, this.output, {this.blend});
}

/// A picked edge, moved to where an occurrence puts it.
///
/// Only the anchor travels: length, curve type and radius are properties of
/// the edge itself and a rigid motion (or a reflection) does not change them.
/// That is precisely why a fingerprint can be re-found at the copy.
EdgeSel placedEdgeSel(EdgeSel e, PatternOccurrence occ, PlaneRef? plane) {
  final m = occ.mat34;
  Vec3 at;
  if (occ.mirror) {
    if (plane == null) return EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius);
    final n = plane.normal.normalized();
    final p0 = Vec3(e.mx, e.my, e.mz);
    at = p0 - n * (2 * (p0 - plane.point).dot(n));
  } else if (m != null) {
    at = _applyMat34(m, Vec3(e.mx, e.my, e.mz));
  } else {
    at = Vec3(e.mx, e.my, e.mz);
  }
  return EdgeSel(at.x, at.y, at.z, e.length, e.kind, e.radius);
}

/// Re-applies a fillet or chamfer at one occurrence: the same blend, on the
/// edges of [body] that the occurrence's copy brought with it.
///
/// Returns null on failure, having said why through [kernel]'s error — most
/// often "the copy's edges are not there", which happens when the feature the
/// blend shapes was not patterned along with it.
KernelSolid? applyBlendOccurrence(PartKernel kernel, KernelSolid body,
    BodyModifyFeature blend, PatternOccurrence occ, PlaneRef? plane) {
  final live = kernel.edgesOf(body);
  if (live.isEmpty) return null;
  // A CLONE: resolveEdges re-anchors the fingerprints it matches, and the
  // real feature's own selections must keep pointing at the ORIGINAL edges.
  final moved = PartFeature.fromJson(blend.toJson());
  if (moved is! BodyModifyFeature) return null;
  for (var i = 0; i < moved.edges.length && i < blend.edges.length; i++) {
    final e = placedEdgeSel(blend.edges[i], occ, plane);
    moved.edges[i]
      ..mx = e.mx
      ..my = e.my
      ..mz = e.mz;
  }
  final (ids, src, _) = moved.resolveEdges(live);
  if (ids.isEmpty) return null;
  if (moved is FilletFeature) {
    final radii = [
      for (final i in src)
        i < moved.radii.length
            ? moved.radii[i]
            : (moved.radii.isEmpty ? 2.0 : moved.radii.last)
    ];
    final radii2 = moved.radii2.any((r) => r > 0)
        ? [for (final i in src) i < moved.radii2.length ? moved.radii2[i] : 0.0]
        : const <double>[];
    return kernel.filletEdges(body, ids, radii, radii2: radii2);
  }
  if (moved is ChamferFeature) {
    final (d1, d2, ang) = moved.kernelParams;
    return kernel.chamferEdges(body, ids, moved.mode, d1, d2, ang);
  }
  return null;
}

bool _recomputePattern(
    PartModel part, PatternFeature f, PartKernel kernel, KernelSolid? base) {
  if (base == null) {
    // Inventor greys the pattern commands out with nothing to pattern; a
    // saved file can still reach here when the upstream feature broke.
    f.computeError = 'nothing to pattern — no solid before this feature';
    return false;
  }
  // ---- 1. what is being copied -----------------------------------------
  final tools = <_PatternTool>[];
  final owned = <KernelSolid>[]; // everything this build must free again
  String? fail;

  void disposeOwned() {
    for (final s in owned) {
      s.dispose();
    }
    owned.clear();
  }

  if (f.patternSolid) {
    // Inventor's "Pattern a solid": the whole body is the tool, and every
    // occurrence is joined onto it.
    tools.add(_PatternTool(null, base, 'join'));
  } else if (f.sources.isEmpty) {
    f.computeError = 'no features selected to pattern';
    return false;
  } else {
    for (final name in f.sources) {
      final src = _patternSource(part, f, name);
      if (src == null) {
        f.computeError = 'the patterned feature "$name" is not available any '
            'more — it was deleted, suppressed, moved below this pattern, or '
            'builds a different body';
        disposeOwned();
        return false;
      }
      if (src is BodyModifyFeature) {
        // A fillet or a chamfer has no volume to copy — what repeats is the
        // OPERATION. It is carried as a blend tool and re-applied at each
        // occurrence (M213); see [applyBlendOccurrence].
        tools.add(_PatternTool(src, null, 'modify', blend: src));
        continue;
      }
      if (src is PatternFeature) {
        // A pattern of a pattern would have to re-run a whole fold per
        // occurrence, and its own sources are already in the body it was
        // built into. Refused by name rather than half-done.
        f.computeError = '"$name" is itself a pattern — pattern the features '
            'it copies instead';
        disposeOwned();
        return false;
      }
      if (src.modifiesBody) {
        // M226 — anything else that CHANGES the body instead of bringing a
        // volume: a hole (M225), and the face edits of M217. Its own solid is
        // the whole body with the change already in it, so the clone path
        // below would place a copy of THAT at every occurrence and subtract
        // the part from itself — silently, and the model would look eaten
        // rather than patterned.
        //
        // Doing it properly means repeating the TOOL, the treatment M213 gave
        // blends; a hole's tool is a cylinder and a face edit's is a swept
        // slab, so each needs its own path. Until then this says so, and names
        // the way round that already works.
        //
        // ORDER MATTERS: this sits below the two more specific refusals above,
        // because a fillet and a pattern are both modifiesBody too and each
        // has a better sentence to offer.
        f.computeError = '"$name" changes the body rather than adding one and '
            'cannot be patterned yet — for a hole, pattern the sketch points '
            'it sits on instead';
        disposeOwned();
        return false;
      }
      if (src is ExtrudeFeature && src.imported) {
        f.computeError = '"$name" is an imported body and has no feature to '
            'copy — pattern the solid instead';
        disposeOwned();
        return false;
      }
      // A CLONE, so building the tool cannot disturb the real feature's
      // folded solid (which holds the whole body at its own position) or
      // re-anchor its profile selections behind its back.
      final clone = PartFeature.fromJson(src.toJson());
      if (clone == null || !recomputeFeature(part, clone, kernel, base: base)) {
        f.computeError = clone?.computeError ??
            'the patterned feature "$name" could not be rebuilt';
        disposeOwned();
        return false;
      }
      final tool = clone.solid;
      if (tool == null) {
        f.computeError = 'the patterned feature "$name" produced no solid';
        disposeOwned();
        return false;
      }
      clone.solid = null; // ownership moves here
      owned.add(tool);
      // 'new' means the source STARTED a body; an occurrence of it belongs to
      // the body being patterned, so it joins.
      tools.add(_PatternTool(
          src, tool, src.output == 'new' ? 'join' : src.output));
    }
  }

  // Tree order, not pick order: a fillet must be applied AFTER the extrusion
  // it rounds, or the edges it looks for do not exist yet at that occurrence.
  if (tools.length > 1) {
    int pos(_PatternTool t) =>
        t.source == null ? -1 : part.features.indexOf(t.source!);
    tools.sort((a, b) => pos(a).compareTo(pos(b)));
  }

  // ---- 2. where the copies go ------------------------------------------
  final firstSolid = tools.firstWhere((t) => t.solid != null,
      orElse: () => _PatternTool(null, null, 'join'));
  if (firstSolid.solid == null) {
    // Only blends were selected. There is nothing to place, and re-blending
    // the same body at another location is not a pattern of anything.
    f.computeError = 'select the feature the '
        '${tools.first.source?.typeLabel.toLowerCase() ?? 'blend'} shapes as '
        'well — a fillet on its own has no shape to copy';
    disposeOwned();
    return false;
  }
  final refPoint = solidCentre(firstSolid.solid!) ?? Vec3.zero;
  var points = const <Vec3>[];
  var normals = const <Vec3>[];
  if (f.mode == PatternKind.sketchDriven) {
    final (pts, perr) = patternPointsOf(part, f);
    if (pts == null) {
      f.computeError = perr;
      disposeOwned();
      return false;
    }
    points = pts;
    // M213 — Variable Orientation: sample the picked face's surface where
    // each occurrence lands. A point that misses the face keeps the original
    // normal, so a pattern that runs off the edge of the shell leans like the
    // parent rather than flipping to something arbitrary.
    final of = f.orientFace;
    if (of != null) {
      final fallback = Vec3(of.nx, of.ny, of.nz).normalized();
      final dir = fallback * -1.0;
      normals = [
        for (final q in points)
          meshNormalAt(base.mesh, q, dir) ?? fallback
      ];
    }
  }
  // A path is stored as a curve in a sketch, and is re-found there by
  // fingerprint — the same contract a sweep's path lives under.
  var ptsA = const <Vec3>[], ptsB = const <Vec3>[];
  for (final (sel, isA) in [(f.pathA, true), (f.pathB, false)]) {
    if (sel == null) continue;
    final (pts, perr) = resolvePath(part, sel);
    if (pts == null) {
      f.computeError = perr ?? 'the pattern path could not be found';
      disposeOwned();
      return false;
    }
    final world = <Vec3>[
      for (var i = 0; i + 2 < pts.length; i += 3)
        Vec3(pts[i], pts[i + 1], pts[i + 2])
    ];
    if (isA) {
      ptsA = world;
    } else {
      ptsB = world;
    }
  }
  final occurrences = patternOccurrences(f,
      refPoint: refPoint,
      points: points,
      pointNormals: normals,
      pathA: ptsA,
      pathB: ptsB);
  if (occurrences.isEmpty) {
    f.computeError = _patternInputError(f);
    disposeOwned();
    return false;
  }

  // ---- 3. combine them into the body -----------------------------------
  //
  // `result` is always a solid this function owns, EXCEPT when it is still
  // `base` — that one belongs to the feature upstream and must never be
  // disposed here. `resultOwned` is what keeps those two apart; getting it
  // wrong is a double free on the device and nothing at all on the host.
  var result = base;
  var resultOwned = false;
  var built = 0, skipped = 0;

  bool combine(KernelSolid tool, String output) {
    final next = combineSolids(kernel, output, result, tool);
    if (next == null) return false;
    if (resultOwned) result.dispose();
    result = next;
    resultOwned = true;
    return true;
  }

  final plane = f.mirrorPlane;
  // Inventor's Remove Original: only the mirrored half survives, so there is
  // nothing to join it ONTO and the occurrence loop has nothing to do. Doing
  // it anyway would mirror the body twice and throw the first one away.
  final removeOnly = f.mode == PatternKind.mirror &&
      f.removeOriginal &&
      f.patternSolid &&
      plane != null;
  for (final occ in removeOnly ? const <PatternOccurrence>[] : occurrences) {
    if (f.suppressed.contains(occ.index)) {
      skipped++;
      continue;
    }
    for (final t in tools) {
      final blend = t.blend;
      if (blend != null) {
        // A blend is not combined INTO the body — it reshapes it, so it
        // replaces the running result outright.
        final out = applyBlendOccurrence(kernel, result, blend, occ, plane);
        if (out == null) {
          fail = 'occurrence ${occ.index}: ${blend.name} could not be applied '
              '— the copy\'s edges were not found'
              '${kernel.lastError.isEmpty ? "" : " (${kernel.lastError})"}';
          break;
        }
        if (resultOwned) result.dispose();
        result = out;
        resultOwned = true;
        built++;
        continue;
      }
      KernelSolid? placed;
      var adjusted = false;
      if (f.compute == PatternCompute.adjust && t.source != null) {
        // Adjust only differs for a feature that HAS a termination; for the
        // others it falls through to the placed copy, which is what
        // "Identical and Adjust are the same solid here" means. A rebuild
        // that was attempted and failed does NOT fall through — see
        // [_adjustedOccurrence].
        (placed, adjusted) =
            _adjustedOccurrence(part, f, t.source!, kernel, base, occ);
      }
      if (!adjusted) {
        placed = _placeOccurrence(kernel, t.solid!, occ, plane);
      }
      if (placed == null) {
        fail = kernel.lastError.isEmpty
            ? 'occurrence ${occ.index} could not be placed'
            : 'occurrence ${occ.index}: ${kernel.lastError}';
        break;
      }
      final ok = combine(placed, t.output);
      placed.dispose();
      if (!ok) {
        fail = 'occurrence ${occ.index} could not be ${t.output}ed into the '
            'body${kernel.lastError.isEmpty ? "" : " (${kernel.lastError})"}';
        break;
      }
      built++;
    }
    if (fail != null) break;
  }

  if (fail == null && removeOnly) {
    // The result is exactly the mirror of the body — not the body plus its
    // mirror.
    final only = kernel.mirrorSolid(base, plane.point, plane.normal);
    if (only == null) {
      fail = kernel.lastError.isEmpty ? 'the mirror failed' : kernel.lastError;
    } else {
      if (resultOwned) result.dispose();
      result = only;
      resultOwned = true;
    }
  }

  disposeOwned();
  if (fail != null) {
    if (resultOwned) result.dispose();
    f.computeError = fail;
    return false;
  }
  if (!resultOwned) {
    // Every occurrence was suppressed. The body is unchanged, and handing on
    // `base` itself would give two features one solid and a double free at
    // the next rebuild — so it is copied by placing it with the identity.
    final copy = kernel.placeSolid(base, translationMat34(Vec3.zero));
    if (copy == null) {
      f.computeError = kernel.lastError.isEmpty
          ? 'every occurrence is suppressed and the body could not be copied'
          : kernel.lastError;
      return false;
    }
    result = copy;
  }
  f.solid = result;
  f.builtOccurrences = occurrences.length + 1; // + the original
  Log.i(
      'feature',
      '${f.name}: ${patternKindName(f.mode)} built $built occurrence'
          '${built == 1 ? "" : "s"} of ${f.patternSolid ? "the solid" : "${tools.length} feature(s)"}'
          '${skipped == 0 ? "" : ", $skipped suppressed"}'
          '${f.compute == PatternCompute.adjust ? ", adjusted" : ""}');
  return true;
}

/// The feature named [name], if it is a legitimate source for [f]: on the
/// same body, above the pattern, and actually built.
PartFeature? _patternSource(PartModel part, PatternFeature f, String name) {
  for (final g in part.features) {
    if (identical(g, f)) return null; // reached the pattern first: it is below
    if (g.name != name) continue;
    if (g.rolledBack) return null;
    // The source must build into the SAME body. Not a rule for tidiness: the
    // rebuild key of this feature is the running chain hash of its own body,
    // so a source on another body could change without this pattern noticing
    // — a cached fold of yesterday's geometry, which is the exact failure
    // mode the chain hash exists to prevent.
    if (g.bodyName != f.bodyName) return null;
    return g;
  }
  return null;
}

/// Why a pattern produced no occurrences — the missing input, by name, rather
/// than "nothing happened".
String _patternInputError(PatternFeature f) => switch (f.mode) {
      PatternKind.rectangular =>
        f.pathA == null && (f.dirA == null || !f.dirA!.valid)
            ? 'no direction selected for Direction A'
            : 'the pattern has only one occurrence — increase the count',
      PatternKind.circular => f.axis == null || !f.axis!.valid
          ? 'no rotation axis selected'
          : 'the pattern has only one occurrence — increase the count',
      PatternKind.sketchDriven =>
        'the sketch holds no points to place occurrences on',
      PatternKind.mirror => 'no mirror plane selected',
    };

/// World points of a sketch-driven pattern, base point FIRST when one was
/// picked (which is the order [patternOccurrences] documents).
(List<Vec3>?, String?) patternPointsOf(PartModel part, PatternFeature f) {
  if (f.pointSketch.isEmpty) return (null, 'no sketch of points selected');
  final cs = part.sketchByName(f.pointSketch);
  if (cs == null) {
    return (null, 'the sketch "${f.pointSketch}" no longer exists');
  }
  final pts = sketchPatternPoints(cs.model);
  if (pts.isEmpty) {
    return (null, 'the sketch "${f.pointSketch}" holds no points — a '
        'sketch-driven pattern places one occurrence per sketch point');
  }
  final frame = sketchFrameOf(cs);
  final ordered = <Offset>[];
  if (f.basePicked) {
    // The base point is where the ORIGINAL sits, so it goes first and never
    // receives a copy of its own. Matched by position because a sketch point
    // has no identity that survives an edit — the same contract ProfileSel
    // and EdgeSel work under.
    var bi = 0;
    var bd = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (pts[i] - Offset(f.baseX, f.baseY)).distance;
      if (d < bd) {
        bd = d;
        bi = i;
      }
    }
    ordered.add(pts[bi]);
    for (var i = 0; i < pts.length; i++) {
      if (i != bi) ordered.add(pts[i]);
    }
  } else {
    ordered.addAll(pts);
  }
  return ([for (final p in ordered) frame.toWorld(p)], null);
}

/// Places a tool solid at one occurrence — a rigid move, or the reflection.
KernelSolid? _placeOccurrence(PartKernel kernel, KernelSolid tool,
    PatternOccurrence occ, PlaneRef? plane) {
  if (occ.mirror) {
    if (plane == null) return null;
    return kernel.mirrorSolid(tool, plane.point, plane.normal);
  }
  final m = occ.mat34;
  if (m == null) return null;
  return kernel.placeSolid(tool, m);
}

/// [PatternCompute.adjust] — rebuild [src] AT the occurrence, so its
/// termination resolves against the body there.
///
/// Returns null when this feature kind has nothing to adjust (no sketch plane
/// to move, or a plain Distance extent that would produce the identical
/// solid), and the caller then places the copy instead. Failing here would be
/// wrong: Adjust asks for each occurrence to be measured where it lands, and
/// for a feature with no measurement to make, the copy IS that answer.
(KernelSolid?, bool) _adjustedOccurrence(PartModel part, PatternFeature f,
    PartFeature src, PartKernel kernel, KernelSolid base,
    PatternOccurrence occ) {
  const notApplicable = (null, false);
  final sketch = featureSketchOf(src);
  if (sketch == null) return notApplicable;
  if (src is! ExtrudeFeature && src is! RevolveFeature) return notApplicable;
  final ext =
      src is ExtrudeFeature ? src.extent : (src as RevolveFeature).extent;
  if (ext == FeatureExtent.distance) return notApplicable; // nothing to measure
  final cs = part.sketchByName(sketch);
  if (cs == null) return notApplicable;
  final frame = sketchFrameOf(cs);
  OccurrenceAt at;
  if (occ.mirror) {
    final plane = f.mirrorPlane;
    if (plane == null) return notApplicable;
    at = OccurrenceAt(mirroredFrame(frame, plane.point, plane.normal),
        mirrorInV: true);
  } else {
    final m = occ.mat34;
    if (m == null) return notApplicable;
    at = OccurrenceAt(placedFrame(frame, m));
  }
  final clone = PartFeature.fromJson(src.toJson());
  if (clone == null) return notApplicable;
  if (!recomputeFeature(part, clone, kernel, base: base, at: at)) {
    // An occurrence that cannot terminate where it landed is real news — a
    // hole through thin air — so it FAILS the feature rather than quietly
    // falling back to a copy of the original, which would silently be the
    // wrong depth. That is what the `true` says.
    Log.w(
        'feature',
        '${f.name}: occurrence ${occ.index} of ${src.name} could not be '
            'adjusted: ${clone.computeError}');
    return (null, true);
  }
  final out = clone.solid;
  clone.solid = null;
  return (out, true);
}

/// Sampled display curve of a sketch entity (for drawing it on its plane
/// in the 3D viewport). Closed polylines repeat the first point.
List<Offset> sketchCurve(Geo g) {
  if (g.type == Geo.polyline) {
    if (g.spline != Geo.straight) return splineCurveFor(g);
    final pts = polyPoints(g);
    if (g.data[0] != 0 && pts.isNotEmpty) return [...pts, pts.first];
    return pts;
  }
  return sampleEntity(g, arcSamples: 64);
}

/// Parses a dialog value: strips a unit suffix (mm / deg / ° / ul), then
/// accepts plain numbers or the full M41 expression grammar (ExprParser —
/// sin, pi, parentheses, ...). Null when it doesn't evaluate to a finite
/// number.
///
/// `ul` is Inventor's UNITLESS suffix, used for counts such as a coil's
/// revolutions. Without it "5 ul" parsed as nothing and every coil method
/// that reads revolutions silently refused to build.
double? parseValueExpr(String raw) {
  var t = raw.trim();
  t = t
      .replaceAll(RegExp(r'(mm|deg|°|ul)\s*$', caseSensitive: false), '')
      .trim();
  if (t.isEmpty) return null;
  final direct = double.tryParse(t.replaceAll(',', '.'));
  if (direct != null) return direct.isFinite ? direct : null;
  final f = ExprParser(t.replaceAll(',', '.')).parse();
  if (f == null) return null;
  final v = f(0);
  return v.isFinite ? v : null;
}

/// Recomputes EVERY feature in order and folds Inventor's boolean chains per
/// body: each non-'new' feature COMBINES its own volume with the accumulated
/// body it shares a [bodyName] with — union for 'join', subtract for 'cut',
/// overlap for 'intersect' — and every earlier feature of that chain is
/// flagged [ExtrudeFeature.consumedByJoin] so the viewport draws exactly ONE
/// solid per body (Inventor's "everything is one part unless you chose New
/// Solid"). The FIRST feature of a body has nothing to combine with, so it
/// materialises as its own prism whatever its output is. 'new' starts a fresh
/// chain. Returns true when every visible feature computed.
/// Everything that can change what [f] computes to: its own parameters, the
/// profiles it picked, and the full state of the sketch it is built on
/// (geometry, layers, end-of-sketch marker and the plane it sits on).
/// Everything about one sketch that can change what a feature built from it
/// looks like. Same content the main signature appends for the first sketch.
String _sketchSig(PartModel part, String name) {
  final cs = part.sketchByName(name);
  if (cs == null) return 'MISSING:$name';
  final b = StringBuffer()
    ..write(name)
    ..write(':')
    ..write(cs.model.eosAfter)
    ..write('/')
    ..write(cs.model.hiddenLayers.join(','))
    ..write('/');
  for (final g in cs.model.geometry) {
    b..write(g.type)..write(',')..write(g.spline)..write(',')..write(g.layer);
    for (final d in g.data) {
      b..write(' ')..write(d);
    }
    b.write(';');
  }
  final fr = sketchFrameOf(cs);
  b
    ..write('|')
    ..write(fr.origin.x)..write(',')..write(fr.origin.y)..write(',')
    ..write(fr.origin.z)..write(',')..write(fr.n.x)..write(',')
    ..write(fr.n.y)..write(',')..write(fr.n.z);
  return b.toString();
}

String featureInputSig(PartModel part, PartFeature f) {
  final b = StringBuffer()
    ..write(f.ownSig())
    ..write('|')
    ..write(f.output)
    ..write(',')
    ..write(f.bodyName)
    ..write(',')
    ..write(f.visible)
    ..write('|');
  // A body-modifying feature has no sketch of its own; everything it depends
  // on arrives through the upstream chain key that recomputeAllFeatures
  // prepends, so there is nothing further to hash here.
  final names = f.sketchNames;
  if (names.isEmpty) {
    b.write(f.modifiesBody ? 'BODY' : 'MISSING');
    return b.toString();
  }
  // More than one for a sweep (profile + path) and a loft (one per section).
  for (final n in names.skip(1)) {
    b..write(_sketchSig(part, n))..write('|');
  }
  final cs = part.sketchByName(names.first);
  if (cs == null) {
    b.write('MISSING');
    return b.toString();
  }
  b
    ..write(cs.model.eosAfter)
    ..write('/')
    ..write(cs.model.hiddenLayers.join(','))
    ..write('/');
  for (final g in cs.model.geometry) {
    b
      ..write(g.type)
      ..write(',')
      ..write(g.spline)
      ..write(',')
      ..write(g.layer)
      ..write(',');
    for (final d in g.data) {
      b
        ..write(d)
        ..write(' ');
    }
    b.write(';');
  }
  final fr = sketchFrameOf(cs);
  b
    ..write('|')
    ..write(fr.origin.x)
    ..write(',')
    ..write(fr.origin.y)
    ..write(',')
    ..write(fr.origin.z)
    ..write(',')
    ..write(fr.n.x)
    ..write(',')
    ..write(fr.n.y)
    ..write(',')
    ..write(fr.n.z);
  return b.toString();
}

/// Recomputes the feature tree, REUSING features whose inputs are unchanged.
///
/// Before this, every feature was re-executed on any edit and each rebuilt
/// solid restarted at coarse tessellation: the device log showed Extrusion1
/// dropping from 50 548 triangles back to 4 304 and re-refining four times
/// just because a SECOND extrude was started — seconds of kernel work thrown
/// away although nothing about it had changed.
///
/// The signature is a RUNNING CHAIN hash: each feature's key includes the key
/// of the previous feature in its body. So a change anywhere upstream changes
/// every downstream key automatically, and a stale fold can never be reused.
/// Pass [force] after loading or undoing, where the kernel handles are new.
/// Rebuilds every feature, and keeps rebuilding until the sketches drawn on
/// solid faces have stopped moving.
///
/// M166 — one pass is not enough, and that is why a sketch on a face did not
/// follow when its face moved. The order inside a single pass is necessarily:
/// build the features (which needs the sketches), THEN re-anchor the sketches
/// onto the faces that just moved (which needs the solids). A sketch that
/// moves in step two therefore moves AFTER every feature built from it — so
/// the extrusion standing on it stayed where the old face was, and nothing
/// scheduled another rebuild. On the device: Extrusion2 edited from 5 mm to
/// 20 mm, its top face moved from y=10 to y=25, and the extrusion on the
/// sketch that sits on that face never left y=10.
///
/// So it iterates. A pass that moves a sketch is followed by another pass,
/// forced so a stale build signature cannot skip the feature that has to
/// change. Two passes settle the ordinary case (move faces, rebuild what
/// stands on them); the cap exists only so a pathological cycle — a sketch
/// whose feature moves the very face it is anchored to — terminates with a
/// complaint instead of hanging the app.
bool recomputeAllFeatures(PartModel part, PartKernel kernel,
        {bool force = false}) =>
    Perf.span('part.rebuildAll', () {
      Perf.gauge('part.features', part.features.length);
      return _recomputeAllFeatures(part, kernel, force: force);
    });

/// The whole-part rebuild, wrapped above so its cost is one number.
///
/// This is what the user waits for after editing a parameter, and it was
/// unmeasured as a WHOLE: `kernel.feature` gave the per-feature cost, but a
/// part rebuilds every feature and may run the loop again when a face-anchored
/// sketch moves. `part.rebuildAll` is the wall the user hits; the `passes`
/// counter says whether a second pass is what made it long.
bool _recomputeAllFeatures(PartModel part, PartKernel kernel,
    {bool force = false}) {
  var ok = _recomputeAllFeaturesOnce(part, kernel, force: force);
  if (!ok) {
    // M182 — a failed feature pass must not chase face anchors or rewrite
    // sketch projections. The part is showing last-good geometry; re-deriving
    // projections from a half-broken body is exactly how closed profiles
    // opened in the device session. The next successful pass re-syncs them.
    Log.w(
        'part',
        'recompute failed — keeping the last good geometry; projections and '
        'face anchors stay frozen until a recompute succeeds');
    return false;
  }
  for (var pass = 1; pass <= _kMaxFaceSettlePasses; pass++) {
    final moved = reanchorFaceSketches(part);
    if (moved == 0) return ok;
    Log.i(
        'part',
        'face-anchored sketches moved ($moved) — rebuilding, pass $pass of '
            '$_kMaxFaceSettlePasses');
    ok = _recomputeAllFeaturesOnce(part, kernel, force: true);
    if (!ok) return false;
  }
  // Still moving after the cap: report it rather than loop. The geometry is
  // whatever the last pass produced, which is the honest answer.
  if (reanchorFaceSketches(part) != 0) {
    Log.w(
        'part',
        'face-anchored sketches STILL moving after $_kMaxFaceSettlePasses '
            'passes — a sketch is probably anchored to a face its own feature '
            'moves; leaving the last result in place');
  }
  return ok;
}

/// How many times a rebuild may chase a moving face before giving up.
const int _kMaxFaceSettlePasses = 3;

bool _recomputeAllFeaturesOnce(PartModel part, PartKernel kernel,
    {bool force = false}) {
  // Counted HERE, not in the caller: the caller runs this once and then again
  // for every pass a moved face-anchored sketch forces. Counting the caller
  // would report 1 for a rebuild that actually ran three times, which is the
  // opposite of what the counter exists to reveal.
  Perf.count('part.rebuild.passes');
  var allOk = true;
  // M128 — DERIVE the End of Part flags here, first, unconditionally.
  //
  // `eopAfter` (a row position) and `rolledBack` (a per-node flag) are two
  // representations of one fact, and every End of Part bug in this file's
  // history has been the two disagreeing: a feature added without re-applying,
  // a marker moved without rebuilding the chain, a row order changed under a
  // stale cut. Maintaining that by convention across six call sites did not
  // work seven times running.
  //
  // The fold is the single funnel every piece of geometry passes through, so
  // re-deriving the flags at its head makes "stale rolledBack" unrepresentable
  // rather than merely discouraged. It is O(rows) and runs once per rebuild.
  applyEndOfPart(part);
  final chainLast = <String, PartFeature>{}; // bodyName -> last in chain
  final upstream = <String, String>{}; // bodyName -> running chain key
  // M182 — a body whose chain broke must not build phantoms downstream. Once a
  // feature on [bodyName] fails, every later feature on that body is marked
  // failed and NOT computed, so a null base can never silently materialise as
  // a standalone prism (that is what turned Extrusion4 into a floating "cut"
  // and let sketch projections chase a broken body in the device session).
  final brokenBody = <String, String>{}; // bodyName -> name of the failing feature
  for (final f in part.features) {
    f.consumedByJoin = false;
    // A suppressed feature does not exist for this build: it is not computed,
    // it does not join the chain, and it holds no solid. Letting it compute
    // was the actual cause of the vanishing/incorrect body — a rolled-back
    // fillet still ran, still marked the extrusion below it as consumedByJoin,
    // and so hid BOTH (one suppressed, one "consumed" by something not being
    // drawn). Disposing here also means no stale geometry can leak into the
    // scene (which filters rolledBack anyway — the M128 contract "it holds no
    // solid" is deliberately kept).
    if (f.rolledBack) {
      f.disposeSolid();
      f.computeError = null;
      continue;
    }
    // M111 — an imported body is not computed FROM anything; it just is. Its
    // solid was read from the STEP file, so recompute leaves it untouched and
    // only does the chain bookkeeping around it.
    // (f is ExtrudeFeature) is needed since M131: `features` is
    // List<PartFeature> now, and only an extrude can be an imported body.
    if (f is ExtrudeFeature && f.imported) {
      final prevI = f.output != 'new' ? chainLast[f.bodyName] : null;
      if (prevI != null && prevI.solid != null) prevI.consumedByJoin = true;
      // M213 — an imported body owns its faces as much as a built one does,
      // and picking one has to name it rather than come back "unknown".
      f.ownSurfaces =
          f.solid == null ? const [] : faceSurfaces(f.solid!.mesh);
      if (f.solid != null) chainLast[f.bodyName] = f;
      continue;
    }
    // M182 — downstream of a failure on the same body: never compute, never
    // join the chain. The feature goes SICK like the culprit (no solid — the
    // honest signal that this body did not build, exactly like Inventor's
    // failed feature chain), and the error names the failing feature instead
    // of inventing a phantom.
    final broke = brokenBody[f.bodyName];
    if (broke != null) {
      f.disposeSolid();
      f.computeError =
          'feature "$broke" on this body failed — nothing further can be built';
      f.builtSig = null;
      allOk = false;
      continue;
    }
    // M227 — a Combine reads another body, so that body's key is part of this
    // feature's key. Empty for every other feature, so nothing else changes.
    final cross = f.inputBodies.isEmpty
        ? ''
        : [for (final b in f.inputBodies) '$b=${upstream[b] ?? ''}'].join(',');
    final sig =
        '${upstream[f.bodyName] ?? ''}#$cross#${featureInputSig(part, f)}';
    if (!force &&
        f.solid != null &&
        f.computeError == null &&
        f.builtSig == sig) {
      // Unchanged: f.solid already holds the folded result AT THIS POSITION,
      // so the boolean below must not run again — only the bookkeeping.
      // A body-modifying feature ALWAYS consumes its predecessor, whatever
      // its (meaningless) output value says.
      final prev = (f.modifiesBody || f.output != 'new')
          ? chainLast[f.bodyName]
          : null;
      if (prev != null && prev.solid != null) prev.consumedByJoin = true;
      // M182 — unconditional: VISIBILITY IS A DISPLAY PROPERTY. Advancing the
      // fold chain on `f.visible` was how hiding one extrusion removed its
      // volume from the body (or left the next modify feature with no base at
      // all). The fold always runs through every feature; `visible` only
      // decides what the viewport draws.
      chainLast[f.bodyName] = f;
      upstream[f.bodyName] = sig;
      continue;
    }
    final prev = (f.modifiesBody || f.output != 'new')
        ? chainLast[f.bodyName]
        : null;
    // M182 — honest null base. A non-'new' feature whose body HAS earlier
    // features but no reachable solid must not materialise as a standalone
    // phantom: it either inherits a broken chain or sits on rolled-back
    // predecessors. Fail it loudly instead.
    if (prev == null && f.output != 'new' && _bodyHasEarlierFeature(part, f)) {
      f.disposeSolid();
      f.computeError =
          'the body has no solid before this feature — an earlier feature '
          'failed, is missing, or was rolled back';
      brokenBody[f.bodyName] = f.name;
      allOk = false;
      continue;
    }
    // Fillet and chamfer MODIFY the accumulated body, so it is their input,
    // not a second operand. Handing it to recomputeFeature (rather than
    // combining afterwards) is what keeps them out of the boolean path
    // entirely — there is no union to perform, the kernel returns the
    // already-modified solid.
    // `base` is handed to EVERY feature now, not just the body-modifying
    // ones: M132's extents (To Next / To / Through All) resolve against the
    // body this feature builds into. A 'new' output has no predecessor, which
    // is precisely why Inventor greys those extents out on a base feature.
    final ok = recomputeFeature(part, f, kernel, base: prev?.solid);
    if (!ok) {
      allOk = false;
      chainLast.remove(f.bodyName); // a broken chain stops accumulating
      brokenBody[f.bodyName] = f.name;
      continue;
    }
    // M213 — provenance, captured HERE and nowhere else. For a feature that
    // brings its own volume this is its solid before the boolean consumes it;
    // for one that modifies the body it is what the modification ADDED, which
    // is why the base is subtracted rather than the whole result claimed.
    if (f.solid != null) {
      final mine = faceSurfaces(f.solid!.mesh);
      f.ownSurfaces = f.modifiesBody && prev?.solid != null
          ? newSurfacesOf(mine, faceSurfaces(prev!.solid!.mesh))
          : mine;
    } else {
      f.ownSurfaces = const [];
    }
    if (f.modifiesBody) {
      if (prev != null && prev.solid != null) prev.consumedByJoin = true;
    } else if (prev != null && prev.solid != null && f.solid != null) {
      final combined = combineSolids(kernel, f.output, prev.solid!, f.solid!);
      if (combined != null) {
        f.disposeSolid();
        f.solid = combined;
        prev.consumedByJoin = true;
      } else {
        // honest failure: keep both standalone solids visible
        f.computeError ??= kernel.lastError;
        brokenBody[f.bodyName] = f.name;
        allOk = false;
        continue;
      }
    }
    chainLast[f.bodyName] = f;
    f.builtSig = f.solid != null && f.computeError == null ? sig : null;
    upstream[f.bodyName] = sig;
  }
  // M153 put reanchorFaceSketches here so no call site could forget it. M166
  // moved it OUT to the loop above: re-anchoring after the features are built
  // is one pass too late for anything standing on the sketch that moved.
  return allOk;
}

/// Whether any feature strictly before [f] in build order belongs to the same
/// body — i.e. whether a null base for [f] means a BROKEN chain rather than a
/// genuine first feature of the body.
bool _bodyHasEarlierFeature(PartModel part, PartFeature f) {
  for (final g in part.features) {
    if (identical(g, f)) return false;
    if (g.bodyName == f.bodyName) return true;
  }
  return false;
}

/// The solid that currently STANDS IN for [bodyName] in the folded scene: the
/// last non-consumed feature of that body carrying a solid (after
/// [recomputeAllFeatures], exactly one feature per body is non-consumed). Null
/// when the body has no computed solid. Used to resolve the target a live
/// boolean preview operates against.
KernelSolid? currentBodySolid(PartModel part, String bodyName) {
  KernelSolid? found;
  for (final f in part.features) {
    if (f.bodyName == bodyName && f.solid != null && !f.consumedByJoin) {
      found = f.solid;
    }
  }
  return found;
}

/// M214 — THE MODEL, as a list of named bodies. What an export must write,
/// and the same set the viewport, the RealityKit scene and the gallery
/// thumbnail draw.
///
/// The rule is three clauses and every one of them earns its place:
///
///   solid != null      — the feature computed something.
///   !consumedByJoin    — it is still the head of its body. THIS is the clause
///                        the STEP export was missing. Each feature stores the
///                        RUNNING accumulation at its own position, so a
///                        block, then that block minus a hole, then that
///                        filleted, are three solids of which only the last is
///                        the part. Exporting all three (and, worse, unioning
///                        them, which is what the kernel did with a list) puts
///                        the material straight back: block ∪ (block − hole)
///                        is the block, hole gone; block ∪ filleted-block is
///                        the block, fillet gone. That is exactly the reported
///                        "holes and fillets are not exported".
///   !rolledBack        — below End of Part is not part of the model yet.
///
/// `visible` is deliberately NOT one of them. M182 settled that visibility is
/// a DISPLAY property: a hidden body is still part of the part, and Inventor
/// exports it too. Hiding a body to see past it must not silently drop it from
/// the file you send to the shop.
///
/// Returned in creation order, so the STEP products come out in the same order
/// the browser lists the bodies.
List<(String, KernelSolid)> partExportBodies(PartModel part) {
  final out = <(String, KernelSolid)>[];
  for (final f in part.features) {
    final s = f.solid;
    if (s == null || f.consumedByJoin || f.rolledBack) continue;
    out.add((f.bodyName, s));
  }
  return out;
}

/// The accumulated solid of [bodyName] considering only features strictly
/// BEFORE [before] in list order — i.e. exactly the base a boolean at
/// [before]'s position operates on. Each folded feature stores its running
/// accumulation at its own position, so the last same-body feature before
/// [before] already holds the union/cut/intersect of everything earlier.
/// Used for the live preview while EDITING an existing feature.
KernelSolid? bodyBaseBefore(
    PartModel part, String bodyName, PartFeature before) {
  KernelSolid? head;
  for (final f in part.features) {
    if (identical(f, before)) break;
    if (f.bodyName == bodyName && f.solid != null) head = f.solid;
  }
  return head;
}

/// The last feature (in list order) that currently carries a computed solid,
/// or null. A NEW extrude with a boolean output targets this feature's body —
/// mirroring [applyExtrude], which adopts the last feature's [bodyName] for a
/// non-'new' output.
PartFeature? lastSolidFeature(PartModel part) {
  PartFeature? last;
  for (final f in part.features) {
    if (f.solid != null && !f.consumedByJoin) last = f;
  }
  return last;
}

// ---------------------------------------------------------------------------
// M76 — projecting 3D model edges into a sketch (Inventor's Project Geometry)
// ---------------------------------------------------------------------------

/// Analytic form of a projected edge, when the kernel gave us one.
///
/// Orthographic projection maps lines to lines and circles/ellipses to
/// ellipses (occt_capi.h says as much), so an exact projection is always
/// possible — it is NOT always the same TYPE. A circle only stays a circle
/// when its plane is parallel to the sketch plane; tilted, it is a genuine
/// ellipse, and drawing it as a circle would be wrong, not just imprecise.
enum ProjKind { polyline, line, circle, arc, ellipse }

/// One projectable model edge, already flattened onto a sketch plane.
class PartEdge {
  /// Index in the part's visible-solid edge list — what `Geo.projSeg` stores
  /// for a `Geo.projSolid` projection.
  final int index;

  /// The edge orthogonally projected onto the sketch plane.
  final List<Offset> pts;

  /// Exact projected form, or [ProjKind.polyline] when the kernel reported no
  /// analytic curve (type 0) and the tessellation is all we have.
  final ProjKind kind;

  /// circle/arc: [c, r]; arc adds [a0, a1]. ellipse: [c, majorVertex,
  /// minorVertex]. line: [p0, p1]. Meaningless for polyline.
  final List<Offset> defs;
  final double radius, a0, a1;

  const PartEdge(this.index, this.pts,
      {this.kind = ProjKind.polyline,
      this.defs = const [],
      this.radius = 0,
      this.a0 = 0,
      this.a1 = 0});

  /// Points for DISPLAY and PICKING only. An analytic edge carries no
  /// tessellation (that is the point of it), so one is generated here — never
  /// use these to build the sketch entity, [geoForPartEdge] does that exactly.
  List<Offset> get displayPts {
    switch (kind) {
      case ProjKind.polyline:
        return pts;
      case ProjKind.line:
        return defs;
      case ProjKind.circle:
        return _sample(defs[0], radius, radius, 0, 2 * math.pi, 0);
      case ProjKind.arc:
        var sweep = a1 - a0;
        while (sweep <= 0) {
          sweep += 2 * math.pi;
        }
        return _sample(defs[0], radius, radius, a0, a0 + sweep, 0);
      case ProjKind.ellipse:
        final maj = defs[1] - defs[0], min = defs[2] - defs[0];
        return _sample(defs[0], maj.distance, min.distance, 0, 2 * math.pi,
            math.atan2(maj.dy, maj.dx));
    }
  }

  static List<Offset> _sample(
      Offset c, double rx, double ry, double t0, double t1, double rot) {
    const n = 64;
    final ca = math.cos(rot), sa = math.sin(rot);
    return [
      for (var i = 0; i <= n; i++)
        () {
          final t = t0 + (t1 - t0) * i / n;
          final x = rx * math.cos(t), y = ry * math.sin(t);
          return Offset(c.dx + x * ca - y * sa, c.dy + x * sa + y * ca);
        }()
    ];
  }
}

/// Projects the analytic edge record [rec] (16 doubles, occt_capi.h) onto
/// [fr]. Returns null when the kernel reported type 0 (no analytic form).
///
/// The maths: a circle/ellipse is C + X·cos t + Y·sin t. Projecting C, X and Y
/// individually gives a 2D curve of the same form, but the projected X and Y
/// are CONJUGATE semi-diameters, not the principal axes — so they cannot be
/// used as ellipse grips directly. Rytz's construction rotates them onto the
/// real axes: the extreme of |X·cos t + Y·sin t| sits at
/// tan(2t) = 2(X·Y) / (|X|² − |Y|²).
PartEdge? analyticProjectedEdge(
    int index, List<double> rec, int off, PlaneFrame fr) {
  final type = rec[off].toInt();
  Offset proj(int i) =>
      fr.toSketch(Vec3(rec[off + i], rec[off + i + 1], rec[off + i + 2]));
  // direction vectors project WITHOUT the origin shift
  Offset dir(int i) {
    final o = fr.toSketch(Vec3.zero);
    return proj(i) - o;
  }

  if (type == 1) {
    final a = proj(1), b = proj(4);
    return PartEdge(index, [a, b], kind: ProjKind.line, defs: [a, b]);
  }
  if (type != 2 && type != 3) return null;

  final c = proj(1);
  final xd = dir(4), yd = dir(7);
  final double rx, ry, t0, t1;
  if (type == 2) {
    rx = ry = rec[off + 10];
    t0 = rec[off + 11];
    t1 = rec[off + 12];
  } else {
    rx = rec[off + 10];
    ry = rec[off + 11];
    t0 = rec[off + 12];
    t1 = rec[off + 13];
  }
  // conjugate semi-diameters in the sketch plane
  final ax = Offset(xd.dx * rx, xd.dy * rx);
  final by = Offset(yd.dx * ry, yd.dy * ry);
  if (ax.distance < 1e-12 && by.distance < 1e-12) return null;

  // Rytz: rotate the conjugate pair onto the principal axes
  final dot = ax.dx * by.dx + ax.dy * by.dy;
  final den = ax.distanceSquared - by.distanceSquared;
  final th = 0.5 * math.atan2(2 * dot, den);
  Offset at(double t) => Offset(ax.dx * math.cos(t) + by.dx * math.sin(t),
      ax.dy * math.cos(t) + by.dy * math.sin(t));
  var p = at(th), q = at(th + math.pi / 2);
  if (q.distance > p.distance) {
    final t = p;
    p = q;
    q = t;
  }
  final full = (t1 - t0).abs() >= 2 * math.pi - 1e-6;

  // Degenerate: the circle is seen EDGE ON and projects to a line segment.
  if (q.distance < 1e-9) {
    return PartEdge(index, [c - p, c + p],
        kind: ProjKind.line, defs: [c - p, c + p]);
  }
  // Equal axes -> a true circle (the source plane is parallel to the sketch)
  if ((p.distance - q.distance).abs() <= 1e-7 * p.distance) {
    final r = p.distance;
    if (full) {
      return PartEdge(index, const [],
          kind: ProjKind.circle, defs: [c], radius: r);
    }
    final s0 = c + Offset(ax.dx * math.cos(t0) + by.dx * math.sin(t0),
        ax.dy * math.cos(t0) + by.dy * math.sin(t0));
    final s1 = c + Offset(ax.dx * math.cos(t1) + by.dx * math.sin(t1),
        ax.dy * math.cos(t1) + by.dy * math.sin(t1));
    final e0 = math.atan2(s0.dy - c.dy, s0.dx - c.dx);
    final e1 = math.atan2(s1.dy - c.dy, s1.dx - c.dx);
    // M211 — WHICH WAY ROUND. An arc is a pair of angles plus a DIRECTION, and
    // both [ProjKind.arc] and Geo.arc mean "counter-clockwise from a0 to a1".
    // The endpoints alone do not carry that: they name two points on a circle,
    // and the two arcs between them are both valid readings.
    //
    // The 3D parameter t runs counter-clockwise about the edge's OWN axis.
    // Whether it still does after projection depends on which side of that
    // axis the sketch plane looks from, which is exactly the sign of the
    // projected conjugate pair's determinant: positive and the sweep survives,
    // negative and the projection MIRRORS it, so t increasing walks clockwise
    // in sketch coordinates. Reading a0 -> a1 counter-clockwise then traces
    // the COMPLEMENT — the other arc of the same circle.
    //
    // "i cant project the shape of the slot on the right. its on the wrong
    // side. there is no geometry." (bug20260805T230205). The sketch was on the
    // part's BOTTOM face, n=(0,-1,0), which views the slot's cap arcs from
    // behind their axis. Tapping the cap at sketch (18.07, 6.84) found
    // nothing — `log.txt`: "Tap geometry on another layer, or the X/Y axis." —
    // because the cap the picker was carrying ran from +90° counter-clockwise
    // to -90°, through (8.99, 0), the mirror image of the real one through
    // (23.20, 0). Note what the user did next: a circle centred (16.10, 0.00)
    // with its rim at (8.99, 0.00). They snapped to the wrong half, because
    // the wrong half is what was drawn.
    //
    // Swapping the endpoints when the projection mirrors keeps the same two
    // points and picks the other reading, which is the arc that is really
    // there. A full circle is unaffected, and so is an ellipse.
    final mirrored = ax.dx * by.dy - ax.dy * by.dx < 0;
    return PartEdge(index, const [],
        kind: ProjKind.arc,
        defs: [c],
        radius: r,
        a0: mirrored ? e1 : e0,
        a1: mirrored ? e0 : e1);
  }
  // A partial ellipse has no grip form in this sketch model, so it stays a
  // polyline rather than being silently closed into a full ellipse.
  if (!full) return null;
  return PartEdge(index, const [],
      kind: ProjKind.ellipse, defs: [c, c + p, c + q]);
}

/// Every B-Rep edge of [part]'s visible solids, projected onto [fr].
///
/// The order is deterministic — features in tree order, then edge index within
/// each solid — because that order IS the identity a projection stores. If the
/// model changes so much that an index no longer exists, the projection is
/// orphaned rather than silently re-pointed at a different edge (Inventor
/// converts an orphan to fixed curves; see [syncSolidProjections]).
///
/// Projection is orthogonal onto the plane, so an edge hidden behind the solid
/// projects exactly like a visible one. That is deliberate: Inventor lets you
/// project hidden edges too, they are only DRAWN differently.
List<PartEdge> partEdges(PartModel part, PlaneFrame fr) =>
    Perf.span('project.partEdges', () => _partEdges(part, fr));

List<PartEdge> _partEdges(PartModel part, PlaneFrame fr) {
  final out = <PartEdge>[];
  var idx = 0;
  for (final f in part.features) {
    final sol = f.solid;
    if (!f.visible || sol == null || f.consumedByJoin) continue;
    final m = sol.mesh;
    final starts = m.edgeStarts;
    final pts = m.edgePoints;
    for (var e = 0; e + 1 < starts.length; e++) {
      final a = starts[e], b = starts[e + 1];
      if (a < 0 || b * 3 > pts.length || b - a < 2) {
        idx++;
        continue;
      }
      final poly = <Offset>[];
      for (var i = a; i < b; i++) {
        poly.add(fr.toSketch(
            Vec3(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2])));
      }
      // Prefer the kernel's ANALYTIC record: a projected circle should be a
      // real circle, not a fine polygon that dimensions as chords.
      PartEdge? exact;
      final cur = m.edgeCurves;
      if ((e + 1) * 16 <= cur.length) {
        exact = analyticProjectedEdge(idx, cur, e * 16, fr);
      }
      out.add(exact ?? PartEdge(idx, poly));
      idx++;
    }
  }
  return out;
}

/// Turns a projected edge polyline into the sketch entity that represents it:
/// a plain LINE for two points, otherwise an open POLYLINE. Kept simple on
/// purpose — a projection is reference geometry, it is never edited, so it
/// does not need to round-trip as an arc or spline to behave correctly.
Geo geoForProjectedEdge(List<Offset> pts, int edgeIndex, String layer) {
  if (pts.length == 2) {
    return Geo(Geo.line, [pts[0].dx, pts[0].dy, pts[1].dx, pts[1].dy],
        layer: layer, proj: Geo.projSolid, projSeg: edgeIndex);
  }
  return Geo(
      Geo.polyline,
      [
        0, // open
        pts.length.toDouble(),
        for (final p in pts) ...[p.dx, p.dy],
      ],
      layer: layer,
      proj: Geo.projSolid,
      projSeg: edgeIndex);
}

/// The sketch entity for a projected edge, using its EXACT form where the
/// kernel gave one: a circle projects as a circle, an arc as an arc, a tilted
/// circle as a true ellipse (Inventor's grips: centre, major, minor vertex).
/// Only a type-0 edge, or a partial ellipse the sketch model cannot express,
/// falls back to the tessellated polyline.
Geo geoForPartEdge(PartEdge e, String layer) {
  switch (e.kind) {
    case ProjKind.line:
      return Geo(Geo.line,
          [e.defs[0].dx, e.defs[0].dy, e.defs[1].dx, e.defs[1].dy],
          layer: layer, proj: Geo.projSolid, projSeg: e.index);
    case ProjKind.circle:
      return Geo(Geo.circle, [e.defs[0].dx, e.defs[0].dy, e.radius],
          layer: layer, proj: Geo.projSolid, projSeg: e.index);
    case ProjKind.arc:
      return Geo(Geo.arc,
          [e.defs[0].dx, e.defs[0].dy, e.radius, e.a0, e.a1, 0.0],
          layer: layer, proj: Geo.projSolid, projSeg: e.index);
    case ProjKind.ellipse:
      return Geo(
          Geo.polyline,
          [
            0, 3, //
            e.defs[0].dx, e.defs[0].dy, //
            e.defs[1].dx, e.defs[1].dy, //
            e.defs[2].dx, e.defs[2].dy,
          ],
          layer: layer,
          spline: Geo.ellipseTag,
          proj: Geo.projSolid,
          projSeg: e.index);
    case ProjKind.polyline:
      return geoForProjectedEdge(e.pts, e.index, layer);
  }
}

/// Re-projects every `projSolid` entity in [gs] from the current model.
///
/// Mirrors what [syncProjections] does for in-sketch sources, but at the part
/// level because the source lives in 3D. Returns true if anything changed.
///
/// An orphan — the source edge no longer exists — becomes [Geo.projBroken]
/// and freezes where it is, exactly as Inventor converts a reference whose
/// parent feature is gone into fixed sketch curves, keeping its constraints.
bool syncSolidProjections(List<Geo> gs, PartModel part, PlaneFrame fr) {
  var any = false;
  List<PartEdge>? edges;
  for (var i = 0; i < gs.length; i++) {
    final g = gs[i];
    if (g.proj != Geo.projSolid) continue;
    edges ??= partEdges(part, fr);
    final src = resolveProjectionSource(g, edges);
    if (src == null ||
        (src.kind == ProjKind.polyline && src.pts.length < 2)) {
      gs[i] = g.withProj(Geo.projBroken, -1); // orphaned: freeze in place
      any = true;
      continue;
    }
    if (src.index != g.projSeg) {
      // M163 — the source is the same edge, the kernel just renumbered it.
      // Follow it, and record the new number so the next rebuild starts from
      // the cheap path again.
      gs[i] = g.withProj(Geo.projSolid, src.index);
    }
    final fresh = geoForPartEdge(src, g.layer);
    if (fresh.type != g.type ||
        fresh.spline != g.spline ||
        !_sameData(fresh.data, g.data)) {
      gs[i] = fresh.withStyle(g.style);
      any = true;
    }
  }
  return any;
}


/// M168 — the SECTION triangles of [sliced]: the faces that lie IN [frame],
/// returned in the sketch's own (u,v) so the 2D painter can hatch them.
///
/// The cut is made AT the sketch plane, so the newly exposed faces are exactly
/// coplanar with the sketch — which is what makes the hatch a 2D job. Inventor
/// draws it the same way: the section is flat on the sketch, not a texture
/// wrapped on a 3D surface.
///
/// Only triangles whose three vertices sit within [tol] of the plane AND whose
/// winding normal is parallel to it are section faces; everything else is the
/// remaining body and must not be hatched.
List<List<Offset>> sectionTrianglesAt(OcctMeshData m, PlaneFrame frame,
    {double tol = 1e-4}) {
  final out = <List<Offset>>[];
  final n = frame.n, o = frame.origin;
  for (var t = 0; t + 2 < m.indices.length; t += 3) {
    final i0 = m.indices[t] * 3, i1 = m.indices[t + 1] * 3,
        i2 = m.indices[t + 2] * 3;
    if (i0 + 2 >= m.positions.length ||
        i1 + 2 >= m.positions.length ||
        i2 + 2 >= m.positions.length) {
      continue;
    }
    final a = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
    final b = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
    final c = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
    if ((a - o).dot(n).abs() > tol ||
        (b - o).dot(n).abs() > tol ||
        (c - o).dot(n).abs() > tol) {
      continue;
    }
    // A sliver triangle contributes nothing and can carry a meaningless
    // normal, so drop it rather than let it decide the plane test.
    final cross = (b - a).cross(c - a);
    if (cross.length < 1e-12) continue;
    out.add([
      frame.toSketch(a),
      frame.toSketch(b),
      frame.toSketch(c),
    ]);
  }
  return out;
}

/// The BOUNDARY of a set of coplanar triangles, as closed loops in the same
/// (u,v) the triangles came in (M222).
///
/// The section faces arrive as a triangle SOUP — that is what a mesh is — and
/// drawing that soup is what made the reported triangles visible: every shared
/// edge got stroked as if it were an edge of the cut. It is not; it is an
/// artefact of how the face was tessellated, and it changes whenever the model
/// is re-meshed.
///
/// An edge that two triangles share is interior; one that belongs to a single
/// triangle is on the boundary. Vertices are welded onto a [weld] grid first,
/// because two triangles of one face meet at coordinates that are equal in the
/// kernel and can differ in the last bit after the transform into sketch
/// coordinates — un-welded, every interior edge would look like two boundary
/// edges and the whole soup would come back.
///
/// Loops keep the winding of the triangles they came from, so an outer
/// boundary and the hole inside it wind opposite ways and both `evenOdd` and
/// `nonZero` fill them correctly.
List<List<Offset>> sectionOutlines(List<List<Offset>> tris,
    {double weld = 1e-6}) {
  if (tris.isEmpty) return const [];
  final ids = <String, int>{};
  final pts = <Offset>[];
  int idOf(Offset p) {
    final key = '${(p.dx / weld).round()},${(p.dy / weld).round()}';
    final hit = ids[key];
    if (hit != null) return hit;
    ids[key] = pts.length;
    pts.add(p);
    return pts.length - 1;
  }

  // Directed edges, counted by their UNDIRECTED key: an interior edge is
  // walked once each way by the two triangles that share it.
  final count = <String, int>{};
  final dir = <String, List<int>>{}; // undirected key -> [from, to] as walked
  void edge(int a, int b) {
    final key = a < b ? '$a-$b' : '$b-$a';
    count[key] = (count[key] ?? 0) + 1;
    dir.putIfAbsent(key, () => [a, b]);
  }

  for (final t in tris) {
    if (t.length < 3) continue;
    final idx = [for (final p in t) idOf(p)];
    for (var i = 0; i < idx.length; i++) {
      edge(idx[i], idx[(i + 1) % idx.length]);
    }
  }

  // Boundary edges, indexed by the vertex they leave from.
  final outgoing = <int, List<List<int>>>{};
  var edges = 0;
  count.forEach((key, n) {
    if (n != 1) return;
    final e = dir[key]!;
    outgoing.putIfAbsent(e[0], () => []).add(e);
    edges++;
  });
  if (edges == 0) return const [];

  final used = <String, bool>{};
  final loops = <List<Offset>>[];
  for (final start in outgoing.keys.toList()) {
    for (final first in outgoing[start]!) {
      final firstKey = '${first[0]}>${first[1]}';
      if (used[firstKey] == true) continue;
      final loop = <int>[first[0]];
      var cur = first;
      // Bounded by the edge count: a malformed soup must not spin here.
      for (var step = 0; step <= edges; step++) {
        used['${cur[0]}>${cur[1]}'] = true;
        loop.add(cur[1]);
        if (cur[1] == first[0]) break; // closed
        final next = outgoing[cur[1]];
        if (next == null) break; // open chain: draw what there is
        List<int>? go;
        for (final e in next) {
          if (used['${e[0]}>${e[1]}'] == true) continue;
          go = e;
          break;
        }
        if (go == null) break;
        cur = go;
      }
      if (loop.length >= 4) {
        // The closing vertex repeats the first one; a Path closes itself.
        loops.add([for (final i in loop.sublist(0, loop.length - 1)) pts[i]]);
      }
    }
  }
  return loops;
}

/// One body's cut faces, ready to hatch (M222).
class SectionSlice {
  final String body;

  /// Closed boundary loops in the sketch's (u,v).
  final List<List<Offset>> loops;

  /// Which entry of [kSectionHatch] this body draws with.
  final int style;
  const SectionSlice(this.body, this.loops, this.style);
}

/// ISO 128-50 section hatching, as (angle in degrees, spacing in SCREEN px).
///
/// The standard's rule is that ADJACENT parts must be distinguishable — by
/// direction, or, when the same direction cannot be avoided, by spacing. Bodies
/// take these in the order they were created, so two bodies next to each other
/// in the browser can never draw the same hatch. Bodies four apart can, and
/// that is the honest limit of an index-based rule: it does not know which
/// bodies TOUCH, only which are neighbours in the list.
const List<(double, double)> kSectionHatch = [
  (45, 7),
  (135, 7),
  (45, 12),
  (135, 12),
];

/// M168 — Inventor's **Slice Graphics**: the solid with everything between the
/// viewer and the sketch plane cut away, so you can see and draw inside the
/// part.
///
/// A real boolean, not a render trick: a half-space box is built on the near
/// side of [frame] and subtracted with the kernel's own cut. That matters
/// because the section faces have to be REAL faces — a hatch has to follow
/// actual face boundaries, and a clipped render has none to follow.
///
/// The box reaches [reach] mm back from the plane and is sized from the part's
/// own extent, so it always swallows whatever is in front however large the
/// model is. Returns null when there is nothing to cut or the kernel refuses,
/// and the caller then shows the solid whole — a failed slice must not make
/// the part vanish.
KernelSolid? sliceSolidAt(
    PartKernel kernel, PartModel part, KernelSolid solid, PlaneFrame frame) {
  if (!kernel.available) return null;
  final (lo, hi) = originExtentBounds(part);
  // Half-diagonal of the part's box, plus a margin: any square of this size
  // centred on the plane covers the whole model in the plane's own axes.
  final r = (hi - lo).length + 10.0;
  if (!r.isFinite || r <= 0) return null;
  // A square profile in the plane's (u,v), extruded BACKWARDS along its
  // normal — the near side, which is what Inventor removes.
  final profile = [
    [
      [
        Offset(-r, -r),
        Offset(r, -r),
        Offset(r, r),
        Offset(-r, r),
      ]
    ]
  ];
  final tool = kernel.extrude(profile, r, 0, frame.mat34(0));
  if (tool == null) return null;
  final cut = kernel.cutSolids(solid, tool);
  tool.dispose();
  return cut;
}

/// M163 — the model edge a projection currently refers to.
///
/// `Geo.projSeg` holds a raw INDEX into the part's visible-solid edge list,
/// and that list is rebuilt from `part.features` and each solid's edge order
/// on every recompute. Adding a chamfer renumbers it. The projection then kept
/// pointing at "edge 5" and silently became a DIFFERENT edge — this is the
/// classic topological-naming failure that [EdgeSel] already exists to solve
/// for fillet and chamfer selections, and projections never got it.
///
/// Measured on the device (build 0f9814d): a sketch held a projected rim of
/// r=2.71 and a circle drawn over it. After a chamfer, `projSeg: 5` resolved
/// to a different edge, the projection shrank to r~2.47, and the sketch that
/// had ONE loop now had two nested 0.24 mm apart — so the extrusion built from
/// it came out as a paper-thin ring. That is the nest of shells in the report.
///
/// No new persisted field is needed: the sketch entity IS the fingerprint of
/// the last good projection. The stored index is tried first (it is right
/// whenever nothing upstream changed, and costs one comparison), and only when
/// that edge no longer LOOKS like the projection do we search for the one that
/// does.
///
/// Returns null when nothing matches well enough, which freezes the projection
/// as `projBroken` — the honest outcome, and the one Inventor gives when a
/// reference's parent is gone.
PartEdge? resolveProjectionSource(Geo g, List<PartEdge> edges) {
  PartEdge? atIndex;
  for (final e in edges) {
    if (e.index == g.projSeg) {
      atIndex = e;
      break;
    }
  }
  final atScore = atIndex == null ? double.infinity : _projScore(atIndex, g);
  // Nothing upstream moved: the cheap, overwhelmingly common case.
  if (atScore <= _kProjExact) return atIndex;

  PartEdge? best;
  var bestScore = double.infinity, runnerUp = double.infinity;
  for (final e in edges) {
    final sc = _projScore(e, g);
    if (sc < bestScore) {
      runnerUp = bestScore;
      bestScore = sc;
      best = e;
    } else if (sc < runnerUp) {
      runnerUp = sc;
    }
  }

  // A RENUMBER: some other edge is exactly the curve we projected, while the
  // stored number no longer is. This is the reported failure — after a chamfer
  // the list shifted, index 5 came to mean a circle 0.24 mm smaller, and the
  // projection silently became that circle.
  if (best != null && bestScore <= _kProjExact && !identical(best, atIndex)) {
    Log.i(
        'project',
        'seg ${g.projSeg} RENUMBERED -> ${best.index} '
            '(stored index now scores ${atScore.toStringAsFixed(4)}, '
            'exact match found elsewhere)');
    return best;
  }

  // The stored index still exists and nothing matches better: the source
  // legitimately CHANGED, and following it is exactly what a projection is
  // for. A projection whose source doubles in length must still track it, and
  // only a better-matching rival is evidence that the number stopped meaning
  // the same edge — so no tolerance is applied here.
  //
  // Except when it is DISQUALIFIED (infinite score): an edge that projects to
  // a different kind of curve is not the same edge changed, it is another
  // edge, and following the number onto it is the bug in miniature.
  if (atIndex != null && atScore.isFinite) {
    Log.i(
        'project',
        'seg ${g.projSeg} source CHANGED by ${atScore.toStringAsFixed(4)} '
            '(no better match among ${edges.length} edges — following it)');
    return atIndex;
  }

  // The number is gone. Fall back to the closest plausible edge, and refuse to
  // guess between near-equals (M158): moving a projection to the wrong edge is
  // the failure this whole function exists to end, and freezing is visible.
  final tol = _projTol(g);
  if (best == null || bestScore > tol) {
    Log.w(
        'project',
        'seg ${g.projSeg} ORPHANED — best of ${edges.length} edges scores '
            '${bestScore.isFinite ? bestScore.toStringAsFixed(4) : "inf"} '
            '> tol ${tol.toStringAsFixed(4)}; freezing');
    return null;
  }
  if (!runnerUp.isInfinite && runnerUp - bestScore < tol) {
    Log.w(
        'project',
        'seg ${g.projSeg} AMBIGUOUS — best ${bestScore.toStringAsFixed(4)} vs '
            'runner-up ${runnerUp.toStringAsFixed(4)} within tol '
            '${tol.toStringAsFixed(4)}; freezing rather than guessing');
    return null;
  }
  Log.i('project',
      'seg ${g.projSeg} -> ${best.index} (score ${bestScore.toStringAsFixed(4)})');
  return best;
}

/// Below this, a candidate and the stored projection are the same curve.
const double _kProjExact = 1e-9;

/// How far [e] is from being the edge [g] was projected from. Infinite when it
/// could not be: an edge that projects to a different KIND of curve is not the
/// same edge seen differently, it is another edge.
double _projScore(PartEdge e, Geo g) {
  final fresh = geoForPartEdge(e, g.layer);
  if (fresh.type != g.type || fresh.spline != g.spline) return double.infinity;
  final a = fresh.data, b = g.data;
  if (a.length != b.length) return double.infinity;
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  final s = math.sqrt(sum);
  return s.isFinite ? s : double.infinity;
}

/// Tolerance for [_projScore], scaled to the projection's own size the way
/// [EdgeSel.bestMatch] scales to its edge: a 200 mm edge may legitimately
/// shift further than a 2 mm one.
///
/// M182 — was 0.25 * (scale + 1): on a 100 mm edge that is a 25 mm bucket,
/// wide enough for a projected segment to fall onto a DIFFERENT edge of the
/// same kind (the device session showed segments of a closed profile jumping
/// to unrelated edges after a body change). 5 % keeps the "same edge moved a
/// little" case working (renumbering drift) without swallowing look-alikes.
double _projTol(Geo g) {
  var scale = 0.0;
  for (final v in g.data) {
    final a = v.abs();
    if (a.isFinite && a > scale) scale = a;
  }
  return 0.05 * (scale + 1.0);
}

bool _sameData(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return false;
  }
  return true;
}

/// Index of the [edges] entry within [tol] of [w], nearest first, or null.
/// Used for both hover highlight and the tap that creates the projection.
int? pickPartEdge(List<PartEdge> edges, Offset w, double tol) {
  var best = -1;
  var bestD = tol;
  for (final e in edges) {
    final ep = e.displayPts;
    for (var i = 0; i + 1 < ep.length; i++) {
      final d = _segDist(w, ep[i], ep[i + 1]);
      if (d < bestD) {
        bestD = d;
        best = e.index;
      }
    }
  }
  return best >= 0 ? best : null;
}

/// Distance from [p] to the segment [a]-[b]. Delegates to the shared
/// [segDistSq], keeping this call site's own 1e-18 degenerate threshold.
double _segDist(Offset p, Offset a, Offset b) =>
    math.sqrt(segDistSq(p, a, b, eps: 1e-18).$1);

// ===========================================================================
// Origin plane / axis extent (M83)
// ===========================================================================
//
// The origin planes used to be fixed 20x20 mm squares (a single half-extent of
// 10, "like the mock"). That is only ever right by accident: on a 200 mm
// bracket the planes disappear inside the part, on a 2 mm pin they swamp it.
// They now FRAME the geometry — each plane's width and height are the part's
// extent along that plane's own u and v axes, plus a little padding.
//
// ONE source of truth on purpose: the RealityKit payload, the CPU painter and
// the plane HIT-TEST all read these functions. If picking used a different
// rectangle than the renderer draws, a plane would be clickable where it is
// not visible (and vice versa) — the exact class of bug the two-renderer split
// keeps producing.

/// Half-extent used when a part has no geometry at all — a fresh part, where
/// the planes are the only thing on screen and are what you pick to start the
/// first sketch. Unchanged from the original fixed size, so an empty part
/// looks exactly as before.
const double kOriginExtentDefault = 10;

/// Padding around the content: a fraction of the extent, never less than
/// [kOriginExtentPadMin] mm. Proportional so the border reads the same at any
/// part size; floored so a flat or tiny part still gets a visible margin.
const double kOriginExtentPadFrac = 0.12;
const double kOriginExtentPadMin = 1.5;

/// Axis-aligned world bounds of everything drawable in [p] — solid meshes plus
/// visible sketch curves — or null when the part holds nothing yet.
///
/// Sketches count: on a fresh part the first sketch exists BEFORE any solid,
/// and a plane that did not grow with it would be the one thing on screen that
/// ignores the drawing on it.
(Vec3, Vec3)? partContentBounds(PartModel p) {
  // MEMOISED. This is called per plane by the painter, per plane by the
  // hit-test on every pointer move, and again when the RealityKit payload is
  // built — and it tessellates sketch curves, which is exactly the funnel M63
  // had to memoise for the gear. The signature below is cheap (it reads the
  // stored numbers, never the tessellation), so the walk happens once per
  // actual geometry change instead of several times per frame.
  final sig = _contentSignature(p);
  if (p.extentSig == sig) return p.extentCache;
  final b = _partContentBounds(p);
  p.extentSig = sig;
  p.extentCache = b;
  return b;
}

/// Cheap digest of everything [partContentBounds] reads. Solids travel by mesh
/// identity (a re-tessellation replaces the object); sketch geometry by its
/// stored parameters, so dragging a curve invalidates immediately.
String _contentSignature(PartModel p) {
  final b = StringBuffer();
  for (final f in p.features) {
    if (!f.visible || f.consumedByJoin) continue;
    final m = f.solid?.mesh;
    if (m == null) continue;
    b.write('s${identityHashCode(m)};');
  }
  for (final cs in p.childSketches) {
    if (!cs.visible) continue;
    b.write('k${cs.plane}${identityHashCode(cs.face)}:');
    for (final g in cs.model.geometry) {
      if (cs.model.hiddenLayers.contains(g.layer)) continue;
      if (g.isConstruction) continue;
      b.write(g.type);
      b.write('/');
      // The spline TAG changes the curve completely for identical data
      // (straight vs CV vs fit vs ellipse vs gear), so it belongs in the key.
      b.write(g.spline);
      for (final d in g.data) {
        b.write(',');
        b.write(d);
      }
      b.write(';');
    }
  }
  return b.toString();
}

(Vec3, Vec3)? _partContentBounds(PartModel p) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  var any = false;
  void add(double x, double y, double z) {
    if (!x.isFinite || !y.isFinite || !z.isFinite) return;
    any = true;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }

  for (final f in p.features) {
    if (!f.visible || f.consumedByJoin) continue;
    final pos = f.solid?.mesh.positions;
    if (pos == null) continue;
    for (var i = 0; i + 2 < pos.length; i += 3) {
      add(pos[i], pos[i + 1], pos[i + 2]);
    }
  }
  for (final cs in p.childSketches) {
    if (!cs.visible) continue;
    final fr = sketchFrameOf(cs);
    for (final g in cs.model.geometry) {
      if (cs.model.hiddenLayers.contains(g.layer)) continue;
      // Construction geometry is scaffolding, not the part — and M45's
      // auto-sized bounding rect around a text block is construction, so
      // counting it would let a label drive the size of the origin planes.
      if (g.isConstruction) continue;
      for (final q in sketchCurve(g)) {
        final w = fr.toWorld(q);
        add(w.x, w.y, w.z);
      }
    }
  }
  if (!any) return null;
  return (Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
}

/// Padded world bounds, with the ORIGIN always inside.
///
/// Including the origin costs nothing for the normal case (parts are modelled
/// around it) and prevents the degenerate one: a part modelled far off-origin
/// would otherwise push its own origin planes off into the distance, away from
/// the origin axes and centre point that are supposed to lie ON them.
(Vec3, Vec3) originExtentBounds(PartModel p) {
  final b = partContentBounds(p);
  if (b == null) {
    const d = kOriginExtentDefault;
    return (const Vec3(-d, -d, -d), const Vec3(d, d, d));
  }
  final (lo, hi) = b;
  double padOf(double a, double c) =>
      math.max(kOriginExtentPadMin, (c - a).abs() * kOriginExtentPadFrac);
  final px = padOf(lo.x, hi.x), py = padOf(lo.y, hi.y), pz = padOf(lo.z, hi.z);
  return (
    Vec3(math.min(lo.x, 0) - px, math.min(lo.y, 0) - py, math.min(lo.z, 0) - pz),
    Vec3(math.max(hi.x, 0) + px, math.max(hi.y, 0) + py, math.max(hi.z, 0) + pz),
  );
}

/// The rectangle origin plane [key] should occupy, in ITS OWN (u, v)
/// coordinates: (uMin, uMax, vMin, vMax).
///
/// Asymmetric on purpose. A part sketched from the origin outwards spans
/// x in [0, 60]; a symmetric half-extent would draw a 120 mm plane for a 60 mm
/// part. Projecting the world box onto the frame's own axes gives the plane
/// the part's width and height, which is what was asked for.
(double, double, double, double) originPlaneRect(PartModel p, String key) =>
    planeRectFor(p, planeFrame(key));

/// M151 — the same padded rectangle for ANY frame, so a work plane is drawn
/// and hit-tested by exactly the code the origin planes use. Keeping one
/// function is the point: M83 fixed a bug where the drawn rectangle and the
/// clickable one had drifted apart, and two plane kinds is two chances to do
/// it again.
(double, double, double, double) planeRectFor(PartModel p, PlaneFrame f) {
  final (lo, hi) = originExtentBounds(p);
  // The frame axes are signed unit world axes, so projecting the two box
  // corners and ordering the result is exact — no need to test all eight.
  double along(Vec3 axis, bool wantMax) {
    final x = axis.x >= 0 == wantMax ? hi.x : lo.x;
    final y = axis.y >= 0 == wantMax ? hi.y : lo.y;
    final z = axis.z >= 0 == wantMax ? hi.z : lo.z;
    return Vec3(x, y, z).dot(axis) - f.origin.dot(axis);
  }

  return (
    along(f.u, false),
    along(f.u, true),
    along(f.v, false),
    along(f.v, true)
  );
}

/// How far origin axis [dir] should reach: (lo, hi) along the axis, so the
/// axes span the same box the planes do instead of poking out of them (or
/// vanishing inside a large part).
(double, double) originAxisSpan(PartModel p, Vec3 dir) {
  final (lo, hi) = originExtentBounds(p);
  return boxSpanAlong(lo, hi, dir);
}

// ===========================================================================
// M91 — the browser TIMELINE and the End of Part marker
// ===========================================================================

/// One row of the part browser's top-level timeline.
class PartNode {
  /// Exactly one of these is set.
  final ChildSketch? sketch;
  final PartFeature? feature;

  /// For a sketch row: true when this is the SHARED copy pinned above its
  /// consumer, rather than a sketch that simply has not been consumed yet.
  final bool sharedCopy;

  const PartNode.forSketch(ChildSketch this.sketch, {this.sharedCopy = false})
      : feature = null;
  const PartNode.forFeature(PartFeature this.feature)
      : sketch = null,
        sharedCopy = false;

  bool get isFeature => feature != null;
  String get name => sketch?.model.name ?? feature!.name;
}

/// The part browser's top-level rows, in TIME order.
///
/// Inventor's browser is a history, not a set of folders: whatever you made
/// last is at the bottom. So a sketch created after an extrusion appears BELOW
/// that extrusion, and the old "all sketches, then all features" grouping is
/// gone.
///
/// Two placement rules on top of plain creation order:
///  * a **consumed** sketch is not a top-level row at all — it nests under the
///    feature that swallowed it (drawn by the feature row).
///  * a **shared** sketch's top-level copy is pinned DIRECTLY ABOVE its first
///    consumer, which is Inventor's "a copy of the sketch displays above its
///    parent feature" — not at its own creation slot, because the whole point
///    of sharing is to show the sketch in relation to the feature using it.
List<PartNode> partTimeline(PartModel part) {
  // Shared sketches are emitted by their consumer, so index them by consumer.
  final pinned = <PartFeature, List<ChildSketch>>{};
  for (final cs in part.childSketches) {
    if (!cs.shared) continue;
    final f = firstConsumerOf(part, cs.model.name);
    if (f != null) (pinned[f] ??= []).add(cs);
  }

  final rows = <(int, PartNode)>[];
  for (final cs in part.childSketches) {
    // Unconsumed sketches sit at their own creation slot. Consumed ones are
    // either nested (handled by the feature row) or pinned above their
    // consumer (below).
    if (firstConsumerOf(part, cs.model.name) == null) {
      rows.add((cs.seq, PartNode.forSketch(cs)));
    }
  }
  for (final f in part.features) {
    for (final cs in pinned[f] ?? const <ChildSketch>[]) {
      // Same sort key as the feature, emitted first — "directly above".
      rows.add((f.seq, PartNode.forSketch(cs, sharedCopy: true)));
    }
    rows.add((f.seq, PartNode.forFeature(f)));
  }
  // Stable sort: equal keys keep insertion order, which is what pins the
  // shared copy immediately above its feature.
  final idx = <(int, PartNode), int>{};
  for (var i = 0; i < rows.length; i++) {
    idx[rows[i]] = i;
  }
  rows.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
  });
  return [for (final r in rows) r.$2];
}

/// Features in build order — the order the End of Part marker counts in.
List<PartFeature> partBuildOrder(PartModel part) =>
    [for (final n in partTimeline(part)) if (n.isFeature) n.feature!];

/// Applies [PartModel.eopAfter] to [ExtrudeFeature.rolledBack].
///
/// Call after anything that changes the feature list or the marker. Returns
/// true when a flag actually changed, so callers can skip a recompute.
bool applyEndOfPart(PartModel part) {
  final nodes = partTimeline(part);
  final cut = part.eopAfter.clamp(0, nodes.length);
  var changed = false;
  // Everything the marker has NOT reached yet is suppressed — features are not
  // built, sketches are not drawn. A sketch nested under a rolled-back feature
  // follows its feature, since the feature row is the one that carries it.
  for (var i = 0; i < nodes.length; i++) {
    final want = i >= cut;
    final n = nodes[i];
    if (n.isFeature) {
      if (n.feature!.rolledBack != want) {
        n.feature!.rolledBack = want;
        changed = true;
      }
    } else {
      if (n.sketch!.rolledBack != want) {
        n.sketch!.rolledBack = want;
        changed = true;
      }
    }
  }
  // A consumed sketch has no row of its own; it is suppressed exactly when the
  // feature that consumed it is.
  for (final cs in part.childSketches) {
    final f = firstConsumerOf(part, cs.model.name);
    if (f == null || cs.shared) continue;
    final want = f.rolledBack;
    if (cs.rolledBack != want) {
      cs.rolledBack = want;
      changed = true;
    }
  }
  return changed;
}

/// True when [f] is suppressed by the End of Part marker.
bool featureRolledBack(PartModel part, PartFeature f) => f.rolledBack;

/// Whether the End of Part marker is anywhere but the end — i.e. the part is
/// showing an earlier state of itself.
bool partIsRolledBack(PartModel part) =>
    part.eopAfter < partTimeline(part).length;
