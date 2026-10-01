// The design data of an Inventor part (PmDCSegment): parameters, sketches
// (entities, constraints, dimensions, placement), the feature timeline and
// the extrusion profiles. Port of tools/ipt/{rse_segment,ipt_dc,ipt_model,
// ipt_features,ipt_profiles}.py -- the layouts are documented there.
//
// RSe objects carry no class tag; everything here is recognised from its
// structure (reference arrays, marker words), as established on Inventor
// 2026 files. Object indices are 0-based; a reference word is
// 0x80000000 | (index + 1). Lengths come out in mm, angles in rad.
import 'dart:math' as math;
import 'dart:typed_data';

import 'acis.dart';
import 'sab.dart';

const int _arr = 0x30000002; // "array of references" marker
const double _cm = 10.0; // Inventor's internal length unit is cm

class DcException implements Exception {
  final String message;
  DcException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- segment
class RseSegment {
  final Uint8List data;
  late final List<int> sizes, starts;
  late final int n;

  RseSegment(this.data, Uint8List meta) {
    final md = ByteData.sublistView(meta);
    if (meta.length < 18) throw DcException('segment meta too short');
    n = md.getUint32(14, Endian.little);
    if (18 + 4 * n > meta.length) throw DcException('segment meta truncated');
    sizes = [for (var i = 0; i < n; i++) md.getUint32(18 + 4 * i, Endian.little) & 0xffffff];
    starts = [];
    var p = 18;
    for (final s in sizes) {
      starts.add(p);
      p += s + 9;
    }
  }

  Uint8List obj(int i) {
    final s = starts[i];
    var e = i + 1 < n ? starts[i + 1] : data.length;
    if (e > data.length) e = data.length;
    if (s >= e) return Uint8List(0);
    return Uint8List.sublistView(data, s, e);
  }

  final Map<int, List<(int, int)>> _refCache = {};

  /// (offset, object index) of every reference in object i, any alignment.
  List<(int, int)> refs(int i) => _refCache.putIfAbsent(i, () {
        final b = obj(i);
        final out = <(int, int)>[];
        for (var o = 0; o + 4 <= b.length; o++) {
          if (b[o + 3] != 0x80) continue;
          final v = (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16));
          if (v > 0 && v <= n) out.add((o, v - 1));
        }
        return out;
      });

  List<int> refIdx(int i) => [for (final r in refs(i)) r.$2];

  /// (offset, text) of every u32-length-prefixed UTF-16 string in object i.
  List<(int, String)> strings(int i, [int minLen = 2]) {
    final b = obj(i);
    final out = <(int, String)>[];
    bool ok(int c) => (c >= 0x20 && c <= 0x7e) || c >= 0xa0;
    var p = 0;
    while (p + 1 < b.length) {
      var k = 0;
      while (p + 2 * k + 1 < b.length && ok(b[p + 2 * k]) && b[p + 2 * k + 1] == 0) {
        k++;
      }
      if (k >= minLen) {
        if (p >= 4) {
          final ln = _u32(b, p - 4)!;
          if (ln > 0 && ln <= k) {
            out.add((p - 4, String.fromCharCodes([for (var j = 0; j < ln; j++) b[p + 2 * j]])));
          }
        }
        p += 2 * k;
      } else {
        p++;
      }
    }
    return out;
  }
}

int? _u32(Uint8List b, int o) =>
    o >= 0 && o + 4 <= b.length ? ByteData.sublistView(b).getUint32(o, Endian.little) : null;

double? _f64(Uint8List b, int o) =>
    o >= 0 && o + 8 <= b.length ? ByteData.sublistView(b).getFloat64(o, Endian.little) : null;

int? _ref(Uint8List b, int o) {
  final v = _u32(b, o);
  if (v == null || v & 0x80000000 == 0) return null;
  return (v & 0x7fffffff) - 1;
}

V3? _v3(Uint8List b, int o, [double s = 1]) {
  final x = _f64(b, o), y = _f64(b, o + 8), z = _f64(b, o + 16);
  if (x == null || y == null || z == null) return null;
  return V3(x * s, y * s, z * s);
}

bool _printable(int c) => c >= 0x20 && !(c >= 0x7f && c < 0xa0) && !(c >= 0xd800 && c < 0xe000);

// ---------------------------------------------------------------- raw DC
class Param {
  final int obj;
  final double value; // internal units (cm / rad)
  final double? nominal;
  Param(this.obj, this.value, this.nominal);
}

class Frame {
  final V3 origin, x, y, n; // world mm
  const Frame(this.origin, this.x, this.y, this.n);
}

class RawConstraint {
  final int obj, system, size;
  final List<(int, int)> parts;
  RawConstraint(this.obj, this.system, this.size, this.parts);
}

class Dc {
  final RseSegment seg;
  Dc(Uint8List data, Uint8List meta) : seg = RseSegment(data, meta);
  int get n => seg.n;
  Uint8List obj(int i) => seg.obj(i);

  Map<String, int>? _names;
  Map<String, int>? _named;

  /// {name: owner object} from the parameter/name index (object 2).
  Map<String, int> nameTable() {
    if (_names != null) return _names!;
    final b = seg.data;
    final out = <String, int>{};
    (String, int, int)? entryAt(int p) {
      final ln = _u32(b, p);
      if (ln == null || ln < 1 || ln > 64 || p + 4 + 2 * ln > b.length) return null;
      final codes = <int>[];
      for (var j = 0; j < ln; j++) {
        final c = b[p + 4 + 2 * j] | (b[p + 5 + 2 * j] << 8);
        if (!_printable(c)) return null;
        codes.add(c);
      }
      final r = _u32(b, p + 4 + 2 * ln);
      if (r == null || r & 0x80000000 == 0) return null;
      return (String.fromCharCodes(codes), (r & 0x7fffffff) - 1, p + 8 + 2 * ln);
    }

    if (n < 4) return _names = out;
    final s2 = seg.starts[2], e2 = seg.starts[3];
    var p = s2;
    while (p < e2) {
      if (entryAt(p) != null) {
        var q = p;
        while (true) {
          final e = entryAt(q);
          if (e == null) break;
          out.putIfAbsent(e.$1, () => e.$2);
          q = e.$3;
        }
        if (q > p + 16) {
          p = q;
          continue;
        }
      }
      p++;
    }
    return _names = out;
  }

  /// {name: object that carries the name string} for browser nodes.
  Map<String, int> namedObjects() {
    if (_named != null) return _named!;
    final out = <String, int>{};
    for (var i = 0; i < n; i++) {
      for (final (o, t) in seg.strings(i, 2)) {
        if (o == 24 || o == 28 || o == 36 || o == 40) out.putIfAbsent(t, () => i);
      }
    }
    return _named = out;
  }

  /// {name: Param} -- value in internal units (cm / rad).
  Map<String, Param> parameters() {
    final out = <String, Param>{};
    nameTable().forEach((name, i) {
      if (i < 0 || i >= n) return;
      final b = obj(i);
      final ln = _u32(b, 20);
      if (ln == null || ln > 40 || 24 + 2 * ln > b.length) return;
      final nm = String.fromCharCodes(
          [for (var j = 0; j < ln; j++) b[24 + 2 * j] | (b[25 + 2 * j] << 8)]);
      if (nm != name) return;
      final vo = 24 + 2 * ln + 12;
      final v = _f64(b, vo);
      if (v == null) return;
      out[name] = Param(i, v, _f64(b, vo + 8));
    });
    return out;
  }

  /// [(name, main object)] -- the object a sketch's entities point to.
  List<(String, int)> sketchMains() {
    final out = <(String, int)>[];
    namedObjects().forEach((name, i) {
      final refs = seg.refIdx(i);
      if (refs.length < 2) return;
      final main = refs[0];
      final end = math.min(n, main + 400);
      for (var e = main + 1; e < end; e++) {
        if (_ref(obj(e), 24) == main) {
          out.add((name, main));
          return;
        }
      }
    });
    return out;
  }

  ({Map<int, ({double x, double y, int flags})> points, Map<int, RawCurve> curves, List<RawConstraint> constraints})
      sketch(int main) {
    final ents = [for (var e = main + 1; e < n; e++) if (_ref(obj(e), 24) == main) e];
    final points = <int, ({double x, double y, int flags})>{};
    final curves = <int, RawCurve>{};
    for (final e in ents) {
      final b = obj(e);
      if (_u32(b, 28) != _arr) {
        final x = _f64(b, 28), y = _f64(b, 36);
        if (x == null || y == null) continue;
        points[e] = (x: x * _cm, y: y * _cm, flags: _u32(b, 20) ?? 0);
      }
    }
    for (final e in ents) {
      final b = obj(e);
      if (_u32(b, 28) != _arr) continue;
      final flags = _u32(b, 20) ?? 0;
      final cnt = _u32(b, 32) ?? 0;
      if (cnt > 64) continue;
      final refs = [for (var k = 0; k < cnt; k++) _ref(b, 44 + 4 * k) ?? -1];
      final p = 44 + 4 * cnt + 8;
      final cref = _ref(b, p);
      final rad = _f64(b, p + 4);
      if (cref != null && points.containsKey(cref) && rad != null && rad > 1e-9 && rad < 1e4) {
        curves[e] = RawCurve(flags, refs, 'arc', centre: cref, radius: rad * _cm);
      } else {
        curves[e] = RawCurve(flags, refs, 'line');
      }
    }
    final cons = _constraintsOf(main, {...points.keys, ...curves.keys});
    return (points: points, curves: curves, constraints: cons);
  }

  List<RawConstraint> _constraintsOf(int main, Set<int> ents) {
    final sys = <int, List<int>>{};
    final end = math.min(n, main + 800);
    for (var i = main + 1; i < end; i++) {
      final b = obj(i);
      final s = _ref(b, 16);
      if (s == null || _u32(b, 20) != 0x30000006) continue;
      final parts = [for (final r in seg.refIdx(i)) if (r != 2 && r != s) r];
      if (parts.isNotEmpty && parts.any(ents.contains)) (sys[s] ??= []).add(i);
    }
    final out = <RawConstraint>[];
    sys.forEach((s, objs) {
      for (final i in objs) {
        final parts = [for (final r in seg.refs(i)) if (r.$2 != 2 && r.$2 != s) r];
        out.add(RawConstraint(i, s, obj(i).length, parts));
      }
    });
    return out;
  }

  /// The sketch's 2D->3D frame, world mm. A placed sketch stores an origin,
  /// one in-plane axis and (in its own reference list) the normal; bytes
  /// 28/29 of the placement object say which axis and whether reversed. A
  /// sketch on an origin plane stores no placement; Inventor's axes for those
  /// are fixed (XY: X,Y  XZ: -X,Z  YZ: Y,Z).
  Frame? frame(int main) {
    final (o, a, nrm) = placement(main);
    if (nrm == null) return null;
    if (o == null) {
      final key = '${nrm.x.round()},${nrm.y.round()},${nrm.z.round()}';
      const base = {
        '0,0,1': (V3(1, 0, 0), V3(0, 1, 0)),
        '0,1,0': (V3(-1, 0, 0), V3(0, 0, 1)),
        '1,0,0': (V3(0, 1, 0), V3(0, 0, 1)),
      };
      final b = base[key];
      if (b == null) return null;
      return Frame(const V3(0, 0, 0), b.$1, b.$2, nrm);
    }
    final (isX, rev) = _placementFlags(main);
    final ax = rev ? a! * -1 : a!;
    if (isX) return Frame(o, ax, nrm.cross(ax), nrm);
    return Frame(o, ax.cross(nrm), ax, nrm);
  }

  (bool, bool) _placementFlags(int main) {
    final end = math.min(n, main + 12);
    for (var i = main; i < end; i++) {
      final b = obj(i);
      if (b.length == 90 && _ref(b, 20) == main - 1) return (b[28] != 0, b[29] != 0);
    }
    return (true, false);
  }

  (V3?, V3?, V3?) placement(int main) {
    V3? normal;
    for (final r in seg.refIdx(main)) {
      final b = obj(r);
      if (b.length == 83 && r != 2) {
        final v = _v3(b, 36);
        if (v != null && (v.length - 1).abs() < 1e-9) normal = v;
      }
    }
    final end = math.min(n, main + 12);
    for (var i = main; i < end; i++) {
      final b = obj(i);
      if (b.length == 90 && _ref(b, 20) == main - 1) {
        final rs = seg.refIdx(i);
        if (rs.length < 4) break;
        final xa = _v3(obj(rs[2]), 36);
        final o = _v3(obj(rs[3]), 36, _cm);
        return (o, xa, normal);
      }
    }
    return (null, null, normal);
  }
}

class RawCurve {
  final int flags;
  final List<int> refs;
  final String kind;
  final int? centre;
  final double? radius;
  RawCurve(this.flags, this.refs, this.kind, {this.centre, this.radius});
}

// ---------------------------------------------------------------- model
const int kProjected = 0x40, kOffsetGen = 0x40000, kConstruction = 0x80000;

class SkPoint {
  final double x, y;
  final bool projected;
  SkPoint(this.x, this.y, this.projected);
}

class SkCurve {
  final String kind; // line | arc
  final List<int> ends, on;
  final bool projected, construction, offset;
  int? centre;
  double radius = 0;
  (double, double) origin = (0, 0), dir = (1, 0);
  SkCurve(this.kind, this.ends, this.on, this.projected, this.construction, this.offset);
}

class SkConstraint {
  final String type;
  final int? point, curve, line;
  final List<int> lines;
  final List<(int, int)> pairs;
  SkConstraint(this.type,
      {this.point, this.curve, this.line, this.lines = const [], this.pairs = const []});
}

class SkDimension {
  final String param;
  final List<int> refs;
  final double rawValue;
  final bool driven;
  String kind = 'unknown';
  double value = 0;
  SkDimension(this.param, this.refs, this.rawValue, this.driven);
}

class InvSketch {
  final String name;
  final int main;
  Frame? frame;
  final points = <int, SkPoint>{};
  final curves = <int, SkCurve>{};
  final constraints = <SkConstraint>[];
  final dimensions = <SkDimension>[];
  InvSketch(this.name, this.main);
}

double _cross2((double, double) a, (double, double) b) => a.$1 * b.$2 - a.$2 * b.$1;
double _dot2((double, double) a, (double, double) b) => a.$1 * b.$1 + a.$2 * b.$2;

class InventorPart {
  final Dc dc;
  late final Map<String, Param> params;
  final paramByObj = <int, String>{};
  final sketches = <InvSketch>[];

  InventorPart(Uint8List data, Uint8List meta) : dc = Dc(data, meta) {
    params = dc.parameters();
    params.forEach((k, v) => paramByObj[v.obj] = k);
    for (final (name, main) in dc.sketchMains()) {
      sketches.add(_sketch(name, main));
    }
  }

  InvSketch _sketch(String name, int main) {
    final raw = dc.sketch(main);
    final s = InvSketch(name, main)..frame = dc.frame(main);
    raw.points.forEach((e, p) => s.points[e] = SkPoint(p.x, p.y, p.flags & kProjected != 0));
    raw.curves.forEach((e, c) {
      if (c.refs.length < 2 || c.refs.take(2).any((r) => !raw.points.containsKey(r))) {
        throw DcException('$name: a curve without its end points');
      }
      final fl = c.flags;
      final d = SkCurve(c.kind, c.refs.sublist(0, 2), c.refs.sublist(2), fl & kProjected != 0,
          fl & kConstruction != 0, fl & kOffsetGen != 0);
      if (c.kind == 'line') {
        // the end points are exact; the stored direction's offset varies
        final p0 = raw.points[c.refs[0]]!, p1 = raw.points[c.refs[1]]!;
        final l = math.sqrt(math.pow(p1.x - p0.x, 2) + math.pow(p1.y - p0.y, 2));
        d.origin = (p0.x, p0.y);
        d.dir = l > 0 ? ((p1.x - p0.x) / l, (p1.y - p0.y) / l) : (1, 0);
      } else {
        d.centre = c.centre;
        d.radius = c.radius!;
      }
      s.curves[e] = d;
    });
    for (final c in raw.constraints) {
      _constraint(s, c);
    }
    return s;
  }

  String? _kind(InvSketch s, int e) {
    if (s.points.containsKey(e)) return 'P';
    final c = s.curves[e];
    if (c != null) return c.kind == 'line' ? 'L' : 'A';
    if (paramByObj.containsKey(e)) return 'D';
    return null;
  }

  void _constraint(InvSketch s, RawConstraint c) {
    final parts = [for (final p in c.parts) p.$2];
    final ents = [for (final r in parts) if (_kind(s, r) != null) (r, _kind(s, r)!)];
    final size = c.size;
    if (ents.any((e) => e.$2 == 'D')) {
      final pname = paramByObj[ents.firstWhere((e) => e.$2 == 'D').$1]!;
      final geo = [for (final e in ents) if (e.$2 != 'D') e.$1];
      s.dimensions.add(_dimension(s, pname, geo));
      return;
    }
    final uniq = <int>[];
    for (final (r, _) in ents) {
      if (!uniq.contains(r)) uniq.add(r);
    }
    final ks = [for (final r in uniq) _kind(s, r)!];
    final sorted = [...ks]..sort();
    if (size == 79 && uniq.length >= 4) {
      s.constraints.add(SkConstraint('offset', pairs: [(uniq[0], uniq[1]), (uniq[2], uniq[3])]));
      return;
    }
    if (ks.length == 1 && ks[0] == 'L' && size == 68) {
      final d = s.curves[uniq[0]]!.dir;
      s.constraints.add(
          SkConstraint(d.$2.abs() < d.$1.abs() ? 'horizontal' : 'vertical', line: uniq[0]));
      return;
    }
    if (sorted.length == 2 && sorted[0] == 'L' && sorted[1] == 'L') {
      final a = uniq[0], b = uniq[1];
      final da = s.curves[a]!.dir, db = s.curves[b]!.dir;
      String t;
      if (_cross2(da, db).abs() < 1e-9) {
        final oa = s.curves[a]!.origin, ob = s.curves[b]!.origin;
        final off = _cross2(da, (ob.$1 - oa.$1, ob.$2 - oa.$2)).abs();
        t = off < 1e-6 ? 'collinear' : 'parallel';
      } else if (_dot2(da, db).abs() < 1e-9) {
        t = 'perpendicular';
      } else {
        t = 'unknown-line-pair';
      }
      s.constraints.add(SkConstraint(t, lines: [a, b]));
      return;
    }
    if (sorted.length == 2 && (sorted[0] == 'L' || sorted[0] == 'A') && sorted[1] == 'P') {
      final cur = uniq.firstWhere((r) => _kind(s, r) == 'L' || _kind(s, r) == 'A');
      final pt = uniq.firstWhere((r) => _kind(s, r) == 'P');
      final cd = s.curves[cur]!;
      String t;
      if (size == 75) {
        s.constraints.add(SkConstraint('midpoint', point: pt, line: cur));
        return;
      } else if (cd.ends.contains(pt)) {
        t = 'endpoint';
      } else if (cd.kind == 'arc' && cd.centre == pt) {
        t = 'centre';
      } else {
        t = 'on_curve';
      }
      s.constraints.add(SkConstraint(t, point: pt, curve: cur));
      return;
    }
    s.constraints.add(SkConstraint('unknown', lines: uniq));
  }

  SkDimension _dimension(InvSketch s, String pname, List<int> geo) {
    final p = params[pname]!;
    final ks = [for (final r in geo) _kind(s, r)];
    final v = p.value;
    bool proj(int r) => s.points[r]?.projected ?? s.curves[r]?.projected ?? false;
    final d = SkDimension(pname, geo, v, geo.every(proj));
    final sorted = [...ks.whereType<String>()]..sort();
    if (ks.length == 2 && ks[0] == 'L' && ks[1] == 'L') {
      final da = s.curves[geo[0]]!.dir, db = s.curves[geo[1]]!.dir;
      if (_cross2(da, db).abs() < 1e-9) {
        d
          ..kind = 'line_line'
          ..value = v * 10;
      } else {
        d
          ..kind = 'angle'
          ..value = v * 180 / math.pi;
      }
    } else if (sorted.length == 2 && sorted[0] == 'L' && sorted[1] == 'P') {
      d
        ..kind = 'point_line'
        ..value = v * 10;
    } else if (ks.length == 2 && ks[0] == 'P' && ks[1] == 'P') {
      d
        ..kind = 'point_point'
        ..value = v * 10;
    } else if (ks.length == 2 && ks[0] == 'A' && ks[1] == 'A') {
      d
        ..kind = 'arc_arc'
        ..value = v * 10;
    } else if (ks.length == 1 && ks[0] == 'A') {
      d
        ..kind = 'radius'
        ..value = v * 10;
    } else {
      d.value = v;
    }
    return d;
  }
}

// ---------------------------------------------------------------- features
class InvFeature {
  final String name;
  final int node, obj;
  String kind = ''; // extrude | fillet
  int? tag; // B-rep tag id of this feature
  int? sketch; // sketch main object
  final params = <String>[];
  String extent = 'distance'; // distance | throughAll
  (V3, V3)? leader; // world mm, the distance dimension's end points
  int? edgeCount;
  InvFeature(this.name, this.node, this.obj);
  @override
  String toString() => '<$kind $name tag=$tag params=$params>';
}

/// The features in timeline order, with B-rep tags where they can be found.
List<InvFeature> timeline(Dc dc, List<(String, int)> sketchMains, Map<String, Param> params,
    Set<int> brepTags) {
  List<int> refs(int i) => dc.seg.refIdx(i);
  final named = dc.namedObjects();
  final nodeOf = <String, (int, int)>{};
  named.forEach((name, node) {
    final rs = refs(node);
    for (final r in rs.take(3)) {
      if (refs(r).take(3).contains(node) && dc.obj(r).length < 1000) {
        nodeOf[name] = (node, r);
        break;
      }
    }
  });
  final feats = <int, InvFeature>{};
  final skSet = {for (final s in sketchMains) s.$2};
  final skNames = {for (final s in sketchMains) s.$1};
  final paramObjs = <int, String>{};
  params.forEach((k, v) => paramObjs[v.obj] = k);
  nodeOf.forEach((name, no) {
    final (node, obj) = no;
    if (skSet.contains(obj) || skNames.contains(name)) return;
    final rs = refs(obj);
    final f = InvFeature(name, node, obj);
    final sk = [for (final r in rs) if (skSet.contains(r)) r];
    final defn = rs.length > 2 ? rs[2] : null;
    if (sk.isNotEmpty && defn != null) {
      f
        ..kind = 'extrude'
        ..sketch = sk[0];
      _extrudeDetails(dc, f, defn, paramObjs);
    } else if (rs.contains(3) && defn != null) {
      f
        ..kind = 'fillet'
        ..edgeCount = rs.where((r) => r == 3).length;
      f.params.addAll(_walkParams(dc, defn, paramObjs, {0, 1, 2, 3, f.obj}));
    } else {
      return;
    }
    feats[obj] = f;
  });
  // timeline order: the browser chain -- node -> chain object -> next node
  final byNode = {for (final f in feats.values) f.node: f};
  final succ = <int, int>{};
  final hasPred = <int>{};
  for (final f in feats.values) {
    for (final c in refs(f.node).take(1)) {
      for (final n2 in refs(c)) {
        if (byNode.containsKey(n2) && n2 != f.node) {
          succ[f.node] = n2;
          hasPred.add(n2);
        }
      }
    }
  }
  final heads = [for (final k in byNode.keys) if (!hasPred.contains(k)) k]..sort();
  final order = <InvFeature>[];
  for (final h in heads) {
    int? nd = h;
    while (nd != null && !order.contains(byNode[nd])) {
      order.add(byNode[nd]!);
      nd = succ[nd];
    }
  }
  // tags: a body's feature list holds one reference per feature, in timeline
  // order, and ends with the body's browser node; the reference value
  // (index + 1) is the id the B-rep face tags carry
  List<int>? best;
  var bestHits = -1;
  named.forEach((name, node) {
    final lim = math.min(dc.n, 64);
    for (var i = 0; i < lim; i++) {
      final rs = refs(i);
      if (rs.isEmpty || rs.last != node) continue;
      final all = [for (final r in rs) if (r > 2) r];
      if (all.length < 2) continue;
      final lst = all.sublist(1, all.length - 1);
      if (lst.length != order.length) continue;
      final hits = lst.where((t) => brepTags.contains(t + 1)).length;
      if (hits > bestHits) {
        best = lst;
        bestHits = hits;
      }
    }
  });
  if (best != null) {
    for (var i = 0; i < order.length; i++) {
      order[i].tag = best![i] + 1;
    }
  }
  return order;
}

List<String> _walkParams(Dc dc, int start, Map<int, String> paramObjs, Set<int> hubs,
    [int depth = 3]) {
  final seen = {start};
  var frontier = [start];
  final found = <String>[];
  for (var d = 0; d < depth; d++) {
    final nxt = <int>[];
    for (final x in frontier) {
      for (final r in dc.seg.refIdx(x)) {
        if (hubs.contains(r) || seen.contains(r)) continue;
        seen.add(r);
        final p = paramObjs[r];
        if (p != null) found.add(p);
        nxt.add(r);
      }
    }
    frontier = nxt;
  }
  return found;
}

void _extrudeDetails(Dc dc, InvFeature f, int defn, Map<int, String> paramObjs) {
  final rs = dc.seg.refIdx(defn);
  if (rs.isEmpty) throw DcException('${f.name}: an extrusion without its extent');
  final extent = rs.last;
  final ers = [for (final r in dc.seg.refIdx(extent)) if (r != 2) r];
  final distObj = ers.isNotEmpty ? ers[0] : null;
  final taperObj = ers.length > 1 ? ers[1] : null;
  for (final o in [distObj, taperObj]) {
    if (o == null) continue;
    for (final r in dc.seg.refIdx(o)) {
      final p = paramObjs[r];
      if (p != null) f.params.add(p);
    }
  }
  final b = distObj != null ? dc.obj(distObj) : Uint8List(0);
  if (b.length >= 56 && _u32(b, 0) == 2) {
    f.leader = (_v3(b, 8, 10)!, _v3(b, 32, 10)!);
  } else {
    f.extent = 'throughAll';
  }
}

// ---------------------------------------------------------------- profiles
class ProfSeg {
  final bool arc;
  final (double, double) p0, p1;
  final (double, double)? centre;
  final double radius;
  ProfSeg(this.arc, this.p0, this.p1, this.centre, this.radius);
}

/// One extrusion profile: a plane frame and loops of (x, y, bulge).
class Profile {
  final int tag;
  final V3 origin, u, v, n; // mm
  List<List<(double, double, double)>> loops = [];
  List<List<ProfSeg>> segments = [];
  Profile(this.tag, this.origin, this.u, this.v, this.n);

  (double, double) to2d(V3 p) {
    final d = p - origin;
    return (d.dot(u), d.dot(v));
  }

  V3 to3d(double x, double y, [double w = 0]) => origin + u * x + v * y + n * w;
}

double signedArea(List<(double, double, double)> loop) {
  var a = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final (x0, y0, b) = loop[i];
    final (x1, y1, _) = loop[(i + 1) % loop.length];
    a += x0 * y1 - x1 * y0;
    if (b != 0) {
      final c = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      final th = 4 * math.atan(b);
      final sh = math.sin(th / 2);
      final r = sh.abs() > 1e-12 ? c / (2 * sh) : 0.0;
      a += r * r * (th - math.sin(th));
    }
  }
  return a / 2;
}

/// All profiles in the DC segment, in body order.
List<Profile> profiles(Uint8List dcData, {double unitMm = 10.0}) {
  final start = findSab(dcData);
  if (start < 0) return const [];
  final sab = parseSab(dcData, start);
  final t = Topo(sab);
  final out = <Profile>[];
  for (final b in t.bodies()) {
    final faces = [for (final sh in t.shells(b)) ...t.faces(sh)];
    if (faces.length != 1) continue;
    final fc = faces[0];
    final g = surfaceOf(sab.records[t.faceInfo(fc).surface]);
    if (g.kind != 'plane') continue;
    final n = g.normal;
    final pr = Profile(sab.records[b].id, g.origin * unitMm, g.udir, n.cross(g.udir), n);
    final loops = <(double, List<(double, double, double)>, List<ProfSeg>)>[];
    for (final lp in t.loops(fc)) {
      final verts = <(double, double, double)>[];
      final segs = <ProfSeg>[];
      for (final c in t.coedges(lp)) {
        final ci = t.coedgeInfo(c);
        final ei = t.edgeInfo(ci.edge);
        var p0 = t.vertexPoint(ei.v0) * unitMm;
        var p1 = t.vertexPoint(ei.v1) * unitMm;
        final cg = curveOf(sab.records[ei.curve]);
        var bulge = 0.0, radius = 0.0;
        V3? centre;
        if (cg.kind == 'circle') {
          var sweep = ei.t1 - ei.t0;
          if (cg.normal.dot(n) <= 0) sweep = -sweep;
          if (ci.reversed) {
            final tmp = p0;
            p0 = p1;
            p1 = tmp;
            sweep = -sweep;
          }
          bulge = math.tan(sweep / 4);
          centre = cg.origin * unitMm;
          radius = cg.radius * unitMm;
        } else if (cg.kind != 'line') {
          throw DcException('a profile edge of type ${cg.kind} is not supported yet');
        } else if (ci.reversed) {
          final tmp = p0;
          p0 = p1;
          p1 = tmp;
        }
        final (x, y) = pr.to2d(p0);
        verts.add((x, y, bulge));
        segs.add(ProfSeg(centre != null, pr.to2d(p0), pr.to2d(p1),
            centre != null ? pr.to2d(centre) : null, radius));
      }
      loops.add((signedArea(verts).abs(), verts, segs));
    }
    loops.sort((a, b) => b.$1.compareTo(a.$1));
    pr.loops = [for (final l in loops) l.$2];
    pr.segments = [for (final l in loops) l.$3];
    out.add(pr);
  }
  return out;
}
