part of 'ai_cad.dart';

// A TURNED PART IN ONE MOVE.
//
// Spools, capstan wheels, cups, vases, knobs and spacers are all the same
// professional move: draw the half-profile on a plane through the axis and
// revolve it. Here that took three ops and a sketch frame the model had to
// get right — which plane, which sketch axis is world Y, where the axis is
// when the shaft is not at the origin — and the lab's runs got it wrong:
// a spool turned about the world origin, 8.7 mm below the shaft it was for;
// a wheel whose groove came out as a plain cylinder. `lathe` takes the
// profile as (radius, height) pairs about a vertical axis the model names in
// world terms, or by the shaft's own face, and builds an ordinary sketch and
// revolve from them, so the timeline stays editable.

extension AiCadLathe on AiCad {
  /// A cylinder or cone face by id, and the body it is on. Face ids are per
  /// body, so [body] names it; otherwise every visible body but [exclude] is
  /// searched, newest first — the shaft is usually on the part that was
  /// there before.
  Future<(Map<String, dynamic>?, String?)> _axisFace(PartModel p, String id,
      {String? body, String? exclude}) async {
    final names = body != null
        ? [body]
        : [
            for (final (name, fs) in p.solidBodies().toList().reversed)
              if (name != exclude && fs.any((f) => f.visible)) name
          ];
    for (final name in names) {
      final found = await _one(
          p, AiAction('faces_where', {'limit': 400, 'body': name}));
      final faces = (found.detail?['faces'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final f = faces.where((f) => f['face'] == id).firstOrNull;
      if (f != null && f['axisAt'] is List) return (f, name);
    }
    return (null, null);
  }

  /// `lathe {profile | start + segments, axis_at?: [x, z] | axis_face?,
  /// base_y?: mm | face id, operation?, body?, id?}` — every point is
  /// [r, y]: r the distance from the axis (≥ 0), y the height above base_y
  /// (world 0 when omitted).
  Future<AiActionOutcome> _lathe(PartModel p, AiAction a) async {
    // Where the axis is, in world X and Z.
    var x0 = 0.0, z0 = 0.0;
    String? fromFace;
    final faceId = a.text('axis_face');
    final at = a.point('axis_at');
    if (faceId != null) {
      final (f, _) = await _axisFace(p, faceId, body: a.text('axis_body'));
      final axisAt = f?['axisAt'];
      if (f == null || axisAt is! List) {
        return AiActionOutcome.failed(a.op,
            'axis_face "$faceId" is not a cylinder or cone face of this part — '
            'find the shaft with faces_where {"type": "cylinder"}');
      }
      final dir = (f['dir'] as List).map((v) => (v as num).toDouble()).toList();
      if (dir[1].abs() < 0.999) {
        return AiActionOutcome.failed(a.op,
            'axis_face "$faceId" is not vertical (its axis is $dir); lathe '
            'turns about a vertical (Y) axis');
      }
      x0 = (axisAt[0] as num).toDouble();
      z0 = (axisAt[2] as num).toDouble();
      fromFace = faceId;
    } else if (at != null) {
      x0 = at[0];
      z0 = at[1];
    }
    // `base_y`: where the profile's y = 0 is — a height, or the id of the
    // flat face the part STANDS ON (a mate, the way a person places a spool
    // on a motor's boss). The lab's spools sat at y = 0, 8.7 mm below the
    // shaft, or sank into the boss, because the model had to work that
    // height out itself.
    var y0 = 0.0;
    String? onFace;
    final base = a.args['base_y'];
    if (base is num) {
      y0 = base.toDouble();
    } else if (base is String && base.isNotEmpty) {
      final h = await _flatFaceHeight(p, base, body: a.text('base_body'));
      if (h == null) {
        return AiActionOutcome.failed(a.op,
            'base_y "$base" is not a flat, horizontal face of any body — give '
            'a face id from faces_where {"axis": "+y"} or a height in mm');
      }
      y0 = h;
      onFace = base;
    }
    // The profile, as a sketch_path in the plane z = z0 (sketch x = world X,
    // sketch y = world Y), shifted so r = 0 is the axis and y = 0 is base_y.
    List<dynamic> shift(Object? q) {
      final pt = aiPoint(q);
      if (pt == null) throw FormatException('a point must be [r, y], got $q');
      if (pt[0] < -1e-9) {
        throw FormatException('r must be ≥ 0 (a radius), got ${pt[0]}');
      }
      return [x0 + pt[0], y0 + pt[1]];
    }

    final Map<String, dynamic> path;
    try {
      final prof = a.args['profile'];
      if (prof is List && prof.length >= 3) {
        final pts = [for (final q in prof) shift(q)];
        path = {
          'start': pts.first,
          'segments': [
            for (final q in pts.skip(1)) {'to': q}
          ],
        };
      } else if (a.args['start'] != null && a.args['segments'] is List) {
        path = {
          'start': shift(a.args['start']),
          'segments': [
            for (final s in (a.args['segments'] as List).cast<Map>())
              {
                for (final e in s.entries)
                  '${e.key}': const {'to', 'through', 'centre', 'center'}
                          .contains(e.key)
                      ? shift(e.value)
                      : e.value
              }
          ],
        };
      } else {
        return AiActionOutcome.failed(
            a.op,
            'give the half-profile as "profile": [[r, y], ...] (closed by '
            'the app), or "start" + "segments" like sketch_path, every point '
            '[r, y]');
      }
    } on FormatException catch (e) {
      return AiActionOutcome.failed(a.op, e.message);
    }
    final id = a.text('id');
    final sk = '${id ?? 'lathe'}_profile_${p.childSketches.length + 1}';
    for (final (op, args) in [
      ('create_sketch', <String, dynamic>{'plane': 'xy', 'offset': z0, 'id': sk}),
      ('sketch_path', <String, dynamic>{'sketch': sk, ...path, 'closed': true}),
    ]) {
      final o = await _one(p, AiAction(op, args));
      if (!o.ok) return AiActionOutcome.failed(a.op, '$op: ${o.error}');
    }
    final rev = await _one(
        p,
        AiAction('revolve', {
          'sketch': sk,
          'axis': 'y',
          'axis_at': [x0, 0],
          'operation': a.text('operation') ?? 'new',
          if (a.text('body') != null) 'body': a.text('body'),
          if (id != null) 'id': id,
        }));
    if (!rev.ok) return AiActionOutcome.failed(a.op, 'revolve: ${rev.error}');
    return AiActionOutcome(a.op, detail: {
      ...?rev.detail,
      'axisAt': [_r(x0), _r(z0)],
      if (fromFace != null) 'axisFrom': fromFace,
      if (base != null) 'baseY': _r(y0),
      if (onFace != null) 'standsOn': onFace,
      'sketch': sk,
    });
  }

  /// The height of a flat, horizontal face by id — searched on [body], or on
  /// every visible body, newest first.
  Future<double?> _flatFaceHeight(PartModel p, String id, {String? body}) async {
    final names = body != null
        ? [body]
        : [
            for (final (name, fs) in p.solidBodies().toList().reversed)
              if (fs.any((f) => f.visible)) name
          ];
    for (final name in names) {
      final found = await _one(
          p, AiAction('faces_where', {'limit': 400, 'body': name}));
      final faces = (found.detail?['faces'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final f = faces.where((f) => f['face'] == id).firstOrNull;
      if (f == null) continue;
      final dir = f['dir'];
      final at = f['at'];
      if (f['type'] == 'plane' &&
          dir is List &&
          (dir[1] as num).abs() > 0.999 &&
          at is List) {
        return (at[1] as num).toDouble();
      }
    }
    return null;
  }
}

// A BORE THAT FITS THE SHAFT IT IS FOR.
//
// #95: "d shape presspassung 1:1 zur kleinen 0.8mm achse". A pro projects
// the shaft's edge into a sketch and cuts it — one move, and the flat of the
// D comes along by itself. Here the model had to find the flat's offset,
// draw an arc and a chord in the right sketch frame and centre it on the
// axis; the lab's spools came out round, Ø1.4, or 0.3 mm off the axis.
// `shaft_bore` takes the shaft's own cross-section from the mesh at the
// middle of its face, offsets it by the fit, and cuts it into the part over
// the height the shaft occupies.
extension AiCadShaftBore on AiCad {
  /// `shaft_bore {face, body?, fit?: "press"|"slide"|"clearance" | clearance?,
  /// through?}` — [face] is the shaft's cylinder face (faces_where).
  Future<AiActionOutcome> _shaftBore(PartModel p, AiAction a) async {
    final faceId = a.text('face') ?? a.text('shaft_face');
    if (faceId == null) {
      return AiActionOutcome.failed(a.op,
          'name the shaft by its cylinder face: {"face": "F8"} (faces_where '
          '{"type": "cylinder"})');
    }
    // The part to bore: the body named, else the newest one (the part just
    // built for this shaft).
    final target = a.text('body') ??
        [
          for (final g in p.features.reversed)
            if (!g.rolledBack && g.solid != null) g.bodyName
        ].firstOrNull;
    if (target == null) {
      return AiActionOutcome.failed(a.op,
          'there is no part to bore — build it first (e.g. with lathe), then '
          'shaft_bore with "body"');
    }
    final (f, shaftBody) = await _axisFace(p, faceId,
        body: a.text('shaft_body'), exclude: target);
    final axisAt = f?['axisAt'];
    if (f == null || axisAt is! List) {
      final (own, _) = await _axisFace(p, faceId, body: target);
      return AiActionOutcome.failed(
          a.op,
          own != null
              ? '"$faceId" is a face of "$target" itself — the part to bore '
                  'is the NEWEST body ("$target"). Build the part on the shaft '
                  'first (lathe with axis_face), or name both: {"body": part, '
                  '"shaft_body": the body with the shaft}'
              : '"$faceId" is not a cylinder face of any other body — find the '
                  'shaft with faces_where {"type": "cylinder", "body": ...}');
    }
    final dir = (f['dir'] as List).map((v) => (v as num).toDouble()).toList();
    if (dir[1].abs() < 0.999) {
      return AiActionOutcome.failed(
          a.op, 'shaft_bore needs a vertical (Y) shaft; "$faceId" is not');
    }
    final x0 = (axisAt[0] as num).toDouble();
    final yMid = (axisAt[1] as num).toDouble();
    final z0 = (axisAt[2] as num).toDouble();
    // The face's height, from its `spans` line: "... · y 8.7..9.7 · ...".
    final spans = '${f['spans'] ?? ''}';
    final ym = RegExp(r'y (-?[\d.]+)\.\.(-?[\d.]+)').firstMatch(spans);
    if (ym == null) {
      return AiActionOutcome.failed(a.op, 'could not read the height of "$faceId"');
    }
    final fy0 = double.parse(ym.group(1)!), fy1 = double.parse(ym.group(2)!);
    final solid = currentBodySolid(p, target);
    final shaftSolid = currentBodySolid(p, shaftBody!);
    if (solid == null || shaftSolid == null) {
      return AiActionOutcome.failed(a.op, 'no solid for "$target" or the shaft');
    }
    // The shaft's outline at the middle of the face: the loop round the axis.
    final loops = aiSliceLoops(shaftSolid.mesh, 1, yMid);
    List<(double, double)>? outline;
    for (final l in loops) {
      if (_inside(l, x0, z0)) outline = l;
    }
    if (outline == null) {
      return AiActionOutcome.failed(a.op, 'could not section the shaft at y $yMid');
    }
    // The fit, as a radial offset of the outline. FDM prints holes undersize,
    // so "press" on a printer is a line-to-line outline (0.0): it comes out
    // tight. Explicit `clearance` wins.
    final fit = a.text('fit') ?? 'press';
    final clearance = a.number('clearance') ??
        switch (fit) { 'slide' => 0.1, 'clearance' => 0.2, _ => 0.0 };
    final ring = _offsetConvex(outline, x0, z0, clearance);
    // Over the height where the shaft and the part overlap.
    final pos = solid.mesh.positions;
    var by0 = double.infinity, by1 = -double.infinity;
    for (var i = 1; i < pos.length; i += 3) {
      by0 = math.min(by0, pos[i]);
      by1 = math.max(by1, pos[i]);
    }
    final from = math.max(by0, fy0) - 0.01;
    final through = a.flag('through') || fy1 >= by1 - 1e-6;
    final to = through ? by1 + 0.01 : math.min(by1, fy1 + 0.2);
    if (to - from <= 0.05) {
      return AiActionOutcome.failed(a.op,
          '"$target" (y ${_r(by0)}..${_r(by1)}) does not reach the shaft '
          '(y ${_r(fy0)}..${_r(fy1)}) — move the part onto it first');
    }
    final sk = 'bore_${p.childSketches.length + 1}';
    List<double> skp((double, double) q) => [q.$1, -q.$2]; // xz: sketch y = -Z
    for (final (op, args) in [
      ('create_sketch', <String, dynamic>{'plane': 'xz', 'offset': from, 'id': sk}),
      ('sketch_path', <String, dynamic>{
        'sketch': sk,
        'start': skp(ring.first),
        'segments': [for (final q in ring.skip(1)) {'to': skp(q)}],
        'closed': true,
      }),
    ]) {
      final o = await _one(p, AiAction(op, args));
      if (!o.ok) return AiActionOutcome.failed(a.op, '$op: ${o.error}');
    }
    final cut = await _one(
        p,
        AiAction('extrude', {
          'sketch': sk,
          'distance': to - from,
          'operation': 'cut',
          'body': target,
          if (a.text('id') != null) 'id': a.text('id'),
        }));
    if (!cut.ok) return AiActionOutcome.failed(a.op, 'the cut: ${cut.error}');
    return AiActionOutcome(a.op, detail: {
      ...?cut.detail,
      'shaft': faceId,
      'axisAt': [_r(x0), _r(z0)],
      'fit': fit,
      'clearance': clearance,
      'boreY': [_r(from), _r(to)],
      'through': through,
    });
  }

  static bool _inside(List<(double, double)> l, double x, double y) {
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

  /// [l] moved outward by [d] from the point (cx, cy), point by point along
  /// the mean of its two edge normals — exact enough for the convex outline
  /// of a shaft and a fit of a tenth or two.
  static List<(double, double)> _offsetConvex(
      List<(double, double)> l, double cx, double cy, double d) {
    // Thin near-duplicates first: a tessellated circle has hundreds.
    final pts = <(double, double)>[];
    for (final q in l) {
      if (pts.isEmpty ||
          math.sqrt(math.pow(q.$1 - pts.last.$1, 2) +
                  math.pow(q.$2 - pts.last.$2, 2)) >
              0.005) {
        pts.add(q);
      }
    }
    if (d == 0) return pts;
    final n = pts.length;
    return [
      for (var i = 0; i < n; i++)
        () {
          final p = pts[i], a = pts[(i - 1 + n) % n], b = pts[(i + 1) % n];
          // Outward: away from the centre.
          var nx = -(b.$2 - a.$2), ny = b.$1 - a.$1;
          final len = math.sqrt(nx * nx + ny * ny);
          if (len < 1e-12) return p;
          nx /= len;
          ny /= len;
          if (nx * (p.$1 - cx) + ny * (p.$2 - cy) < 0) {
            nx = -nx;
            ny = -ny;
          }
          return (p.$1 + nx * d, p.$2 + ny * d);
        }()
    ];
  }
}
