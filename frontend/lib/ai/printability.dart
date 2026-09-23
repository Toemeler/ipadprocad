/// What an FDM printer cannot build without support, measured on the mesh.
///
/// ISSUE #87 — "it is not fdm printable". The part the assistant handed over
/// was a cup whose handle's upper arm left the wall horizontally: its whole
/// underside is a ceiling in mid-air, which a filament printer draws onto
/// nothing. The model had written "all overhangs self-supporting" into its own
/// requirements, marked nothing done, and said "Fertig" — because nothing it
/// could read said otherwise. This is that reading.
///
/// Printed the way the app models a part — standing on its lowest Y, +Y up —
/// a surface needs support where it faces DOWN more steeply than the process
/// allows. The limit is a surface rising 30 degrees from horizontal — leaning
/// 60 degrees from vertical — which the owner's printers take without
/// support; the textbook 45 degrees rejected handles that print cleanly.
/// Faces lying on the bed are not overhangs; they are the first layer.
///
/// A flat ceiling held up on both sides of a short span (the top of a slot, a
/// window in a wall) is a BRIDGE, and a printer bridges ten or fifteen
/// millimetres cleanly — so it is not reported. See [overhangMatters] for
/// how "held up" is tested.
library;

import 'dart:math' as math;

import '../ffi/occt_engine.dart' show OcctMeshData;

/// One face of the body that faces down too steeply to print unsupported.
class Overhang {
  Overhang(this.face);

  /// Mesh face index, or -1 when the mesh carries no face identity.
  final int face;
  double area = 0;

  /// The most downward the face gets: -1 is a flat ceiling.
  double minNy = 0;
  double cx = 0, cy = 0, cz = 0;
  double x0 = double.infinity, x1 = double.negativeInfinity;
  double z0 = double.infinity, z1 = double.negativeInfinity;
  double yLow = double.infinity;

  bool get flat => minNy < -0.995;

  /// The shorter horizontal extent of the face — a bridge's span when flat.
  double get span => math.min(x1 - x0, z1 - z0);

  /// How far it leans out from vertical at its steepest: 90 is a ceiling,
  /// [kFdmOverhangLimitDeg] the limit.
  double get angleDeg => math.asin((-minNy).clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// How far a surface may lean out from vertical and still print unsupported:
/// 60 degrees, i.e. rising at least 30 degrees from horizontal.
const double kFdmOverhangLimitDeg = 60;

/// Downward faces leaning out further than [limitDeg] from vertical, largest
/// first.
List<Overhang> fdmOverhangs(OcctMeshData mesh,
    {double limitDeg = kFdmOverhangLimitDeg,
    double bedTolerance = 0.3,
    double minArea = 1}) {
  final p = mesh.positions;
  final idx = mesh.indices;
  if (p.length < 9 || idx.length < 3) return const [];
  var yMin = double.infinity;
  for (var i = 1; i < p.length; i += 3) {
    if (p[i] < yMin) yMin = p[i];
  }
  // A face leaning out by exactly the limit is printable; give the
  // tessellation two degrees of slack so a surface drawn AT the limit is not
  // flagged by its own facets. Leaning out by θ from vertical is a normal
  // whose Y is -sin θ.
  final threshold = -math.sin((limitDeg + 2) * math.pi / 180);
  final faces = mesh.triFaces;
  final byFace = <int, Overhang>{};
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
    if (a + 2 >= p.length || b + 2 >= p.length || c + 2 >= p.length) continue;
    final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
    final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
    // Counter-clockwise seen from outside, so the cross product points out.
    final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-12) continue;
    final unitY = ny / len;
    if (unitY >= threshold) continue;
    final lowest = math.min(p[a + 1], math.min(p[b + 1], p[c + 1]));
    final highest = math.max(p[a + 1], math.max(p[b + 1], p[c + 1]));
    // On the bed: the first layer, not an overhang.
    if (highest - yMin <= bedTolerance) continue;
    final area = len / 2;
    final f = faces.isNotEmpty && t ~/ 3 < faces.length ? faces[t ~/ 3] : -1;
    final o = byFace.putIfAbsent(f, () => Overhang(f));
    final mx = (p[a] + p[b] + p[c]) / 3;
    final my = (p[a + 1] + p[b + 1] + p[c + 1]) / 3;
    final mz = (p[a + 2] + p[b + 2] + p[c + 2]) / 3;
    o.cx = (o.cx * o.area + mx * area) / (o.area + area);
    o.cy = (o.cy * o.area + my * area) / (o.area + area);
    o.cz = (o.cz * o.area + mz * area) / (o.area + area);
    o.area += area;
    if (unitY < o.minNy) o.minNy = unitY;
    for (final q in [a, b, c]) {
      o.x0 = math.min(o.x0, p[q]);
      o.x1 = math.max(o.x1, p[q]);
      o.z0 = math.min(o.z0, p[q + 2]);
      o.z1 = math.max(o.z1, p[q + 2]);
    }
    if (lowest < o.yLow) o.yLow = lowest;
  }
  final out = [
    for (final o in byFace.values)
      if (o.area >= minArea) o
  ]..sort((x, y) => y.area.compareTo(x.area));
  return out;
}

/// Whether [x],[y],[z] lies inside the closed [mesh]: a ray straight up,
/// and an odd number of crossings.
bool meshContains(OcctMeshData mesh, double x, double y, double z) {
  final p = mesh.positions;
  final idx = mesh.indices;
  var crossings = 0;
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
    if (a + 2 >= p.length || b + 2 >= p.length || c + 2 >= p.length) continue;
    // Barycentric test in the XZ plane, then the hit's height.
    final ax = p[a], az = p[a + 2], bx = p[b], bz = p[b + 2];
    final cx = p[c], cz = p[c + 2];
    final d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz);
    if (d.abs() < 1e-14) continue; // edge-on to a vertical ray
    final l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d;
    final l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d;
    final l3 = 1 - l1 - l2;
    if (l1 < 0 || l2 < 0 || l3 < 0) continue;
    final hy = l1 * p[a + 1] + l2 * p[b + 1] + l3 * p[c + 1];
    if (hy > y) crossings++;
  }
  return crossings.isOdd;
}

/// Whether an overhang is worth stopping the part for.
///
/// Anything leaning out past the limit over more than a few square
/// millimetres — except a flat ceiling that is a BRIDGE: short enough to
/// span, and held up on both sides of its short span. The second half is the
/// one #87 needed. The underside of a handle arm is ten millimetres across,
/// which is a fine bridge, but nothing holds up either side of it — it is a
/// cantilever, and it droops. So material is looked for just beyond each side
/// of the span, a millimetre below the ceiling.
bool overhangMatters(Overhang o, OcctMeshData mesh,
    {double maxBridge = 12, double minArea = 8}) {
  if (o.area < minArea) return false;
  if (!o.flat || o.span > maxBridge) return true;
  final alongX = (o.x1 - o.x0) <= (o.z1 - o.z0);
  final y = o.yLow - 1.0;
  final (ax, az, bx, bz) = alongX
      ? (o.x0 - 0.5, o.cz, o.x1 + 0.5, o.cz)
      : (o.cx, o.z0 - 0.5, o.cx, o.z1 + 0.5);
  final heldA = meshContains(mesh, ax, y, az);
  final heldB = meshContains(mesh, bx, y, bz);
  return !(heldA && heldB);
}

/// What needs support and where, one sentence each, at most three; empty
/// when nothing does.
List<String> overhangReport(OcctMeshData mesh, {String body = ''}) {
  final out = <String>[];
  var yMin = double.infinity;
  for (var i = 1; i < mesh.positions.length; i += 3) {
    if (mesh.positions[i] < yMin) yMin = mesh.positions[i];
  }
  for (final o in fdmOverhangs(mesh)) {
    if (!overhangMatters(o, mesh)) continue;
    String mm(double v) => v.toStringAsFixed(1);
    out.add('${body.isEmpty ? '' : '$body: '}'
        '${o.flat ? 'a flat ceiling' : 'a surface leaning out ${o.angleDeg.round()}°'}'
        ' of ${o.area.round()} mm² at (${mm(o.cx)}, ${mm(o.cy)}, ${mm(o.cz)}), '
        '${mm(o.yLow - yMin)} mm above the bed, '
        '${o.flat ? 'not held up on both sides — it would be printed in mid-air' : 'flatter than the 30° above horizontal an FDM printer builds without support'}');
    if (out.length >= 3) break;
  }
  return out;
}
