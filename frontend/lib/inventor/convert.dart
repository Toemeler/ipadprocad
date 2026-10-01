// Inventor .ipt -> the app's part document (.ptp), with the full feature
// tree. Port of tools/ipt/ipt_convert.py (and ipt2ptp.py for the fallback);
// the reasoning is documented there.
//
//  1. container, final B-rep (exact), DC segment (sketches, parameters,
//     feature timeline, extrusion profiles);
//  2. sketches -> app sketches, every constraint verified on Inventor's own
//     geometry;
//  3. features -> app features. Extrusion direction and operation come from
//     the faces each feature left in Inventor's result (their tags); fillet
//     edges are found by replaying the tree in the app's own kernel and
//     picking, at each fillet, the edges whose blend at that radius is one of
//     the faces Inventor tagged for that fillet;
//  4. Inventor's exact bodies ride along as the features' stored result, so
//     the app shows exactly what Inventor built until something is edited.
//
// When the tree uses something not supported yet, the part still arrives
// with its exact bodies (as imported solids) -- never as nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:crypto/crypto.dart' as crypto;

import '../doc_file.dart';
import '../ffi/occt_engine.dart';
import '../ffi/qcad_engine.dart' show Geo;
import '../part_model.dart'
    show ProfileInput, planarFaceRecs, pointInPolygon, profileLoopsOf, regionAnchor, regionsFrom;
import 'acis.dart';
import 'dc.dart';
import 'ipt_file.dart';
import 'sab.dart';
import 'sketch_out.dart';

const String kIptConverterFull = 'ipt2ptp/2';
const String kIptConverterBodies = 'ipt2ptp/1';
const String kIptSourceEntry = 'inventor/source.ipt';
const String kIptInfoEntry = 'inventor/source.json';
const String kIptResultEntry = 'inventor/result.step';

class IptConversionException implements Exception {
  final String message;
  IptConversionException(this.message);
  @override
  String toString() => message;
}

class IptConversion {
  final Uint8List ptp;
  final bool fullTree;
  final String? fallbackReason;
  final List<String> log;
  IptConversion(this.ptp, this.fullTree, this.fallbackReason, this.log);
}

String _sha(List<int> b) => crypto.sha256.convert(b).toString();

// ------------------------------------------------------------------ B-rep
const _blend = 'INV_NMX_BLEND_TAG', _sweep = 'INV_NMX_SWEEPGENERATED_TAG';
const _matched = 'INV_NMX_MATCHED_ATTRIB', _dep = 'INV_NMX_FEATURE_DEPENDENCY_ATTRIB';

/// {face record: [(kind, feature id)]} from Inventor's face attributes.
Map<int, List<(String, int)>> faceTags(Sab sab) {
  final out = <int, List<(String, int)>>{};
  for (final r in sab.records) {
    if (r.type != 'face') continue;
    final ps = r.ptrs;
    var a = ps.isEmpty ? -1 : ps[0];
    final seen = <int>{};
    while (a >= 0 && a < sab.records.length && seen.add(a)) {
      final ar = sab.records[a];
      final names = <String>[];
      final ints = <int>[];
      for (final v in ar.fields) {
        if (v is int) ints.add(v);
        if (v is SabEnum) ints.add(v.v);
        if (v is String) names.add(v);
        if (v is SabIdent) names.add(v.s);
      }
      if (names.isNotEmpty) {
        final nm = names[0];
        if ((nm == _blend || nm == _sweep || nm == _matched) && ints.length >= 5) {
          (out[r.index] ??= []).add((nm, ints[4]));
        } else if (nm == _dep && ints.length >= 5) {
          final end = math.min(ints.length, 4 + ints[3]);
          for (var k = 4; k < end; k++) {
            (out[r.index] ??= []).add((nm, ints[k]));
          }
        }
      }
      final nxt = ar.ptrs;
      a = nxt.length > 2 ? nxt[2] : -1;
    }
  }
  return out;
}

class BrepInfo {
  final Sab sab;
  final Topo t;
  late final Map<int, List<(String, int)>> tags;
  final bodyOfFace = <int, int>{};
  final faces = <int>[];
  final _sd = <int, SurfDist>{};
  final _pts = <int, List<V3>>{};

  BrepInfo(this.sab) : t = Topo(sab) {
    tags = faceTags(sab);
    final bodies = t.bodies();
    for (var bi = 0; bi < bodies.length; bi++) {
      for (final sh in t.shells(bodies[bi])) {
        for (final f in t.faces(sh)) {
          bodyOfFace[f] = bi;
          faces.add(f);
        }
      }
    }
  }

  Set<int> allTagIds() => {for (final l in tags.values) for (final e in l) e.$2};

  List<int> facesOf(int? fid, Set<String>? kinds) {
    if (fid == null) return const [];
    return [
      for (final e in tags.entries)
        if (e.value.any((k) => k.$2 == fid && (kinds == null || kinds.contains(k.$1)))) e.key
    ];
  }

  Geom surface(int f) => surfaceOf(sab.records[t.faceInfo(f).surface]);
  SurfDist surfDist(int f) => _sd.putIfAbsent(f, () => SurfDist(surface(f)));

  List<V3> facePoints(int f) => _pts.putIfAbsent(f, () {
        final out = <V3>[];
        for (final lp in t.loops(f)) {
          for (final c in t.coedges(lp)) {
            final ei = t.edgeInfo(t.coedgeInfo(c).edge);
            out.add(t.vertexPoint(ei.v0) * 10);
            out.add(t.vertexPoint(ei.v1) * 10);
          }
        }
        return out;
      });

  V3? outwardNormalAt(int f, V3 pMm) {
    final g = surface(f);
    final fi = t.faceInfo(f);
    final s = (fi.reversed != g.reversed) ? -1.0 : 1.0;
    if (g.kind == 'plane') return g.normal * s;
    if (g.kind == 'cylinder') {
      final q = pMm * 0.1 - g.origin;
      final rad = q - g.axis * q.dot(g.axis);
      return rad.unit * s;
    }
    return null;
  }

  double? radiusMm(int f) {
    final g = surface(f);
    if (g.kind == 'cylinder') return g.radius * 10;
    if (g.kind == 'torus') return g.minorR.abs() * 10;
    return null;
  }
}

V3 _mean(List<V3> ps) {
  var s = const V3(0, 0, 0);
  for (final p in ps) {
    s = s + p;
  }
  return s * (1 / ps.length);
}

(V3, V3) _box(List<V3> ps) {
  var lo = ps.first, hi = ps.first;
  for (final p in ps) {
    lo = V3(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z));
    hi = V3(math.max(hi.x, p.x), math.max(hi.y, p.y), math.max(hi.z, p.z));
  }
  return (lo, hi);
}

// ------------------------------------------------------------------ surfaces
List<double> _fullKnots(List<(double, int)> k) {
  final out = <double>[];
  for (var i = 0; i < k.length; i++) {
    final m = k[i].$2 + ((i == 0 || i == k.length - 1) ? 1 : 0);
    for (var j = 0; j < m; j++) {
      out.add(k[i].$1);
    }
  }
  return out;
}

(int, List<double>) _basis(List<double> u, int p, double t) {
  final n = u.length - p - 2;
  int span;
  if (t >= u[n + 1]) {
    span = n;
  } else {
    var s = 0;
    while (s < u.length && u[s] <= t) {
      s++;
    }
    span = math.min(math.max(p, s - 1), n);
  }
  final nn = List<double>.filled(p + 1, 0)..[0] = 1;
  final left = List<double>.filled(p + 1, 0), right = List<double>.filled(p + 1, 0);
  for (var j = 1; j <= p; j++) {
    left[j] = t - u[span + 1 - j];
    right[j] = u[span + j] - t;
    var saved = 0.0;
    for (var r = 0; r < j; r++) {
      final den = right[r + 1] + left[j - r];
      final tmp = den != 0 ? nn[r] / den : 0.0;
      nn[r] = saved + right[r + 1] * tmp;
      saved = left[j - r] * tmp;
    }
    nn[j] = saved;
  }
  return (span, nn);
}

V3 evalSurface(BSpline bs, List<double> uk, List<double> vk, double u, double v) {
  final pu = bs.deg[0], pv = bs.deg[1];
  final (su, nu) = _basis(uk, pu, u);
  final (sv, nv) = _basis(vk, pv, v);
  var num = const V3(0, 0, 0);
  var den = 0.0;
  for (var a = 0; a <= pu; a++) {
    for (var b = 0; b <= pv; b++) {
      final i = su - pu + a, j = sv - pv + b;
      final w = bs.wgrid != null ? bs.wgrid![i][j] : 1.0;
      num = num + bs.grid[i][j] * (nu[a] * nv[b] * w);
      den += nu[a] * nv[b] * w;
    }
  }
  return num * (1 / den);
}

/// Distance from a point to a surface (model units).
class SurfDist {
  final Geom g;
  List<double>? _uk, _vk, _us, _vs;
  List<List<V3>>? _grid;

  SurfDist(this.g) {
    if (g.kind == 'bspline_surface') {
      final bs = g.bs!;
      _uk = _fullKnots(bs.knots[0]);
      _vk = _fullKnots(bs.knots[1]);
      final u0 = bs.knots[0].first.$1, u1 = bs.knots[0].last.$1;
      final v0 = bs.knots[1].first.$1, v1 = bs.knots[1].last.$1;
      _us = [for (var i = 0; i < 41; i++) u0 + (u1 - u0) * i / 40];
      _vs = [for (var i = 0; i < 41; i++) v0 + (v1 - v0) * i / 40];
      _grid = [
        for (final u in _us!) [for (final v in _vs!) evalSurface(bs, _uk!, _vk!, u, v)]
      ];
    }
  }

  double call(V3 p) {
    switch (g.kind) {
      case 'plane':
        return (p - g.origin).dot(g.normal).abs();
      case 'cylinder':
        final q = p - g.origin;
        return ((q - g.axis * q.dot(g.axis)).length - g.radius).abs();
      case 'cone':
        final q = p - g.origin;
        final h = q.dot(g.axis);
        final rad = (q - g.axis * h).length;
        return (rad - (g.radius + h * g.tan)).abs() / math.sqrt(1 + g.tan * g.tan);
      case 'torus':
        final q = p - g.origin;
        final h = q.dot(g.axis);
        final rad = (q - g.axis * h).length;
        final d = math.sqrt((rad - g.majorR) * (rad - g.majorR) + h * h);
        return (d - g.minorR.abs()).abs();
      case 'sphere':
        return ((p - g.origin).length - g.radius).abs();
      case 'bspline_surface':
        final bs = g.bs!;
        final us = _us!, vs = _vs!, grid = _grid!;
        var bi = 0, bj = 0;
        var best = double.infinity;
        for (var i = 0; i < us.length; i++) {
          for (var j = 0; j < vs.length; j++) {
            final d = (grid[i][j] - p).length;
            if (d < best) {
              best = d;
              bi = i;
              bj = j;
            }
          }
        }
        var u = us[bi], v = vs[bj];
        var du = us[1] - us[0], dv = vs[1] - vs[0];
        for (var it = 0; it < 40; it++) {
          var improved = false;
          for (final (su, sv) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final uu = (u + su * du).clamp(us.first, us.last);
            final vv = (v + sv * dv).clamp(vs.first, vs.last);
            final dd = (evalSurface(bs, _uk!, _vk!, uu, vv) - p).length;
            if (dd < best) {
              best = dd;
              u = uu;
              v = vv;
              improved = true;
            }
          }
          if (!improved) {
            du /= 2;
            dv /= 2;
            if (du < 1e-9) break;
          }
        }
        return best;
    }
    throw IptConversionException('no distance for a ${g.kind} surface');
  }
}

// ------------------------------------------------------------------ solids
/// Point-in-solid by ray parity against a closed triangle mesh.
class MeshSolid {
  final List<V3> a = [], e1 = [], e2 = [];
  late final V3 lo, hi;

  MeshSolid(Float64List pos, Int32List idx) {
    V3 vt(int i) => V3(pos[3 * i], pos[3 * i + 1], pos[3 * i + 2]);
    for (var t = 0; t + 2 < idx.length; t += 3) {
      final p0 = vt(idx[t]);
      a.add(p0);
      e1.add(vt(idx[t + 1]) - p0);
      e2.add(vt(idx[t + 2]) - p0);
    }
    final all = [for (var i = 0; i < pos.length ~/ 3; i++) vt(i)];
    final bb = all.isEmpty ? (const V3(0, 0, 0), const V3(0, 0, 0)) : _box(all);
    lo = bb.$1;
    hi = bb.$2;
  }

  int _hits(V3 p, V3 d) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      final h = d.cross(e2[i]);
      final det = e1[i].dot(h);
      if (det.abs() <= 1e-14) continue;
      final inv = 1 / det;
      final s = p - a[i];
      final u = s.dot(h) * inv;
      if (u < 0) continue;
      final q = s.cross(e1[i]);
      final v = q.dot(d) * inv;
      if (v < 0 || u + v > 1) continue;
      if (e2[i].dot(q) * inv > 1e-9) n++;
    }
    return n;
  }

  bool contains(V3 p) {
    if (p.x < lo.x || p.y < lo.y || p.z < lo.z || p.x > hi.x || p.y > hi.y || p.z > hi.z) {
      return false;
    }
    var votes = 0;
    for (final d in const [V3(0.5773, 0.5774, 0.5775), V3(-0.3, 0.8, 0.52), V3(0.71, -0.4, -0.58)]) {
      votes += _hits(p, d.unit) % 2;
    }
    return votes >= 2;
  }
}

// ------------------------------------------------------------------ profiles
int matchProfile(InvSketch sk, List<Profile> profs) {
  final fr = sk.frame!;
  final pts = [for (final p in sk.points.values) fr.origin + fr.x * p.x + fr.y * p.y];
  (double, int)? best;
  for (var pi = 0; pi < profs.length; pi++) {
    final pr = profs[pi];
    if ((pr.n.dot(fr.n).abs() - 1).abs() > 1e-6 || pr.loops.isEmpty || pts.isEmpty) continue;
    var d = 0.0;
    for (final (x, y, _) in pr.loops[0]) {
      final v = pr.to3d(x, y);
      var m = double.infinity;
      for (final q in pts) {
        m = math.min(m, (v - q).length);
      }
      d = math.max(d, m);
    }
    if (best == null || d < best.$1) best = (d, pi);
  }
  if (best == null || best.$1 > 1e-6) {
    throw IptConversionException('${sk.name}: no extrusion profile matches the sketch');
  }
  return best.$2;
}

bool _inside(List<(double, double, double)> loop, double px, double py) {
  var c = false;
  final n = loop.length;
  for (var i = 0; i < n; i++) {
    final (x0, y0, _) = loop[i];
    final (x1, y1, _) = loop[(i + 1) % n];
    if ((y0 > py) != (y1 > py) && px < x0 + (py - y0) * (x1 - x0) / (y1 - y0)) c = !c;
  }
  return c;
}

double _segDist(List<(double, double, double)> loop, double px, double py) {
  var d = 1e18;
  for (var i = 0; i < loop.length; i++) {
    final (x0, y0, _) = loop[i];
    final (x1, y1, _) = loop[(i + 1) % loop.length];
    final vx = x1 - x0, vy = y1 - y0;
    final l2 = vx * vx + vy * vy;
    final t = l2 == 0 ? 0.0 : (((px - x0) * vx + (py - y0) * vy) / l2).clamp(0.0, 1.0);
    final dx = px - x0 - t * vx, dy = py - y0 - t * vy;
    d = math.min(d, math.sqrt(dx * dx + dy * dy));
  }
  return d;
}

/// An interior point of the profile's region (3D) and its area (mm^2).
(V3, double) profileAnchor(Profile pr) {
  final outer = pr.loops[0];
  var area = 0.0;
  for (var i = 0; i < pr.loops.length; i++) {
    area += signedArea(pr.loops[i]).abs() * (i == 0 ? 1 : -1);
  }
  var a = 0.0, cx = 0.0, cy = 0.0;
  for (var i = 0; i < outer.length; i++) {
    final (x0, y0, _) = outer[i];
    final (x1, y1, _) = outer[(i + 1) % outer.length];
    final c = x0 * y1 - x1 * y0;
    a += c;
    cx += (x0 + x1) * c;
    cy += (y0 + y1) * c;
  }
  a /= 2;
  if (a != 0) {
    cx /= 6 * a;
    cy /= 6 * a;
  } else {
    cx = outer[0].$1;
    cy = outer[0].$2;
  }
  final holes = pr.loops.skip(1).toList();
  if (_inside(outer, cx, cy) && !holes.any((h) => _inside(h, cx, cy))) {
    return (pr.to3d(cx, cy), area);
  }
  final xs = [for (final p in outer) p.$1], ys = [for (final p in outer) p.$2];
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
  final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  (double, double, double)? best;
  for (var i = 1; i < 60; i++) {
    final gx = x0 + (x1 - x0) * i / 60;
    for (var j = 1; j < 60; j++) {
      final gy = y0 + (y1 - y0) * j / 60;
      if (!_inside(outer, gx, gy) || holes.any((h) => _inside(h, gx, gy))) continue;
      var d = _segDist(outer, gx, gy);
      for (final h in holes) {
        d = math.min(d, _segDist(h, gx, gy));
      }
      if (best == null || d > best.$1) best = (d, gx, gy);
    }
  }
  if (best == null) throw IptConversionException('a profile without an interior');
  return (pr.to3d(best.$2, best.$3), area);
}

// ------------------------------------------------------------------ semantics
(String, String, int?) _extrusionSemantics(InvFeature feat, InvSketch sk, Profile pr, BrepInfo brep,
    bool Function(int?) firstInBody, List<MeshSolid> solids, int? lastBody) {
  final fr = sk.frame!;
  final o = fr.origin, n = fr.n;
  final faces = brep.facesOf(feat.tag, {_sweep});
  String direction;
  final ld = feat.leader;
  if (ld != null) {
    final s0 = (ld.$1 - o).dot(n), s1 = (ld.$2 - o).dot(n);
    if ((s0 + s1).abs() < 1e-6 && s0.abs() > 1e-6) {
      direction = 'symmetric';
    } else {
      direction = (s1 - s0) > 0 ? 'default' : 'flipped';
    }
  } else {
    final side = <double>[
      for (final f in faces)
        for (final p in brep.facePoints(f))
          if ((p - o).dot(n).abs() > 1e-6) (p - o).dot(n)
    ];
    if (side.isNotEmpty && side.every((s) => s < 0)) {
      direction = 'flipped';
    } else if (side.isNotEmpty && side.every((s) => s > 0)) {
      direction = 'default';
    } else {
      direction = 'symmetric';
    }
  }
  // operation, from a side face: does its outward normal point away from the
  // profile (material added) or into it (material removed)?
  final anchor = profileAnchor(pr).$1;
  var votes = 0;
  int? body;
  for (final f in faces) {
    final g = brep.surface(f);
    if (g.kind != 'plane' || g.normal.dot(n).abs() > 1e-6) continue; // side faces only
    final c = _mean(brep.facePoints(f));
    final nrm = brep.outwardNormalAt(f, c)!;
    var radial = c - anchor;
    radial = radial - n * radial.dot(n);
    if (radial.length < 1e-9) continue;
    votes += nrm.dot(radial) > 0 ? 1 : -1;
    body = brep.bodyOfFace[f];
  }
  if (body == null && faces.isNotEmpty) body = brep.bodyOfFace[faces[0]];
  if (votes == 0 && solids.isNotEmpty) {
    // No face of Inventor's result still carries this feature's tag (a later
    // feature re-tagged them). Ask the result itself: is the extruded region
    // material, or empty?
    double mid;
    if (direction == 'symmetric') {
      mid = 0;
    } else if (ld != null) {
      final l = (ld.$2 - ld.$1).length;
      mid = direction == 'default' ? l / 2 : -l / 2;
    } else {
      mid = direction == 'default' ? 0.5 : -0.5;
    }
    int? inside;
    final p = anchor + n * mid;
    for (var bi = 0; bi < solids.length; bi++) {
      if (solids[bi].contains(p)) inside = bi;
    }
    if (inside == null) {
      votes = -1;
      body = lastBody;
    } else {
      votes = 1;
      body = inside;
    }
  }
  final output = votes >= 0 ? (firstInBody(body) ? 'new' : 'join') : 'cut';
  return (direction, output, body);
}

double _gap(double r, double dihedralDeg) {
  final h = dihedralDeg * math.pi / 360;
  return r * (1 / math.max(math.cos(h), 1e-9) - 1);
}

List<OcctEdgeInfo> _matchEdges(OcctShape shape, double r, List<int> blendFaces, BrepInfo brep,
    {double tol = 0.005}) {
  final out = <OcctEdgeInfo>[];
  final boxes = {for (final f in blendFaces) f: _box(brep.facePoints(f))};
  for (final e in shape.allEdges()) {
    if (e.faceCount != 2 || e.dihedralDeg < 1 || e.length < 1e-6) continue;
    final m = V3(e.mx, e.my, e.mz);
    final g = _gap(r, e.dihedralDeg);
    for (final f in blendFaces) {
      final (lo, hi) = boxes[f]!;
      final pad = 3 * r;
      if (m.x < lo.x - pad || m.y < lo.y - pad || m.z < lo.z - pad) continue;
      if (m.x > hi.x + pad || m.y > hi.y + pad || m.z > hi.z + pad) continue;
      if ((brep.surfDist(f)(m * 0.1) * 10 - g).abs() < tol) {
        out.add(e);
        break;
      }
    }
  }
  return out;
}

Map<String, Object?> _edgeSel(OcctEdgeInfo e) => {
      'm': [e.mx, e.my, e.mz],
      'l': e.length,
      'k': (e.kind >= 1 && e.kind <= 3) ? e.kind : 4,
      'r': e.radius,
    };

// ------------------------------------------------------------------ helpers
const _bodyNamePattern =
    r'^(Solid|Volumenkörper|Volumen|Corps|Cuerpo|Corpo|Body|Körper)\s?\d+$';

List<String> _bodyNames(Dc dc, int n) {
  final pat = RegExp(_bodyNamePattern);
  final named = dc.namedObjects().entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final found = [for (final e in named) if (pat.hasMatch(e.key)) e.key];
  final out = [for (var i = 0; i < n; i++) i < found.length ? found[i] : 'Solid${i + 1}'];
  final seen = <String>{};
  for (var i = 0; i < out.length; i++) {
    var s = out[i];
    while (seen.contains(s)) {
      s = "$s'";
    }
    out[i] = s;
    seen.add(s);
  }
  return out;
}

/// An isometric camera fitted to the part, the app's fitViewCamera rule.
Map<String, Object?> _camera(Sab sab) {
  final t = Topo(sab);
  final unit = sab.unitMm;
  const az = math.pi / 4, pol = 0.955;
  final s = V3(math.cos(az), 0, -math.sin(az));
  final d = V3(math.sin(pol) * math.sin(az), math.cos(pol), math.sin(pol) * math.cos(az));
  final u = s.cross(d * -1).unit;
  final pts = [for (final r in sab.records) if (r.type == 'vertex') t.vertexPoint(r.index) * unit];
  if (pts.isEmpty) return {'az': az, 'pol': pol, 'h': 27.0, 'ox': 0.0, 'oy': 0.0};
  final ss = [for (final p in pts) p.dot(s)], uu = [for (final p in pts) p.dot(u)];
  final sMin = ss.reduce(math.min), sMax = ss.reduce(math.max);
  final uMin = uu.reduce(math.min), uMax = uu.reduce(math.max);
  final half = math.max((uMax - uMin) / 2, (sMax - sMin) / 2) / 0.82;
  return {
    'az': az,
    'pol': pol,
    'h': half > 1e-6 ? half : 27.0,
    'ox': (sMax + sMin) / 2,
    'oy': (uMax + uMin) / 2,
  };
}

List<double> _placeMat(V3 u, V3 v, V3 n, V3 o, double z0) => [
      u.x, v.x, n.x, o.x + n.x * z0, //
      u.y, v.y, n.y, o.y + n.y * z0,
      u.z, v.z, n.z, o.z + n.z * z0,
    ];

/// A value converted from cm or rad, without the last-bit noise of the
/// conversion (0.6 cm is 6 mm, not 6.000000000000001).
double _clean(double v) => v == 0 || !v.isFinite ? v : double.parse(v.toStringAsPrecision(12));

String _fmtG(double v) {
  // Python's '{:g}' for the values a dimension carries
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsPrecision(6);
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

Map<String, Object?> _info(IptFile ipt, String sourceName, List<String> bodyNames) => {
      'source_name': sourceName,
      'source_sha256': _sha(ipt.raw),
      'metadata': ipt.metadata(),
      'bodies': [for (final b in bodyNames) {'name': b}],
    };

Uint8List _json(Object o) => utf8.encode(jsonEncode(o));
Uint8List _prettyJson(Object o) => utf8.encode(const JsonEncoder.withIndent('  ').convert(o));

// ------------------------------------------------------------------ entry
/// Converts an Inventor part. Tries the full feature tree first and falls
/// back to the exact bodies; throws only when not even those can be read.
IptConversion convertIpt(Uint8List raw, String name, {String sourceName = '', OcctFfi? ffi}) {
  final log = <String>[];
  final ipt = IptFile(raw);
  final src = sourceName.isEmpty ? '$name.ipt' : sourceName;
  final k = ffi ?? OcctFfi.instance();
  String? why;
  if (k != null) {
    try {
      return IptConversion(_convertFull(ipt, name, src, k, log), true, null, log);
    } catch (e) {
      why = '$e';
      log.add('full feature tree not convertible ($e); exact bodies instead');
    }
  } else {
    why = 'no modelling kernel';
  }
  return IptConversion(_convertBodies(ipt, name, src), false, why, log);
}

/// [convertIpt] on a background isolate: the replay runs the modelling
/// kernel feature by feature, which can take a while on a part whose blends
/// the kernel has to try hard at, and the UI must not freeze meanwhile.
Future<IptConversion> convertIptInBackground(Uint8List raw, String name, String sourceName) =>
    Isolate.run(() => convertIpt(raw, name, sourceName: sourceName));

Sab _brep(IptFile ipt) {
  final seg = ipt.segments()['PmBRepSegment'];
  if (seg == null) throw IptConversionException('the file has no part geometry (not a part?)');
  return parseSab(seg.data);
}

/// The exact bodies as imported solids, no feature tree (ipt2ptp/1).
Uint8List _convertBodies(IptFile ipt, String name, String src) {
  final sab = _brep(ipt);
  final nb = sab.ofType('body').length;
  final dcSeg = ipt.segments()['PmDCSegment'];
  List<String> names;
  try {
    names = dcSeg == null
        ? [for (var i = 0; i < nb; i++) 'Solid${i + 1}']
        : _bodyNames(Dc(dcSeg.data, dcSeg.meta), nb);
  } catch (_) {
    names = [for (var i = 0; i < nb; i++) 'Solid${i + 1}'];
  }
  final md = ipt.metadata();
  final r = brepToStep(sab,
      names: names, product: (md['part_number'] as String?) ?? name, author: (md['author'] as String?) ?? '');
  final stepEntry = 'imports/$name.step';
  final features = [
    for (var i = 0; i < r.names.length; i++)
      {
        'kind': 'extrude', 'name': 'Import${i + 1}', 'seq': i, 'body': r.names[i],
        'visible': true, 'output': 'new',
        'imported': true, 'importPath': stepEntry, 'importIndex': i,
        'sketch': '', 'profiles': [], 'dir': 'default',
        'a': 5.0, 'b': 5.0, 'taper': 0.0,
        'exprA': '5 mm', 'exprB': '5 mm', 'exprTaper': '0.00 deg',
        'imate': false, 'match': true, 'extent': 'distance',
      }
  ];
  final meta = {
    'version': 1, 'type': 'part',
    'vis': {for (final k in ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']) k: false},
    'cam': _camera(sab),
    'sketches': [],
    'features': features,
    'featureN': features.length, 'solidN': features.length, 'seqNext': features.length,
  };
  final entries = <String, Uint8List>{
    'meta.json': _json(meta),
    stepEntry: ascii.encode(r.step),
    kIptSourceEntry: ipt.raw,
  };
  final thumb = ipt.thumbnailPng();
  if (thumb != null) entries['preview.png'] = Uint8List.fromList(thumb);
  final info = {
    'converter': kIptConverterBodies,
    ..._info(ipt, src, r.names),
    // what ptp2ipt checks: the imported bodies, unchanged
    'features': [for (final f in features) [f['name'], f['kind'], f['body']]],
    'cached': [],
  };
  entries[kIptInfoEntry] = _prettyJson(info);
  return DocFile('part', entries).encode();
}

Uint8List _convertFull(IptFile ipt, String name, String src, OcctFfi k, List<String> log) {
  final dcSeg = ipt.segments()['PmDCSegment'];
  if (dcSeg == null) throw IptConversionException('the file has no design data');
  final sab = _brep(ipt);
  final brep = BrepInfo(sab);
  final part = InventorPart(dcSeg.data, dcSeg.meta);
  final dc = part.dc;
  final profs = profiles(dcSeg.data);
  final mains = dc.sketchMains();
  final feats = timeline(dc, mains, part.params, brep.allTagIds());
  if (feats.isEmpty) throw IptConversionException('no features found');
  final sketches = {for (final s in part.sketches) s.main: s};

  // ---- sketches
  final appSketches = <int, AppSketch>{};
  for (final s in part.sketches) {
    final a = convertSketch(s);
    final (worst, bad) = checkSketch(a);
    if (bad.isNotEmpty) {
      throw IptConversionException('${s.name}: ${bad.length} constraint(s) not satisfied after conversion');
    }
    appSketches[s.main] = a;
    log.add('sketch ${s.name}: ${a.geos.length} entities, ${a.cons.length} constraints '
        '(worst residual ${worst.toStringAsExponential(1)})');
  }

  final bodyNames = _bodyNames(dc, sab.ofType('body').length);
  final seenBody = <int?>{};
  bool firstInBody(int? bi) => !seenBody.contains(bi);

  final md = ipt.metadata();
  final step = brepToStep(sab, names: bodyNames, product: name, author: (md['author'] as String?) ?? '');
  final owned = <OcctShape>[];
  final bodies = <int, OcctShape>{};
  try {
    // Inventor's result, as solids to classify points against
    final tmp = File('${Directory.systemTemp.path}/ipt2ptp_${DateTime.now().microsecondsSinceEpoch}.step');
    tmp.writeAsStringSync(step.step);
    final solids = <MeshSolid>[];
    try {
      for (final s in k.importStepSolids(tmp.path)) {
        final m = s.mesh(linDeflection: 0.02, angDeflection: 0.1);
        if (m != null) solids.add(MeshSolid(m.positions, m.indices));
        s.dispose();
      }
    } finally {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }

    int? lastBody;
    final features = <Map<String, Object?>>[];
    final sketchRows = <Map<String, Object?>>[];
    final usedSketches = <int>{};
    var seq = 0;
    final filletFacesUsed = <int>{};
    void setBody(int bi, OcctShape s) {
      bodies[bi] = s;
      owned.add(s);
    }

    for (final f in feats) {
      if (f.kind == 'extrude') {
        final sk = sketches[f.sketch];
        final a = appSketches[f.sketch];
        if (sk == null || a == null) throw IptConversionException('${f.name}: its sketch was not found');
        final pr = profs[matchProfile(sk, profs)];
        final (direction, output, bi) =
            _extrusionSemantics(f, sk, pr, brep, firstInBody, solids, lastBody);
        if (bi == null) throw IptConversionException('${f.name}: no body');
        seenBody.add(bi);
        lastBody = bi;
        final dist = f.params.isNotEmpty ? _clean(part.params[f.params[0]]!.value * 10) : 0.0;
        final taper =
            f.params.length > 1 ? _clean(part.params[f.params[1]]!.value * 180 / math.pi) : 0.0;
        final extent = f.extent;
        // the sketch comes first in the timeline; a sketch on a face records
        // WHICH face, measured on the body built up to here, so an edit that
        // moves the face takes the sketch along -- as in Inventor
        if (usedSketches.add(f.sketch!)) {
          final row = _sketchRow(a, seq);
          if (a.plane == 'face' && bodies.isNotEmpty) {
            final ref = _faceRef(bodies.values, sk, profileAnchor(pr).$1);
            if (ref != null) row['faceRef'] = ref;
          }
          sketchRows.add(row);
          seq++;
        }
        final sels = _profileSels(a, pr, f.name);
        final h = extent == 'distance' ? dist : 1000.0;
        final st = switch (direction) { 'default' => 0.0, 'flipped' => -h, _ => -h / 2 };
        final sSign = pr.n.dot(sk.frame!.n) > 0 ? 1.0 : -1.0;
        final start = sSign > 0 ? st : -(st + h);
        final loops = [
          for (final l in pr.loops) [for (final (x, y, b) in l) ...[x, y, b]]
        ];
        final raw = k.extrudeProfileArcs(loops, h, taperDeg: taper);
        if (raw == null) throw IptConversionException('${f.name}: extrude failed: ${k.lastError()}');
        final tool = raw.transformed(_placeMat(pr.u, pr.v, pr.n, pr.origin, start));
        raw.dispose();
        if (tool == null) throw IptConversionException('${f.name}: placement failed');
        owned.add(tool);
        if (output == 'new') {
          bodies[bi] = tool;
        } else {
          final base = bodies[bi];
          if (base == null) throw IptConversionException('${f.name}: $output into a body not made yet');
          final r = output == 'cut' ? k.cut(base, tool) : k.fuse(base, tool);
          if (r == null) throw IptConversionException('${f.name}: $output failed: ${k.lastError()}');
          setBody(bi, r);
        }
        log.add('${f.name}: extrude $direction $extent ${_fmtG(dist)} mm $output -> ${bodyNames[bi]} '
            '(volume ${bodies[bi]!.volume.toStringAsFixed(3)})');
        features.add({
          'kind': 'extrude', 'name': f.name, 'seq': seq, 'body': bodyNames[bi],
          'visible': true, 'output': output, 'sketch': a.name,
          'profiles': sels,
          'dir': direction, 'a': extent == 'distance' ? dist : 5.0, 'b': 0.0,
          'taper': taper, 'exprA': extent == 'distance' ? '${_fmtG(dist)} mm' : '5 mm',
          'exprB': '0 mm', 'exprTaper': '${taper.toStringAsFixed(2)} deg', 'imate': false, 'match': true,
          'extent': extent,
        });
        seq++;
      } else {
        if (f.params.isEmpty) throw IptConversionException('${f.name}: a fillet without its radius');
        final r = _clean(part.params[f.params[0]]!.value * 10);
        final blend = brep.facesOf(f.tag, {_blend});
        if (bodies.isEmpty) throw IptConversionException('${f.name}: a fillet before any body');
        final bi = blend.isNotEmpty ? brep.bodyOfFace[blend[0]]! : bodies.keys.first;
        final base = bodies[bi];
        if (base == null) throw IptConversionException('${f.name}: its body was not built');
        var es = _matchEdges(base, r, blend, brep);
        if (f.edgeCount != null && es.length < f.edgeCount!) {
          // faces a LATER feature re-tagged (FEATURE_DEPENDENCY) lost this
          // fillet's tag; offer the unclaimed ones of this radius
          final extra = [
            for (final fc in brep.faces)
              if (!filletFacesUsed.contains(fc) &&
                  (brep.tags[fc] ?? const []).any((t) => t.$1 == _dep) &&
                  brep.radiusMm(fc) != null &&
                  (brep.radiusMm(fc)! - r).abs() < 1e-6)
                fc
          ];
          final es2 = _matchEdges(base, r, [...blend, ...extra], brep);
          if (es2.length > es.length) {
            filletFacesUsed.addAll(extra);
            es = es2;
          }
        }
        filletFacesUsed.addAll(blend);
        final picked = [for (final e in es) if (e.length > 0.05) e];
        var note = '';
        if (picked.isNotEmpty) {
          final rep = BlendReport();
          final built = base.filletEdges([for (final e in picked) e.index],
              List.filled(picked.length, r), report: rep);
          if (built != null) {
            setBody(bi, built);
            if (rep.dropped.isNotEmpty) note = ' (${rep.dropped.length} edges not built by the kernel)';
          } else {
            note = ' (not built by the kernel)';
          }
        }
        log.add('${f.name}: fillet r=${_fmtG(r)} mm, ${picked.length} edges '
            '(Inventor stored ${f.edgeCount})$note');
        features.add({
          'kind': 'fillet', 'name': f.name, 'seq': seq, 'body': bodyNames[bi], 'visible': true,
          'output': 'join', 'edges': [for (final e in picked) _edgeSel(e)],
          'radii': List.filled(picked.length, r),
          'exprRadius': '${_fmtG(r)} mm', 'allFillets': false, 'allRounds': false,
        });
        seq++;
      }
    }
    // sketches no feature uses still belong to the part
    for (final s in part.sketches) {
      if (usedSketches.add(s.main)) {
        sketchRows.add(_sketchRow(appSketches[s.main]!, seq));
        seq++;
      }
    }

    // ---- exact results: the whole of Inventor's result per body
    final lastOfBody = <String, int>{};
    for (var i = 0; i < features.length; i++) {
      lastOfBody[features[i]['body'] as String] = i;
    }
    lastOfBody.forEach((b, i) {
      features[i]['cache'] = {'step': kIptResultEntry, 'index': bodyNames.indexOf(b), 'sig': '*'};
    });

    final meta = {
      'version': 1, 'type': 'part',
      'vis': {for (final k in ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']) k: false},
      'cam': _camera(sab),
      'sketches': sketchRows,
      'features': features,
      'featureN': features.length, 'solidN': bodyNames.length, 'seqNext': seq,
    };
    final entries = <String, Uint8List>{
      'meta.json': _json(meta),
      kIptResultEntry: ascii.encode(step.step),
      kIptSourceEntry: ipt.raw,
    };
    for (final a in appSketches.values) {
      entries.addAll(sketchFiles(a));
    }
    final thumb = ipt.thumbnailPng();
    if (thumb != null) entries['preview.png'] = Uint8List.fromList(thumb);
    final info = {
      'converter': kIptConverterFull,
      ..._info(ipt, src, step.names),
      'parameters': {for (final e in part.params.entries) e.key: e.value.value},
      // What ptp2ipt / the app check to know the part is still Inventor's:
      // the same feature list, and every stored result still in place -- the
      // app drops a stored result exactly when an edit changes the tree under it.
      'features': [for (final fe in features) [fe['name'], fe['kind'], fe['body']]],
      'cached': [for (final fe in features) if (fe.containsKey('cache')) fe['name']],
    };
    entries[kIptInfoEntry] = _prettyJson(info);
    return DocFile('part', entries).encode();
  } finally {
    for (final s in owned) {
      s.dispose();
    }
  }
}

/// The app's profile picks for an Inventor profile: every region the app
/// finds in the sketch -- with the app's own region rule, so the fold
/// re-matches them as they are -- whose interior lies in Inventor's profile.
/// Inventor builds one profile from several adjacent regions where the
/// sketch divides it; the app keeps them as one pick each.
List<Map<String, Object?>> _profileSels(AppSketch a, Profile pr, String feature) {
  final geos = [
    for (final g in a.geos)
      // an app arc carries a sixth value, its direction (0: counter-clockwise)
      Geo(g.type, g.type == Geo.arc ? [...g.data, 0] : g.data,
          layer: kSketchLayer, spline: g.tag ?? Geo.straight, style: g.style)
  ];
  final regions = regionsFrom(profileLoopsOf(ProfileInput(geos, const [kSketchLayer], const {}, 1)));
  // Inventor's loops in the sketch's 2D frame, arcs sampled
  final polys = <List<Offset>>[];
  for (final loop in pr.loops) {
    final pts = <Offset>[];
    for (var i = 0; i < loop.length; i++) {
      final (x0, y0, b) = loop[i];
      final (x1, y1, _) = loop[(i + 1) % loop.length];
      final steps = b == 0 ? 1 : 24;
      final th = 4 * math.atan(b);
      final c = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      for (var k = 0; k < steps; k++) {
        var x = x0, y = y0;
        if (b != 0 && c > 0) {
          // point on the bulged arc at fraction k/steps of the sweep
          final r = c / (2 * math.sin(th / 2));
          final mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
          final d = r * math.cos(th / 2);
          final nx = -(y1 - y0) / c, ny = (x1 - x0) / c;
          final cx = mx + nx * d, cy = my + ny * d;
          final a0 = math.atan2(y0 - cy, x0 - cx);
          final an = a0 + th * k / steps;
          x = cx + r.abs() * math.cos(an);
          y = cy + r.abs() * math.sin(an);
        }
        final (u, v) = _toApp2d(a, pr.to3d(x, y));
        pts.add(Offset(u, v));
      }
    }
    polys.add(pts);
  }
  final out = <Map<String, Object?>>[];
  var got = 0.0;
  for (final r in regions) {
    final an = regionAnchor(r);
    if (!pointInPolygon(an, polys[0])) continue;
    if (polys.skip(1).any((h) => pointInPolygon(an, h))) continue;
    out.add({'x': an.dx, 'y': an.dy, 'a': r.outer.area});
    got += r.outer.area - r.holes.fold<double>(0, (s, h) => s + h.area);
  }
  final want = profileAnchor(pr).$2;
  if (out.isEmpty || (got - want).abs() > 0.005 * want + 0.5) {
    throw IptConversionException('$feature: the sketch regions do not make up the Inventor profile '
        '(${got.toStringAsFixed(2)} of ${want.toStringAsFixed(2)} mm²)');
  }
  return out;
}

Map<String, Object?> _sketchRow(AppSketch a, int seq) {
  final row = <String, Object?>{'name': a.name, 'plane': a.plane, 'vis': false, 'seq': seq};
  final fr = a.frame;
  if (a.plane == 'face' && fr != null) {
    final (u, v, n, o) = fr;
    row['frame'] = [u.x, u.y, u.z, v.x, v.y, v.z, n.x, n.y, n.z, o.x, o.y, o.z];
  }
  return row;
}

(double, double) _toApp2d(AppSketch a, V3 p) {
  if (a.plane == 'face') {
    final (u, v, _, o) = a.frame!;
    return ((p - o).dot(u), (p - o).dot(v));
  }
  final (u, v, _) = kAppPlanes[a.plane]!;
  return (p.dot(u), p.dot(v));
}

/// The planar face the sketch lies on, as the app records it.
Map<String, Object?>? _faceRef(Iterable<OcctShape> bodies, InvSketch sk, V3 anchor) {
  final fr = sk.frame!;
  final n = fr.n;
  (double, V3, V3, double)? best;
  for (final shape in bodies) {
    final m = shape.mesh(linDeflection: 0.02, angDeflection: 0.1);
    if (m == null) continue;
    for (final r in planarFaceRecs(m)) {
      final c = V3(r.c.x, r.c.y, r.c.z), rn = V3(r.n.x, r.n.y, r.n.z);
      if (rn.dot(n) < 0.999) continue;
      if ((c - fr.origin).dot(n).abs() > 1e-6) continue; // not in the sketch plane
      final dv = c - anchor;
      final d = (dv - n * dv.dot(n)).length;
      if (best == null || d < best.$1) best = (d, c, rn, r.area);
    }
  }
  if (best == null) return null;
  final (_, c, rn, area) = best;
  return {
    'c': [c.x, c.y, c.z],
    'n': [rn.x, rn.y, rn.z],
    'a': area,
  };
}

// ------------------------------------------------------------------ back to .ipt
/// Why a part cannot be written back as an .ipt, or null when it can: the
/// embedded original is written byte for byte, so it must still BE the part.
String? iptExportBlocker(Map<String, Uint8List> entries, Map<String, Object?> meta) {
  final src = entries[kIptSourceEntry];
  final infoB = entries[kIptInfoEntry];
  if (src == null || infoB == null) return 'not-from-inventor';
  final Map info;
  try {
    info = jsonDecode(utf8.decode(infoB)) as Map;
  } catch (_) {
    return 'damaged';
  }
  if (_sha(src) != info['source_sha256']) return 'damaged';
  final feats = (meta['features'] as List?) ?? const [];
  final now = [
    for (final f in feats) [(f as Map)['name'], f['kind'], f['body']]
  ];
  final was = (info['features'] as List?) ?? const [];
  if (jsonEncode(now) != jsonEncode(was)) return 'edited';
  final cachedNow = {
    for (final f in feats)
      if ((f as Map)['cache'] is Map) f['name']
  };
  for (final c in (info['cached'] as List?) ?? const []) {
    if (!cachedNow.contains(c)) return 'edited';
  }
  // the bodies-only form: the imported STEP must be the one written
  if (info['converter'] == kIptConverterBodies) {
    for (final f in feats) {
      final p = (f as Map)['importPath'];
      if (p is String && !entries.containsKey(p)) return 'edited';
    }
  }
  return null;
}
