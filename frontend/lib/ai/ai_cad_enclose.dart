part of 'ai_cad.dart';

// #93 — "das Gehäuse ist viel grösser als es sein müsste und nicht an die
// Form der Innereien angepasst."
//
// Asked for a case around a Ø4.4 spool and a Ø28 wheel, the model drew a
// 33 × 37 mm rounded rectangle, because a rectangle is what a sketch op
// makes easily. Following the contents meant projecting every body, taking
// the outline and offsetting it twice, by hand, in sketch coordinates — so it
// never happened. This op does exactly that, from the bodies themselves.

extension AiCadEnclose on AiCad {
  /// `enclose {bodies?, wall?, clearance?, floor?, rim?, id?}` — an open-top
  /// case whose walls follow the contents' footprint seen from above (+Y):
  /// the convex outline around every named body, [clearance] off it inside
  /// and [wall] thicker outside, standing on a [floor] under the lowest
  /// content and rising [rim] above the highest.
  Future<AiActionOutcome> _enclose(PartModel p, AiAction a) async {
    final wall = a.number('wall') ?? 2.0;
    // 1.0 mm: what FDM enclosure guides give for printed walls round
    // components (0.5 mm is the figure for SLA/SLS and the tight end).
    final clearance = a.number('clearance') ?? 1.0;
    final floor = a.number('floor') ?? wall;
    final rim = a.number('rim') ?? 0.0;
    if (wall <= 0 || clearance < 0 || floor <= 0 || rim < 0) {
      return AiActionOutcome.failed(
          a.op, 'wall and floor must be > 0, clearance and rim ≥ 0 (mm)');
    }
    final visible = {
      for (final (name, fs) in p.solidBodies())
        if (fs.any((f) => f.visible)) name
    };
    final asked = a.args['bodies'];
    final names = asked is List && asked.isNotEmpty
        ? [for (final b in asked) '$b']
        : visible.toList();
    if (names.isEmpty) {
      return AiActionOutcome.failed(a.op, 'there is nothing to enclose');
    }
    final pts = <math.Point<double>>[];
    var yMin = double.infinity, yMax = -double.infinity;
    for (final name in names) {
      final solid = currentBodySolid(p, name);
      if (solid == null) {
        return AiActionOutcome.failed(
            a.op,
            'no body named "$name" with a solid — the bodies are '
            '${p.bodyNames.join(", ")}');
      }
      final pos = solid.mesh.positions;
      for (var i = 0; i + 2 < pos.length; i += 3) {
        pts.add(math.Point(pos[i], pos[i + 2]));
        yMin = math.min(yMin, pos[i + 1]);
        yMax = math.max(yMax, pos[i + 1]);
      }
    }
    final hull = aiConvexHull(pts);
    if (hull.length < 3) {
      return AiActionOutcome.failed(a.op, 'the contents have no footprint');
    }
    final inner = aiOffsetHull(hull, clearance);
    final outer = aiOffsetHull(hull, clearance + wall);
    final base = yMin - floor, top = yMax + rim;
    final id = a.text('id') ?? 'case';

    // Built from the ops the model has, so the timeline holds an ordinary
    // sketch and extrusion it can edit, not a black box.
    Future<AiActionOutcome> step(String op, Map<String, dynamic> args) =>
        _one(p, AiAction(op, args));
    // A sketch on XZ has sketch +y along world -Z.
    List<double> sk(math.Point<double> q) => [q.x, -q.y];
    Map<String, dynamic> path(String sketch, List<math.Point<double>> ring) => {
          'sketch': sketch,
          'start': sk(ring.first),
          'segments': [
            for (final q in ring.skip(1)) {'to': sk(q)}
          ],
          'closed': true,
        };

    final outSk = '${id}_outline', inSk = '${id}_pocket';
    for (final (op, args) in [
      ('create_sketch', {'plane': 'xz', 'offset': base, 'id': outSk}),
      ('sketch_path', path(outSk, outer)),
    ]) {
      final o = await step(op, args);
      if (!o.ok) return AiActionOutcome.failed(a.op, '$op: ${o.error}');
    }
    final shell = await step('extrude', {
      'sketch': outSk,
      'distance': top - base,
      'operation': 'new',
      'id': id,
    });
    if (!shell.ok) {
      return AiActionOutcome.failed(a.op, 'the case body: ${shell.error}');
    }
    final body = shell.detail?['body'];
    for (final (op, args) in [
      ('create_sketch', {'plane': 'xz', 'offset': yMin, 'id': inSk}),
      ('sketch_path', path(inSk, inner)),
    ]) {
      final o = await step(op, args);
      if (!o.ok) return AiActionOutcome.failed(a.op, '$op: ${o.error}');
    }
    final pocket = await step('extrude', {
      'sketch': inSk,
      // Out through the open top, so no skin is left over the rim.
      'distance': top - yMin + 1,
      'operation': 'cut',
      if (body != null) 'body': body,
      'id': '${id}_pocket',
    });
    if (!pocket.ok) {
      return AiActionOutcome.failed(a.op, 'the pocket: ${pocket.error}');
    }
    double span(List<math.Point<double>> r,
            double Function(math.Point<double>) f) =>
        r.map(f).reduce(math.max) - r.map(f).reduce(math.min);
    return AiActionOutcome(a.op, detail: {
      'feature': id,
      'body': body,
      'contents': names,
      'outsideMm': [
        _r(span(outer, (q) => q.x)),
        _r(top - base),
        _r(span(outer, (q) => q.y)),
      ],
      'floorTopY': _r(yMin),
      'wall': wall,
      'clearance': clearance,
      'note': 'The walls follow the convex outline of the contents seen from '
          'above, $clearance mm clear of them, open at the top. Cut outlets, '
          'shaft holes and mounting features into it as ordinary features; a '
          'lid is a separate body on the rim.',
    });
  }
}

/// The convex hull of [pts], counter-clockwise, without repeated points
/// (Andrew's monotone chain).
List<math.Point<double>> aiConvexHull(List<math.Point<double>> pts) {
  final s = [...pts]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (s.length < 3) return s;
  double cross(
          math.Point<double> o, math.Point<double> a, math.Point<double> b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <math.Point<double>>[];
  for (final q in s) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, q) <= 1e-12) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <math.Point<double>>[];
  for (final q in s.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, q) <= 1e-12) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [
    ...lower.sublist(0, lower.length - 1),
    ...upper.sublist(0, upper.length - 1)
  ];
}

/// [hull] grown outward by [d] — the Minkowski sum with a circle, which for a
/// convex outline is exactly its offset — then thinned so that no point
/// lies closer than 0.02 mm to the line through its neighbours.
List<math.Point<double>> aiOffsetHull(List<math.Point<double>> hull, double d) {
  if (d <= 0) return _thin(hull);
  const n = 32;
  final grown = <math.Point<double>>[
    for (final q in hull)
      for (var k = 0; k < n; k++)
        math.Point(q.x + d * math.cos(2 * math.pi * k / n),
            q.y + d * math.sin(2 * math.pi * k / n)),
  ];
  return _thin(aiConvexHull(grown));
}

List<math.Point<double>> _thin(List<math.Point<double>> ring) {
  var out = [...ring];
  for (var pass = 0; pass < 4 && out.length > 8; pass++) {
    final kept = <math.Point<double>>[];
    for (var i = 0; i < out.length; i++) {
      final a = kept.isEmpty ? out.last : kept.last;
      final b = out[i], c = out[(i + 1) % out.length];
      final len = a.distanceTo(c);
      final dev = len < 1e-12
          ? 0.0
          : ((c.x - a.x) * (a.y - b.y) - (a.x - b.x) * (c.y - a.y)).abs() / len;
      if (dev >= 0.02 || b.distanceTo(a) > 3) kept.add(b);
    }
    if (kept.length == out.length || kept.length < 3) break;
    out = kept;
  }
  return out;
}
