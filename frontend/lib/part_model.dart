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
  final String key; // 'xy' | 'yz' | 'xz'
  final Vec3 u, v, n;
  const PlaneFrame(this.key, this.u, this.v, this.n);

  Vec3 toWorld(Offset p, [double w = 0]) =>
      u * p.dx + v * p.dy + n * w;

  /// Row-major 3x4 rigid placement for [occt_transform]: columns u,v,n,
  /// translation = normal * [zOffset] (where the extrusion starts).
  List<double> mat34(double zOffset) => [
        u.x, v.x, n.x, n.x * zOffset, //
        u.y, v.y, n.y, n.y * zOffset, //
        u.z, v.z, n.z, n.z * zOffset, //
      ];
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

  Vec3 get dir => Vec3(math.sin(pol) * math.sin(az), math.cos(pol),
      math.sin(pol) * math.cos(az));

  void home() {
    az = math.pi / 4;
    pol = 0.955;
    halfH = 27;
    ox = 0;
    oy = 0;
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
      ..angle = math.atan2(
          pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);
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

/// One region per loop: the loop as outer plus its DIRECT children as holes.
List<ProfileRegion> regionsFrom(List<ProfileLoop> loops) {
  final parent = <int, int>{}; // loop id -> parent loop id
  for (final l in loops) {
    ProfileLoop? best;
    for (final o in loops) {
      if (o.id == l.id || !_loopInside(l, o)) continue;
      if (best == null || o.area < best.area) best = o;
    }
    if (best != null) parent[l.id] = best.id;
  }
  return [
    for (final l in loops)
      ProfileRegion(
          l, [for (final c in loops) if (parent[c.id] == l.id) c]),
  ];
}

/// The region under a tap at sketch point [p], Inventor-style: the smallest
/// loop containing the point is the region's outer boundary.
ProfileRegion? regionAt(List<ProfileRegion> regions, Offset p) {
  ProfileRegion? best;
  for (final r in regions) {
    if (!pointInPolygon(p, r.outer.pts)) continue;
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

  // runtime (never serialised)
  KernelSolid? solid;
  String? computeError;

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
  final String plane; // 'xy' | 'yz' | 'xz'
  ChildSketch(this.model, this.plane);
}

class PartModel {
  final String name;
  final List<ChildSketch> childSketches = [];
  final List<ExtrudeFeature> features = [];

  /// Origin-item visibility (all invisible by default, like the mock).
  final Map<String, bool> vis = {
    'yz': false, 'xz': false, 'xy': false,
    'x': false, 'y': false, 'z': false, 'cp': false,
  };
  final PartCamera camera = PartCamera();
  int featureN = 0, solidN = 0;
  bool dirty = false;

  PartModel(this.name);

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
            {'name': c.model.name, 'plane': c.plane}
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
      features.add(
          ExtrudeFeature.fromJson((f as Map).cast<String, dynamic>()));
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
// kernel bridge — the ONLY seam between part features and OCCT, so host
// tests can inject a fake while the app itself never fakes a B-Rep.
// ---------------------------------------------------------------------------
class KernelSolid {
  /// Display mesh in WORLD coordinates.
  final OcctMeshData mesh;
  final double volume;

  /// World-space B-Rep handle (null in test fakes). Owned by this solid.
  final OcctShape? shape;
  KernelSolid(this.mesh, this.volume, this.shape);
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
        final loops = [
          for (final loop in g)
            [
              for (final p in loop) ...[p.dx, p.dy]
            ]
        ];
        final part = ffi.extrudeProfile(loops, height, taperDeg: taperDeg);
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
      final mesh = placed.mesh();
      if (mesh == null) {
        _err = ffi.lastError();
        placed.dispose();
        return null;
      }
      return KernelSolid(mesh, placed.volume, placed);
    } catch (e) {
      _err = '$e';
      acc?.dispose();
      return null;
    }
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
  final frame = planeFrame(cs.plane);
  final solid =
      kernel.extrude(groups, height, f.taperDeg, frame.mat34(zOff));
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
  t = t
      .replaceAll(RegExp(r'(mm|deg|°)\s*$', caseSensitive: false), '')
      .trim();
  if (t.isEmpty) return null;
  final direct = double.tryParse(t.replaceAll(',', '.'));
  if (direct != null) return direct.isFinite ? direct : null;
  final f = ExprParser(t.replaceAll(',', '.')).parse();
  if (f == null) return null;
  final v = f(0);
  return v.isFinite ? v : null;
}
