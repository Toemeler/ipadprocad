part of 'ai_cad.dart';

// A HANDLE THAT MEETS THE WALL.
//
// #94 "the floating bar": a handle placed where the wall would have been,
// on a cup whose taper went the other way, touching it only at its foot. The
// lab's runs repeated it — ends that stopped short of a tapered wall, ends
// that went through it into the cup, a finger gap of 3 mm. A person places a
// handle by picking two points ON the wall. `handle` does that: it measures
// the wall's outside and inside at the two heights, along the side named,
// and ends the handle in the middle of the wall at both, whatever the taper,
// then builds it from ordinary features (a sweep, or an extruded outline).

extension AiCadHandle on AiCad {
  /// `handle {body?, side?: "+x"|"-x"|"+z"|"-z", from_y, to_y, reach?,
  /// style?: "round"|"angular", size?, width?, thickness?, corner?, id?}`.
  Future<AiActionOutcome> _handle(PartModel p, AiAction a) async {
    final body = a.text('body') ??
        [
          for (final g in p.features.reversed)
            if (!g.rolledBack && g.solid != null) g.bodyName
        ].firstOrNull;
    if (body == null) {
      return AiActionOutcome.failed(a.op, 'build the body first');
    }
    final solid = currentBodySolid(p, body);
    if (solid == null) return AiActionOutcome.failed(a.op, 'no solid "$body"');
    final side = (a.text('side') ?? '+x').toLowerCase();
    if (!const {'+x', '-x', '+z', '-z', 'x', 'z'}.contains(side)) {
      return AiActionOutcome.failed(a.op, 'side must be "+x", "-x", "+z" or "-z"');
    }
    final alongX = side.contains('x');
    final sgn = side.startsWith('-') ? -1.0 : 1.0;
    // The axis: the body's middle in X and Z (a cup is turned about it).
    final pos = solid.mesh.positions;
    var x0 = double.infinity, x1 = -double.infinity;
    var z0 = double.infinity, z1 = -double.infinity;
    var y0 = double.infinity, y1 = -double.infinity;
    for (var i = 0; i + 2 < pos.length; i += 3) {
      x0 = math.min(x0, pos[i]);
      x1 = math.max(x1, pos[i]);
      y0 = math.min(y0, pos[i + 1]);
      y1 = math.max(y1, pos[i + 1]);
      z0 = math.min(z0, pos[i + 2]);
      z1 = math.max(z1, pos[i + 2]);
    }
    final at = a.point('axis_at');
    final cx = at?[0] ?? (x0 + x1) / 2, cz = at?[1] ?? (z0 + z1) / 2;
    final h = y1 - y0;
    final fromY = a.number('from_y') ?? y0 + h * 0.2;
    final toY = a.number('to_y') ?? y0 + h * 0.8;
    if (!(fromY > y0 && toY < y1 && toY > fromY)) {
      return AiActionOutcome.failed(a.op,
          'from_y and to_y must lie inside the body (y ${_r(y0)}..${_r(y1)}) '
          'and from_y < to_y');
    }
    final style = (a.text('style') ?? 'round').toLowerCase();
    final size = a.number('size') ?? a.number('diameter') ?? 10.0;
    final width = a.number('width') ?? 8.0;
    final thick = a.number('thickness') ?? 12.0;
    final reach = a.number('reach') ?? 22.0;
    // The wall along the side, at a height: outside and inside radius.
    (double, double)? wallAt(double y) {
      final loops = aiSliceLoops(solid.mesh, 1, y + 1.3e-7);
      if (loops.isEmpty) return null;
      bool material(double t) {
        final px = alongX ? cx + sgn * t : cx;
        final pz = alongX ? cz : cz + sgn * t;
        var n = 0;
        for (final l in loops) {
          if (_AiCadHandleGeom.inLoop(l, px, pz)) n++;
        }
        return n.isOdd;
      }

      // Outermost material along the ray, then inward to where it ends.
      final far = math.max(x1 - x0, z1 - z0) + 1;
      double? rOut;
      for (var t = far; t > 0; t -= 0.05) {
        if (material(t)) {
          rOut = t;
          break;
        }
      }
      if (rOut == null) return null;
      var rIn = rOut;
      while (rIn > 0.05 && material(rIn - 0.05)) {
        rIn -= 0.05;
      }
      return (rOut, rIn);
    }

    final lo = wallAt(fromY), hi = wallAt(toY);
    if (lo == null || hi == null) {
      return AiActionOutcome.failed(a.op,
          'found no wall on the ${side.startsWith('-') ? side : '+${side.replaceAll('+', '')}'} '
          'side at y ${_r(fromY)} or ${_r(toY)}');
    }
    // Ends in the middle of the wall; a solid body (no inside) gets 60 %
    // of the handle's own size of engagement.
    final grip = style == 'angular' ? width : size;
    double end((double, double) w) {
      final t = w.$1 - w.$2;
      return t < w.$1 - 0.1 ? w.$1 - math.min(t / 2, grip * 0.6) : w.$1 - grip * 0.6;
    }

    final uLo = end(lo), uHi = end(hi);
    final uOut = math.max(lo.$1, hi.$1) + reach; // the inside of the grip
    // Sketch frame: a vertical plane through the axis along the side.
    // xy (z = cz): sketch x = world X. yz (x = cx): sketch x = world -Z.
    final plane = alongX ? 'xy' : 'yz';
    final offset = alongX ? cz : cx;
    List<double> sk(double u, double y) => alongX
        ? [cx + sgn * u, y]
        : [-(cz + sgn * u), y];
    final id = a.text('id') ?? 'handle';
    final skName = '${id}_path_${p.childSketches.length + 1}';
    final o1 = await _one(p,
        AiAction('create_sketch', {'plane': plane, 'offset': offset, 'id': skName}));
    if (!o1.ok) return AiActionOutcome.failed(a.op, 'create_sketch: ${o1.error}');
    AiActionOutcome built;
    if (style == 'angular') {
      final w2 = width / 2;
      final pts = [
        sk(uLo, fromY - w2),
        sk(uOut + width, fromY - w2),
        sk(uOut + width, toY + w2),
        sk(uHi, toY + w2),
        sk(uHi, toY - w2),
        sk(uOut, toY - w2),
        sk(uOut, fromY + w2),
        sk(uLo, fromY + w2),
      ];
      final d = await _one(p,
          AiAction('sketch_polygon', {'sketch': skName, 'points': pts}));
      if (!d.ok) return AiActionOutcome.failed(a.op, 'outline: ${d.error}');
      built = await _one(
          p,
          AiAction('extrude', {
            'sketch': skName,
            'distance': thick,
            'direction': 'symmetric',
            'operation': 'join',
            'body': body,
            'id': id,
          }));
    } else {
      final uMid = uOut + size / 2;
      final corner = a.number('corner') ??
          math.max(0.5, math.min(reach * 0.5, (toY - fromY) / 3));
      final d = await _one(
          p,
          AiAction('sketch_path', {
            'sketch': skName,
            'closed': false,
            'start': sk(uLo, fromY),
            'segments': [
              {'to': sk(uMid, fromY), 'round': corner},
              {'to': sk(uMid, toY), 'round': corner},
              {'to': sk(uHi, toY)},
            ],
          }));
      if (!d.ok) return AiActionOutcome.failed(a.op, 'path: ${d.error}');
      built = await _one(
          p,
          AiAction('sweep', {
            'path_sketch': skName,
            'profile_circle': size,
            'operation': 'join',
            'body': body,
            'id': id,
          }));
    }
    if (!built.ok) {
      return AiActionOutcome.failed(a.op, 'the handle: ${built.error}');
    }
    return AiActionOutcome(a.op, detail: {
      ...?built.detail,
      'style': style,
      'side': side,
      'endsAtY': [_r(fromY), _r(toY)],
      'wallOutsideR': [_r(lo.$1), _r(hi.$1)],
      'fingerGapMm': _r(reach),
      'reachesToR': _r(uOut + (style == 'angular' ? width : size)),
    });
  }
}

class _AiCadHandleGeom {
  static bool inLoop(List<(double, double)> l, double x, double y) {
    var inside = false;
    for (var i = 0, j = l.length - 1; i < l.length; j = i++) {
      final a = l[i], b = l[j];
      if ((a.$2 > y) != (b.$2 > y) &&
          x < (b.$1 - a.$1) * (y - a.$2) / (b.$2 - a.$2) + a.$1) {
        inside = !inside;
      }
    }
    return inside;
  }
}
