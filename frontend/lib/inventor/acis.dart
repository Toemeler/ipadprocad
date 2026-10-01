// ASM/ACIS B-rep records -> geometry and topology, and -> STEP AP214.
// Port of tools/ipt/acis_to_step.py; see there for the reasoning.
//
// Analytic geometry maps one to one. Procedural ACIS geometry (blends,
// intersection curves) is written as the B-spline fit ACIS keeps with it,
// which is what Inventor's own STEP export writes too.
//
// Orientation: loops are copied as they are; an ACIS surface may face
// inward (cone cos < 0, torus minor < 0, sphere r < 0, spline reversed flag)
// where STEP's never does, and ADVANCED_FACE.same_sense absorbs that.
import 'dart:math' as math;
import 'dart:typed_data';

import 'sab.dart';

class AcisException implements Exception {
  final String message;
  AcisException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- vectors
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  V3 get unit {
    final l = length;
    if (l < 1e-300) throw AcisException('zero-length direction');
    return this * (1 / l);
  }

  V3 get perp {
    final t = x.abs() < 0.9 ? const V3(1, 0, 0) : const V3(0, 1, 0);
    return cross(t).unit;
  }

  @override
  String toString() => '($x, $y, $z)';
}

// ---------------------------------------------------------------- cursor
class _Cur {
  final List<Object> f;
  int i;
  _Cur(this.f, [this.i = 0]);
  Object get peek => f[i];
  Object next() => f[i++];

  double real() {
    final v = next();
    if (v is double) return v;
    if (v is int) return v.toDouble();
    throw AcisException('expected a number, got $v');
  }

  int integer() {
    final v = next();
    if (v is int) return v;
    throw AcisException('expected an int, got $v');
  }

  V3 vec() {
    final v = peek;
    if (v is Float64List && v.length == 3) {
      i++;
      return V3(v[0], v[1], v[2]);
    }
    return V3(real(), real(), real());
  }

  bool logical() {
    final v = next();
    if (v is bool) return v;
    throw AcisException('expected a logical, got $v');
  }

  void interval() {
    for (var k = 0; k < 2; k++) {
      if (logical()) real();
    }
  }
}

Iterable<(int depth, int index)> _depthScan(List<Object> f) sync* {
  var d = 0;
  for (var i = 0; i < f.length; i++) {
    if (identical(f[i], sabOpen)) {
      d++;
    } else if (identical(f[i], sabClose)) {
      d--;
    } else {
      yield (d, i);
    }
  }
}

// ---------------------------------------------------------------- B-splines
class BSpline {
  bool rational = false;
  List<int> deg = [];
  List<List<(double, int)>> knots = [];
  List<int> closure = [];
  List<V3> ctrl = []; // curve
  List<List<V3>> grid = []; // surface, [u][v]
  List<double>? weights;
  List<List<double>>? wgrid;
}

List<(double, int)> _knots(_Cur c, int n) => [for (var i = 0; i < n; i++) (c.real(), c.integer())];
int _ncp(List<(double, int)> k, int deg) => k.fold<int>(0, (a, e) => a + e.$2) - deg + 1;

bool _isInt(Object v) => v is int;

bool _bs3SurfaceAt(List<Object> f, int i) =>
    f[i] is SabIdent &&
    ((f[i] as SabIdent).s == 'nubs' || (f[i] as SabIdent).s == 'nurbs') &&
    i + 3 < f.length &&
    _isInt(f[i + 1]) &&
    _isInt(f[i + 2]) &&
    f[i + 3] is SabEnum;

bool _bs3CurveAt(List<Object> f, int i) =>
    f[i] is SabIdent &&
    ((f[i] as SabIdent).s == 'nubs' || (f[i] as SabIdent).s == 'nurbs') &&
    i + 2 < f.length &&
    _isInt(f[i + 1]) &&
    f[i + 2] is SabEnum;

BSpline _readCurve(List<Object> f, int i) {
  final c = _Cur(f, i);
  final b = BSpline()..rational = (c.next() as SabIdent).s == 'nurbs';
  final p = c.integer();
  b.deg = [p];
  b.closure = [(c.next() as SabEnum).v];
  b.knots = [_knots(c, c.integer())];
  final n = _ncp(b.knots[0], p);
  final w = <double>[];
  for (var k = 0; k < n; k++) {
    b.ctrl.add(c.vec());
    if (b.rational) w.add(c.real());
  }
  if (b.rational) b.weights = w;
  return b;
}

/// Surface control points: the u index varies FASTEST (verified on
/// Inventor 2026 blends, tools/ipt/check_geometry.py).
BSpline _readSurface(List<Object> f, int i) {
  final c = _Cur(f, i);
  final b = BSpline()..rational = (c.next() as SabIdent).s == 'nurbs';
  final pu = c.integer(), pv = c.integer();
  b.deg = [pu, pv];
  b.closure = [(c.next() as SabEnum).v, (c.next() as SabEnum).v];
  c.next();
  c.next(); // singularities
  final nku = c.integer(), nkv = c.integer();
  final ku = _knots(c, nku), kv = _knots(c, nkv);
  b.knots = [ku, kv];
  final nu = _ncp(ku, pu), nv = _ncp(kv, pv);
  final flat = <V3>[], ws = <double>[];
  for (var k = 0; k < nu * nv; k++) {
    flat.add(c.vec());
    if (b.rational) ws.add(c.real());
  }
  b.grid = [for (var u = 0; u < nu; u++) [for (var v = 0; v < nv; v++) flat[v * nu + u]]];
  if (b.rational) {
    b.wgrid = [for (var u = 0; u < nu; u++) [for (var v = 0; v < nv; v++) ws[v * nu + u]]];
  }
  return b;
}

// ---------------------------------------------------------------- geometry
class Geom {
  String kind = '';
  bool reversed = false;
  V3 origin = const V3(0, 0, 0), normal = const V3(0, 0, 1), udir = const V3(1, 0, 0);
  V3 axis = const V3(0, 0, 1), major = const V3(1, 0, 0), dir = const V3(1, 0, 0), pole = const V3(0, 0, 1);
  double radius = 0, ratio = 1, tan = 0, majorR = 0, minorR = 0;
  BSpline? bs;
}

Geom surfaceOf(SabRecord r) {
  final c = _Cur(r.fields, 3);
  final g = Geom();
  switch (r.type) {
    case 'plane-surface':
      g.kind = 'plane';
      g.origin = c.vec();
      g.normal = c.vec().unit;
      final u = c.vec();
      g.udir = u.length < 1e-12 ? g.normal.perp : u.unit;
    case 'cone-surface':
      g.origin = c.vec();
      g.axis = c.vec().unit;
      g.major = c.vec();
      g.ratio = c.real();
      c.interval();
      final s = c.real(), co = c.real();
      c.real();
      if ((g.ratio - 1).abs() > 1e-9) {
        throw AcisException('elliptical cones and cylinders are not supported yet');
      }
      g.radius = g.major.length;
      g.reversed = co < 0;
      if (s.abs() < 1e-12) {
        g.kind = 'cylinder';
      } else {
        g.kind = 'cone';
        g.tan = s / co;
      }
    case 'torus-surface':
      g.kind = 'torus';
      g.origin = c.vec();
      g.axis = c.vec().unit;
      g.majorR = c.real();
      g.minorR = c.real();
      final u = c.vec();
      g.udir = u.length < 1e-12 ? g.axis.perp : u.unit;
      g.reversed = g.minorR < 0;
      if (g.majorR < 0) throw AcisException('self-intersecting tori are not supported yet');
    case 'sphere-surface':
      g.kind = 'sphere';
      g.origin = c.vec();
      final r0 = c.real();
      final u = c.vec(), pl = c.vec();
      g.radius = r0.abs();
      g.reversed = r0 < 0;
      g.pole = pl.length > 1e-12 ? pl.unit : const V3(0, 0, 1);
      g.udir = u.length > 1e-12 ? u.unit : g.pole.perp;
    case 'spline-surface':
      g.kind = 'bspline_surface';
      g.reversed = c.logical();
      int? hit;
      for (final (d, i) in _depthScan(r.fields)) {
        if (d == 1 && _bs3SurfaceAt(r.fields, i)) hit = i;
      }
      if (hit == null) throw AcisException('a spline surface carries no B-spline fit');
      g.bs = _readSurface(r.fields, hit);
    default:
      throw AcisException('unsupported surface type ${r.type}');
  }
  return g;
}

Geom curveOf(SabRecord r) {
  final c = _Cur(r.fields, 3);
  final g = Geom();
  switch (r.type) {
    case 'straight-curve':
      g.kind = 'line';
      g.origin = c.vec();
      g.dir = c.vec().unit;
    case 'ellipse-curve':
      g.origin = c.vec();
      g.normal = c.vec().unit;
      g.major = c.vec();
      g.ratio = c.real();
      g.kind = (g.ratio - 1).abs() < 1e-12 ? 'circle' : 'ellipse';
      g.radius = g.major.length;
    case 'intcurve-curve':
      g.kind = 'bspline_curve';
      g.reversed = c.logical();
      int? hit;
      for (final (d, i) in _depthScan(r.fields)) {
        if (d == 1 && _bs3CurveAt(r.fields, i)) {
          hit = i;
          break;
        }
      }
      if (hit == null) throw AcisException('an intersection curve carries no B-spline fit');
      g.bs = _readCurve(r.fields, hit);
    default:
      throw AcisException('unsupported curve type ${r.type}');
  }
  return g;
}

// ---------------------------------------------------------------- topology
class Topo {
  final Sab sab;
  Topo(this.sab);
  List<SabRecord> get r => sab.records;
  List<int> p(int i) => r[i].ptrs;

  Iterable<int> chain(int start, int nxt) sync* {
    final seen = <int>{};
    var s = start;
    while (s >= 0 && seen.add(s)) {
      yield s;
      s = p(s)[nxt];
    }
  }

  List<int> bodies() => [for (final x in r) if (x.type == 'body') x.index];

  Iterable<int> shells(int b) sync* {
    for (final l in chain(p(b)[2], 2)) {
      yield* chain(p(l)[3], 2);
    }
  }

  List<int> faces(int shell) => chain(p(shell)[4], 2).toList();
  List<int> loops(int face) => chain(p(face)[3], 2).toList();

  List<int> coedges(int loop) {
    final out = <int>[];
    final c0 = p(loop)[3];
    var c = c0;
    while (c >= 0) {
      out.add(c);
      c = p(c)[2];
      if (c == c0 || out.length > 100000) break;
    }
    return out;
  }

  ({int loop, int surface, bool reversed}) faceInfo(int f) {
    final pp = p(f);
    final lg = [for (final v in r[f].fields) if (v is bool) v];
    return (loop: pp[3], surface: pp[6], reversed: lg.isNotEmpty && lg[0]);
  }

  ({int edge, bool reversed}) coedgeInfo(int c) {
    final lg = [for (final v in r[c].fields) if (v is bool) v];
    return (edge: p(c)[5], reversed: lg.first);
  }

  ({int v0, int v1, double t0, double t1, int curve, bool reversed}) edgeInfo(int e) {
    final c = _Cur(r[e].fields, 3);
    final v0 = (c.next() as SabPtr).i;
    final t0 = c.real();
    final v1 = (c.next() as SabPtr).i;
    final t1 = c.real();
    c.next();
    final curve = (c.next() as SabPtr).i;
    final rev = c.logical();
    return (v0: v0, v1: v1, t0: t0, t1: t1, curve: curve, reversed: rev);
  }

  V3 vertexPoint(int v) => _Cur(r[p(v)[3]].fields, 3).vec();
}

// ---------------------------------------------------------------- STEP
String _real(double x) {
  if (x == 0) return '0.';
  var s = x.toString().toUpperCase();
  if (s.contains('E')) {
    final parts = s.split('E');
    var m = parts[0];
    if (!m.contains('.')) m = '$m.';
    final e = int.parse(parts[1]);
    return '${m}E${e < 0 ? '-' : '+'}${e.abs().toString().padLeft(2, '0')}';
  }
  return s.contains('.') ? s : '$s.';
}

String stepString(String s) {
  final b = StringBuffer("'");
  for (final ch in s.runes) {
    if (ch == 0x27) {
      b.write("''");
    } else if (ch == 0x5C) {
      b.write(r'\\');
    } else if (ch >= 32 && ch < 127) {
      b.writeCharCode(ch);
    } else {
      b.write('\\X2\\${ch.toRadixString(16).toUpperCase().padLeft(4, '0')}\\X0\\');
    }
  }
  b.write("'");
  return b.toString();
}

class _W {
  final lines = <String>[];
  final _cache = <String, int>{};
  int n = 0;

  int add(String text, [String? key]) {
    if (key != null) {
      final c = _cache[key];
      if (c != null) return c;
    }
    n++;
    lines.add('#$n=$text;');
    if (key != null) _cache[key] = n;
    return n;
  }

  int point(V3 p) => add("CARTESIAN_POINT('',(${_real(p.x)},${_real(p.y)},${_real(p.z)}))",
      'P${p.x},${p.y},${p.z}');
  int direction(V3 d) =>
      add("DIRECTION('',(${_real(d.x)},${_real(d.y)},${_real(d.z)}))", 'D${d.x},${d.y},${d.z}');

  int axis2(V3 o, V3 z, V3 x) {
    var xx = x - z * x.dot(z);
    xx = xx.length > 1e-12 ? xx.unit : z.perp;
    return add("AXIS2_PLACEMENT_3D('',#${point(o)},#${direction(z)},#${direction(xx)})");
  }
}

(List<double>, List<int>) _knotLists(List<(double, int)> k) {
  final vals = [for (final e in k) e.$1];
  final mults = [for (final e in k) e.$2];
  mults[0] += 1;
  mults[mults.length - 1] += 1;
  return (vals, mults);
}

int _bsCurve(_W w, BSpline b, double s) {
  final p = b.deg[0];
  final (vals, mults) = _knotLists(b.knots[0]);
  final pts = b.ctrl.map((q) => '#${w.point(q * s)}').join(',');
  final kv = vals.map(_real).join(','), km = mults.join(',');
  final closed = b.closure[0] != 0 ? '.T.' : '.F.';
  if (!b.rational) {
    return w.add("B_SPLINE_CURVE_WITH_KNOTS('',$p,($pts),.UNSPECIFIED.,$closed,.F.,($km),($kv),.UNSPECIFIED.)");
  }
  final ws = b.weights!.map(_real).join(',');
  return w.add('(BOUNDED_CURVE() B_SPLINE_CURVE($p,($pts),.UNSPECIFIED.,$closed,.F.) '
      'B_SPLINE_CURVE_WITH_KNOTS(($km),($kv),.UNSPECIFIED.) CURVE() GEOMETRIC_REPRESENTATION_ITEM() '
      "RATIONAL_B_SPLINE_CURVE(($ws)) REPRESENTATION_ITEM(''))");
}

int _bsSurface(_W w, BSpline b, double s) {
  final pu = b.deg[0], pv = b.deg[1];
  final (vu, mu) = _knotLists(b.knots[0]);
  final (vv, mv) = _knotLists(b.knots[1]);
  final rows = b.grid.map((row) => '(${row.map((q) => '#${w.point(q * s)}').join(',')})').join(',');
  final cu = b.closure[0] != 0 ? '.T.' : '.F.', cv = b.closure[1] != 0 ? '.T.' : '.F.';
  final k = '(${mu.join(',')}),(${mv.join(',')}),(${vu.map(_real).join(',')}),(${vv.map(_real).join(',')})';
  if (!b.rational) {
    return w.add("B_SPLINE_SURFACE_WITH_KNOTS('',$pu,$pv,($rows),.UNSPECIFIED.,$cu,$cv,.F.,$k,.UNSPECIFIED.)");
  }
  final ws = b.wgrid!.map((row) => '(${row.map(_real).join(',')})').join(',');
  return w.add('(BOUNDED_SURFACE() B_SPLINE_SURFACE($pu,$pv,($rows),.UNSPECIFIED.,$cu,$cv,.F.) '
      'B_SPLINE_SURFACE_WITH_KNOTS($k,.UNSPECIFIED.) GEOMETRIC_REPRESENTATION_ITEM() '
      "RATIONAL_B_SPLINE_SURFACE(($ws)) REPRESENTATION_ITEM('') SURFACE())");
}

int _surface(_W w, Geom g, double s) {
  switch (g.kind) {
    case 'plane':
      return w.add("PLANE('',#${w.axis2(g.origin * s, g.normal, g.udir)})");
    case 'cylinder':
      return w.add("CYLINDRICAL_SURFACE('',#${w.axis2(g.origin * s, g.axis, g.major.unit)},${_real(g.radius * s)})");
    case 'cone':
      var axis = g.axis, t = g.tan;
      if (t < 0) {
        axis = axis * -1;
        t = -t;
      }
      return w.add("CONICAL_SURFACE('',#${w.axis2(g.origin * s, axis, g.major.unit)},"
          '${_real(g.radius * s)},${_real(math.atan(t))})');
    case 'torus':
      return w.add("TOROIDAL_SURFACE('',#${w.axis2(g.origin * s, g.axis, g.udir)},"
          '${_real(g.majorR * s)},${_real(g.minorR.abs() * s)})');
    case 'sphere':
      return w.add("SPHERICAL_SURFACE('',#${w.axis2(g.origin * s, g.pole, g.udir)},${_real(g.radius * s)})");
    case 'bspline_surface':
      return _bsSurface(w, g.bs!, s);
  }
  throw AcisException(g.kind);
}

int _curve(_W w, Geom g, double s) {
  switch (g.kind) {
    case 'line':
      final v = w.add("VECTOR('',#${w.direction(g.dir)},1.)");
      return w.add("LINE('',#${w.point(g.origin * s)},#$v)");
    case 'circle':
      return w.add("CIRCLE('',#${w.axis2(g.origin * s, g.normal, g.major.unit)},${_real(g.radius * s)})");
    case 'ellipse':
      return w.add("ELLIPSE('',#${w.axis2(g.origin * s, g.normal, g.major.unit)},"
          '${_real(g.radius * s)},${_real(g.radius * g.ratio * s)})');
    case 'bspline_curve':
      return _bsCurve(w, g.bs!, s);
  }
  throw AcisException(g.kind);
}

/// Every body of [sab] as one STEP file, one solid per body, in millimetres.
({String step, List<String> names}) brepToStep(Sab sab,
    {List<String>? names, String product = 'Part', String author = ''}) {
  final t = Topo(sab);
  final unit = sab.unitMm;
  final w = _W();
  final lenU = w.add('(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))');
  final angU = w.add('(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT(\$,.RADIAN.))');
  final solU = w.add('(NAMED_UNIT(*) SI_UNIT(\$,.STERADIAN.) SOLID_ANGLE_UNIT())');
  final unc = w.add("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-05),#$lenU,'distance_accuracy_value','confusion accuracy')");
  final ctx = w.add('(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#$unc)) '
      'GLOBAL_UNIT_ASSIGNED_CONTEXT((#$lenU,#$angU,#$solU)) '
      "REPRESENTATION_CONTEXT('Context #1','3D Context with UNIT and UNCERTAINTY'))");
  final solids = <int>[];
  final solidNames = <String>[];
  final bodies = t.bodies();
  for (var bi = 0; bi < bodies.length; bi++) {
    final b = bodies[bi];
    final name = names != null && bi < names.length ? names[bi] : 'Solid${bi + 1}';
    final vtx = <int, int>{}, edges = <int, int>{};
    final surfCache = <int, (Geom, int)>{};
    final shells = <(bool, int)>[];
    for (final sh in t.shells(b)) {
      final faceIds = <int>[];
      final used = <int, int>{};
      for (final f in t.faces(sh)) {
        final fi = t.faceInfo(f);
        final (g, sid) = surfCache.putIfAbsent(fi.surface, () {
          final gg = surfaceOf(t.r[fi.surface]);
          return (gg, _surface(w, gg, unit));
        });
        final bounds = <int>[];
        for (final lp in t.loops(f)) {
          final oes = <int>[];
          for (final c in t.coedges(lp)) {
            final ci = t.coedgeInfo(c);
            used[ci.edge] = (used[ci.edge] ?? 0) + 1;
            final eid = edges.putIfAbsent(ci.edge, () {
              final ei = t.edgeInfo(ci.edge);
              for (final v in [ei.v0, ei.v1]) {
                vtx.putIfAbsent(v, () => w.add("VERTEX_POINT('',#${w.point(t.vertexPoint(v) * unit)})"));
              }
              if (ei.curve < 0) throw AcisException('an edge has no curve');
              final cg = curveOf(t.r[ei.curve]);
              final cid = _curve(w, cg, unit);
              final same = !(ei.reversed ^ cg.reversed);
              return w.add("EDGE_CURVE('',#${vtx[ei.v0]},#${vtx[ei.v1]},#$cid,${same ? '.T.' : '.F.'})");
            });
            oes.add(w.add("ORIENTED_EDGE('',*,*,#$eid,${ci.reversed ? '.F.' : '.T.'})"));
          }
          final loop = w.add("EDGE_LOOP('',(${oes.map((o) => '#$o').join(',')}))");
          bounds.add(w.add("FACE_BOUND('',#$loop,.T.)"));
        }
        final same = !(fi.reversed ^ g.reversed);
        faceIds.add(w.add("ADVANCED_FACE('',(${bounds.map((x) => '#$x').join(',')}),#$sid,${same ? '.T.' : '.F.'})"));
      }
      final closed = used.values.every((n) => n == 2);
      final kind = closed ? 'CLOSED_SHELL' : 'OPEN_SHELL';
      shells.add((closed, w.add("$kind('',(${faceIds.map((x) => '#$x').join(',')}))")));
    }
    if (shells.isEmpty) continue;
    int sol;
    if (shells.every((s) => s.$1)) {
      sol = shells.length == 1
          ? w.add('MANIFOLD_SOLID_BREP(${stepString(name)},#${shells[0].$2})')
          : w.add('BREP_WITH_VOIDS(${stepString(name)},#${shells[0].$2},'
              '(${shells.skip(1).map((s) => '#${s.$2}').join(',')}))');
    } else {
      sol = w.add('SHELL_BASED_SURFACE_MODEL(${stepString(name)},(${shells.map((s) => '#${s.$2}').join(',')}))');
    }
    solids.add(sol);
    solidNames.add(name);
  }
  final origin = w.axis2(const V3(0, 0, 0), const V3(0, 0, 1), const V3(1, 0, 0));
  final rep = w.add('ADVANCED_BREP_SHAPE_REPRESENTATION(${stepString(product)},'
      '(${[...solids, origin].map((s) => '#$s').join(',')}),#$ctx)');
  final app = w.add("APPLICATION_CONTEXT('core data for automotive mechanical design processes')");
  w.add("APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#$app)");
  final pc = w.add("PRODUCT_CONTEXT('',#$app,'mechanical')");
  final prod = w.add("PRODUCT(${stepString(product)},${stepString(product)},'',(#$pc))");
  final pdf = w.add("PRODUCT_DEFINITION_FORMATION('','',#$prod)");
  final pdc = w.add("PRODUCT_DEFINITION_CONTEXT('part definition',#$app,'design')");
  final pd = w.add("PRODUCT_DEFINITION('design','',#$pdf,#$pdc)");
  final pds = w.add("PRODUCT_DEFINITION_SHAPE('','',#$pd)");
  w.add('SHAPE_DEFINITION_REPRESENTATION(#$pds,#$rep)');
  w.add("PRODUCT_RELATED_PRODUCT_CATEGORY('part',\$,(#$prod))");
  final now = DateTime.now().toIso8601String().split('.').first;
  final head = 'ISO-10303-21;\nHEADER;\n'
      "FILE_DESCRIPTION(('Exact B-rep converted from an Autodesk Inventor part'),'2;1');\n"
      "FILE_NAME(${stepString('$product.step')},'$now',(${stepString(author)}),(''),"
      "'Prototype','${sab.header['asm']}','');\n"
      "FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n";
  return (step: '$head${w.lines.join('\n')}\nENDSEC;\nEND-ISO-10303-21;\n', names: solidNames);
}
