// THE ASSISTANT BENCHMARK — does a change make the assistant better or worse?
//
// It runs the real controller loop, against a real provider, on the real
// OpenCascade kernel, for the requests users actually made, and scores the
// part the app measures at the end — never the model's account of it. It
// also times what a user feels: seconds to the first executed CAD operation,
// and the whole turn against the time a skilled person needs in a desktop
// CAD tool for the same part (`refSeconds`, ~8 s per operation a pro uses).
//
//   AI_BENCH=live AI_BENCH_KEY=... PROTOTYPE_NATIVE_DIR=... \
//   flutter test test/bench/ai_bench_test.dart
//
//   AI_BENCH=replay  — each scenario's canned replies instead of a model: no
//                      key, deterministic, proves the harness and the checks.
//
//   AI_BENCH_ONLY=cup,spool   only these scenarios
//   AI_BENCH_SET=main|holdout|all   (default main; `holdout` is never tuned on)
//   AI_BENCH_PARALLEL=6       scenarios run at once (default 1)
//   AI_BENCH_REPEAT=3         runs of each scenario (creative ones: at least 3)
//   AI_BENCH_OUT=run.json     the report
//   AI_BENCH_RENDER=dir       a PNG of every finished part, three views
//   AI_BENCH_PROVIDER / AI_BENCH_MODEL   default deepseek / deepseek-flash
//
// Without AI_BENCH set, or without the kernel, it SKIPS.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_store.dart';
import 'package:prototype/ai/ai_trace.dart';
import 'package:prototype/ai/mesh_topology.dart';
import 'package:prototype/ai/printability.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'bench_geometry.dart';

/// Answers from a script instead of a model.
class _ReplayBackend implements AiBackend {
  _ReplayBackend(this.replies);
  final List<String> replies;
  var _next = 0;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider,
          label: 'Replay',
          available: true,
          supportsImages: false);
  @override
  Future<bool> hasKey(AiProvider provider) async => true;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    final text = _next < replies.length ? replies[_next++] : 'Fertig.';
    request.onStream?.call(AiStreamStage.writing);
    return AiReply(text, 'replay');
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}

AiProvider _provider(String name) => AiProvider.values.firstWhere(
    (p) => p.name == name,
    orElse: () => throw ArgumentError('AI_BENCH_PROVIDER "$name" is not one '
        'of ${AiProvider.values.map((p) => p.name).join(", ")}'));

/// A real HTTP client: flutter_test replaces HttpClient with one that answers
/// 400 to everything, and the container reaches the internet through a proxy.
IOClient _realClient() {
  HttpOverrides.global = null;
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..idleTimeout = const Duration(seconds: 30);
  return IOClient(client);
}

Tri _tri(KernelSolid s) => Tri(s.mesh.positions, s.mesh.indices);

/// A body's mesh at a fine tessellation, for measurements to ±0.05 mm.
Tri? _body(PartModel p, String name) {
  final s = currentBodySolid(p, name);
  if (s == null) return null;
  // Fine enough for ±0.05 mm on a small part, without drowning a vase in
  // millions of triangles: a four-thousandth of its size.
  final b = Tri(s.mesh.positions, s.mesh.indices).bounds();
  final diag = math.sqrt(math.pow(b[3] - b[0], 2) +
      math.pow(b[4] - b[1], 2) + math.pow(b[5] - b[2], 2));
  final lin = (diag / 4000).clamp(0.004, 0.05);
  if ((s.meshLin - lin).abs() > 1e-9) s.refine(lin, 0.1);
  return _tri(s);
}

List<String> _bodies(PartModel p) => [
      for (final (name, _) in p.solidBodies())
        if (currentBodySolid(p, name) != null &&
            p.features.any((f) =>
                f.bodyName == name && f.visible && !f.rolledBack))
          name
    ];

/// What the app measured about the finished part.
Map<String, dynamic> _measure(AppState app, Set<String> before) {
  final p = app.currentPart!;
  var volume = 0.0, pieces = 0;
  final all = _bodies(p);
  final fresh = [for (final b in all) if (!before.contains(b)) b];
  final meshes = [for (final b in fresh) _body(p, b)].whereType<Tri>();
  for (final b in fresh) {
    final s = currentBodySolid(p, b)!;
    volume += s.volume;
    pieces += meshComponentCount(s.mesh);
  }
  final m = Tri.merge(meshes);
  final bb = m.pos.isEmpty ? const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] : m.bounds();
  final size = [bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2]];
  final box = size[0] * size[1] * size[2];
  final newFeatures = [
    for (final f in p.features)
      if (!f.rolledBack && fresh.contains(f.bodyName) || !f.rolledBack && f.bodyName.isEmpty)
        f.kind
  ];
  return {
    'bodies': all.length,
    'newBodies': fresh,
    'pieces': pieces,
    'volumeMm3': volume,
    'sizeMm': size,
    'box': bb,
    'fill': box > 0 ? volume / box : 0,
    'features': [for (final f in p.features) if (!f.rolledBack) f.kind],
    'newFeatures': newFeatures,
    'overhangs': [
      for (final b in fresh)
        if (currentBodySolid(p, b) != null)
          ...overhangReport(currentBodySolid(p, b)!.mesh)
    ],
    'sick': [
      for (final f in p.features)
        if (!f.rolledBack && f.computeError != null) f.name
    ],
  };
}

double _n(Object? v) => (v as num).toDouble();

/// Faces of the part, by the app's own `faces_where` (exact B-Rep values).
Future<List<Map<String, dynamic>>> _faces(AppState app,
    Map<String, dynamic> args) async {
  final r = await AiCad(app).run([AiAction('faces_where', {'limit': 200, ...args})]);
  if (r.outcomes.isEmpty || !r.outcomes.first.ok) return const [];
  final faces = r.outcomes.first.detail?['faces'];
  return faces is List ? faces.cast<Map<String, dynamic>>() : const [];
}

/// The capacity of an open vessel: area enclosed by material, section by
/// section, from the bottom to the top of the part, in ml.
double _capacityMl(Tri m, {double dy = 0.25}) {
  final b = m.bounds();
  var v = 0.0;
  for (var y = b[1] + dy / 2; y < b[4]; y += dy) {
    v += slice(m, 1, y).enclosed * dy;
  }
  return v / 1000;
}

/// Every check that failed, as a sentence. Empty is a pass.
Future<List<String>> _check(AppState app, Map<String, dynamic> m,
    Map<String, dynamic> c, Set<String> before) async {
  final p = app.currentPart!;
  final fresh = (m['newBodies'] as List).cast<String>();
  final freshMeshes = {
    for (final b in fresh)
      if (_body(p, b) != null) b: _body(p, b)!
  };
  final ctx = _Ctx(
      m,
      Tri.merge(freshMeshes.values),
      freshMeshes,
      [
        for (final b in _bodies(p))
          if (!fresh.contains(b) && _body(p, b) != null) _body(p, b)!
      ],
      await _faces(app, {'type': 'cylinder'}),
      await _faces(app, {'type': 'cone'}));
  final (failures, measured) = await Isolate.run(() {
    final f = _pureCheck(ctx, c);
    return (f, ctx.m);
  });
  m.addAll(measured);
  return failures;
}

List<String> _pureCheck(_Ctx x, Map<String, dynamic> c) {
  final out = <String>[];
  final m = x.m, mesh = x.mesh;
  final size = (m['sizeMm'] as List).cast<double>();
  if (c['bodies'] != null && m['bodies'] != c['bodies']) {
    out.add('bodies ${m['bodies']} != ${c['bodies']}');
  }
  if (c['pieces'] != null && m['pieces'] != c['pieces']) {
    out.add('pieces ${m['pieces']} != ${c['pieces']}');
  }
  if (c['noSick'] == true && (m['sick'] as List).isNotEmpty) {
    out.add('features that do not build: ${m['sick']}');
  }
  if (c['maxFill'] != null && _n(m['fill']) > _n(c['maxFill'])) {
    out.add('fills ${_n(m['fill']).toStringAsFixed(2)} of its box — '
        'a slab, not the part (max ${c['maxFill']})');
  }
  final big = size.fold<double>(0, math.max);
  if (c['sizeMax'] != null && big > _n(c['sizeMax'])) {
    out.add('largest size ${big.toStringAsFixed(1)} > ${c['sizeMax']}');
  }
  if (c['sizeMin'] != null && big < _n(c['sizeMin'])) {
    out.add('largest size ${big.toStringAsFixed(1)} < ${c['sizeMin']}');
  }
  final ranges = c['size'];
  if (ranges is Map) {
    for (final (i, axis) in const [(0, 'x'), (1, 'y'), (2, 'z')]) {
      final r = ranges[axis];
      if (r is List && (size[i] < _n(r[0]) || size[i] > _n(r[1]))) {
        out.add('$axis size ${size[i].toStringAsFixed(2)} outside $r');
      }
    }
  }
  // Sizes in any orientation: the three extents, sorted, against sorted
  // targets — for a request that names dimensions but not which axis.
  final dims = c['dims'];
  if (dims is List) {
    final want = [for (final d in dims) _n(d)]..sort();
    final got = [...size]..sort();
    final tol = _n(c['dimsTol'] ?? 0.1);
    for (var i = 0; i < 3; i++) {
      if ((got[i] - want[i]).abs() > tol) {
        out.add('dimensions ${got.map((d) => d.toStringAsFixed(2)).join(" × ")}'
            ' ≠ ${want.join(" × ")} ±$tol');
        break;
      }
    }
  }
  final near = c['volumeNear'];
  if (near is Map) {
    final want = _n(near['value']);
    final tol = _n(near['tolerance']);
    final got = _n(m['volumeMm3']);
    if ((got - want).abs() > want * tol) {
      out.add('volume ${got.toStringAsFixed(0)} mm³, expected '
          '${want.toStringAsFixed(0)} ±${(tol * 100).toStringAsFixed(0)}%');
    }
  }
  if (c['minFeatures'] != null &&
      (m['features'] as List).length < _n(c['minFeatures'])) {
    out.add('only ${(m['features'] as List).length} features');
  }
  if (c['printable'] == true && (m['overhangs'] as List).isNotEmpty) {
    out.add('needs support to print: ${(m['overhangs'] as List).join('; ')}');
  }
  final kinds = c['featureKinds'];
  if (kinds is List) {
    for (final k in kinds.cast<String>()) {
      final any = k.split('|');
      if (!(m['features'] as List).any(any.contains)) {
        out.add('no ${any.join(" or ")} feature');
      }
    }
  }
  final cap = c['capacityMl'];
  if (cap is Map && mesh.pos.isNotEmpty) {
    final got = _capacityMl(mesh);
    m['capacityMl'] = got;
    if (cap['min'] != null && got < _n(cap['min']) ||
        cap['max'] != null && got > _n(cap['max'])) {
      out.add('holds ${got.toStringAsFixed(0)} ml, wanted '
          '${cap['min']}..${cap['max']} ml');
    }
  }
  if (c['tapersUp'] == true && mesh.pos.isNotEmpty) {
    final b = mesh.bounds();
    final h = b[4] - b[1];
    final lo = slice(mesh, 1, b[1] + h * 0.25).enclosed;
    final hi = slice(mesh, 1, b[1] + h * 0.85).enclosed;
    m['taper'] = {'enclosedAt25': lo, 'enclosedAt85': hi};
    if (!(hi > lo * 1.08)) {
      out.add('does not widen upward: inside ${lo.toStringAsFixed(0)} mm² '
          'at 25 % height, ${hi.toStringAsFixed(0)} mm² at 85 %');
    }
  }
  if (c['openTop'] == true && mesh.pos.isNotEmpty) {
    final b = mesh.bounds();
    final top = slice(mesh, 1, b[4] - 0.3);
    if (top.enclosed <= 0 && top.material > 0.5 * (b[3] - b[0]) * (b[5] - b[2])) {
      out.add('the top is closed');
    }
  }
  final custom = c['custom'];
  if (custom is Map) {
    for (final e in custom.entries) {
      final f = _custom[e.key.split('#').first];
      if (f == null) {
        out.add('unknown check ${e.key}');
        continue;
      }
      try {
        out.addAll(f(x, (e.value as Map).cast<String, dynamic>()));
      } catch (err, st) {
        out.add('check ${e.key} threw: $err ${st.toString().split("\n").take(3).join(" | ")}');
      }
    }
  }
  return out;
}

/// Everything a check may read, as plain data, so the checks can run on
/// another isolate and never stall the clocks of the runs beside them.
class _Ctx {
  _Ctx(this.m, this.mesh, this.freshMeshes, this.old, this.cylinders,
      this.cones);
  final Map<String, dynamic> m;
  final Tri mesh;
  final Map<String, Tri> freshMeshes;
  final List<Tri> old;
  final List<Map<String, dynamic>> cylinders, cones;
}

typedef _Check = List<String> Function(_Ctx x, Map<String, dynamic> a);

/// The outer radius of a turned body round a vertical axis, as a profile.
List<(double, double)> _radiusProfile(Tri m, P2 axis, {double dy = 0.05}) {
  final b = m.bounds();
  final out = <(double, double)>[];
  for (var y = b[1] + dy / 2; y < b[4]; y += dy) {
    final s = slice(m, 1, y);
    var r = 0.0;
    for (final l in s.outers) {
      r = math.max(r, radii(l, axis).$1);
    }
    if (r > 0) out.add((y, r));
  }
  return out;
}

/// A groove: the band of the profile below the flanges, and whether it is
/// symmetric about its own middle within [tol].
List<String> _groove(List<(double, double)> prof, double tol,
    Map<String, dynamic> m, String label) {
  if (prof.length < 6) return ['$label: no profile'];
  final rmax = prof.map((e) => e.$2).reduce(math.max);
  final rmin = prof.map((e) => e.$2).reduce(math.min);
  if (rmax - rmin < 0.1) return ['$label: no groove (radius constant)'];
  // The groove is the lowest band of radius; take the points within 0.05 of
  // the minimum and their middle.
  final low = [for (final e in prof) if (e.$2 < rmin + 0.05) e.$1];
  final mid = (low.first + low.last) / 2;
  m['${label}GrooveY'] = mid;
  m['${label}GrooveR'] = rmin;
  m['${label}OuterR'] = rmax;
  double at(double y) {
    var best = prof.first;
    for (final e in prof) {
      if ((e.$1 - y).abs() < (best.$1 - y).abs()) best = e;
    }
    return best.$2;
  }

  final half = math.min(mid - prof.first.$1, prof.last.$1 - mid);
  var worst = 0.0;
  for (var d = 0.0; d < half * 0.9; d += 0.05) {
    worst = math.max(worst, (at(mid + d) - at(mid - d)).abs());
  }
  // The flanges either side must reach close to the same radius too.
  m['${label}GrooveAsym'] = worst;
  if (worst > tol) {
    return ['$label: groove not symmetric (${worst.toStringAsFixed(2)} mm)'];
  }
  return const [];
}

final Map<String, _Check> _custom = {
  // #95 — a spool press-fitted on the motor's Ø0.8 D-shaft.
  'spoolOnShaft': (x, a) {
    final m = x.m, mesh = x.mesh;
    final out = <String>[];
    final fresh = (m['newBodies'] as List).cast<String>();
    if (fresh.length != 1) return ['expected one new body, got $fresh'];
    final spool = mesh;
    final axis = P2(_n(a['axis'][0]), _n(a['axis'][1]));
    final shaftY = [_n(a['shaftY'][0]), _n(a['shaftY'][1])];
    final b = spool.bounds();
    final od = math.max(b[3] - b[0], b[5] - b[2]);
    final h = b[4] - b[1];
    m['spool'] = {'od': od, 'h': h, 'y': [b[1], b[4]]};
    if (od > _n(a['maxOd']) + 0.05) out.add('Ø${od.toStringAsFixed(2)} > ${a['maxOd']}');
    if (h > _n(a['maxH']) + 0.05) out.add('height ${h.toStringAsFixed(2)} > ${a['maxH']}');
    // The bore, at the middle of the shaft's height.
    final yMid = math.max(b[1], shaftY[0]) / 2 + math.min(b[4], shaftY[1]) / 2;
    if (b[1] > shaftY[1] - 0.3 || b[4] < shaftY[0] + 0.3) {
      out.add('spool (y ${b[1].toStringAsFixed(2)}..${b[4].toStringAsFixed(2)}) '
          'does not sit on the shaft (y ${shaftY[0]}..${shaftY[1]})');
      return out;
    }
    final s = slice(spool, 1, yMid);
    final holes = s.holes.toList();
    if (holes.isEmpty) return [...out, 'no bore at the shaft height'];
    holes.sort((x, y) => x.area.compareTo(y.area));
    final bore = holes.first;
    // Centre of the bore's circumscribed circle: the D's flat moves the
    // centroid, so use the middle of the round part — the box in the
    // direction along the flat, and the round side opposite the flat.
    final bx = bore.box();
    final cz = (bx[1] + bx[3]) / 2;
    final xRound = bx[2]; // round side at +x for this motor
    final cx = xRound - _n(a['shaftR']);
    final off = math.sqrt(math.pow(cx - axis.x, 2) + math.pow(cz - axis.y, 2));
    final shaftArea = _n(a['shaftArea']);
    m['bore'] = {
      'centre': [cx, cz],
      'offset': off,
      'area': bore.area,
      'box': bx,
    };
    if (off > _n(a['tol'])) {
      out.add('bore centre ${off.toStringAsFixed(3)} mm off the shaft axis');
    }
    if ((bore.area - shaftArea).abs() > shaftArea * _n(a['areaTol'])) {
      out.add('bore area ${bore.area.toStringAsFixed(3)} mm² vs shaft '
          '${shaftArea.toStringAsFixed(3)} mm² (±${(_n(a['areaTol']) * 100).round()} %)');
    }
    // A D, not a round hole: its box is narrower across the flat.
    final w = bx[2] - bx[0], d = bx[3] - bx[1];
    if (!(w < d - 0.03)) out.add('bore is not a D (${w.toStringAsFixed(2)} × ${d.toStringAsFixed(2)})');
    out.addAll(_groove(_radiusProfile(spool, axis), _n(a['grooveTol']), m, 'spool'));
    out.addAll(_noClash(x, _n(a['clash'] ?? 0.08)));
    return out;
  },
  // #93 — a capstan wheel beside the spool, 1:10, same height.
  'capstan': (x, a) {
    final m = x.m, mesh = x.mesh;
    final out = <String>[];
    final fresh = (m['newBodies'] as List).cast<String>();
    if (fresh.length != 1) return ['expected one new body, got $fresh'];
    final b = mesh.bounds();
    final axis = P2((b[0] + b[3]) / 2, (b[2] + b[5]) / 2);
    final prof = _radiusProfile(mesh, axis, dy: 0.04);
    out.addAll(_groove(prof, _n(a['grooveTol']), m, 'wheel'));
    final cord = _n(a['cord']);
    final small = _n(a['smallGrooveD']);
    final bigGroove = (m['wheelGrooveR'] as double?) ?? 0;
    final ratio = (2 * bigGroove + cord) / (small + cord);
    m['ratio'] = ratio;
    if ((ratio - _n(a['ratio'])).abs() > _n(a['ratioTol'])) {
      out.add('ratio ${ratio.toStringAsFixed(2)} (groove Ø${(2 * bigGroove).toStringAsFixed(2)}), '
          'wanted ${a['ratio']} ±${a['ratioTol']}');
    }
    final h = b[4] - b[1];
    if ((h - _n(a['height'])).abs() > 0.1) {
      out.add('height ${h.toStringAsFixed(2)} ≠ ${a['height']}');
    }
    final gy = (m['wheelGrooveY'] as double?) ?? 0;
    if ((gy - _n(a['grooveY'])).abs() > _n(a['heightTol'])) {
      out.add('groove at y ${gy.toStringAsFixed(2)}, the spool\'s is at ${a['grooveY']}');
    }
    // The axle bore.
    final s = slice(mesh, 1, (b[1] + b[4]) / 2);
    final holes = s.holes.toList()..sort((x, y) => y.area.compareTo(x.area));
    final central = holes.where((l) {
      final c = l.centroid;
      return math.sqrt(math.pow(c.x - axis.x, 2) + math.pow(c.y - axis.y, 2)) < 0.2;
    }).toList();
    if (central.isEmpty) {
      out.add('no central bore');
    } else {
      final d = 2 * math.sqrt(central.first.area / math.pi);
      m['wheelBore'] = d;
      final lo = _n(a['bore'][0]), hi = _n(a['bore'][1]);
      if (d < lo || d > hi) out.add('bore Ø${d.toStringAsFixed(2)} outside $lo..$hi');
    }
    out.addAll(_noClash(x, 0.05));
    return out;
  },
  // #93 — a case round motor, spool and wheel, with a cord outlet.
  'fittedCase': (x, a) {
    final m = x.m, mesh = x.mesh;
    final out = <String>[];
    final fresh = (m['newBodies'] as List).cast<String>();
    if (fresh.length != 1) return ['expected one new body (the case), got $fresh'];
    final contents = Tri.merge(x.old);
    final cb = contents.bounds();
    final b = mesh.bounds();
    final slack = _n(a['slack']);
    final wx = b[3] - b[0], wz = b[5] - b[2];
    final cx = cb[3] - cb[0], cz = cb[5] - cb[2];
    m['case'] = {'size': [wx, b[4] - b[1], wz], 'contents': [cx, cb[4] - cb[1], cz]};
    if (wx > cx + slack || wz > cz + slack) {
      out.add('case ${wx.toStringAsFixed(1)} × ${wz.toStringAsFixed(1)} for '
          'contents ${cx.toStringAsFixed(1)} × ${cz.toStringAsFixed(1)} '
          '(allowed + $slack)');
    }
    if (b[4] < cb[4] - 0.5) out.add('case lower than its contents');
    out.addAll(_noClash(x, 0.05));
    // The outlet: at the groove height the wall is open somewhere, so the
    // section of the case there encloses nothing.
    final gy = _n(a['grooveY']);
    var open = false;
    for (var y = gy - 1.0; y <= gy + 1.0; y += 0.25) {
      if (slice(mesh, 1, y).enclosed < 1e-3) open = true;
    }
    if (!open) out.add('no outlet in the wall at the cord height');
    return out;
  },
  // #94 — a handle joined to the cup along its height, not a floating bar.
  'handle': (x, a) {
    final m = x.m, mesh = x.mesh;
    final out = <String>[];
    final b = mesh.bounds();
    final cx = _n(a['axis'][0]), cz = _n(a['axis'][1]);
    final cupR = _n(a['cupTopR']);
    // Which side the handle is on: the far extent from the axis.
    final dxp = b[3] - cx, dxm = cx - b[0], dzp = b[5] - cz, dzm = cz - b[2];
    final ext = [dxp, dxm, dzp, dzm];
    final side = ext.indexOf(ext.reduce(math.max));
    final reach = ext[side];
    m['handleReach'] = reach - cupR;
    if (reach - cupR < _n(a['minReach'])) {
      out.add('handle stands only ${(reach - cupR).toStringAsFixed(1)} mm off the cup');
    }
    // Vertical extent of material beyond the cup wall on that side.
    final ys = <double>[];
    for (var y = b[1] + 0.5; y < b[4]; y += 0.5) {
      final s = slice(mesh, 1, y);
      for (final l in s.outers) {
        final bx = l.box();
        final far = [bx[2] - cx, cx - bx[0], bx[3] - cz, cz - bx[1]][side];
        if (far > cupR + 3) {
          ys.add(y);
          break;
        }
      }
    }
    final h = b[4] - b[1];
    final span = ys.isEmpty ? 0.0 : ys.last - ys.first;
    m['handleSpan'] = span / h;
    if (span < _n(a['minSpan']) * h) {
      out.add('handle spans ${(100 * span / h).round()} % of the height');
    }
    // A finger opening: in the vertical section through the handle, an
    // enclosed hole between handle and wall.
    final axis = side < 2 ? 2 : 0; // cut across the handle's direction
    final c = axis == 2 ? cz : cx;
    final s = slice(mesh, axis, c);
    final gaps = s.holes.where((l) {
      final bx = l.box();
      // (x,y) for a z-section, (y,z) for an x-section
      final lateral = axis == 2 ? [bx[0] - cx, bx[2] - cx] : [bx[1] - cz, bx[3] - cz];
      final outward = side.isEven ? lateral[0] : -lateral[1];
      return outward > cupR * 0.6 && l.area > 60;
    }).toList();
    if (gaps.isEmpty) out.add('no finger opening between handle and wall');
    return out;
  },
  // #82 — the plate's holes where the request put them.
  'holes': (x, a) {
    final m = x.m, mesh = x.mesh;
    final out = <String>[];
    final b = mesh.bounds();
    final ext = [b[3] - b[0], b[4] - b[1], b[5] - b[2]];
    final axis = a['axis'] == 'thin'
        ? ext.indexOf(ext.reduce(math.min))
        : {'x': 0, 'y': 1, 'z': 2}[a['axis'] ?? 'y']!;
    final c = (b[axis] + b[axis + 3]) / 2;
    final s = slice(mesh, axis, c);
    final holes = s.holes.toList();
    final got = [
      for (final h in holes)
        (h.centroid, 2 * math.sqrt(h.area / math.pi))
    ];
    // Positions relative to the section's own box centre.
    final a1 = axis == 0 ? 1 : 0, a2 = axis == 2 ? 1 : 2;
    final mx = (b[a1] + b[a1 + 3]) / 2, mz = (b[a2] + b[a2 + 3]) / 2;
    m['holes'] = [
      for (final (p, d) in got)
        [
          (p.x - mx).toStringAsFixed(2),
          (p.y - mz).toStringAsFixed(2),
          d.toStringAsFixed(2)
        ]
    ];
    final want = (a['want'] as List).cast<Map>();
    if (holes.length != want.length) {
      out.add('${holes.length} holes, wanted ${want.length}');
    }
    final tol = _n(a['tol'] ?? 0.1);
    for (final w in want) {
      final d0 = _n(w['d'][0]), d1 = _n(w['d'][1]);
      final at = w['at'] as List?;
      final hit = got.any((g) {
        if (g.$2 < d0 - 0.02 || g.$2 > d1 + 0.02) return false;
        if (at == null) return true;
        // Symmetric patterns: accept either sign.
        final ok1 = ((g.$1.x - mx).abs() - _n(at[0]).abs()).abs() <= tol &&
            ((g.$1.y - mz).abs() - _n(at[1]).abs()).abs() <= tol;
        final ok2 = ((g.$1.x - mx).abs() - _n(at[1]).abs()).abs() <= tol &&
            ((g.$1.y - mz).abs() - _n(at[0]).abs()).abs() <= tol;
        return a['anyOrientation'] == true ? ok1 || ok2 : ok1;
      });
      if (!hit) out.add('no hole Ø${w['d']} at ${at ?? "anywhere"}');
    }
    return out;
  },
  // A countersunk screw hole: a cone face, and a through hole.
  'countersink': (x, a) {
    final m = x.m, mesh = x.mesh;
    final cones = x.cones;
    m['cones'] = [for (final f in cones) f['diameter']];
    if (cones.isEmpty) return ['no countersink (no cone face)'];
    return const [];
  },
  // A clip: an enclosed channel for the cable that is open on one side.
  'clip': (x, a) {
    final m = x.m, mesh = x.mesh;
    final d = _n(a['cable']);
    final b = mesh.bounds();
    // Look along each axis for a section with a round-ish gap of about the
    // cable's size that is NOT enclosed — i.e. a C, open to the outside.
    // Cheap proxy: somewhere along each axis, a section has a C-shaped outer
    // loop whose box is bigger than the cable and whose area is well below
    // a full ring's.
    for (var axis = 0; axis < 3; axis++) {
      final c = (b[axis] + b[axis + 3]) / 2;
      final s = slice(mesh, axis, c);
      for (final l in s.outers) {
        final bx = l.box();
        final w = bx[2] - bx[0], h = bx[3] - bx[1];
        if (w < d || h < d) continue;
        // A point at the cable's centre candidate: the loop does not contain
        // points near its own middle if it is a C round an empty middle.
        for (var i = 0; i < 40; i++) {
          final t = P2(bx[0] + w * (0.2 + 0.6 * (i % 7) / 6),
              bx[1] + h * (0.2 + 0.6 * (i ~/ 7) / 5));
          if (!l.contains(t)) {
            // Is there room for the cable round t?
            var free = true;
            for (var k = 0; k < 12 && free; k++) {
              final ang = k * math.pi / 6;
              final q = P2(t.x + 0.45 * d * math.cos(ang),
                  t.y + 0.45 * d * math.sin(ang));
              if (l.contains(q)) free = false;
            }
            if (free && !s.holes.any((hl) => hl.contains(t))) {
              m['clipAxis'] = axis;
              return const [];
            }
          }
        }
      }
    }
    return ['no open channel for a Ø$d cable'];
  },
  // Bores through one wall of a housing, spaced as asked.
  'bores': (x, a) {
    final m = x.m, mesh = x.mesh;
    final out = <String>[];
    final cyl = x.cylinders;
    final d = _n(a['d']);
    final bores = [
      for (final f in cyl)
        if ((_n(f['diameter']) - d).abs() <= 0.1 && f['concave'] == true) f
    ];
    m['bores'] = [for (final f in bores) f['axisAt'] ?? f['at']];
    if (bores.length < _n(a['count'])) {
      return ['${bores.length} concave Ø$d bores, wanted ${a['count']}'];
    }
    if (a['spacing'] != null && bores.length >= 2) {
      final p0 = ((bores[0]['axisAt'] ?? bores[0]['at']) as List).map(_n).toList();
      final p1 = ((bores[1]['axisAt'] ?? bores[1]['at']) as List).map(_n).toList();
      // Distance perpendicular to their shared axis direction.
      final dir = (bores[0]['dir'] as List).map(_n).toList();
      final v = [p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]];
      final along = v[0] * dir[0] + v[1] * dir[1] + v[2] * dir[2];
      final perp = math.sqrt(math.max(0,
          v[0] * v[0] + v[1] * v[1] + v[2] * v[2] - along * along));
      m['boreSpacing'] = perp;
      if ((perp - _n(a['spacing'])).abs() > 0.1) {
        out.add('bores ${perp.toStringAsFixed(2)} apart, wanted ${a['spacing']}');
      }
    }
    return out;
  },
  // A wall of the stated thickness: the thinnest material between the
  // enclosed space and the outside, at mid height.
  'wall': (x, a) {
    final m = x.m, mesh = x.mesh;
    final b = mesh.bounds();
    var holes = <Loop>[];
    for (final f in const [0.5, 0.3, 0.7, 0.15, 0.85]) {
      final s = slice(mesh, 1, b[1] + (b[4] - b[1]) * f);
      holes = s.holes.toList()..sort((x, y) => y.area.compareTo(x.area));
      if (holes.isNotEmpty) break;
    }
    if (holes.isEmpty) return ['not hollow'];
    final hb = holes.first.box();
    final t = math.min(math.min(hb[0] - b[0], b[3] - hb[2]),
        math.min(hb[1] - b[2], b[5] - hb[3]));
    m['wall'] = t;
    if ((t - _n(a['t'])).abs() > _n(a['tol'] ?? 0.1)) {
      return ['wall ${t.toStringAsFixed(2)} mm, wanted ${a['t']}'];
    }
    return const [];
  },
  // A hexagonal nut pocket seen in a section.
  'hexPocket': (x, a) {
    final m = x.m, mesh = x.mesh;
    final b = mesh.bounds();
    final af = _n(a['af']);
    for (final y in [b[1] + 0.5, b[4] - 0.5]) {
      final s = slice(mesh, 1, y);
      for (final h in s.holes) {
        final bx = h.box();
        final w = bx[2] - bx[0], d = bx[3] - bx[1];
        final small = math.min(w, d), large = math.max(w, d);
        if ((small - af).abs() <= 0.1 &&
            (large - af * 2 / math.sqrt(3)).abs() <= 0.15) {
          return const [];
        }
      }
    }
    return ['no hex pocket AF $af near a face'];
  },
};

/// Whether new bodies cut into the bodies that were there before (beyond a
/// press fit of [depth]).
List<String> _noClash(_Ctx x, double depth) {
  final out = <String>[];
  for (final e in x.freshMeshes.entries) {
    for (final o in x.old) {
      final hits = surfaceSamples(o, max: 800)
          .where((pt) => deeplyInside(e.value, pt, depth))
          .length;
      if (hits > 0) out.add('${e.key} cuts into an existing body ($hits samples)');
    }
  }
  return out;
}

class _Run {
  _Run(this.s, this.n);
  final Map<String, dynamic> s;
  final int n;
}

Future<Map<String, dynamic>> _runOne(_Run run, String mode, Map<String, String> env,
    OcctPartKernel kernel) async {
  final s = run.s;
  final live = mode == 'live';
  final backend = live
      ? DeviceAiBackend(
          keyReader: (_) async => env['AI_BENCH_KEY'], clientFactory: _realClient)
      : _ReplayBackend(mode == 'setup'
          ? const []
          : (s['replay'] as List? ?? const []).cast<String>());
  final controller = AiController(backend: backend);
  final app = AppState(ai: controller)..partKernel = kernel;
  final dir = Directory.systemTemp.createTempSync('prototype_bench_');
  app.docsDirForTest = dir;
  await app.createNamedPart('Bench');
  await controller.initialize(AiStore(Directory('${dir.path}/ai')));
  await controller.configure(
      provider: live
          ? _provider(env['AI_BENCH_PROVIDER'] ?? 'deepseek')
          : AiProvider.deepseek,
      model: live ? (env['AI_BENCH_MODEL'] ?? 'deepseek-flash') : 'replay',
      allowEdits: true);
  final imp = s['import'] as String?;
  if (imp != null) {
    final n = await app.importStepIntoPart('test/bench/$imp');
    if (n == 0) throw StateError('import $imp failed');
  }
  final setup = [
    for (final a in (s['setup'] as List? ?? const []).cast<Map>())
      AiAction(a['op'] as String,
          {for (final e in a.entries) if (e.key != 'op') '${e.key}': e.value})
  ];
  if (setup.isNotEmpty) {
    final r = await AiCad(app).run(setup);
    if (!r.ok) throw StateError('setup: ${jsonEncode(r.toJson())}');
  }
  final bodiesBefore = _bodies(app.currentPart!).toSet();
  int featuresOf(String b) => app.currentPart!.features
      .where((f) => f.bodyName == b && !f.rolledBack)
      .length;
  final countBefore = {for (final b in bodiesBefore) b: featuresOf(b)};
  // Every event of this conversation, timed on this run's own clock.
  final clock = Stopwatch();
  final mine = <(int, AiTraceEvent)>[];
  final requests = <String>{};
  final sessions = <String>{};
  void tap(AiTraceEvent e) {
    final ours = (e.sessionId != null && sessions.contains(e.sessionId)) ||
        (e.requestId != null && requests.contains(e.requestId));
    if (!ours) return;
    if (e.requestId != null) requests.add(e.requestId!);
    mine.add((clock.elapsedMilliseconds, e));
  }

  _taps.add(tap);
  sessions.add(controller.currentSession.id);
  clock.start();
  final answers = (s['answers'] as List? ?? const []).cast<String>();
  final prompts = [s['prompt'] as String, ...(s['then'] as List? ?? const []).cast<String>()];
  var said = 0;
  for (final prompt in prompts) {
    controller.updateDraft(prompt);
    await controller.send();
    while (said < answers.length &&
        controller.currentSession.messages.isNotEmpty &&
        controller.currentSession.messages.last.role == 'assistant' &&
        aiReplyIsQuestion(controller.currentSession.messages.last.text)) {
      controller.updateDraft(answers[said++]);
      await controller.send();
    }
  }
  clock.stop();
  _taps.remove(tap);
  final events = [for (final (_, e) in mine) e];
  int? firstOp;
  for (final (t, e) in mine) {
    if (e.kind != 'actions.parsed' || e.data['parseError'] != null) continue;
    final acts = (e.data['actions'] as List? ?? const []);
    if (acts.any((x) => x is Map && !kAiReadOnlyOps.contains(x['op']))) {
      firstOp = t;
      break;
    }
  }
  var input = 0, output = 0, reasoning = 0, cached = 0;
  for (final e in events.where((e) => e.kind == 'usage')) {
    input += (e.data['input'] as num?)?.toInt() ?? 0;
    output += (e.data['output'] as num?)?.toInt() ?? 0;
    reasoning += (e.data['reasoning'] as num?)?.toInt() ?? 0;
    cached += (e.data['cacheRead'] as num?)?.toInt() ?? 0;
  }
  // A body the turn added features to is part of the answer (a shell on a
  // box, a handle joined to a cup); the ones it left alone are the context.
  final before = {
    for (final b in bodiesBefore)
      if (featuresOf(b) == countBefore[b]) b
  };
  final m = _measure(app, before);
  final failures =
      await _check(app, m, (s['checks'] as Map).cast<String, dynamic>(), before);
  final seconds = clock.elapsedMilliseconds / 1000;
  final ref = _n(s['refSeconds'] ?? 60);
  final rolled = events
      .where((e) => e.kind == 'actions.report' && e.data['reverted'] == true)
      .length;
  final failedBlocks = events
      .where((e) => e.kind == 'actions.report' && e.data['ok'] == false)
      .length;
  final speed = <String>[
    if (firstOp == null) 'nothing was built',
    if (firstOp != null && firstOp > 5000)
      'first op after ${(firstOp / 1000).toStringAsFixed(1)} s (> 5 s)',
    if (seconds > ref) 'took ${seconds.toStringAsFixed(1)} s (pro: ${ref.toStringAsFixed(0)} s)',
    if (rolled > 1) '$rolled blocks rolled back',
  ];
  final transcript = [
    for (final msg in controller.currentSession.messages)
      '--- ${msg.role}\n${msg.text.length > 6000 ? '${msg.text.substring(0, 6000)}…' : msg.text}'
  ].join('\n');
  final renders = <String>[];
  final rdir = env['AI_BENCH_RENDER'];
  if (rdir != null && rdir.isNotEmpty) {
    Directory(rdir).createSync(recursive: true);
    File('$rdir/${s['id']}-${run.n}.txt').writeAsStringSync(transcript);
    // Drawn after every run has finished: the painter works on this isolate
    // and would stall the clocks of the runs still going.
    _renderJobs.add(() async {
      for (final (az, pol) in const [(45.0, 55.0), (225.0, 70.0), (0.0, 90.0)]) {
        try {
          final png = await app.aiRenderView(
              azRad: az * math.pi / 180, polRad: pol * math.pi / 180,
              width: 480, height: 480);
          if (png == null) continue;
          File('$rdir/${s['id']}-${run.n}-az${az.round()}.png')
              .writeAsBytesSync(png);
        } catch (_) {}
      }
    });
  }
  final result = {
    'id': s['id'],
    'run': run.n,
    'set': s['set'] ?? 'main',
    'issue': s['issue'],
    'mode': mode,
    'pass': failures.isEmpty,
    'fast': speed.isEmpty,
    'failures': failures,
    'speed': speed,
    'firstOpS': firstOp == null ? null : firstOp / 1000,
    'seconds': seconds,
    'refSeconds': ref,
    'rounds': events.where((e) => e.kind == 'round').length,
    'blocks': events.where((e) => e.kind == 'actions.report').length,
    'failedBlocks': failedBlocks,
    'rolledBack': rolled,
    'thinkingCuts': events.where((e) => e.kind == 'thinking.cut').length,
    'questions': said,
    'tokens': {
      'input': input,
      'cached': cached,
      'output': output,
      'reasoning': reasoning
    },
    'part': m,
    'error': controller.currentSession.errorCode,
    'renders': renders,
    'signature': _signature(m),
  };
  return result;
}

/// What makes two designs different: proportions, size, what they are made of.
Map<String, dynamic> _signature(Map<String, dynamic> m) => {
      'size': [for (final d in (m['sizeMm'] as List)) (d as double).round()],
      'volume': (_n(m['volumeMm3']) / 100).round() * 100,
      'features': (m['newFeatures'] as List).join(','),
    };

bool _distinct(Map<String, dynamic> a, Map<String, dynamic> b) {
  final sa = (a['size'] as List).map(_n).toList();
  final sb = (b['size'] as List).map(_n).toList();
  for (var i = 0; i < 3; i++) {
    if ((sa[i] - sb[i]).abs() > 0.08 * math.max(sa[i], sb[i])) return true;
  }
  if ((_n(a['volume']) - _n(b['volume'])).abs() >
      0.15 * math.max(_n(a['volume']), _n(b['volume']))) {
    return true;
  }
  return a['features'] != b['features'];
}

final List<void Function(AiTraceEvent)> _taps = [];
final List<Future<void> Function()> _renderJobs = [];

/// JSON has no infinities; a measurement of nothing must still print.
Object? _finite(Object? v) => v is Map
    ? {for (final e in v.entries) '${e.key}': _finite(e.value)}
    : v is List
        ? [for (final x in v) _finite(x)]
        : v is double && !v.isFinite
            ? '$v'
            : v;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final mode = env['AI_BENCH'];
  final kernel = OcctPartKernel();
  final skip = mode == null
      ? 'set AI_BENCH=replay or AI_BENCH=live to run the assistant benchmark'
      : !kernel.available
          ? 'the benchmark needs the real kernel — set PROTOTYPE_NATIVE_DIR'
          : (mode == 'live' && (env['AI_BENCH_KEY'] ?? '').isEmpty)
              ? 'AI_BENCH=live needs AI_BENCH_KEY'
              : false;
  final spec = jsonDecode(File('test/bench/scenarios.json').readAsStringSync())
      as Map<String, dynamic>;
  final only = (env['AI_BENCH_ONLY'] ?? '')
      .split(',')
      .where((s) => s.trim().isNotEmpty)
      .toSet();
  final set = env['AI_BENCH_SET'] ?? 'main';
  final scenarios = [
    for (final s in (spec['scenarios'] as List).cast<Map<String, dynamic>>())
      if (only.isNotEmpty
          ? only.contains(s['id'])
          : (set == 'all' || (s['set'] ?? 'main') == set))
        if (mode != 'replay' || s['replay'] != null) s
  ];
  final parallel = int.tryParse(env['AI_BENCH_PARALLEL'] ?? '') ?? 1;
  final repeat = int.tryParse(env['AI_BENCH_REPEAT'] ?? '') ?? 1;

  test('assistant benchmark', () async {
    AiTrace.tap = (e) {
      for (final t in List.of(_taps)) {
        t(e);
      }
    };
    final queue = <_Run>[
      for (var n = 0; n < repeat; n++)
        for (final s in scenarios) _Run(s, n),
      // Creative scenarios always get three runs to compare.
      if (repeat < 3)
        for (var n = repeat; n < 3; n++)
          for (final s in scenarios)
            if (s['creative'] == true && mode == 'live') _Run(s, n),
    ];
    final results = <Map<String, dynamic>>[];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final run = queue.removeAt(0);
        Map<String, dynamic> r;
        try {
          r = await _runOne(run, mode!, env, kernel);
        } catch (e, st) {
          r = {
            'id': run.s['id'],
            'run': run.n,
            'pass': false,
            'fast': false,
            'failures': ['harness: $e'],
            'speed': const [],
            'stack': '$st',
          };
        }
        results.add(r);
        // ignore: avoid_print
        print('BENCH ${jsonEncode(_finite(r))}');
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    AiTrace.tap = null;
    for (final job in _renderJobs) {
      await job();
    }
    // Creativity: every pair of runs of a creative scenario must differ.
    final creative = <String, List<String>>{};
    for (final s in scenarios.where((s) => s['creative'] == true)) {
      final runs = results.where((r) => r['id'] == s['id'] && r['signature'] != null).toList();
      final same = <String>[];
      for (var i = 0; i < runs.length; i++) {
        for (var j = i + 1; j < runs.length; j++) {
          if (!_distinct(runs[i]['signature'] as Map<String, dynamic>,
              runs[j]['signature'] as Map<String, dynamic>)) {
            same.add('runs ${runs[i]['run']} and ${runs[j]['run']} are the same design');
          }
        }
      }
      creative[s['id'] as String] = same;
    }
    final passed = results.where((r) => r['pass'] == true).length;
    final fast = results.where((r) => r['fast'] == true).length;
    final summary = {
      'at': DateTime.now().toUtc().toIso8601String(),
      'mode': mode,
      'set': set,
      'passed': passed,
      'fast': fast,
      'of': results.length,
      'creative': creative,
      'scenarios': results,
    };
    final out = env['AI_BENCH_OUT'];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(_finite(summary)));
    }
    // ignore: avoid_print
    print('BENCH SUMMARY $passed/${results.length} accurate, '
        '$fast/${results.length} fast, creative ${jsonEncode(creative)}');
    for (final r in results) {
      // ignore: avoid_print
      print('  ${r['id']}#${r['run']}: ${r['pass'] == true ? "OK " : "BAD"} '
          '${r['fast'] == true ? "fast" : "slow"} '
          'first ${r['firstOpS']} s, total ${r['seconds']} s / ${r['refSeconds']} s, '
          'rounds ${r['rounds']}, rb ${r['rolledBack']}, cuts ${r['thinkingCuts']} '
          '${[...(r['failures'] as List), ...(r['speed'] as List)].join("; ")}');
    }
    if (mode == 'replay') {
      expect(passed, results.length,
          reason: results.where((r) => r['pass'] != true).map(jsonEncode).join('\n'));
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 90)));
}
