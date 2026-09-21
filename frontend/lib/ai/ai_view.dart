/// What the body LOOKS LIKE, as text the model can actually read.
///
/// ISSUE #72 — "ich denke nicht dass die KI wirklich sieht". That was exactly
/// right, and not as a figure of speech: `look` renders a PNG, and the two
/// providers this app ships with that cannot receive an image (Apple's
/// on-device model, DeepSeek's chat models) were handed a report that said
/// "a view was rendered but you have NOT seen it". On DeepSeek the eye was
/// closed every single time. The model then built a plate standing on its
/// edge, cut two holes straight through a part meant to HOLD something, and
/// reported success — because nothing it could read contradicted it.
///
/// A picture is not the only way to see. This renders the same orthographic
/// projection the viewport uses into a coarse occupancy grid and prints it.
/// It costs a few hundred characters, it reaches every provider, and it
/// answers the questions the digest cannot:
///
///   - IS IT THE RIGHT WAY UP? A plate lying flat and a plate standing on its
///     edge have the same bounding box numbers in different slots, and the
///     same digest line. They do not have the same silhouette.
///   - CAN YOU SEE THROUGH IT? An opening enclosed by material is a hole that
///     goes all the way through from this direction. That is the "kein Boden"
///     bug, visible at a glance rather than inferred.
///   - IS THE SHAPE EVEN CONNECTED? Two separate blobs read as two islands.
///
/// WHAT IT IS NOT. It is not a measurement. The cell size is stated so a
/// reader knows the resolution it is looking at, and every op that returns one
/// repeats that dimensions come from `describe_shape`. A 44-column grid cannot
/// resolve a 0.2 mm step and does not pretend to.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../part_model.dart' show Vec3, PartCamera;

/// A rendered text view: the occupancy grid plus the frame it was taken in.
class TextView {
  TextView({
    required this.cols,
    required this.rows,
    required this.cells,
    required this.enclosed,
    required this.cellW,
    required this.cellH,
    required this.right,
    required this.up,
    required this.toward,
    required this.widthMm,
    required this.heightMm,
    required this.depthMm,
    required this.azDeg,
    required this.polDeg,
    required this.openings,
    required this.islands,
  });

  final int cols, rows;

  /// Row-major, row 0 at the TOP of the screen. True where the body covers.
  final List<bool> cells;

  /// Row-major; true for an empty cell the background cannot reach — an
  /// opening you can see straight through.
  final List<bool> enclosed;

  final double cellW, cellH;
  final Vec3 right, up, toward;
  final double widthMm, heightMm, depthMm;
  final double azDeg, polDeg;

  /// How many separate see-through openings, and how many separate bodies of
  /// material, the silhouette has.
  final int openings, islands;

  bool get isEmpty => !cells.contains(true);

  /// The picture. Framed, because a silhouette with no border leaves the
  /// reader guessing where the empty space ends.
  String get art {
    final b = StringBuffer();
    final bar = '+${'-' * cols}+';
    b.writeln(bar);
    for (var r = 0; r < rows; r++) {
      b.write('|');
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        b.write(cells[i] ? '#' : (enclosed[i] ? 'o' : ' '));
      }
      b.writeln('|');
    }
    b.write(bar);
    return b.toString();
  }

  String toText() {
    final b = StringBuffer();
    b.writeln('VIEW az ${_d(azDeg)}° pol ${_d(polDeg)}° — orthographic, '
        '$cols × $rows cells of ${_d(cellW)} × ${_d(cellH)} mm');
    b.writeln('screen right = ${_dirLabel(right)} · screen up = '
        '${_dirLabel(up)} · you are looking from ${_dirLabel(toward)}');
    b.writeln('silhouette ${_d(widthMm)} wide × ${_d(heightMm)} high, '
        '${_d(depthMm)} mm deep away from you');
    b.writeln(art);
    b.writeln("'#' is material, 'o' is an opening you can see straight "
        'through from here, blank is background.');
    if (openings > 0) {
      b.writeln('$openings opening(s) go right through the body along this '
          'direction.');
    }
    if (islands > 1) {
      b.writeln('The silhouette falls into $islands separate pieces from '
          'this direction.');
    }
    b.write('This is a coarse picture, not a measurement — take every '
        'dimension from describe_shape.');
    return b.toString();
  }
}

String _d(double v) => v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// A direction as a name when it is one, and as numbers when it is not.
/// Naming a direction that is 12° off an axis would be a small lie in the one
/// place the model is trying to establish which way up the part is.
String _dirLabel(Vec3 v) {
  const names = ['X', 'Y', 'Z'];
  final c = [v.x, v.y, v.z];
  for (var i = 0; i < 3; i++) {
    if (c[i].abs() > 0.999) return '${c[i] > 0 ? "+" : "-"}${names[i]}';
  }
  return '(${c.map((x) => x.toStringAsFixed(2)).join(", ")})';
}

/// The widest grid a view may use. Wider reads no better and costs tokens in
/// every round of the loop, not once.
const int kTextViewMaxCols = 48;

/// Renders [positions]/[indices] as seen from (az, pol), in the SAME frame the
/// viewport uses — [PartCamera.dir] for the eye direction and
/// [PartCamera.rightFor] for screen right — so what the model reads and what
/// the user sees are the same view, not two conventions that happen to agree
/// on a cube.
TextView? renderTextView(Float64List positions, Int32List indices,
    {required double azRad, required double polRad, int cols = 44}) {
  if (positions.length < 9 || indices.length < 3) return null;
  cols = cols.clamp(12, kTextViewMaxCols);

  final cam = PartCamera(az: azRad, pol: polRad);
  final toward = cam.dir; // from the body toward the eye
  final right = PartCamera.rightFor(azRad);
  final up = right.cross(toward * -1).normalized();

  final n = positions.length ~/ 3;
  final su = Float64List(n), sv = Float64List(n);
  var u0 = double.infinity, u1 = -double.infinity;
  var v0 = double.infinity, v1 = -double.infinity;
  var d0 = double.infinity, d1 = -double.infinity;
  for (var i = 0; i < n; i++) {
    final x = positions[i * 3], y = positions[i * 3 + 1], z = positions[i * 3 + 2];
    final u = x * right.x + y * right.y + z * right.z;
    final v = x * up.x + y * up.y + z * up.z;
    final d = x * toward.x + y * toward.y + z * toward.z;
    su[i] = u;
    sv[i] = v;
    if (u < u0) u0 = u;
    if (u > u1) u1 = u;
    if (v < v0) v0 = v;
    if (v > v1) v1 = v;
    if (d < d0) d0 = d;
    if (d > d1) d1 = d;
  }
  final w = u1 - u0, h = v1 - v0;
  if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return null;

  // A character cell is about twice as tall as it is wide, so a square part
  // needs half as many rows as columns to come out square on screen.
  final cellW = w / cols;
  var rows = (h / (cellW * 2)).round();
  rows = rows.clamp(3, 30);
  final cellH = h / rows;

  final cells = List<bool>.filled(cols * rows, false);

  // Cell coordinates: column 0 is -u, row 0 is +v (top of the screen).
  double cx(double u) => (u - u0) / w * cols;
  double cy(double v) => (v1 - v) / h * rows;

  for (var t = 0; t + 2 < indices.length; t += 3) {
    final a = indices[t], b = indices[t + 1], c = indices[t + 2];
    if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n) continue;
    final ax = cx(su[a]), ay = cy(sv[a]);
    final bx = cx(su[b]), by = cy(sv[b]);
    final gx = cx(su[c]), gy = cy(sv[c]);
    // A triangle smaller than a cell covers no cell centre; its own centre
    // still marks one, so a fine tessellation does not render as lace.
    final mid = ((ay + by + gy) / 3).floor() * cols + ((ax + bx + gx) / 3).floor();
    if (mid >= 0 && mid < cells.length) cells[mid] = true;
    final lo = math.max(0, math.min(ax, math.min(bx, gx)).floor());
    final hi = math.min(cols - 1, math.max(ax, math.max(bx, gx)).ceil());
    final top = math.max(0, math.min(ay, math.min(by, gy)).floor());
    final bot = math.min(rows - 1, math.max(ay, math.max(by, gy)).ceil());
    final area = (bx - ax) * (gy - ay) - (gx - ax) * (by - ay);
    if (area.abs() < 1e-12) continue;
    for (var r = top; r <= bot; r++) {
      for (var col = lo; col <= hi; col++) {
        final i = r * cols + col;
        if (cells[i]) continue;
        final px = col + 0.5, py = r + 0.5;
        final w0 = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / area;
        final w1 = ((px - ax) * (gy - ay) - (gx - ax) * (py - ay)) / area;
        if (w0 >= 0 && w1 >= 0 && w0 + w1 <= 1) cells[i] = true;
      }
    }
  }

  // An empty cell the border cannot reach is an opening THROUGH the body.
  final reached = List<bool>.filled(cols * rows, false);
  final queue = <int>[];
  void seed(int i) {
    if (!cells[i] && !reached[i]) {
      reached[i] = true;
      queue.add(i);
    }
  }

  for (var c = 0; c < cols; c++) {
    seed(c);
    seed((rows - 1) * cols + c);
  }
  for (var r = 0; r < rows; r++) {
    seed(r * cols);
    seed(r * cols + cols - 1);
  }
  while (queue.isNotEmpty) {
    final i = queue.removeLast();
    final r = i ~/ cols, c = i % cols;
    if (c > 0) seed(i - 1);
    if (c < cols - 1) seed(i + 1);
    if (r > 0) seed(i - cols);
    if (r < rows - 1) seed(i + cols);
  }
  final enclosed = [
    for (var i = 0; i < cells.length; i++) !cells[i] && !reached[i]
  ];

  return TextView(
    cols: cols,
    rows: rows,
    cells: cells,
    enclosed: enclosed,
    cellW: cellW,
    cellH: cellH,
    right: right,
    up: up,
    toward: toward,
    widthMm: w,
    heightMm: h,
    depthMm: d1 - d0,
    azDeg: azRad * 180 / math.pi,
    polDeg: polRad * 180 / math.pi,
    openings: _regions(enclosed, cols, rows),
    islands: _regions(cells, cols, rows),
  );
}

/// How many separate 4-connected regions of [mask] there are.
int _regions(List<bool> mask, int cols, int rows) {
  final seen = List<bool>.filled(mask.length, false);
  var count = 0;
  final stack = <int>[];
  for (var start = 0; start < mask.length; start++) {
    if (!mask[start] || seen[start]) continue;
    count++;
    seen[start] = true;
    stack.add(start);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final r = i ~/ cols, c = i % cols;
      void go(int j) {
        if (mask[j] && !seen[j]) {
          seen[j] = true;
          stack.add(j);
        }
      }

      if (c > 0) go(i - 1);
      if (c < cols - 1) go(i + 1);
      if (r > 0) go(i - cols);
      if (r < rows - 1) go(i + cols);
    }
  }
  return count;
}
