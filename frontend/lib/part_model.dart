// iPadProCAD — 3D part documents (M56).
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
import 'snap.dart' show sampleEntity;
import 'spline.dart' show splineCurveFor, polyPoints;
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
  PartCamera(
      {this.az = math.pi / 4,
      this.pol = 0.955,
      this.halfH = 27,
      this.ox = 0,
      this.oy = 0});

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
    pol = math.acos(d.y.clamp(-1.0, 1.0)).clamp(0.001, math.pi - 0.001);
    if (d.y.abs() < 0.999) az = math.atan2(d.x, d.z);
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

/// True when profile geometry [g] participates in profiles: drawn on a live,
/// visible layer, not construction/centerline format (Inventor's rule).
bool _profileGeo(SketchModel s, Geo g) {
  if (g.isConstruction || g.isCenterline) return false;
  if (s.hiddenLayers.contains(g.layer)) return false;
  final li = s.layers.indexOf(g.layer);
  if (li >= 0 && li >= s.eosAfter) return false; // below End of Sketch
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
List<ProfileLoop> profileLoops(SketchModel s) {
  const tol = 1e-6;
  final loops = <ProfileLoop>[];
  var nextId = 0;

  void addLoop(List<Offset> raw, Set<int> ents) {
    if (raw.length < 3) return;
    final a = _signedArea(raw);
    if (a.abs() < 1e-6) return; // degenerate sliver
    final pts = a > 0 ? raw : raw.reversed.toList();
    loops.add(ProfileLoop(
        nextId++, pts, a.abs(), _centroidOf(pts), Set<int>.of(ents)));
  }

  // 1. split entities into standalone closed loops and open chains
  final chains = <(List<Offset>, int)>[]; // (points, entity index)
  for (var i = 0; i < s.geometry.length; i++) {
    final g = s.geometry[i];
    if (!_profileGeo(s, g)) continue;
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

  return [
    for (final l in loops)
      // SOLID rings sit at even depth; odd-depth loops are the holes of the
      // ring that contains them, so they are not top-level regions.
      if (depthOf(l.id).isEven)
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

class ExtrudeFeature {
  String name; // Extrusion1, Extrusion2, ...
  String bodyName; // Solid1, ...
  final String sketchName;
  final List<ProfileSel> profiles;
  ExtrudeDirection direction;
  double distanceA, distanceB, taperDeg;
  String exprA, exprB, exprTaper; // what the user typed (redisplayed on edit)
  bool iMate, matchShape;
  bool visible;

  /// Inventor's Output boolean: 'join' merges this volume into the previous
  /// body (the default once a base feature exists), 'new' starts a separate
  /// solid body. Cut/Intersect are future work.
  String output;

  // runtime (never serialised)
  KernelSolid? solid;
  String? computeError;

  /// True when a LATER visible join-feature carries the fused body this
  /// feature is part of — the viewport then skips this one (its volume is
  /// inside the accumulated solid of the chain's last feature).
  bool consumedByJoin = false;

  ExtrudeFeature({
    required this.name,
    required this.bodyName,
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
    this.visible = true,
    this.output = 'join',
  });

  Map<String, dynamic> toJson() => {
        'kind': 'extrude',
        'name': name,
        'body': bodyName,
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
        'visible': visible,
        'output': output,
      };

  static ExtrudeFeature fromJson(Map<String, dynamic> j) => ExtrudeFeature(
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
        visible: j['visible'] as bool? ?? true,
        output: j['output'] as String? ?? 'join',
      );

  void disposeSolid() {
    solid?.dispose();
    solid = null;
  }
}

// ---------------------------------------------------------------------------
// part document
// ---------------------------------------------------------------------------
class ChildSketch {
  final SketchModel model;
  final String plane; // 'xy' | 'yz' | 'xz' | 'face'
  final PlaneFrame? face; // set iff plane == 'face' (sketch on a solid face)

  /// Inventor semantics: a sketch stays visible in the 3D scene until a
  /// feature consumes it; consumption turns visibility OFF, and the browser
  /// eye can turn it back on (persisted).
  bool visible;
  ChildSketch(this.model, this.plane, [this.face, this.visible = true]);
}

/// The first feature that consumes [sketchName], or null (Inventor nests the
/// consumed sketch under exactly this feature in the browser).
ExtrudeFeature? firstConsumerOf(PartModel part, String sketchName) {
  for (final f in part.features) {
    if (f.sketchName == sketchName) return f;
  }
  return null;
}

/// The working frame of a child sketch: its stored face frame, or the fixed
/// origin-plane frame. EVERY consumer of a sketch's plane goes through this.
PlaneFrame sketchFrameOf(ChildSketch cs) => cs.face ?? planeFrame(cs.plane);

class PartModel {
  final String name;
  final List<ChildSketch> childSketches = [];
  final List<ExtrudeFeature> features = [];

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
  int featureN = 0, solidN = 0;
  bool dirty = false;

  PartModel(this.name);

  /// Distinct solid bodies in creation order (Inventor's "Solid Bodies"
  /// folder). A body is the set of features sharing a bodyName; its display
  /// entry is the LAST feature that actually carries geometry for it (join
  /// chains fold into one body). Returns [(bodyName, features-of-body)].
  List<(String, List<ExtrudeFeature>)> solidBodies() {
    final order = <String>[];
    final byName = <String, List<ExtrudeFeature>>{};
    for (final f in features) {
      if (f.solid == null && f.computeError == null) continue;
      byName.putIfAbsent(f.bodyName, () {
        order.add(f.bodyName);
        return <ExtrudeFeature>[];
      }).add(f);
    }
    return [for (final n in order) (n, byName[n]!)];
  }

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

  String nextFeatureName() => 'Extrusion${++featureN}';
  String nextSolidName() => 'Solid${++solidN}';

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
              if (c.face != null) 'frame': c.face!.frameJson(),
            }
        ],
        'features': [for (final f in features) f.toJson()],
        'featureN': featureN,
        'solidN': solidN,
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
      features.add(ExtrudeFeature.fromJson((f as Map).cast<String, dynamic>()));
    }
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
/// far-away solid stays cheap). Falls back to the coarse default on bad input.
double viewLinearDeflection(double halfH, double viewHpx,
    {double pxSag = 0.4, double floor = 1e-4, double ceil = 5.0}) {
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

  /// Writes the union of [solids] as STEP to [path].
  bool exportStep(List<KernelSolid> solids, String path);
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
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    final ffi = _ffi;
    if (ffi == null) {
      _err = 'no 3D kernel linked (occt_* symbols missing)';
      return null;
    }
    final sa = a.shape, sb = b.shape;
    if (sa == null || sb == null) {
      _err = 'fuse needs kernel-backed solids';
      return null;
    }
    final raw = ffi.fuse(sa, sb);
    if (raw == null) {
      _err = ffi.lastError();
      return null;
    }
    // v4: merge the same-domain faces/edges the boolean leaves behind —
    // otherwise the weld renders spurious fragment lines (M58 device find).
    final fused = ffi.unify(raw) ?? raw;
    if (!identical(fused, raw)) raw.dispose();
    final mesh = fused.mesh(
        linDeflection: kCoarseLinDeflection,
        angDeflection: kCoarseAngDeflection);
    if (mesh == null) {
      _err = ffi.lastError();
      fused.dispose();
      return null;
    }
    return KernelSolid(mesh, fused.volume, fused,
        meshLin: kCoarseLinDeflection,
        remesher: (lin, ang) =>
            fused.mesh(linDeflection: lin, angDeflection: ang));
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
}

/// Recomputes [f] against the CURRENT sketch state: re-matches the picked
/// profiles (nearest region by anchor, sanity-checked by area), builds the
/// loop groups, and asks the kernel for the solid. On success the solid and
/// the anchors are updated; on failure the old solid is dropped and
/// [ExtrudeFeature.computeError] says exactly why (Inventor's sick-feature
/// behaviour, minus the guessing).
bool recomputeFeature(PartModel part, ExtrudeFeature f, PartKernel kernel) {
  f.disposeSolid();
  f.computeError = null;
  final cs = part.sketchByName(f.sketchName);
  if (cs == null) {
    f.computeError = 'sketch "${f.sketchName}" no longer exists';
    return false;
  }
  final regions = regionsFrom(profileLoops(cs.model));
  if (regions.isEmpty) {
    f.computeError = 'no closed profile in "${f.sketchName}"';
    return false;
  }
  final groups = <List<List<Offset>>>[];
  for (final sel in f.profiles) {
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
      f.computeError = 'a picked profile could not be found any more';
      return false;
    }
    final ip = interiorPointOf(best.outer);
    sel.ax = ip.dx;
    sel.ay = ip.dy;
    sel.area = best.outer.area;
    groups.add([best.outer.pts, for (final h in best.holes) h.pts]);
  }
  if (groups.isEmpty) {
    f.computeError = 'no profile selected';
    return false;
  }
  final (height, zOff) = extrudeSpan(f.direction, f.distanceA, f.distanceB);
  if (!(height > 0)) {
    f.computeError = 'distance must be greater than 0';
    return false;
  }
  final frame = sketchFrameOf(cs);
  final solid = kernel.extrude(groups, height, f.taperDeg, frame.mat34(zOff));
  if (solid == null) {
    f.computeError = kernel.lastError;
    return false;
  }
  f.solid = solid;
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

/// Parses a dialog value: strips a unit suffix (mm / deg / °), then accepts
/// plain numbers or the full M41 expression grammar (ExprParser — sin, pi,
/// parentheses, ...). Null when it doesn't evaluate to a finite number.
double? parseValueExpr(String raw) {
  var t = raw.trim();
  t = t.replaceAll(RegExp(r'(mm|deg|°)\s*$', caseSensitive: false), '').trim();
  if (t.isEmpty) return null;
  final direct = double.tryParse(t.replaceAll(',', '.'));
  if (direct != null) return direct.isFinite ? direct : null;
  final f = ExprParser(t.replaceAll(',', '.')).parse();
  if (f == null) return null;
  final v = f(0);
  return v.isFinite ? v : null;
}

/// Recomputes EVERY feature in order and folds Inventor's Join chains: each
/// 'join' feature's solid becomes the boolean union of its own volume with
/// the accumulated body it joins (matched by bodyName), and every earlier
/// feature of that chain is flagged [ExtrudeFeature.consumedByJoin] so the
/// viewport draws exactly ONE solid per body — Inventor's "everything is one
/// part unless you chose New Solid". 'new' features start a fresh chain.
/// Returns true when every visible feature computed.
bool recomputeAllFeatures(PartModel part, PartKernel kernel) {
  var allOk = true;
  final chainLast = <String, ExtrudeFeature>{}; // bodyName -> last in chain
  for (final f in part.features) {
    f.consumedByJoin = false;
    final ok = recomputeFeature(part, f, kernel);
    if (!ok) {
      allOk = false;
      chainLast.remove(f.bodyName); // a broken chain stops accumulating
      continue;
    }
    final prev = f.output == 'join' ? chainLast[f.bodyName] : null;
    if (prev != null && prev.solid != null && f.solid != null) {
      final fused = kernel.fuseSolids(prev.solid!, f.solid!);
      if (fused != null) {
        f.disposeSolid();
        f.solid = fused;
        prev.consumedByJoin = true;
      } else {
        // honest failure: keep both standalone solids visible
        f.computeError ??= kernel.lastError;
        allOk = false;
      }
    }
    if (f.visible) chainLast[f.bodyName] = f;
  }
  return allOk;
}
