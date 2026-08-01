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
import 'dart:math' as math;
import 'dart:ui';

import 'app_state.dart' show SketchModel;
import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'log.dart';
import 'perf.dart';
import 'snap.dart' show sampleEntity;
import 'spline.dart' show splineCurveFor, polyPoints;
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
PlaneFrame? frameForPlaneKey(PartModel p, String key) {
  if (kPlaneKeys.contains(key)) return planeFrame(key);
  for (final w in p.workPlanes) {
    if (w.id == key) return w.frame;
  }
  return null;
}

/// How a work plane was defined. Two kinds for now, both parametric only in
/// the sense that the DEFINITION is recorded; the frame is baked at creation.
enum WorkPlaneKind { offset, midplane }

/// A plane offset from [base] along its own normal by [d] mm.
///
/// The u/v axes are inherited so a sketch on the offset plane has the same
/// orientation as one on the base — an offset plane that silently rotated its
/// sketch axes would be worse than useless.
PlaneFrame offsetPlaneFrame(PlaneFrame base, double d) => PlaneFrame(
    kWorkPlaneKey, base.u, base.v, base.n, base.origin + base.n * d);

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

  WorkPlane(this.name, this.seq, this.kind, this.def, this.frame,
      {this.visible = true, this.base, this.offset});

  /// Whether [setOffset] can move this plane.
  bool get offsetEditable => kind == WorkPlaneKind.offset && base != null;

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
          'd': offset,
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
      );
    } catch (_) {
      // A corrupt entry must not take the whole part down with it.
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
bool _profileGeo(ProfileInput in, Geo g) {
  if (g.isConstruction || g.isCenterline) return false;
  if (in.hidden.contains(g.layer)) return false;
  final li = in.layers.indexOf(g.layer);
  if (li >= 0 && li >= in.eosAfter) return false; // below End of Sketch
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
        final pts = List<Offset>.of(splineCurveFor(g));
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
List<ProfileLoop> _arrangementLoops(ProfileInput in) {
  const tol = 1e-6;

  // ---- 1. every profile curve as straight segments -------------------------
  final segA = <Offset>[], segB = <Offset>[], segE = <int>[];
  for (var i = 0; i < in.geometry.length; i++) {
    final g = in.geometry[i];
    if (!_profileGeo(in, g)) continue;
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
  return kept;
}

/// How many closed loops [in] yields — the cheap shape of the profile
/// question. M182 — the projection guard uses this to refuse an update that
/// would open a loop a feature builds on: it runs the same arrangement code as
/// [profileLoops] but over an arbitrary candidate geometry list, silently.
int profileLoopCount(ProfileInput in) => _profileLoops(in).length;

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

List<ProfileLoop> _profileLoops(ProfileInput in) {
  // The arrangement subsumes the endpoint-chaining finder below and adds
  // crossings; the old path stays as a fallback so a bail-out can never leave
  // the sketch with no profile at all.
  final arranged = _arrangementLoops(in);
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
  for (var i = 0; i < in.geometry.length; i++) {
    final g = in.geometry[i];
    if (!_profileGeo(in, g)) continue;
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
  double score(OcctEdgeInfo e) {
    if (!e.filletable) return double.infinity;
    if (kind != 0 && e.kind != 0 && kind != e.kind) return double.infinity;
    final dx = e.mx - mx, dy = e.my - my, dz = e.mz - mz;
    final d = math.sqrt(dx * dx + dy * dy + dz * dz);
    var s = d + 0.05 * (e.length - length).abs();
    // M152 — RADIUS. It was stored from the beginning and never read, which
    // is how a chamfer picked on the inner rim of a boss came back after
    // recompute sitting on the outer rim of the cylinder underneath it. Two
    // concentric circles have midpoints only (R - r) apart, so position alone
    // cannot tell them apart, and length is deliberately a weak term. Radius
    // is the one thing that separates them, and it is weighted to say so.
    //
    // Not disqualifying, for the same reason length is not: a chamfer on a
    // neighbouring edge legitimately shrinks the circle it belongs to, and a
    // hard match would lose the edge on exactly the edits where keeping it
    // matters most.
    if (radius > 0 && e.radius > 0) s += 1.5 * (e.radius - radius).abs();
    return s;
  }

  /// The live edge this selection now refers to, or null when it is gone.
  /// [tol] is in model units and scales with the edge: a 200 mm edge may
  /// legitimately shift further than a 2 mm one.
  OcctEdgeInfo? bestMatch(List<OcctEdgeInfo> edges) {
    OcctEdgeInfo? best;
    var bestScore = double.infinity;
    var runnerUp = double.infinity;
    for (final e in edges) {
      final s = score(e);
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
    final scale = (kind == 2 || kind == 3) && radius > 0 ? radius : length.abs();
    final tol = 0.25 * (scale + 1.0);
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
      case 'sweep':
        return SweepFeature.fromJson(j);
      case 'loft':
        return LoftFeature.fromJson(j);
      case 'coil':
        return CoilFeature.fromJson(j);
      default:
        return null;
    }
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
    final ids = <int>[];
    final src = <int>[];
    var lost = 0;
    final taken = <int>{};
    for (var i = 0; i < edges.length; i++) {
      final sel = edges[i];
      final m = sel.bestMatch(live);
      // M164 — say what each stored selection resolved to. A chamfer landing
      // on the wrong edge, or silently vanishing, is invisible in the log
      // without this: only "edges=2" was ever printed, which says nothing
      // about WHICH two. The `want` line is the fingerprint as picked, `got`
      // is the live edge it matched.
      final want = 'r=${sel.radius.toStringAsFixed(4)} '
          'l=${sel.length.toStringAsFixed(3)} k=${sel.kind} '
          'm=(${sel.mx.toStringAsFixed(3)},${sel.my.toStringAsFixed(3)},'
          '${sel.mz.toStringAsFixed(3)})';
      // One live edge can only serve one selection: without this, two picks
      // that both drifted toward the same survivor would silently collapse
      // into a double-radius fillet on one edge.
      if (m == null || !taken.add(m.index)) {
        Log.w(
            'edge',
            'sel[$i] LOST — $want; '
                '${m == null ? "no confident match among ${live.length} live "
                    "edges (gone, or two candidates too alike to choose)" 
                    : "edge ${m.index} already taken by an earlier selection"}');
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
          'workPlanes=${workPlanes.length}',
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
  bool exportStep(List<KernelSolid> solids, String path);

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
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
          List<double> radii, {List<double> radii2 = const []}) =>
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
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
          double d1, double d2, double angleDeg) =>
      null;

  /// M111 — reads a STEP file as one [KernelSolid] per SOLID, so an imported
  /// assembly becomes several bodies rather than one opaque compound. Empty
  /// list on failure or when the file holds no solids.
  List<KernelSolid> importStepSolids(String path);
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
  String _err = '';

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
    final raw = op(ffi, sa, sb);
    if (raw == null) {
      _err = ffi.lastError();
      return null;
    }
    final result = ffi.unify(raw) ?? raw;
    if (!identical(result, raw)) raw.dispose();
    final mesh = result.mesh(
        linDeflection: kCoarseLinDeflection,
        angDeflection: kCoarseAngDeflection);
    if (mesh == null) {
      _err = ffi.lastError();
      result.dispose();
      return null;
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
      List<double> radii, {List<double> radii2 = const []}) {
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
    return _wrapOwned(
        ffi, shape.filletEdges(edgeIds, radii, radii2: radii2));
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
      double d1, double d2, double angleDeg) {
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
        ));
  }

  @override
  bool exportStep(List<KernelSolid> solids, String path) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return false;
    }
    final shapes = [
      for (final s in solids)
        if (s.shape != null && !s.shape!.disposed) s.shape!
    ];
    if (shapes.isEmpty) {
      _err = 'no solids to export';
      return false;
    }
    if (shapes.length == 1) return shapes.first.exportStep(path);
    OcctShape? acc;
    try {
      for (final s in shapes) {
        if (acc == null) {
          final seed = ffi.fuse(s, s); // cheap copy via self-union
          if (seed == null) {
            _err = ffi.lastError();
            return false;
          }
          acc = seed;
        } else {
          final fused = ffi.fuse(acc, s);
          acc.dispose();
          if (fused == null) {
            _err = ffi.lastError();
            return false;
          }
          acc = fused;
        }
      }
      final ok = acc!.exportStep(path);
      if (!ok) _err = ffi.lastError();
      return ok;
    } finally {
      acc?.dispose();
    }
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

}

/// Re-matches [profiles] against the current regions of [sketchName] and
/// returns the loop groups to hand the kernel, or an error string.
///
/// Shared by extrude and revolve: both pick profiles from a sketch the same
/// way, and duplicating this was how the two would have drifted apart.
(List<List<List<Offset>>>?, PlaneFrame?, String?) resolveProfiles(
    PartModel part, String sketchName, List<ProfileSel> profiles) {
  final cs = part.sketchByName(sketchName);
  if (cs == null) return (null, null, 'sketch "$sketchName" no longer exists');
  final regions = regionsFrom(profileLoops(cs.model));
  if (regions.isEmpty) return (null, null, 'no closed profile in "$sketchName"');
  final groups = <List<List<Offset>>>[];
  for (final sel in profiles) {
    final anchor = Offset(sel.ax, sel.ay);
    ProfileRegion? best;
    var bestD = double.infinity;
    for (final r in regions) {
      final d = (interiorPointOf(r.outer) - anchor).distance;
      if (d < bestD) {
        bestD = d;
        best = r;
      }
    }
    // sanity: the anchor should still sit INSIDE the matched region, or at
    // least the region should not have changed beyond recognition
    if (best == null ||
        (!pointInPolygon(anchor, best.outer.pts) &&
            (best.outer.area - sel.area).abs() > 0.5 * sel.area)) {
      return (null, null, 'a picked profile could not be found any more');
    }
    final ip = interiorPointOf(best.outer);
    sel.ax = ip.dx;
    sel.ay = ip.dy;
    sel.area = best.outer.area;
    groups.add([best.outer.pts, for (final h in best.holes) h.pts]);
  }
  if (groups.isEmpty) return (null, null, 'no profile selected');
  return (groups, sketchFrameOf(cs), null);
}

/// Recomputes [f] against the CURRENT model state and stores the resulting
/// solid, or an honest [PartFeature.computeError] (Inventor's sick-feature
/// behaviour, minus the guessing).
///
/// [base] is the accumulated solid of this feature's body at this position.
/// A body-modifying feature (fillet, chamfer) REQUIRES it — that is its
/// input, not something to combine with afterwards.
bool recomputeFeature(PartModel part, PartFeature f, PartKernel kernel,
    {KernelSolid? base}) {
  final ok = Perf.span(
      'kernel.feature', () => _recomputeFeature(part, f, kernel, base));
  // M164 — every feature rebuild, named, with its outcome. A part that comes
  // back different after a reopen is a SEQUENCE of these going wrong, and
  // until now the log showed only the ones that happened to toast.
  // M182 — a FAIL that still carries a solid is KEEPING LAST-GOOD GEOMETRY
  // (the recompute is non-destructive now); say so, so a device log can never
  // be misread as "this feature built a fresh solid".
  final tris = f.solid?.mesh.indices.length;
  Log.i(
      'feature',
      '${ok ? "ok  " : "FAIL"} ${f.name} (${f.kind}) body=${f.bodyName} '
          'op=${f.output}'
          '${base == null ? "" : " base=present"}'
          '${tris == null ? " solid=null" : " tris=${tris ~/ 3}"}'
          '${ok ? "" : (tris == null ? "" : " kept-last-good")}'
          '${f.computeError == null ? "" : "  err=${f.computeError}"}');
  return ok;
}

bool _recomputeFeature(
    PartModel part, PartFeature f, PartKernel kernel, KernelSolid? base) {
  f.computeError = null;
  // M182 — NON-DESTRUCTIVE on failure. The old code called f.disposeSolid()
  // here, so a failing recompute destroyed the last good solid BEFORE the new
  // one was known to work; the fold then rebuilt from a broken base and the
  // damage was persisted by the next save. Now the old solid stays alive
  // until a new one exists, and a failure leaves it untouched — the part
  // keeps displaying the last good geometry (the same principle as the 2D
  // solver's "never render diverged geometry").
  final old = f.solid;
  final ok = _dispatchRecompute(part, f, kernel, base);
  if (!ok) return false;
  if (old != null && !identical(old, f.solid)) old.dispose();
  return true;
}

bool _dispatchRecompute(
    PartModel part, PartFeature f, PartKernel kernel, KernelSolid? base) {
  if (f is BodyModifyFeature) return _recomputeBodyModify(f, kernel, base);
  if (f is ExtrudeFeature) return _recomputeExtrude(part, f, kernel, base);
  if (f is RevolveFeature) return _recomputeRevolve(part, f, kernel, base);
  if (f is SweepFeature) return _recomputeSweep(part, f, kernel);
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
(double, double, String?) resolveRevolveSweep(
    RevolveFeature f, PlaneFrame frame, KernelSolid? base, PartKernel kernel) {
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
  final axP = frame.toWorld(Offset(f.axPx, f.axPy));
  final axD = frame.u * f.axDx + frame.v * f.axDy;
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
    KernelSolid? base) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles);
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
    KernelSolid? base) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles);
  if (groups == null || frame == null) {
    f.computeError = err ?? 'profile resolution failed';
    return false;
  }
  if (f.axDx == 0 && f.axDy == 0) {
    f.computeError = 'no axis of revolution selected';
    return false;
  }
  final (sweep, startOffset, sweepErr) =
      resolveRevolveSweep(f, frame, base, kernel);
  if (sweepErr != null || !(sweep > 0)) {
    f.computeError = sweepErr ?? 'angle must be greater than 0';
    return false;
  }
  // Inventor's Symmetric/Flipped/Asymmetric rotate WHERE the sweep starts.
  // The shim always sweeps in the positive direction from the profile, so the
  // offset rides in the placement transform — the same trick extrudeSpan uses
  // for the linear case, and the reason neither path ever mirrors a solid.
  final solid = kernel.revolve(groups, sweep, f.axPx, f.axPy, f.axDx, f.axDy,
      frame.mat34Rotated(f.axPx, f.axPy, f.axDx, f.axDy, startOffset));
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

bool _recomputeSweep(PartModel part, SweepFeature f, PartKernel kernel) {
  final (groups, frame, err) =
      resolveProfiles(part, f.sketchName, f.profiles);
  if (groups == null || frame == null) {
    f.computeError = err ?? 'profile resolution failed';
    return false;
  }
  final sel = f.path;
  if (sel == null) {
    f.computeError = 'no path selected';
    return false;
  }
  final (pts, perr) = resolvePath(part, sel);
  if (pts == null) {
    f.computeError = perr ?? 'path resolution failed';
    return false;
  }
  final solid = kernel.sweep(groups, frame.mat34(0), pts,
      orientation: f.orientation,
      taperDeg: f.taperDeg,
      twistDeg: f.twistDeg);
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
  return true;
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
    out = kernel.filletEdges(base, ids, radii, radii2: radii2);
  } else if (f is ChamferFeature) {
    final (d1, d2, ang) = f.kernelParams;
    out = kernel.chamferEdges(base, ids, f.mode, d1, d2, ang);
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
  return true;
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
      if (f.solid != null) chainLast[f.bodyName] = f;
      continue;
    }
    // M182 — downstream of a failure on the same body: never compute, never
    // join the chain. The old solid (if any) is kept so the scene can keep
    // showing last-good geometry; the error names the culprit.
    final broke = brokenBody[f.bodyName];
    if (broke != null) {
      f.computeError =
          'feature "$broke" on this body failed — nothing further can be built';
      f.builtSig = null;
      allOk = false;
      continue;
    }
    final sig = '${upstream[f.bodyName] ?? ''}#${featureInputSig(part, f)}';
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
    return PartEdge(index, const [],
        kind: ProjKind.arc,
        defs: [c],
        radius: r,
        a0: math.atan2(s0.dy - c.dy, s0.dx - c.dx),
        a1: math.atan2(s1.dy - c.dy, s1.dx - c.dx));
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
