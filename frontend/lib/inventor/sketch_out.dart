// An Inventor sketch -> the app's sketch files (DXF + JSON sidecars).
// Port of tools/ipt/ptp_sketch.py and check_sketch.py.
//
// The app keeps a sketch as a DXF (lines, arcs, circles; a sketch POINT is a
// circle tagged in .splines.json) plus sidecars; constraints address entities
// by their DXF index and points as (entity, point) with the grip numbering of
// constraints.dart: line 0/1 = ends, arc 0 = centre, 1 = start, 2 = end,
// circle 0 = centre.
//
// Inventor keeps points as objects that lines and arcs share. Each Inventor
// point becomes one or more entity points tied by coincident constraints; a
// point that is nobody's end or centre becomes a sketch point.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'acis.dart';
import 'dc.dart';
import 'dxf_template.dart';

// constraints.dart CType indices (the sidecar stores the enum index)
const Map<String, int> kCT = {
  'coincident': 0, 'collinear': 1, 'concentric': 2, 'fix': 3, 'parallel': 4,
  'perpendicular': 5, 'horizontal': 6, 'vertical': 7, 'tangent': 8, 'smooth': 9,
  'symmetric': 10, 'equal': 11, 'dimension': 12, 'midpoint': 13, 'pattern': 14,
};
const int kLine = 1, kCircle = 2, kArc = 3;
const int _pointTag = 5; // Geo.pointTag
const double _pointR = 0.35; // kSketchPointRadius
const int _styleConstruction = 2;
const int _projCenter = -1; // kProjCenter
const String kSketchLayer = 'Layer 1';

/// The app's frames of the origin planes (part_model.dart planeFrame).
const Map<String, (V3, V3, V3)> kAppPlanes = {
  'xy': (V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1)),
  'xz': (V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0)),
  'yz': (V3(0, 0, -1), V3(0, 1, 0), V3(1, 0, 0)),
};

class SketchConvertException implements Exception {
  final String message;
  SketchConvertException(this.message);
  @override
  String toString() => message;
}

class AppGeo {
  final int type;
  final List<double> data;
  final int style;
  final int? tag;
  AppGeo(this.type, this.data, this.style, [this.tag]);
}

class AppSketch {
  final String name;
  final geos = <AppGeo>[];
  final cons = <Map<String, Object?>>[];
  String plane = 'face';
  (V3, V3, V3, V3)? frame; // (u, v, n, origin) world mm, for plane == 'face'
  AppSketch(this.name);
}

bool _close(V3 a, V3 b) => (a - b).x.abs() < 1e-9 && (a - b).y.abs() < 1e-9 && (a - b).z.abs() < 1e-9;

AppSketch convertSketch(InvSketch sk) {
  final fr = sk.frame;
  if (fr == null) throw SketchConvertException('${sk.name}: no placement');
  final a = AppSketch(sk.name);
  (double, double) Function((double, double)) to2d = (p) => p;
  var placed = false;
  for (final e in kAppPlanes.entries) {
    final (u, v, nn) = e.value;
    if (_close(fr.n, nn) && fr.origin.dot(fr.n).abs() < 1e-9) {
      a.plane = e.key;
      to2d = (p) {
        final w = fr.origin + fr.x * p.$1 + fr.y * p.$2;
        return (w.dot(u), w.dot(v));
      };
      placed = true;
      break;
    }
  }
  if (!placed) {
    // a face/work-plane sketch keeps Inventor's own frame
    a.plane = 'face';
    a.frame = (fr.x, fr.y, fr.n, fr.origin);
  }
  final pts = {for (final e in sk.points.entries) e.key: to2d((e.value.x, e.value.y))};

  // ---- entities: curves first (Inventor order), then lone points
  final occ = {for (final e in sk.points.keys) e: <(int, int)>[]};
  final index = <int, int>{};
  final projected = <int>[];
  final curveIds = sk.curves.keys.toList()..sort();
  for (final e in curveIds) {
    final c = sk.curves[e]!;
    final i = a.geos.length;
    index[e] = i;
    final style = (c.construction || c.projected) ? _styleConstruction : 0;
    if (c.kind == 'line') {
      final p0 = pts[c.ends[0]]!, p1 = pts[c.ends[1]]!;
      a.geos.add(AppGeo(kLine, [p0.$1, p0.$2, p1.$1, p1.$2], style));
      occ[c.ends[0]]!.add((i, 0));
      occ[c.ends[1]]!.add((i, 1));
    } else {
      final ctr = pts[c.centre]!;
      final s = pts[c.ends[0]]!, t = pts[c.ends[1]]!;
      var a0 = math.atan2(s.$2 - ctr.$2, s.$1 - ctr.$1);
      var a1 = math.atan2(t.$2 - ctr.$2, t.$1 - ctr.$1);
      final sweep = (a1 - a0) % (2 * math.pi);
      if (sweep > math.pi + 1e-9) {
        // the minor arc, running s -> t or t -> s
        final tmp = a0;
        a0 = a1;
        a1 = tmp;
        occ[c.ends[1]]!.add((i, 1));
        occ[c.ends[0]]!.add((i, 2));
      } else {
        occ[c.ends[0]]!.add((i, 1));
        occ[c.ends[1]]!.add((i, 2));
      }
      occ[c.centre]!.add((i, 0));
      a.geos.add(AppGeo(kArc, [ctr.$1, ctr.$2, c.radius, a0, a1], style));
    }
    if (c.projected) projected.add(i);
  }
  final pointIds = sk.points.keys.toList()..sort();
  for (final e in pointIds) {
    if (occ[e]!.isNotEmpty) continue;
    final p = sk.points[e]!;
    final q = pts[e]!;
    if (p.projected && q.$1.abs() < 1e-9 && q.$2.abs() < 1e-9) {
      occ[e]!.add((_projCenter, 0)); // Inventor's projected centre point
      continue;
    }
    final i = a.geos.length;
    a.geos.add(AppGeo(kCircle, [q.$1, q.$2, _pointR], 0, _pointTag));
    occ[e]!.add((i, 0));
    if (p.projected) projected.add(i);
  }

  Map<String, int> pref(int e) {
    final l = occ[e];
    if (l == null || l.isEmpty) throw SketchConvertException('${sk.name}: a point no entity uses');
    return {'e': l[0].$1, 'p': l[0].$2};
  }

  int idx(int? e) {
    final i = index[e];
    if (i == null) throw SketchConvertException('${sk.name}: a constraint on a missing entity');
    return i;
  }

  void add(String t, {List<Object> pts = const [], List<int> ents = const [], Map<String, Object?>? kw}) {
    a.cons.add({'t': kCT[t], 'p': pts, 'e': ents, ...?kw});
  }

  // ---- connectivity: one Inventor point shared by several entities
  occ.forEach((e, lst) {
    for (final (ent, pt) in lst.skip(1)) {
      add('coincident', pts: [
        {'e': lst[0].$1, 'p': lst[0].$2},
        {'e': ent, 'p': pt}
      ]);
    }
  });

  // ---- projected geometry is reference geometry: pinned where it is
  for (final i in projected) {
    final g = a.geos[i];
    final k = g.type == kArc ? 5 : (g.type == kLine ? 4 : 3);
    add('fix', ents: [i], kw: {'an': g.data.sublist(0, k)});
  }

  // ---- geometric constraints
  final offsets = <(int, int)>[];
  for (final c in sk.constraints) {
    switch (c.type) {
      case 'endpoint':
      case 'centre':
        continue; // carried by the shared points
      case 'on_curve':
        add('coincident', pts: [pref(c.point!)], ents: [idx(c.curve)]);
      case 'midpoint':
        add('midpoint', pts: [pref(c.point!)], ents: [idx(c.line)]);
      case 'horizontal':
      case 'vertical':
        final g = a.geos[idx(c.line)].data;
        final dx = g[2] - g[0], dy = g[3] - g[1];
        add(dy.abs() < dx.abs() ? 'horizontal' : 'vertical', ents: [idx(c.line)]);
      case 'parallel':
      case 'perpendicular':
      case 'collinear':
        add(c.type, ents: [idx(c.lines[0]), idx(c.lines[1])]);
      case 'offset':
        offsets.addAll(c.pairs);
      default:
        throw SketchConvertException('${sk.name}: constraint ${c.type} has no mapping yet');
    }
  }

  // Inventor's OFFSET has no single counterpart. The offset loop is pinned by
  // arcs concentric with their source (shared centre, above), all offset arcs
  // equal, lines tangent to the arcs they meet, and the offset distance as a
  // dimension (Inventor's own, below).
  final offArcs = {
    for (final (_, o) in offsets)
      if (sk.curves[o]?.kind == 'arc') idx(o)
  }.toList()
    ..sort();
  for (final i in offArcs.skip(1)) {
    add('equal', ents: [offArcs[0], i]);
  }
  for (final (_, o) in offsets) {
    final oc = sk.curves[o];
    if (oc == null || oc.kind != 'line') continue;
    final li = idx(o);
    for (final end in oc.ends) {
      for (final (ent, _) in occ[end]!) {
        if (offArcs.contains(ent)) add('tangent', ents: [li, ent]);
      }
    }
  }

  // ---- dimensions
  for (final d in sk.dimensions) {
    final kw = <String, Object?>{'v': d.value, 'nm': d.param};
    if (d.driven) kw['dr'] = true;
    final refs = d.refs;
    switch (d.kind) {
      case 'point_point':
        add('dimension', pts: [pref(refs[0]), pref(refs[1])], kw: {'k': 'dist', ...kw});
      case 'point_line':
        final pt = refs.firstWhere(sk.points.containsKey);
        final ln = refs.firstWhere(sk.curves.containsKey);
        final ends = sk.curves[ln]!.ends;
        add('dimension', pts: [pref(pt), pref(ends[0]), pref(ends[1])], kw: {'k': 'pline', ...kw});
      case 'line_line':
        final la = sk.curves[refs[0]]!, lb = sk.curves[refs[1]]!;
        add('dimension',
            pts: [pref(la.ends[0]), pref(lb.ends[0]), pref(lb.ends[1])], kw: {'k': 'pline', ...kw});
      case 'angle':
        // 'ang4' takes the two directions as point pairs: order each pair so
        // the directed angle between them IS Inventor's value
        final ea = sk.curves[refs[0]]!.ends;
        var eb = sk.curves[refs[1]]!.ends;
        double ang(List<int> ea, List<int> eb) {
          final a0 = pts[ea[0]]!, a1 = pts[ea[1]]!, b0 = pts[eb[0]]!, b1 = pts[eb[1]]!;
          final da = (a1.$1 - a0.$1, a1.$2 - a0.$2), db = (b1.$1 - b0.$1, b1.$2 - b0.$2);
          return (math.atan2(da.$1 * db.$2 - da.$2 * db.$1, da.$1 * db.$1 + da.$2 * db.$2) * 180 / math.pi)
              .abs();
        }

        if ((ang(ea, eb) - d.value).abs() > 1e-6) eb = eb.reversed.toList();
        if ((ang(ea, eb) - d.value).abs() > 1e-6) {
          throw SketchConvertException('${sk.name}: angle ${d.param} does not match its lines');
        }
        add('dimension',
            pts: [pref(ea[0]), pref(ea[1]), pref(eb[0]), pref(eb[1])], kw: {'k': 'ang4', ...kw});
      case 'arc_arc':
        add('dimension', ents: [idx(refs[0]), idx(refs[1])], kw: {'k': 'gap', ...kw});
      case 'radius':
        add('dimension', ents: [idx(refs[0])], kw: {'k': 'rad', ...kw});
      default:
        throw SketchConvertException('${sk.name}: dimension ${d.param} has no mapping yet');
    }
  }
  return a;
}

// ---------------------------------------------------------------- check
(double, double) _point(List<AppGeo> geos, Map r) {
  final e = r['e'] as int, p = r['p'] as int;
  if (e == _projCenter) return (0, 0);
  final g = geos[e];
  final d = g.data;
  if (g.type == kLine) return p == 0 ? (d[0], d[1]) : (d[2], d[3]);
  if (g.type == kCircle || p == 0) return (d[0], d[1]);
  final an = p == 1 ? d[3] : d[4];
  return (d[0] + math.cos(an) * d[2], d[1] + math.sin(an) * d[2]);
}

double _dist((double, double) a, (double, double) b) =>
    math.sqrt((a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2));

/// Residuals of one converted constraint on the geometry as Inventor left
/// it, with the equations of solver.dart.
List<double> constraintResiduals(List<AppGeo> geos, Map<String, Object?> c) {
  final t = kCT.entries.firstWhere((e) => e.value == c['t']).key;
  final p = [for (final r in c['p'] as List) _point(geos, r as Map)];
  final e = (c['e'] as List).cast<int>();
  ((double, double), (double, double)) line(int i) {
    final d = geos[i].data;
    return ((d[0], d[1]), (d[2], d[3]));
  }

  double crossDir(((double, double), (double, double)) l1, ((double, double), (double, double)) l2,
      {bool dot = false}) {
    final d1 = (l1.$2.$1 - l1.$1.$1, l1.$2.$2 - l1.$1.$2);
    final d2 = (l2.$2.$1 - l2.$1.$1, l2.$2.$2 - l2.$1.$2);
    final s = math.sqrt(d1.$1 * d1.$1 + d1.$2 * d1.$2) * math.sqrt(d2.$1 * d2.$1 + d2.$2 * d2.$2);
    return dot ? (d1.$1 * d2.$1 + d1.$2 * d2.$2) / s : (d1.$1 * d2.$2 - d1.$2 * d2.$1) / s;
  }

  double ptLine((double, double) q, ((double, double), (double, double)) l) {
    final dx = l.$2.$1 - l.$1.$1, dy = l.$2.$2 - l.$1.$2;
    final len = math.sqrt(dx * dx + dy * dy);
    return ((q.$1 - l.$1.$1) * -dy + (q.$2 - l.$1.$2) * dx) / len;
  }

  switch (t) {
    case 'coincident':
      if (p.length >= 2) return [p[0].$1 - p[1].$1, p[0].$2 - p[1].$2];
      final g = geos[e[0]];
      if (g.type == kArc || g.type == kCircle) {
        return [_dist(p[0], (g.data[0], g.data[1])) - g.data[2]];
      }
      return [ptLine(p[0], line(e[0]))];
    case 'fix':
      return [0];
    case 'horizontal':
      final l = line(e[0]);
      return [l.$2.$2 - l.$1.$2];
    case 'vertical':
      final l = line(e[0]);
      return [l.$2.$1 - l.$1.$1];
    case 'parallel':
      return [crossDir(line(e[0]), line(e[1]))];
    case 'perpendicular':
      return [crossDir(line(e[0]), line(e[1]), dot: true)];
    case 'collinear':
      final l1 = line(e[0]), l2 = line(e[1]);
      return [ptLine(l2.$1, l1), ptLine(l2.$2, l1)];
    case 'midpoint':
      final l = line(e[0]);
      return [(l.$1.$1 + l.$2.$1) / 2 - p[0].$1, (l.$1.$2 + l.$2.$2) / 2 - p[0].$2];
    case 'equal':
      final g1 = geos[e[0]], g2 = geos[e[1]];
      if (g1.type == kLine) {
        final a = line(e[0]), b = line(e[1]);
        return [_dist(a.$1, a.$2) - _dist(b.$1, b.$2)];
      }
      return [g1.data[2] - g2.data[2]];
    case 'tangent':
      final d = geos[e[1]].data;
      return [ptLine((d[0], d[1]), line(e[0])).abs() - d[2]];
    case 'dimension':
      final v = (c['v'] as num).toDouble();
      switch (c['k']) {
        case 'dist':
          return [_dist(p[0], p[1]) - v];
        case 'pline':
          return [ptLine(p[0], (p[1], p[2])).abs() - v];
        case 'ang4':
          final da = (p[1].$1 - p[0].$1, p[1].$2 - p[0].$2);
          final db = (p[3].$1 - p[2].$1, p[3].$2 - p[2].$2);
          final an = (math.atan2(da.$1 * db.$2 - da.$2 * db.$1, da.$1 * db.$1 + da.$2 * db.$2) * 180 / math.pi)
              .abs();
          return [an - v];
        case 'gap':
          return [(geos[e[1]].data[2] - geos[e[0]].data[2]).abs() - v];
        case 'rad':
          return [geos[e[0]].data[2] - v];
      }
  }
  throw SketchConvertException('no residual for $t');
}

/// (worst residual, constraints above [tol]).
(double, List<Map<String, Object?>>) checkSketch(AppSketch a, {double tol = 1e-6}) {
  var worst = 0.0;
  final bad = <Map<String, Object?>>[];
  for (final c in a.cons) {
    final r = constraintResiduals(a.geos, c).fold<double>(0, (m, x) => math.max(m, x.abs()));
    if (r > worst) worst = r;
    if (r > tol || r.isNaN) bad.add(c);
  }
  return (worst, bad);
}

// ---------------------------------------------------------------- files
/// A DXF real exactly as the app's own writer prints it (dxflib's
/// DL_WriterA::dxfReal: "%.16f", trailing zeros cut, one decimal kept), so a
/// converted sketch reads back the same numbers after the app re-saves it.
String _num(double v) {
  if (!v.isFinite) return '0.0';
  var s = v.toStringAsFixed(16);
  final dot = s.indexOf('.');
  var end = dot + 2;
  for (var i = dot + 1; i < s.length; i++) {
    if (s[i] != '0') end = i + 1;
  }
  return end < s.length ? s.substring(0, end) : s;
}

String _dxfEntities(List<AppGeo> geos) {
  final out = StringBuffer();
  var h = 0x100;
  for (final g in geos) {
    h++;
    final d = g.data;
    final kind = g.type == kLine ? 'LINE' : (g.type == kArc ? 'ARC' : 'CIRCLE');
    out.write('  0\n$kind\n  5\n${h.toRadixString(16).toUpperCase()}\n100\nAcDbEntity\n  8\n$kSketchLayer\n'
        ' 62\n256\n370\n-1\n 48\n1.0\n  6\nBYLAYER\n');
    if (g.type == kLine) {
      out.write('100\nAcDbLine\n 10\n${_num(d[0])}\n 20\n${_num(d[1])}\n 30\n0.0\n'
          ' 11\n${_num(d[2])}\n 21\n${_num(d[3])}\n 31\n0.0\n');
    } else {
      out.write('100\nAcDbCircle\n 10\n${_num(d[0])}\n 20\n${_num(d[1])}\n 30\n0.0\n 40\n${_num(d[2])}\n');
      if (g.type == kArc) {
        out.write('100\nAcDbArc\n 50\n${_num(d[3] * 180 / math.pi)}\n 51\n${_num(d[4] * 180 / math.pi)}\n');
      }
    }
  }
  return out.toString();
}

/// An app-style DXF: the template's header/tables/objects, our entities.
String sketchDxf(List<AppGeo> geos) {
  const t = kSketchDxfTemplate;
  final i = t.indexOf('ENTITIES');
  final j = t.indexOf('  0\nENDSEC', i);
  final start = t.indexOf('\n', i) + 1;
  return t.substring(0, start) + _dxfEntities(geos) + t.substring(j);
}

/// {entry name: bytes} for the sketch, under sketches/.
Map<String, Uint8List> sketchFiles(AppSketch a) {
  final base = 'sketches/${a.name}';
  Uint8List enc(Object o) => utf8.encode(jsonEncode(o));
  return {
    '$base.dxf': utf8.encode(sketchDxf(a.geos)),
    '$base.cons.json': enc(a.cons),
    '$base.params.json': enc([]),
    '$base.texts.json': enc([]),
    '$base.images.json': enc([]),
    '$base.splines.json': enc({
      for (var i = 0; i < a.geos.length; i++)
        if (a.geos[i].tag != null) '$i': a.geos[i].tag
    }),
    '$base.styles.json': enc({
      for (var i = 0; i < a.geos.length; i++)
        if (a.geos[i].style != 0) '$i': a.geos[i].style
    }),
    '$base.proj.json': enc({}),
    '$base.gears.json': enc({}),
    '$base.layers.json': enc({
      'version': 3, 'layers': [kSketchLayer], 'hidden': [], 'locked': [], 'eos': 1,
    }),
  };
}
