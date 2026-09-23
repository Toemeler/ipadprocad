// Geometry the benchmark measures on the finished part: plane sections of the
// triangle mesh, what is material and what is enclosed in each section, and
// whether a point is inside a body. Pure Dart over positions/indices, so a
// check never depends on what the model said it built.
import 'dart:math' as math;

class P2 {
  const P2(this.x, this.y);
  final double x, y;
}

/// A triangle mesh in world millimetres.
class Tri {
  Tri(this.pos, this.idx);
  final List<double> pos;
  final List<int> idx;

  List<double> bounds() {
    final b = [
      double.infinity, double.infinity, double.infinity,
      -double.infinity, -double.infinity, -double.infinity
    ];
    for (var i = 0; i + 2 < pos.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        b[k] = math.min(b[k], pos[i + k]);
        b[k + 3] = math.max(b[k + 3], pos[i + k]);
      }
    }
    return b;
  }

  static Tri merge(Iterable<Tri> parts) {
    final pos = <double>[];
    final idx = <int>[];
    for (final t in parts) {
      final base = pos.length ~/ 3;
      pos.addAll(t.pos);
      idx.addAll(t.idx.map((i) => i + base));
    }
    return Tri(pos, idx);
  }
}

/// One closed outline in a section, in the plane's two remaining axes
/// (for axis y: (x, z); for axis x: (y, z); for axis z: (x, y)).
class Loop {
  Loop(this.pts);
  final List<P2> pts;
  int depth = 0;
  double get area {
    var a = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      a += p.x * q.y - q.x * p.y;
    }
    return (a / 2).abs();
  }

  P2 get centroid {
    var a = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      final c = p.x * q.y - q.x * p.y;
      a += c;
      cx += (p.x + q.x) * c;
      cy += (p.y + q.y) * c;
    }
    if (a.abs() < 1e-12) return pts.first;
    return P2(cx / (3 * a), cy / (3 * a));
  }

  bool contains(P2 t) {
    var inside = false;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      final a = pts[i], b = pts[j];
      if ((a.y > t.y) != (b.y > t.y) &&
          t.x < (b.x - a.x) * (t.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  List<double> box() {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final p in pts) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
    return [x0, y0, x1, y1];
  }
}

/// A plane section: its loops, each with a nesting depth. Depth 0 is an
/// outside boundary, 1 a hole in it, 2 an island in the hole, ...
class Section {
  Section(this.loops);
  final List<Loop> loops;

  double get material {
    var a = 0.0;
    for (final l in loops) {
      a += l.depth.isEven ? l.area : -l.area;
    }
    return a;
  }

  /// Area enclosed by material but not material: the water a cup holds at
  /// this height, the bore of a wheel.
  double get enclosed {
    var a = 0.0;
    for (final l in loops) {
      if (l.depth == 0) continue;
      a += l.depth.isOdd ? l.area : -l.area;
    }
    return a;
  }

  Iterable<Loop> get holes => loops.where((l) => l.depth.isOdd);
  Iterable<Loop> get outers => loops.where((l) => l.depth.isEven);
}

int _other1(int axis) => axis == 0 ? 1 : 0;
int _other2(int axis) => axis == 2 ? 1 : 2;

/// Sections [mesh] with the plane `coord[axis] == c`.
Section slice(Tri mesh, int axis, double c) {
  c += 1.3e-6; // never exactly through a vertex
  final a1 = _other1(axis), a2 = _other2(axis);
  final segs = <(P2, P2)>[];
  final p = mesh.pos;
  for (var t = 0; t + 2 < mesh.idx.length; t += 3) {
    final v = [mesh.idx[t], mesh.idx[t + 1], mesh.idx[t + 2]];
    final d = [for (final i in v) p[i * 3 + axis] - c];
    final pts = <P2>[];
    for (var e = 0; e < 3; e++) {
      final i = e, j = (e + 1) % 3;
      if ((d[i] < 0) != (d[j] < 0)) {
        final s = d[i] / (d[i] - d[j]);
        final vi = v[i] * 3, vj = v[j] * 3;
        pts.add(P2(p[vi + a1] + s * (p[vj + a1] - p[vi + a1]),
            p[vi + a2] + s * (p[vj + a2] - p[vi + a2])));
      }
    }
    if (pts.length == 2) segs.add((pts[0], pts[1]));
  }
  // Chain segments into loops by their quantised end points.
  String key(P2 q) =>
      '${(q.x * 2e4).round()},${(q.y * 2e4).round()}';
  final at = <String, List<int>>{};
  for (var i = 0; i < segs.length; i++) {
    at.putIfAbsent(key(segs[i].$1), () => []).add(i);
    at.putIfAbsent(key(segs[i].$2), () => []).add(i);
  }
  final used = List<bool>.filled(segs.length, false);
  final loops = <Loop>[];
  for (var s0 = 0; s0 < segs.length; s0++) {
    if (used[s0]) continue;
    used[s0] = true;
    final pts = <P2>[segs[s0].$1];
    var cur = segs[s0].$2;
    final startKey = key(segs[s0].$1);
    for (var guard = 0; guard < segs.length; guard++) {
      final k = key(cur);
      if (k == startKey) break;
      pts.add(cur);
      int? next;
      for (final i in at[k] ?? const <int>[]) {
        if (!used[i]) {
          next = i;
          break;
        }
      }
      if (next == null) break;
      used[next] = true;
      cur = key(segs[next].$1) == k ? segs[next].$2 : segs[next].$1;
    }
    if (pts.length >= 3) loops.add(Loop(pts));
  }
  for (final l in loops) {
    final probe = l.pts.first;
    l.depth = loops.where((o) => !identical(o, l) && o.contains(probe)).length;
  }
  return Section(loops);
}

/// Whether [pt] is inside the closed mesh, by ray parity along a slightly
/// skewed direction.
bool insideMesh(Tri mesh, List<double> pt) {
  const dir = [1.0, 0.000731, 0.000419];
  var hits = 0;
  final p = mesh.pos;
  for (var t = 0; t + 2 < mesh.idx.length; t += 3) {
    final a = mesh.idx[t] * 3, b = mesh.idx[t + 1] * 3, c = mesh.idx[t + 2] * 3;
    final e1 = [p[b] - p[a], p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]];
    final e2 = [p[c] - p[a], p[c + 1] - p[a + 1], p[c + 2] - p[a + 2]];
    final h = [
      dir[1] * e2[2] - dir[2] * e2[1],
      dir[2] * e2[0] - dir[0] * e2[2],
      dir[0] * e2[1] - dir[1] * e2[0]
    ];
    final det = e1[0] * h[0] + e1[1] * h[1] + e1[2] * h[2];
    if (det.abs() < 1e-14) continue;
    final f = 1 / det;
    final s = [pt[0] - p[a], pt[1] - p[a + 1], pt[2] - p[a + 2]];
    final u = f * (s[0] * h[0] + s[1] * h[1] + s[2] * h[2]);
    if (u < 0 || u > 1) continue;
    final q = [
      s[1] * e1[2] - s[2] * e1[1],
      s[2] * e1[0] - s[0] * e1[2],
      s[0] * e1[1] - s[1] * e1[0]
    ];
    final w = f * (dir[0] * q[0] + dir[1] * q[1] + dir[2] * q[2]);
    if (w < 0 || u + w > 1) continue;
    final tt = f * (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]);
    if (tt > 1e-9) hits++;
  }
  return hits.isOdd;
}

/// Triangle centroids, a cheap sample of a surface.
List<List<double>> surfaceSamples(Tri mesh, {int max = 1500}) {
  final n = mesh.idx.length ~/ 3;
  final step = math.max(1, n ~/ max);
  final out = <List<double>>[];
  for (var t = 0; t < n; t += step) {
    final a = mesh.idx[t * 3] * 3,
        b = mesh.idx[t * 3 + 1] * 3,
        c = mesh.idx[t * 3 + 2] * 3;
    out.add([
      for (var k = 0; k < 3; k++)
        (mesh.pos[a + k] + mesh.pos[b + k] + mesh.pos[c + k]) / 3
    ]);
  }
  return out;
}

/// How deep [pt] lies inside [mesh]: the distance to the nearest vertex, as a
/// cheap stand-in (0 when outside).
bool deeplyInside(Tri mesh, List<double> pt, double depth) {
  if (!insideMesh(mesh, pt)) return false;
  for (final d in const [
    [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]
  ]) {
    if (!insideMesh(mesh,
        [pt[0] + d[0] * depth, pt[1] + d[1] * depth, pt[2] + d[2] * depth])) {
      return false;
    }
  }
  return true;
}

/// Mean and max distance of a loop's points from an axis point.
(double, double, double) radii(Loop l, P2 axis) {
  var sum = 0.0, mx = 0.0, mn = double.infinity;
  for (final p in l.pts) {
    final r = math.sqrt(math.pow(p.x - axis.x, 2) + math.pow(p.y - axis.y, 2));
    sum += r;
    mx = math.max(mx, r);
    mn = math.min(mn, r);
  }
  return (sum / l.pts.length, mn, mx);
}
