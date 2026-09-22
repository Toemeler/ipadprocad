part of 'ai_cad.dart';

/// PROFILES THAT CLOSE BECAUSE OF HOW THEY ARE WRITTEN.
///
/// ISSUE #83 — the session's first block drew a C-clip as two arcs and two
/// lines, each end typed separately, and missed closing by 0.000127 mm. #82
/// lost a whole block the same way at 0.0008 mm. Widening the weld tolerance
/// papered over two specific roundings; it cannot make a profile of
/// independently-typed ends correct, because the model is still guessing
/// where each end of the last curve landed.
///
/// A path has one start and a list of segments, and EACH SEGMENT BEGINS WHERE
/// THE ACTUAL GEOMETRY OF THE PREVIOUS ONE ENDED — the app's endpoint, not the
/// model's number for it. The closing segment ends at the start point itself.
/// There is no pair of coordinates that has to agree, so there is nothing to
/// round and nothing to weld.
///
///   {"op": "sketch_path", "start": [0, 0], "segments": [
///      {"to": [40, 0]},                          line to a point
///      {"by": [0, 20], "round": 3},              line by an offset, corner
///                                                  after it rounded R3
///      {"to": [0, 20], "centre": [20, 20]},      arc about a centre
///      {"to": [x, y], "through": [x, y]},        arc through a point
///      {"to": [x, y], "radius": 8, "cw": true},  arc of a radius
///      {"to": [x, y], "tangent": true}           arc tangent to the last one
///   ]}
///
/// A path is closed unless `"closed": false`; `corner_radius` rounds every
/// corner between two straight segments.

/// One segment while the path is being built. Lines keep their ends; arcs
/// keep their centre and turning direction, and their ends are always
/// DERIVED from the centre, radius and angle — the same arithmetic the
/// profile finder uses to read them back.
class _Seg {
  _Seg.line(this.a, this.b)
      : arc = false,
        c = Offset.zero,
        r = 0,
        cw = false;
  _Seg.arc(this.a, this.b, this.c, this.r, this.cw) : arc = true;
  final bool arc;
  Offset a, b;
  final Offset c;
  final double r;
  final bool cw;
  double round = 0;

  /// Unit direction of travel at the end of the segment.
  Offset get endDir {
    if (!arc) return _unit(b - a);
    final rad = b - c;
    // Tangent of a circle, turned the way the arc travels.
    return _unit(cw ? Offset(rad.dy, -rad.dx) : Offset(-rad.dy, rad.dx));
  }
}

Offset _unit(Offset v) {
  final d = v.distance;
  return d < 1e-12 ? Offset.zero : v / d;
}

double _cross(Offset u, Offset v) => u.dx * v.dy - u.dy * v.dx;

/// A point on the circle about [c] of radius [r] at angle [t], by the same
/// formula the profile finder evaluates, so an arc's end and the next line's
/// start are the same double.
Offset _onCircle(Offset c, double r, double t) =>
    Offset(c.dx + r * math.cos(t), c.dy + r * math.sin(t));

/// Why a path cannot be built, or its geometry and a summary.
(List<Geo>?, Map<String, dynamic>?, String?) buildSketchPath(
    AiAction a, String layer) {
  final start = a.point('start');
  if (start == null) {
    return (null, null, 'start must be a point [x, y]');
  }
  final raw = a.args['segments'];
  if (raw is! List || raw.isEmpty) {
    return (null, null, 'segments must be a non-empty list');
  }
  if (raw.length > 200) return (null, null, 'at most 200 segments');
  final closed = a.flag('closed', fallback: true);
  final segs = <_Seg>[];
  final origin = Offset(start[0], start[1]);
  var at = origin;
  for (var i = 0; i < raw.length; i++) {
    final s = raw[i];
    final n = i + 1;
    if (s is! Map) return (null, null, 'segment $n must be an object');
    double? numOf(String k) {
      final v = s[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    final byPt = aiPoint(s['by']);
    final toPt = aiPoint(s['to']);
    final Offset end;
    if (byPt != null) {
      end = at + Offset(byPt[0], byPt[1]);
    } else if (toPt != null) {
      end = Offset(toPt[0], toPt[1]);
    } else {
      return (null, null, 'segment $n needs "to": [x, y] or "by": [dx, dy]');
    }
    if ((end - at).distance < 1e-9) {
      return (null, null, 'segment $n ends where it starts');
    }
    final centre = aiPoint(s['centre'] ?? s['center']);
    final through = aiPoint(s['through']);
    final radius = numOf('radius');
    final cw = s['cw'] == true;
    _Seg seg;
    if (centre != null) {
      final c = Offset(centre[0], centre[1]);
      final r = (at - c).distance;
      final rEnd = (end - c).distance;
      if (r < 1e-9) return (null, null, 'segment $n: the centre is the start');
      // The end the model typed may be rounded; the arc ends where the angle
      // it names meets THIS circle, and the next segment starts there. A
      // miss bigger than a rounding is a wrong centre, and is said so.
      if ((rEnd - r).abs() > math.max(0.01, r * 1e-3)) {
        return (
          null,
          null,
          'segment $n: the end (${_r(end.dx)}, ${_r(end.dy)}) is '
              '${_r(rEnd)} from the centre but the start is ${_r(r)} from it '
              '— both ends of an arc lie on one circle'
        );
      }
      final t1 = math.atan2(end.dy - c.dy, end.dx - c.dx);
      seg = _Seg.arc(at, _onCircle(c, r, t1), c, r, cw);
    } else if (through != null) {
      final arc =
          arcThrough(at, Offset(through[0], through[1]), end);
      if (arc == null) {
        return (null, null, 'segment $n: the three points are in a line');
      }
      final c = Offset(arc.data[0], arc.data[1]);
      seg = _Seg.arc(at, _onCircle(c, arc.data[2], arc.data[4]), c,
          arc.data[2], arc.data[5] > 0.5);
    } else if (radius != null) {
      final chord = end - at;
      final half = chord.distance / 2;
      if (radius < half - 1e-9) {
        return (
          null,
          null,
          'segment $n: radius ${_r(radius)} is smaller than half the '
              'distance to the end (${_r(half)})'
        );
      }
      final h = math.sqrt(math.max(0, radius * radius - half * half));
      final mid = at + chord / 2;
      final left = Offset(-chord.dy, chord.dx) / chord.distance;
      // Travelling anticlockwise, the centre is on your left; the long way
      // round puts it on the other side of the chord.
      final large = s['large'] == true;
      final onLeft = cw == large;
      final c = mid + left * (onLeft ? h : -h);
      final t1 = math.atan2(end.dy - c.dy, end.dx - c.dx);
      seg = _Seg.arc(at, _onCircle(c, radius, t1), c, radius, cw);
    } else if (s['tangent'] == true) {
      if (segs.isEmpty) {
        return (null, null, 'segment $n: a tangent arc needs a segment before it');
      }
      final t = segs.last.endDir;
      final left = Offset(-t.dy, t.dx);
      final d = end - at;
      final side = d.dx * left.dx + d.dy * left.dy;
      if (side.abs() < 1e-9) {
        return (
          null,
          null,
          'segment $n: the end is straight ahead — use a line ("to") instead'
        );
      }
      // The centre is on the normal at the start, equidistant from both ends.
      final k = (d.dx * d.dx + d.dy * d.dy) / (2 * side);
      final c = at + left * k;
      final r = k.abs();
      final t1 = math.atan2(end.dy - c.dy, end.dx - c.dx);
      seg = _Seg.arc(at, _onCircle(c, r, t1), c, r, k < 0);
    } else {
      seg = _Seg.line(at, end);
    }
    final rr = numOf('round');
    if (rr != null) {
      if (rr < 0) return (null, null, 'segment $n: round must be >= 0');
      seg.round = rr;
    }
    segs.add(seg);
    at = seg.b;
  }
  // Closing: back to the start exactly.
  if (closed) {
    final gap = (at - origin).distance;
    if (gap > 1e-6) {
      segs.add(_Seg.line(at, origin));
    } else {
      // Already home. A line snaps its end onto the start; an arc's end is
      // derived and is within a micron, which the profile finder welds.
      final last = segs.last;
      if (!last.arc) last.b = origin;
    }
    if (segs.length < 2 || (segs.length == 2 && !segs.any((s) => s.arc))) {
      return (null, null, 'a closed path needs at least three sides, or an arc');
    }
  }
  // Corner rounding between two straight segments.
  final corner = a.number('corner_radius') ?? 0;
  final startRound = a.number('start_round') ?? 0;
  final out = <_Seg>[];
  final rounded = <int>[];
  // Corner i sits between segs[i] and segs[i+1] (and, closed, last→first).
  final radii = [
    for (var i = 0; i < segs.length; i++)
      segs[i].round > 0 ? segs[i].round : corner
  ];
  if (closed && startRound > 0) radii[segs.length - 1] = startRound;
  final fillets = List<_Seg?>.filled(segs.length, null);
  for (var i = 0; i < segs.length; i++) {
    final r = radii[i];
    if (r <= 0) continue;
    final j = i + 1 < segs.length ? i + 1 : (closed ? 0 : -1);
    if (j < 0) continue;
    final s1 = segs[i], s2 = segs[j];
    if (s1.arc || s2.arc) {
      if (segs[i].round > 0) {
        return (
          null,
          null,
          'segment ${i + 1}: "round" works between two straight segments — '
              'this corner has an arc on one side'
        );
      }
      continue;
    }
    final v = s1.b;
    final u = _unit(s1.a - v), w = _unit(s2.b - v);
    final cosT = (u.dx * w.dx + u.dy * w.dy).clamp(-1.0, 1.0);
    final theta = math.acos(cosT);
    if (theta > math.pi - 1e-6) continue; // straight on: no corner
    if (theta < 1e-6) {
      return (null, null, 'segment ${i + 1}: the path doubles back on itself');
    }
    final t = r / math.tan(theta / 2);
    if (t > (s1.b - s1.a).distance - 1e-9 ||
        t > (s2.b - s2.a).distance - 1e-9) {
      return (
        null,
        null,
        'the R${_r(r)} corner at (${_r(v.dx)}, ${_r(v.dy)}) does not fit: it '
            'needs ${_r(t)} mm of straight on each side'
      );
    }
    final t1 = v + u * t, t2 = v + w * t;
    final c = v + _unit(u + w) * (r / math.sin(theta / 2));
    // Turning left (anticlockwise) when the second leg is to the left of
    // the direction of travel along the first.
    final ccw = _cross(-u, w) > 0;
    final a1 = math.atan2(t1.dy - c.dy, t1.dx - c.dx);
    final a2 = math.atan2(t2.dy - c.dy, t2.dx - c.dx);
    final arcStart = _onCircle(c, r, a1), arcEnd = _onCircle(c, r, a2);
    s1.b = arcStart;
    s2.a = arcEnd;
    fillets[i] = _Seg.arc(arcStart, arcEnd, c, r, !ccw);
    rounded.add(i);
  }
  for (var i = 0; i < segs.length; i++) {
    out.add(segs[i]);
    if (fillets[i] != null) out.add(fillets[i]!);
  }
  // The rounding moved line ends onto the fillet arcs; if trimming made two
  // corners of one line meet, that line is gone and so is the path.
  for (final s in out) {
    if (!s.arc && (s.b - s.a).distance < 1e-9) {
      return (null, null, 'two corner radii use up a whole side between them');
    }
  }
  final geos = <Geo>[
    for (final s in out)
      if (s.arc)
        Geo(
            Geo.arc,
            [
              s.c.dx,
              s.c.dy,
              s.r,
              math.atan2(s.a.dy - s.c.dy, s.a.dx - s.c.dx),
              math.atan2(s.b.dy - s.c.dy, s.b.dx - s.c.dx),
              s.cw ? 1.0 : 0.0
            ],
            layer: layer)
      else
        Geo(Geo.line, [s.a.dx, s.a.dy, s.b.dx, s.b.dy], layer: layer)
  ];
  return (
    geos,
    {
      'shape': closed ? 'closed path' : 'open path',
      'segments': out.length,
      'arcs': out.where((s) => s.arc).length,
      if (rounded.isNotEmpty) 'roundedCorners': rounded.length,
      'end': [_r(out.last.b.dx), _r(out.last.b.dy)],
    },
    null
  );
}

/// A ring, or a C with an opening — the shape of a clip, a cable holder, a
/// collar — as ONE closed profile.
///
///   {"op": "sketch_ring", "x": 0, "y": 0, "outer": 12, "inner": 7,
///    "opening": 5, "opening_deg": 270}
///
/// `outer` and `inner` are DIAMETERS. `opening` is the width of the mouth,
/// measured straight across at the inner edge — the size a cable has to pass
/// — and `opening_deg` is the direction it faces. Without an opening this is
/// two circles: extrude it and the default region rule leaves the middle
/// open, which is what a ring is.
(List<Geo>?, Map<String, dynamic>?, String?) buildSketchRing(
    AiAction a, String layer) {
  final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
  final od = a.number('outer') ??
      (a.number('outer_radius') == null ? null : a.number('outer_radius')! * 2);
  final id = a.number('inner') ??
      (a.number('inner_radius') == null ? null : a.number('inner_radius')! * 2);
  if (od == null || id == null || od <= 0 || id <= 0) {
    return (null, null, 'outer and inner diameters must be > 0');
  }
  if (id >= od) {
    return (null, null, 'inner (${_r(id)}) must be smaller than outer (${_r(od)})');
  }
  final ro = od / 2, ri = id / 2;
  final c = Offset(x, y);
  final gap = a.number('opening');
  if (gap == null || gap <= 0) {
    return (
      [
        Geo(Geo.circle, [x, y, ro], layer: layer),
        Geo(Geo.circle, [x, y, ri], layer: layer),
      ],
      {
        'shape': 'ring',
        'centre': [_r(x), _r(y)],
        'outer': _r(od),
        'inner': _r(id),
        'wall': _r(ro - ri),
      },
      null
    );
  }
  if (gap >= id) {
    return (
      null,
      null,
      'an opening of ${_r(gap)} is as wide as the inner diameter '
          '(${_r(id)}) — nothing would be held. Make it narrower than the '
          'bore; a snap-in mouth is typically 70-90% of it'
    );
  }
  final facing = (a.number('opening_deg') ?? 0) * math.pi / 180;
  // The mouth has parallel sides, `gap` apart, so its width is the same at
  // the inner and the outer edge — a cable meets the narrowest point first.
  final hi = math.asin((gap / 2) / ri), ho = math.asin((gap / 2) / ro);
  final oStart = facing + ho, oEnd = facing - ho; // outer, anticlockwise
  final iStart = facing - hi, iEnd = facing + hi; // inner, clockwise
  final po1 = _onCircle(c, ro, oStart), po2 = _onCircle(c, ro, oEnd);
  final pi1 = _onCircle(c, ri, iStart), pi2 = _onCircle(c, ri, iEnd);
  return (
    [
      Geo(Geo.arc, [x, y, ro, oStart, oEnd, 0.0], layer: layer),
      Geo(Geo.line, [po2.dx, po2.dy, pi1.dx, pi1.dy], layer: layer),
      Geo(Geo.arc, [x, y, ri, iStart, iEnd, 1.0], layer: layer),
      Geo(Geo.line, [pi2.dx, pi2.dy, po1.dx, po1.dy], layer: layer),
    ],
    {
      'shape': 'C ring',
      'centre': [_r(x), _r(y)],
      'outer': _r(od),
      'inner': _r(id),
      'wall': _r(ro - ri),
      'opening': _r(gap),
      'openingFacesDeg': _r(facing * 180 / math.pi),
    },
    null
  );
}
