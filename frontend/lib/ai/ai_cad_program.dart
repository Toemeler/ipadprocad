part of 'ai_cad.dart';

// A WHOLE PART AS ONE PROGRAM, IN WORLD COORDINATES.
//
// The AI lab measured where the model goes wrong: nearly never in what the
// user asked for, nearly always in space — a sketch plane whose y points at
// world -Z, a cut pointed away from the body, a spool turned 8.7 mm below
// its shaft — and in state across many small steps: feature ids, what is
// already built, what a failed step left behind. What it does well is write
// a complete program in one go, name its numbers, and compare a list of
// requirements with a list of measurements.
//
// So a part is a PROGRAM: shapes added and cut in world millimetres (Y up),
// with no sketch frames, every step naming where it is in the world; then
// shell, blends and the relational moves (a handle on a wall, a bore on a
// shaft). Sending the program again REPLACES the part — the whole thing is
// rebuilt from it, in milliseconds — so a correction is a rewrite, never a
// diff against state the model has to remember. The model states what the
// finished part must measure (`expect`); the app measures every item.
//
// The program compiles to ordinary sketches and features, so the timeline
// stays editable by hand.

/// A revolve profile with a smooth curve through its points, as a designer
/// draws a vase or a knob: centripetal Catmull-Rom between the points, 8
/// samples a span. Points ON the axis (r = 0) stay corners, and so do the
/// profile's first and last points; the curve passes through every point
/// the model gave. The model is good at choosing a few points, and bad at
/// writing curves — the app draws the curve.
List<List<num>> aiSmoothProfile(List<List<num>> pts) {
  // A SHARP turn stays a corner — a rim, a step, the wall turning back
  // into the inside. Curving through one overshoots, and the profile
  // crossed itself (a cup's rim; the kernel then hung on its chamfer).
  bool sharp(int i) {
    if (i <= 0 || i >= pts.length - 1) return true;
    final ax = (pts[i][0] - pts[i - 1][0]).toDouble(),
        ay = (pts[i][1] - pts[i - 1][1]).toDouble();
    final bx = (pts[i + 1][0] - pts[i][0]).toDouble(),
        by = (pts[i + 1][1] - pts[i][1]).toDouble();
    final la = math.sqrt(ax * ax + ay * ay), lb = math.sqrt(bx * bx + by * by);
    if (la < 1e-9 || lb < 1e-9) return true;
    final cos = (ax * bx + ay * by) / (la * lb);
    return cos < math.cos(60 * math.pi / 180);
  }

  bool corner(int i) =>
      i == 0 || i == pts.length - 1 || pts[i][0].abs() < 1e-9 || sharp(i);
  final out = <List<num>>[pts.first];
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    // A span that starts or ends on the axis, or runs between two corners,
    // stays straight.
    if (a[0].abs() < 1e-9 || b[0].abs() < 1e-9 || (corner(i) && corner(i + 1))) {
      out.add(b);
      continue;
    }
    final p0 = corner(i) ? a : pts[i - 1];
    final p3 = corner(i + 1) ? b : pts[i + 2];
    double d(List<num> u, List<num> v) {
      final dx = (u[0] - v[0]).toDouble(), dy = (u[1] - v[1]).toDouble();
      return math.pow(math.max(1e-12, dx * dx + dy * dy), 0.25).toDouble();
    }

    final t0 = 0.0, t1 = t0 + d(p0, a), t2 = t1 + d(a, b), t3 = t2 + d(b, p3);
    List<double> lerp(List<num> u, List<num> v, double ta, double tb, double t) {
      final w = (tb - ta).abs() < 1e-12 ? 0.0 : (t - ta) / (tb - ta);
      return [u[0] + (v[0] - u[0]) * w, u[1] + (v[1] - u[1]) * w];
    }

    // Three samples a span: denser curves reach the kernel as many short
    // arcs, and a shell of that surface fails far more often (0 of 4 test
    // vessels at 8 samples, 3 of 4 at 3).
    const samples = 3;
    for (var k = 1; k <= samples; k++) {
      if (k == samples) {
        out.add(b);
        break;
      }
      final t = t1 + (t2 - t1) * k / samples;
      final a1 = lerp(p0, a, t0, t1, t), a2 = lerp(a, b, t1, t2, t);
      final a3 = lerp(b, p3, t2, t3, t);
      final b1 = lerp(a1, a2, t0, t2, t), b2 = lerp(a2, a3, t1, t3, t);
      final c = lerp(b1, b2, t1, t2, t);
      out.add([math.max(0.0, c[0]), c[1]]);
    }
  }
  // Still crossing itself somewhere: the straight profile, as given.
  return _crossesItself(out) ? pts : out;
}

/// Whether two non-adjacent segments of the closed outline [l] cross.
bool _crossesItself(List<List<num>> l) {
  final n = l.length;
  double cr(List<num> o, List<num> a, List<num> b) =>
      ((a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])).toDouble();
  for (var i = 0; i < n; i++) {
    final a = l[i], b = l[(i + 1) % n];
    for (var j = i + 2; j < n; j++) {
      if (i == 0 && j == n - 1) continue; // they share a point
      final c = l[j], d = l[(j + 1) % n];
      final d1 = cr(c, d, a), d2 = cr(c, d, b);
      final d3 = cr(a, b, c), d4 = cr(a, b, d);
      if (((d1 > 1e-12 && d2 < -1e-12) || (d1 < -1e-12 && d2 > 1e-12)) &&
          ((d3 > 1e-12 && d4 < -1e-12) || (d3 < -1e-12 && d4 > 1e-12))) {
        return true;
      }
    }
  }
  return false;
}

/// A "part" name as given, made usable: "Tisch-Haken" is Tisch_Haken, not
/// a refused block.
String aiProgramPartName(String? raw) {
  var n = (raw ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
  n = n.replaceAll(RegExp(r'^_+|_+$'), '');
  if (n.isEmpty) return 'part';
  if (!RegExp(r'^[A-Za-z]').hasMatch(n)) n = 'p$n';
  return n.length > 24 ? n.substring(0, 24) : n;
}

extension AiCadProgram on AiCad {
  Future<AiActionOutcome> _program(PartModel p, AiAction a) async {
    final part = aiProgramPartName(a.text('part'));
    final raw = a.args['steps'];
    if (raw is List && raw.isEmpty) {
      // "steps": [] removes the part — the way to drop a draft version.
      if (!p.features.any((f) => f.name.startsWith('p_${part}_'))) {
        // A BODY name ("Solid7") whose every feature a program made: that
        // body goes. The model met a stray body of its own and could only
        // ask the user to delete it. A body the user built is never
        // removed this way.
        final rows = [
          for (final f in p.features)
            if (f.bodyName == a.text('part')) f
        ];
        if (rows.isNotEmpty && rows.every((f) => f.name.startsWith('p_'))) {
          for (final f in rows.reversed) {
            final o = await _one(p, AiAction('delete_feature', {'feature': f.name}));
            if (!o.ok) return AiActionOutcome.failed(a.op, o.error!);
          }
          _programBodies.removeWhere((_, b) => b == a.text('part'));
          return AiActionOutcome(a.op,
              detail: {'body': a.text('part'), 'removed': true});
        }
        return AiActionOutcome.failed(a.op, 'there is no part "$part" to remove');
      }
      final (_, err) = await _programBegin(p, part);
      if (err != null) return AiActionOutcome.failed(a.op, err);
      return AiActionOutcome(a.op, detail: {'part': part, 'removed': true});
    }
    if (raw is! List) {
      return AiActionOutcome.failed(a.op, 'a program needs "steps": [...]');
    }
    final others = [
      for (final k in _programBodies.keys)
        if (k != part) k
    ];
    // Repeats are expanded first, so every later message names a real step.
    final steps = <(int, String, Map<String, dynamic>)>[];
    final repeats = <int, Map<String, dynamic>>{}; // step -> its "repeat"
    for (var i = 0; i < raw.length; i++) {
      final one = _programStepOf(raw[i]);
      if (one == null) {
        return AiActionOutcome.failed(a.op,
            'step ${i + 1}: every step is one shape or feature, as '
            '{"cylinder": {...}} — got ${jsonEncode(raw[i])}');
      }
      final (kind, params) = one;
      final (copies, err) = _repeat(kind, params);
      if (err != null) {
        return AiActionOutcome.failed(a.op, 'step ${i + 1} ($kind): $err');
      }
      for (final c in copies) {
        steps.add((i + 1, kind, c));
      }
      if (copies.length >= 3 && params['repeat'] is Map) {
        repeats[i + 1] = (params['repeat'] as Map).cast<String, dynamic>();
      }
    }

    // STREAMED? The steps that already ran while the reply was being
    // written are skipped, if they are exactly the ones this program starts
    // with; anything else is undone and the program runs from the top.
    // ON an existing body: the steps change that body, and sending the
    // program again replaces only what the program did to it.
    // "on" written into every step instead of once: the same thing.
    var onName = a.text('on');
    if (onName == null && raw.isNotEmpty) {
      final each = {
        for (final st in raw)
          if (st is Map)
            (st.values.whereType<Map>().firstOrNull?['on'] ?? st['on'])
      };
      if (each.length == 1 && each.single is String) onName = each.single as String;
    }
    String? on;
    if (onName != null) {
      on = _programBodies[aiProgramPartName(onName)] ?? onName;
      // "on" the body this very program made is just sending it again: the
      // rebuild removes that body first, and joining onto it then failed.
      final makers = [
        for (final f in p.features)
          if (f.bodyName == on) f.name
      ];
      if (makers.isNotEmpty &&
          makers.every((n) => n.startsWith('p_${part}_'))) {
        on = null;
      }
    }
    if (on != null) {
      if (currentBodySolid(p, on) == null) {
        final names = [for (final (n, _) in p.solidBodies()) n];
        return AiActionOutcome.failed(a.op,
            '"on": there is no body "$onName" — the bodies are ${names.join(', ')}');
      }
    }
    final live = _live;
    _ProgramState st;
    var from = 0;
    if (live != null &&
        on == null &&
        live.part == part &&
        !live.broken &&
        live.done.length <= steps.length &&
        [for (var k = 0; k < live.done.length; k++)
          jsonEncode([steps[k].$2, steps[k].$3]) == live.done[k]]
            .every((ok) => ok)) {
      st = live.state;
      from = live.done.length;
    } else {
      if (live != null) {
        await app.aiRestore(p, live.snap);
        app.aiForgetRegions();
        _live = null;
      }
      final (s0, err) = await _programBegin(p, part);
      if (s0 == null) return AiActionOutcome.failed(a.op, err!);
      st = s0..body = on;
    }
    for (var k = from; k < steps.length; k++) {
      final (index, kind, params) = steps[k];
      // A repeated hole is ONE hole feature with many places, as in any CAD:
      // one boolean instead of one per copy on an ever busier body.
      // A repeated SHAPE (three copies or more, onto a body that exists) is
      // the first copy and ONE pattern feature: the pattern unites the
      // copies and meets the body once. Copy by copy, 48 spherical grip
      // dimples on a knob took up to 178 s a block (AI lab).
      final rep = repeats[index];
      if (rep != null &&
          kind != 'hole' &&
          _kProgramShapes.contains(kind) &&
          st.body != null &&
          (k == 0 || steps[k - 1].$1 != index)) {
        final n = steps.where((q) => q.$1 == index).length;
        final done = await _programPattern(p, st, index, kind, params, rep, n);
        if (done != null) {
          if (done.isNotEmpty) return AiActionOutcome.failed(a.op, done);
          k += n - 1;
          continue;
        }
        // Null: the pattern did not build — the copies run one by one.
      }
      final group = kind == 'hole' ? _holeGroup(p, st, steps, k) : null;
      if (group != null) {
        final merged = await _programStep(p, st, index, kind, {
          ...params,
          '_places': [for (final g in group) g.$3['at']],
        });
        if (merged == null) {
          k += group.length - 1;
          continue;
        }
        // Refused as a whole: run the copies one by one, which names the
        // copy that is wrong.
      }
      final skippedBefore = st.skipped.length;
      final err = await _programStep(p, st, index, kind, params);
      final nCopies = steps.where((s) => s.$1 == index).length;
      if (st.skipped.length > skippedBefore && nCopies > 1) {
        final j0 = steps.indexWhere((s) => s.$1 == index);
        st.skipped[st.skipped.length - 1] = st.skipped.last.replaceFirst(
            'step $index (', 'step $index, copy ${k - j0 + 1} of $nCopies (');
      }
      if (err != null) {
        // Which copy of a repeat: the first ones may have cut fine.
        final n = steps.where((s) => s.$1 == index).length;
        final j = steps.indexWhere((s) => s.$1 == index);
        return AiActionOutcome.failed(
            a.op,
            n > 1
                ? err.replaceFirst('step $index (',
                    'step $index, copy ${k - j + 1} of $n (')
                : err);
      }
    }
    final body = st.body;
    final built = st.built;
    final old = st.replaced;
    if (body == null) {
      return AiActionOutcome.failed(a.op, 'the program built no body');
    }
    _programBodies[part] = body;
    // A NEW name for what is plainly the same part again — it fills most of
    // the space an earlier program part fills — is a new version, not a
    // second part: the earlier one goes. A mug rebuilt as "Mug2", "Mug3"
    // left three cups standing inside each other (AI lab). Two real parts
    // do not fill the same space.
    final superseded = <String>[];
    if (old == 0 && on == null) {
      superseded.addAll(await _supersededBy(p, part, body));
      for (final other in superseded) {
        await _programBegin(p, other);
      }
    }
    // Every sketch is an internal of the program: none stays on screen (a
    // sketch shared by two features kept its lines in the renders).
    for (final cs in p.childSketches) {
      if (cs.model.name.startsWith('p_${part}_')) {
        p.sketchByName(cs.model.name)?.visible = false;
      }
    }
    final solid = currentBodySolid(p, body);
    final bb = solid?.shape?.bbox();
    final expect = a.args['expect'];
    final checks = expect is Map
        ? await _expectations(p, body, expect.cast<String, dynamic>())
        : <Map<String, dynamic>>[];
    // One piece unless the program says otherwise: a join that floated is
    // no longer refused step by step, so it is caught here.
    if (!(expect is Map && expect.containsKey('pieces')) && solid != null) {
      final got = meshComponentCount(solid.mesh);
      if (got != 1) {
        checks.add({
          'what': 'pieces (a shape that touches nothing floats loose)',
          'want': 1, 'got': got, 'ok': false,
        });
      }
    }
    final failed = [
      for (final c in checks)
        if (c['ok'] != true) c
    ];
    if (failed.isNotEmpty || st.skipped.isNotEmpty) {
      _expectFailures[part] = [
        ...st.skipped,
        for (final c in failed)
          'Part "$part" (${body}): expected ${c['what']} ${jsonEncode(c['want'])}, '
              'measured ${jsonEncode(c['got'])}.'
      ];
    }
    return AiActionOutcome(a.op, detail: {
      'part': part,
      'body': body,
      'steps': steps.length,
      'features': built.length,
      if (bb != null && bb.length == 6)
        'sizeMm': [_r(bb[3] - bb[0]), _r(bb[4] - bb[1]), _r(bb[5] - bb[2])],
      if (bb != null && bb.length == 6)
        'extentMm': {
          'x': [_r(bb[0]), _r(bb[3])],
          'y': [_r(bb[1]), _r(bb[4])],
          'z': [_r(bb[2]), _r(bb[5])],
        },
      if (solid != null) 'volumeMm3': _r(solid.volume),
      if (solid != null && bb != null && bb.length == 6)
        'sections': _sectionDigest(solid, bb[1], bb[4]),
      if (solid != null) ...?_boresReport(p, body, solid),
      if (solid != null && (aiCapacityMl(solid.mesh) ?? 0) >= 1)
        'holdsMl': _r(aiCapacityMl(solid.mesh)!),
      if (checks.isNotEmpty) 'expect': checks,
      if (bb != null && bb.length == 6 && bb[1] < -0.05)
        'belowGround': 'the part reaches y ${_r(bb[1])}, below the ground '
            '(y = 0). Y is UP: a box size is [x, height, z].',
      if (old > 0) 'replaced': 'the previous "$part" ($old features)',
      if (st.notes.isNotEmpty) 'notes': st.notes,
      if (on == null) ...?_relations(p, body),
      if (superseded.isNotEmpty)
        'replacedVersion': 'the earlier ${superseded.join(', ')} filled the '
            'same space, so this is its new version and it was removed — send '
            'a part again under its own name to change it',
      if (old == 0 && others.isNotEmpty && superseded.isEmpty)
        'otherParts': 'also in the model: ${others.join(', ')}. A new name '
            'ADDS a part; to change one, send it under its own name; '
            '{"part": "<name>", "steps": []} removes it.',
    });
  }

  /// A step as (kind, arguments), or null. `{"hole": {...}, "repeat": {...}}`
  /// — an option written NEXT TO the shape instead of inside it — is the
  /// same step: the one key holding an object is the shape, the rest are
  /// its options.
  static (String, Map<String, dynamic>)? _programStepOf(Object? s) {
    if (s is! Map || s.isEmpty) return null;
    final shapes = [
      for (final e in s.entries)
        if (e.value is Map && e.key != 'repeat') e
    ];
    if (shapes.length != 1) return null;
    final params = Map<String, dynamic>.from(shapes.single.value as Map);
    for (final e in s.entries) {
      if (e.key != shapes.single.key) params.putIfAbsent('${e.key}', () => e.value);
    }
    return ('${shapes.single.key}', params);
  }

  /// The first copy of a repeated shape, then one pattern feature of it.
  /// '' when done; an error for the program when the FIRST copy fails (as
  /// it would one by one); null when the pattern could not be built and the
  /// copies should run one by one instead.
  Future<String?> _programPattern(PartModel p, _ProgramState st, int index,
      String kind, Map<String, dynamic> first, Map<String, dynamic> rep,
      int count) async {
    final before = st.built.length;
    final snap = app.aiSnapshot(p);
    final err = await _programStep(p, st, index, kind, first);
    if (err != null) return err;
    final made = st.built.sublist(before);
    if (made.isEmpty) return null; // skipped (it cut nothing): one by one
    final step = rep['step'], around = rep['around'];
    final Map<String, dynamic> args;
    if (step is List && step.length == 3) {
      final v = [for (final e in step) (e as num).toDouble()];
      final len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
      if (len < 1e-9) return null;
      args = {
        'kind': 'rect',
        'features': made,
        'count': count,
        'spacing': len,
        'direction': [for (final e in v) e / len],
      };
    } else if (around is List && around.length == 2) {
      final total = (rep['angle'] as num?)?.toDouble() ?? 360;
      args = {
        'kind': 'circ',
        'features': made,
        'count': count,
        'angle': total,
        // The same turn the copies were placed by: about -Y (see [_repeat]).
        'axis': [0, -1, 0],
        'centre': [(around[0] as num).toDouble(), 0, (around[1] as num).toDouble()],
      };
    } else {
      return null;
    }
    _inProgram++;
    try {
      final o = await _one(p, AiAction('pattern', {
        ...args,
        'body': st.body,
        'id': st.next(),
      }));
      if (!o.ok) {
        // Back to before the first copy; the caller runs them one by one.
        await app.aiRestore(p, snap);
        st.built.removeRange(before, st.built.length);
        return null;
      }
      final f = o.detail?['feature'];
      if (f is String) st.built.add(f);
      return '';
    } finally {
      _inProgram--;
    }
  }

  /// A blind hole whose floor lands ON the far face of the wall (depth 4 in
  /// a 4 mm leg) is meant to go through: drilled as it stands it leaves a
  /// floor of zero thickness, and a fillet next to it CRASHED the kernel (an
  /// L bracket, AI lab). Material just short of the floor and none just past
  /// it is that case.
  Map<String, dynamic> _holeDepthSnapped(
      PartModel p, _ProgramState st, Map<String, dynamic> m) {
    final depth = m['depth'];
    final at = _vec3(m['at']);
    final into = '${m['into'] ?? '-y'}';
    if (depth is! num || at == null || st.body == null) return m;
    if (!RegExp(r'^[+-][xyz]$').hasMatch(into)) return m;
    final solid = currentBodySolid(p, st.body!);
    if (solid == null) return m;
    final k = const {'x': 0, 'y': 1, 'z': 2}[into[1]]!;
    bool inside(double sign, double t) {
      final q = [...at]..[k] += sign * t;
      return aiInsideMesh(solid.mesh, q[0], q[1], q[2]);
    }

    final d = depth.toDouble();
    // Probed on the hole's axis, which is still material before it is cut —
    // both ways, because a hole pointed away from the part is drilled the
    // other way (see the flip in _commitFeature).
    for (final sign in const [1.0, -1.0]) {
      if (inside(sign, d - 0.05) && !inside(sign, d + 0.05)) {
        return Map<String, dynamic>.of(m)..remove('depth');
      }
    }
    return m;
  }

  /// The copies of the repeated hole starting at [k] when they can be one
  /// feature: the same hole on one plane, every copy entering material at
  /// its "at". Null otherwise (then they run one by one).
  List<(int, String, Map<String, dynamic>)>? _holeGroup(PartModel p,
      _ProgramState st, List<(int, String, Map<String, dynamic>)> steps, int k) {
    final first = steps[k];
    final group = [
      for (var i = k; i < steps.length && steps[i].$1 == first.$1; i++) steps[i]
    ];
    if (group.length < 2 || st.body == null) return null;
    final solid = currentBodySolid(p, st.body!);
    if (solid == null) return null;
    final into = '${first.$3['into'] ?? '-y'}';
    if (!RegExp(r'^[+-][xyz]$').hasMatch(into)) return null;
    final axis = const {'x': 0, 'y': 1, 'z': 2}[into[1]]!;
    final sign = into[0] == '+' ? 1.0 : -1.0;
    String same(Map<String, dynamic> m) =>
        jsonEncode({for (final e in m.entries) if (e.key != 'at') e.key: e.value});
    final key = same(first.$3);
    final a0 = _vec3(first.$3['at']);
    if (a0 == null) return null;
    final d = _num(first.$3['d']);
    final probe = math.min(0.05, math.max(d, 0.1) * 0.1);
    for (final g in group) {
      final at = _vec3(g.$3['at']);
      if (at == null || same(g.$3) != key) return null;
      if ((at[axis] - a0[axis]).abs() > 1e-9) return null;
      final q = [...at]..[axis] += sign * probe;
      if (!aiInsideMesh(solid.mesh, q[0], q[1], q[2])) return null;
    }
    return group;
  }

  /// Where a NEW part stands against every other body, in numbers: the gap
  /// or overlap on each axis, and for each of its bores the nearest shaft
  /// of the other body on a parallel axis — how far off that axis it is and
  /// how much the two overlap along it. The model placed a spool 4.7 mm
  /// below the shaft it was told about; this is where it can read that.
  Map<String, dynamic>? _relations(PartModel p, String body) {
    final mine = currentBodySolid(p, body);
    if (mine == null) return null;
    final others = [
      for (final (n, _) in p.solidBodies())
        if (n != body && currentBodySolid(p, n) != null) n
    ];
    if (others.isEmpty) return null;
    final mb = AiCad._boxOf(mine);
    final myRound = digests.of(p, body, app.partKernel)?.roundFeatureList() ??
        const [];
    ({int axis, double lo, double hi}) worldSpan(
        ({DigestFace f, double lo, double hi, bool partial}) g) {
      final d = g.f.dir;
      final k = d.x.abs() > 0.999 ? 0 : d.y.abs() > 0.999 ? 1 : d.z.abs() > 0.999 ? 2 : -1;
      if (k < 0) return (axis: -1, lo: g.lo, hi: g.hi);
      final flip = [d.x, d.y, d.z][k] < 0;
      return (axis: k, lo: flip ? -g.hi : g.lo, hi: flip ? -g.lo : g.hi);
    }

    const names = ['x', 'y', 'z'];
    final out = <String>[];
    for (final o in others.take(4)) {
      final ob = AiCad._boxOf(currentBodySolid(p, o)!);
      final parts = <String>[];
      for (var k = 0; k < 3; k++) {
        final gapBelow = ob[k] - mb[k + 3]; // mine ends before it starts
        final gapAbove = mb[k] - ob[k + 3];
        if (gapBelow > 0.01) {
          parts.add('${names[k]}: yours ends ${_r(gapBelow)} before it '
              '(${_r(mb[k])}..${_r(mb[k + 3])} vs ${_r(ob[k])}..${_r(ob[k + 3])})');
        } else if (gapAbove > 0.01) {
          parts.add('${names[k]}: yours starts ${_r(gapAbove)} after it '
              '(${_r(mb[k])}..${_r(mb[k + 3])} vs ${_r(ob[k])}..${_r(ob[k + 3])})');
        } else {
          parts.add('${names[k]}: overlapping');
        }
      }
      var line = '$o — ${parts.join('; ')}';
      final shafts = [
        for (final g in digests.of(p, o, app.partKernel)?.roundFeatureList() ??
            const <({DigestFace f, double lo, double hi, bool partial})>[])
          if (!g.f.concave) g
      ];
      for (final bore in myRound.where((g) => g.f.concave)) {
        final bs = worldSpan(bore);
        if (bs.axis < 0) continue;
        ({DigestFace f, double lo, double hi, bool partial})? best;
        var bestOff = double.infinity, bestScore = double.infinity;
        for (final sh in shafts) {
          final ss = worldSpan(sh);
          if (ss.axis != bs.axis) continue;
          final a = [bore.f.at.x, bore.f.at.y, bore.f.at.z];
          final b = [sh.f.at.x, sh.f.at.y, sh.f.at.z];
          var off = 0.0;
          for (var k = 0; k < 3; k++) {
            if (k != bs.axis) off += (a[k] - b[k]) * (a[k] - b[k]);
          }
          off = math.sqrt(off);
          // The shaft a bore is FOR has about its diameter: ranked first.
          final score = off +
              100 * (sh.f.diameter - bore.f.diameter).abs() /
                  math.max(bore.f.diameter, 0.1);
          if (best == null || score < bestScore) {
            bestScore = score;
            bestOff = off;
            best = sh;
          }
        }
        if (best == null || bestOff > 3 * best.f.diameter + 1) continue;
        final ss = worldSpan(best);
        final along = math.min(bs.hi, ss.hi) - math.max(bs.lo, ss.lo);
        line += '. Your Ø${_r(bore.f.diameter)} bore and its F${best.f.id} '
            'Ø${_r(best.f.diameter)} shaft: axes ${_r(bestOff)} mm apart; '
            'along ${names[bs.axis]} yours ${_r(bs.lo)}..${_r(bs.hi)}, the '
            'shaft ${_r(ss.lo)}..${_r(ss.hi)}'
            '${along > 0 ? ' (sharing ${_r(along)} mm)' : ' (they do not meet)'}';
      }
      out.add(line);
    }
    return {'relations': out};
  }

  /// Earlier program parts that [body] (part [part], just built) mostly
  /// occupies: over half of the smaller one's volume is shared.
  Future<List<String>> _supersededBy(
      PartModel p, String part, String body) async {
    final mine = currentBodySolid(p, body);
    if (mine == null || !app.partKernel.available) return const [];
    final mb = AiCad._boxOf(mine);
    final out = <String>[];
    for (final e in _programBodies.entries.toList()) {
      if (e.key == part || e.value == body) continue;
      final other = currentBodySolid(p, e.value);
      if (other == null) continue;
      final ob = AiCad._boxOf(other);
      final overlap = [
        for (var k = 0; k < 3; k++)
          math.min(mb[k + 3], ob[k + 3]) - math.max(mb[k], ob[k])
      ];
      if (overlap.any((o) => o <= 0)) continue;
      KernelSolid? common;
      try {
        common = app.partKernel.intersectSolids(mine, other);
        final shared = common?.volume ?? 0;
        if (shared > 0.5 * math.min(mine.volume, other.volume)) {
          out.add(e.key);
        }
      } catch (_) {
      } finally {
        common?.shape?.dispose();
      }
    }
    return out;
  }

  /// Clears the previous version of [part] and starts a new one.
  Future<(_ProgramState?, String?)> _programBegin(PartModel p, String part) async {
    final prefix = 'p_${part}_';
    final old = [
      for (final f in p.features.reversed)
        if (f.name.startsWith(prefix)) f.name
    ];
    for (final name in old) {
      final o = await _one(p, AiAction('delete_feature', {'feature': name}));
      if (!o.ok) {
        return (null, 'could not replace the previous "$part": ${o.error}');
      }
    }
    p.childSketches.removeWhere((cs) => cs.model.name.startsWith(prefix));
    _programBodies.remove(part);
    _expectFailures.remove(part);
    return (_ProgramState(part, prefix, old.length), null);
  }

  /// Runs one (expanded) step; null, or why it failed.
  ///
  /// Inside a program a shape may stand alone for a
  /// moment (the legs first, then the top that joins them), so the per-step
  /// "does not touch the body it joins" refusal is off here; the finished
  /// part is checked for loose pieces instead.
  Future<String?> _programStep(PartModel p, _ProgramState st, int index,
      String kind, Map<String, dynamic> params) async {
    _inProgram++;
    try {
      // A smooth revolve is remembered with the model as it was before it,
      // so a shell that cannot offset the smooth surface can fall back.
      if (kind == 'revolve' && params['smooth'] == true) {
        st.smoothRevolve = (app.aiSnapshot(p), st.built.length, index, params,
            st.body);
      } else if (kind != 'shell') {
        st.smoothRevolve = null;
      }
      final err = await _programStepInner(p, st, index, kind, params);
      final sr = st.smoothRevolve;
      if (err != null && kind == 'shell' && sr != null) {
        // A shell straight after a SMOOTH revolve that does not offset (the
        // kernel meets the curve as many short arcs, and "no parameter on
        // edge" is the usual answer): the revolve again with straight
        // segments between the same points, then the shell again.
        st.smoothRevolve = null;
        await app.aiRestore(p, sr.$1);
        st.built.removeRange(sr.$2, st.built.length);
        st.body = sr.$5;
        final plain = Map<String, dynamic>.of(sr.$4)..remove('smooth');
        final again = await _programStepInner(p, st, sr.$3, 'revolve', plain);
        if (again != null) return err;
        final shelled = await _programStepInner(p, st, index, kind, params);
        if (shelled != null) return shelled;
        st.notes.add('step ${sr.$3} (revolve): the smooth curve could not '
            'be shelled, so it was built with straight segments between your '
            'points — more points give a rounder form');
        return null;
      }
      return err;
    } finally {
      _inProgram--;
    }
  }

  Future<String?> _programStepInner(PartModel p, _ProgramState st, int index,
      String kind, Map<String, dynamic> params) async {
    // Written BEFORE the step runs: a kernel fault inside it ends the log
    // here, and this line is then the only record of what was asked.
    final said = jsonEncode(params);
    Log.i('ai', 'program ${st.part} step $index $kind '
        '${said.length > 400 ? '${said.substring(0, 400)}…' : said}');
    final mode = '${params['mode'] ?? 'add'}'.toLowerCase();
    if (!const {'add', 'cut', 'common'}.contains(mode)) {
      return 'step $index ($kind): "mode" is "add", "cut" or "common"';
    }
    if (st.body == null && _kProgramShapes.contains(kind) && mode != 'add') {
      return 'step $index ($kind): the first shape must ADD material — there '
          'is nothing to $mode yet';
    }
    if (kind == 'hole') params = _holeDepthSnapped(p, st, params);
    final operation = st.body == null
        ? 'new'
        : switch (mode) { 'cut' => 'cut', 'common' => 'intersect', _ => 'join' };
    final (actions, why) =
        _compileStep(kind, params, operation, st.body, st.next);
    if (actions == null) return 'step $index ($kind): $why';
    for (final act in actions) {
      final o = await _one(p, act);
      // A blend is a finishing touch: one that cannot be built (no edge
      // matched, no radius fits) is skipped and reported, and the part
      // stands without it — a failed rim fillet threw away a whole cup.
      if (!o.ok && (kind == 'fillet' || kind == 'chamfer')) {
        st.skipped.add('step $index ($kind) was skipped: ${o.error}');
        return null;
      }
      if (!o.ok && (o.error ?? '').contains('removed no material')) {
        // A cut in empty space harms nothing: it is skipped and reported,
        // and the rest of the part is built. Refusing the whole program for
        // it threw away every good step with it — 36 times on one cable
        // clip (AI lab), and the model never saw a part to correct.
        st.skipped.add('step $index ($kind) was skipped: ${o.error}');
        return null;
      }
      if (!o.ok) return 'step $index ($kind): ${o.error}';
      final b = o.detail?['body'];
      if (b is String && st.body == null && !kAiReadOnlyOps.contains(act.op)) {
        st.body = b;
      }
      final f = o.detail?['feature'];
      if (f is String) st.built.add(f);
    }
    return null;
  }

  /// STREAMING: runs the steps of a program that have arrived so far, while
  /// the rest is still being written. Called with everything parsed so far;
  /// only steps not yet run are run, in order, one call at a time. The
  /// document is snapshot first; the final `program` action either carries
  /// on from here or restores that snapshot and runs from the top.
  Future<void> streamProgram(String part, Map<String, dynamic> vars,
      List<Map<String, dynamic>> steps) {
    final prev = _liveQueue;
    final name = aiProgramPartName(part);
    final next = prev.then((_) => _streamProgram(name, vars, steps));
    _liveQueue = next.catchError((_) {});
    return _liveQueue;
  }

  Future<void> _streamProgram(String part, Map<String, dynamic> vars,
      List<Map<String, dynamic>> raw) async {
    final p = app.currentPart;
    if (p == null) return;
    var live = _live;
    if (live != null && (live.part != part || live.broken)) return;
    if (live == null) {
      final snap = app.aiSnapshot(p);
      if (vars.isNotEmpty) {
        final (v, why) = _resolve(p, AiAction('vars', vars));
        if (v == null || !(await _one(p, v)).ok) return;
      }
      final (st, err) = await _programBegin(p, part);
      if (st == null) {
        await app.aiRestore(p, snap);
        return;
      }
      live = _live = _LiveProgram(part, snap, st);
    }
    for (var i = live.rawDone; i < raw.length; i++) {
      final s = raw[i];
      live.rawDone = i + 1;
      final (resolved, why) = _resolve(p, AiAction('program', {'steps': [s]}));
      final one = resolved == null
          ? null
          : _programStepOf((resolved.args['steps'] as List).single);
      if (one == null) {
        live.broken = true;
        return;
      }
      final (kind, params) = one;
      final (copies, err) = _repeat(kind, params);
      if (err != null) {
        live.broken = true;
        return;
      }
      // A repeated shape streams as ONE pattern too (see [_program]): copy
      // by copy, twelve near-coincident slots on a knob hung the kernel
      // while the reply was still arriving (AI lab).
      final rep = params['repeat'];
      if (copies.length >= 3 &&
          rep is Map &&
          kind != 'hole' &&
          _kProgramShapes.contains(kind) &&
          live.state.body != null) {
        final done = await _programPattern(p, live.state, i + 1, kind,
            copies.first, rep.cast<String, dynamic>(), copies.length);
        if (done != null) {
          if (done.isNotEmpty) {
            live.broken = true;
            return;
          }
          for (final c in copies) {
            live.done.add(jsonEncode([kind, c]));
          }
          app.aiNotify();
          continue;
        }
      }
      for (final c in copies) {
        final e = await _programStep(p, live.state, i + 1, kind, c);
        if (e != null) {
          live.broken = true;
          return;
        }
        live.done.add(jsonEncode([kind, c]));
      }
      app.aiNotify();
      AiTrace.record('program.streamed',
          data: {'part': part, 'step': i + 1, 'kind': kind});
    }
  }

  // ---- repeats ------------------------------------------------------------

  /// A step with "repeat": copies moved by a step vector, or turned about a
  /// vertical axis. Positions (base, center, at, min/max, an extrude's
  /// outline) move; sizes do not.
  (List<Map<String, dynamic>>, String?) _repeat(
      String kind, Map<String, dynamic> params) {
    final r = params['repeat'];
    if (r == null) return ([params], null);
    if (r is! Map) return (const [], '"repeat" must be an object');
    final count = (r['count'] as num?)?.toInt() ?? 0;
    if (count < 1 || count > 200) {
      return (const [], 'repeat.count must be 1..200');
    }
    final base = Map<String, dynamic>.of(params)..remove('repeat');
    final step = r['step'];
    final around = r['around'];
    final out = <Map<String, dynamic>>[];
    for (var k = 0; k < count; k++) {
      List<double> move(List<double> q) {
        if (step is List && step.length == 3) {
          return [
            for (var i = 0; i < 3; i++) q[i] + k * (step[i] as num).toDouble()
          ];
        }
        if (around is List && around.length == 2) {
          final total = (r['angle'] as num?)?.toDouble() ?? 360;
          final ang = (total >= 360 ? total / count : total / math.max(1, count - 1)) *
              k * math.pi / 180;
          final cx = (around[0] as num).toDouble(),
              cz = (around[1] as num).toDouble();
          final dx = q[0] - cx, dz = q[2] - cz;
          return [
            cx + dx * math.cos(ang) - dz * math.sin(ang),
            q[1],
            cz + dx * math.sin(ang) + dz * math.cos(ang)
          ];
        }
        return q;
      }

      if (!(step is List && step.length == 3) &&
          !(around is List && around.length == 2)) {
        return (const [],
            'repeat needs "step": [dx, dy, dz] or "around": [x, z] (a vertical '
            'axis), with "count"');
      }
      final c = Map<String, dynamic>.of(base);
      for (final key in const ['base', 'center', 'at', 'min', 'max']) {
        final v = c[key];
        if (v is List && v.length == 3 && v.every((e) => e is num)) {
          c[key] = move([for (final e in v) (e as num).toDouble()]);
        }
      }
      if (kind == 'extrude' || kind == 'sweep') {
        if (around != null) {
          return (const [],
              'repeat "around" moves positioned shapes (box, cylinder, cone, '
              'sphere, hole); draw the copies of an outline as more outlines');
        }
        // A translation within the plane moves the outline; along its
        // normal it moves "at".
        final plane = '${c['plane'] ?? 'xz'}';
        final d = [for (final e in step as List) k * (e as num).toDouble()];
        final (iu, iv, inormal) = switch (plane) {
          'xy' => (0, 1, 2),
          'yz' => (1, 2, 0),
          _ => (0, 2, 1),
        };
        c['at'] = ((c['at'] as num?)?.toDouble() ?? 0) + d[inormal];
        c.addAll(_shiftShapes(c, d[iu], d[iv]));
      }
      out.add(c);
    }
    return (out, null);
  }

  Map<String, dynamic> _shiftShapes(Map<String, dynamic> c, double du, double dv) {
    List<dynamic> pt(Object? q) => q is List && q.length >= 2
        ? [(q[0] as num) + du, (q[1] as num) + dv, ...q.skip(2)]
        : (q as List? ?? const []);
    Object? shape(Object? s) {
      if (s is List) return [for (final q in s) pt(q)]; // a polygon
      if (s is! Map) return s;
      final m = Map<String, dynamic>.of(s.cast<String, dynamic>());
      if (m['start'] != null) m['start'] = pt(m['start']);
      if (m['segments'] is List) {
        m['segments'] = [
          for (final seg in (m['segments'] as List).cast<Map>())
            {
              for (final e in seg.entries)
                '${e.key}': const {'to', 'through', 'centre', 'center'}.contains(e.key)
                    ? pt(e.value)
                    : e.value
            }
        ];
      }
      for (final k in const ['circle', 'rect', 'slot', 'ngon']) {
        final v = m[k];
        if (v is List && v.length >= 2) {
          final l = [for (final e in v) (e as num).toDouble()];
          l[0] += du;
          l[1] += dv;
          if (k == 'rect' || k == 'slot') {
            l[2] += du;
            l[3] += dv;
          }
          m[k] = l;
        }
      }
      if (m['poly'] is List) m['poly'] = [for (final q in m['poly'] as List) pt(q)];
      return m;
    }

    return {
      if (c['outline'] != null) 'outline': shape(c['outline']),
      if (c['path'] != null) 'path': shape(c['path']),
      if (c['holes'] is List)
        'holes': [for (final h in c['holes'] as List) shape(h)],
    };
  }

  // ---- compiling a step -----------------------------------------------------

  static const Set<String> _kProgramShapes = {
    'box', 'cylinder', 'cone', 'sphere', 'revolve', 'extrude', 'sweep',
  };

  /// World (u, v) in a plane to that plane's sketch coordinates, and the
  /// plane's normal axis. xz: (x, z) — the ground; xy: (x, y); yz: (y, z).
  static (List<double> Function(double, double), int, bool)? _planeMap(
      String plane) {
    switch (plane) {
      case 'xz':
        return ((u, v) => [u, -v], 1, true); // mirror: arcs turn the other way
      case 'xy':
        return ((u, v) => [u, v], 2, false);
      case 'yz':
        return ((u, v) => [-v, u], 0, false);
    }
    return null;
  }

  static double _num(Object? v, [double fallback = 0]) =>
      v is num ? v.toDouble() : fallback;

  static List<double>? _vec3(Object? v) =>
      v is List && v.length == 3 && v.every((e) => e is num)
          ? [for (final e in v) (e as num).toDouble()]
          : null;

  (List<AiAction>?, String?) _compileStep(String kind, Map<String, dynamic> m,
      String operation, String? body, String Function() next) {
    Map<String, dynamic> target(Map<String, dynamic> x) => {
          ...x,
          'operation': operation,
          if (body != null) 'body': body,
        };
    switch (kind) {
      case 'box':
        {
          List<double>? lo = _vec3(m['min']), hi = _vec3(m['max']);
          final size = _vec3(m['size']);
          final c = _vec3(m['center']), b = _vec3(m['base']);
          if (lo == null || hi == null) {
            if (size == null || (c == null && b == null)) {
              return (null,
                  'give "min" and "max" corners, or "size" with "center" or '
                  '"base" (the middle of its bottom face)');
            }
            final mid = c ?? [b![0], b[1] + size[1] / 2, b[2]];
            lo = [for (var i = 0; i < 3; i++) mid[i] - size[i] / 2];
            hi = [for (var i = 0; i < 3; i++) mid[i] + size[i] / 2];
          }
          final sx = hi[0] - lo[0], sy = hi[1] - lo[1], sz = hi[2] - lo[2];
          if (sx <= 0 || sy <= 0 || sz <= 0) {
            return (null, 'max must be larger than min on every axis');
          }
          final sk = next();
          final r = _num(m['r'] ?? m['corner_radius']);
          return ([
            AiAction('create_sketch', {'plane': 'xz', 'offset': lo[1], 'id': sk}),
            r > 0
                ? AiAction('sketch_rounded_rect', {
                    'sketch': sk,
                    'x': (lo[0] + hi[0]) / 2,
                    'y': -(lo[2] + hi[2]) / 2,
                    'width': sx,
                    'height': sz,
                    'radius': r,
                    'centered': true
                  })
                : AiAction('sketch_rect', {
                    'sketch': sk,
                    'x': (lo[0] + hi[0]) / 2,
                    'y': -(lo[2] + hi[2]) / 2,
                    'width': sx,
                    'height': sz,
                    'centered': true
                  }),
            AiAction('extrude', target({'sketch': sk, 'distance': sy, 'id': next()})),
          ], null);
        }
      case 'cylinder':
        {
          final b = _vec3(m['base']) ?? _vec3(m['at']);
          final d = m['d'] is num ? _num(m['d']) : 2 * _num(m['r']);
          final h = _num(m['h']);
          if (b == null || d <= 0 || h == 0) {
            return (null,
                'give "base" [x, y, z] (the middle of its start face), "d" '
                '(or "r") and "h" (length along the axis; negative runs the '
                'other way)');
          }
          final axis = '${m['axis'] ?? 'y'}';
          final (plane, off, pt) = switch (axis) {
            'x' => ('yz', b[0], [-b[2], b[1]]),
            'z' => ('xy', b[2], [b[0], b[1]]),
            _ => ('xz', b[1], [b[0], -b[2]]),
          };
          final sk = next();
          return ([
            AiAction('create_sketch', {'plane': plane, 'offset': off, 'id': sk}),
            AiAction('sketch_circle', {'sketch': sk, 'x': pt[0], 'y': pt[1], 'diameter': d}),
            AiAction('extrude', target({
              'sketch': sk,
              'distance': h.abs(),
              if (h < 0) 'direction': 'flipped',
              'id': next()
            })),
          ], null);
        }
      case 'cone':
        {
          final b = _vec3(m['base']);
          final d1 = _num(m['d1']), d2 = _num(m['d2']), h = _num(m['h']);
          if (b == null || h <= 0 || d1 < 0 || d2 < 0 || d1 + d2 <= 0) {
            return (null, 'give "base" [x, y, z], "d1" at the base, "d2" at the other end, "h" > 0');
          }
          return _revolveActions(
              [[0, 0], [d1 / 2, 0], [d2 / 2, h], [0, h]],
              '${m['axis'] ?? 'y'}', b, target, next);
        }
      case 'sphere':
        {
          final c = _vec3(m['center']);
          final d = m['d'] is num ? _num(m['d']) : 2 * _num(m['r']);
          if (c == null || d <= 0) return (null, 'give "center" and "d"');
          final r = d / 2;
          return _revolveActions(null, 'y', c, target, next, path: {
            'start': [0, -r],
            'segments': [
              {'to': [0, r], 'through': [r, 0]}
            ],
          });
        }
      case 'revolve':
        {
          final b = _vec3(m['base']) ?? const [0.0, 0.0, 0.0];
          final prof = m['profile'];
          if (prof is List && prof.length >= 3) {
            final pts = [for (final q in prof) (q as List).cast<num>()];
            return _revolveActions(
                m['smooth'] == true ? aiSmoothProfile(pts) : pts,
                '${m['axis'] ?? 'y'}', b, target, next);
          }
          if (m['start'] != null && m['segments'] is List) {
            return _revolveActions(null, '${m['axis'] ?? 'y'}', b, target, next,
                path: {'start': m['start'], 'segments': m['segments']});
          }
          return (null,
              'give the half-section as "profile": [[r, h], ...] or "start" + '
              '"segments" (r = distance from the axis, h = along it from base)');
        }
      case 'extrude':
        {
          final plane = '${m['plane'] ?? 'xz'}';
          final map = _planeMap(plane);
          if (map == null) return (null, '"plane" is "xz", "xy" or "yz"');
          final (to, _, mirror) = map;
          final at = _num(m['at']);
          final dist = _num(m['distance']);
          final sym = m['symmetric'] == true;
          if (dist == 0) {
            return (null, 'give "distance" (along the plane\'s normal: +y for xz, +z for xy, +x for yz; negative the other way)');
          }
          final sk = next();
          final draws = <AiAction>[];
          for (final s in [m['outline'], ...(m['holes'] as List? ?? const [])]) {
            if (s == null) continue;
            final (acts, err) = _drawShape(sk, s, to, mirror);
            if (acts == null) return (null, err);
            draws.addAll(acts);
          }
          if (draws.isEmpty) return (null, 'give an "outline"');
          return ([
            AiAction('create_sketch', {'plane': plane, 'offset': at, 'id': sk}),
            ...draws,
            AiAction('extrude', target({
              'sketch': sk,
              'distance': dist.abs(),
              if (sym) 'direction': 'symmetric' else if (dist < 0) 'direction': 'flipped',
              'id': next()
            })),
          ], null);
        }
      case 'sweep':
        {
          final plane = '${m['plane'] ?? 'xy'}';
          final map = _planeMap(plane);
          if (map == null) return (null, '"plane" is "xz", "xy" or "yz"');
          final (to, _, mirror) = map;
          final path = m['path'];
          final d = _num(m['d']);
          if (path is! Map || d <= 0) {
            return (null, 'give "path": {"start", "segments"} in the plane and "d" (the round section)');
          }
          final sk = next();
          final (acts, err) = _drawShape(sk, {...path.cast<String, dynamic>(), 'closed': false}, to, mirror);
          if (acts == null) return (null, err);
          return ([
            AiAction('create_sketch', {'plane': plane, 'offset': _num(m['at']), 'id': sk}),
            ...acts,
            AiAction('sweep', target({'path_sketch': sk, 'profile_circle': d, 'id': next()})),
          ], null);
        }
      case 'hole':
        {
          final at = _vec3(m['at']);
          final d = _num(m['d']);
          final into = '${m['into'] ?? '-y'}';
          if (at == null || d <= 0 || !RegExp(r'^[+-][xyz]$').hasMatch(into)) {
            return (null,
                'give "at" [x, y, z] ON the face it enters, "d", and "into": '
                '"-y" (down, default), "+y", "-x", "+x", "-z" or "+z"');
          }
          if (body == null) return (null, 'a hole needs material — add a shape first');
          final ax = into[1];
          final (plane, off, pt) = switch (ax) {
            'x' => ('yz', at[0], [-at[2], at[1]]),
            'z' => ('xy', at[2], [at[0], at[1]]),
            _ => ('xz', at[1], [at[0], -at[2]]),
          };
          final sk = next();
          final cs = m['countersink'], cb = m['counterbore'];
          // Copies of a repeat, merged (see [_holeGroup]): same plane.
          final many = [
            for (final q in (m['_places'] as List? ?? const []))
              if (_vec3(q) case final v?)
                switch (ax) {
                  'x' => [-v[2], v[1]],
                  'z' => [v[0], v[1]],
                  _ => [v[0], -v[2]],
                }
          ];
          return ([
            AiAction('create_sketch', {'plane': plane, 'offset': off, 'id': sk}),
            AiAction('hole', {
              'sketch': sk,
              if (many.length > 1) 'places': many else ...{
                'x': pt[0],
                'y': pt[1],
              },
              'diameter': d,
              if (m['depth'] is num) 'depth': _num(m['depth']) else 'through_all': true,
              'flip': into.startsWith('+'),
              'body': body,
              if (cs is List && cs.isNotEmpty) ...{
                'type': 'countersink',
                'cs_diameter': cs[0],
                if (cs.length > 1) 'cs_angle': cs[1],
              },
              if (cb is List && cb.length >= 2) ...{
                'type': 'counterbore',
                'cb_diameter': cb[0],
                'cb_depth': cb[1],
              },
              'id': next(),
            }),
          ], null);
        }
      case 'shell':
        if (body == null) return (null, 'shell a shape — add one first');
        return ([
          AiAction('shell', {
            'thickness': _num(m['t'] ?? m['thickness']),
            'open': m['open'] ?? 'top',
            if (m['outward'] == true) 'outward': true,
            'body': body,
            'id': next(),
          })
        ], null);
      case 'fillet':
      case 'chamfer':
        if (body == null) return (null, '$kind a shape — add one first');
        return ([
          AiAction(kind, {
            kind == 'fillet' ? 'radius' : 'distance':
                _num(m['r'] ?? m['radius'] ?? m['d'] ?? m['distance']),
            'edges': m['edges'] ?? 'outer',
            if (m['near'] != null) 'near': m['near'],
            'body': body,
            'id': next(),
          })
        ], null);
      case 'handle':
      case 'shaft_bore':
      case 'lathe':
      case 'enclose':
        {
          final args = Map<String, dynamic>.of(m)..remove('mode');
          if (kind == 'lathe') {
            args['operation'] = operation;
            if (body != null) args['body'] = body;
          } else if (kind != 'enclose' && body != null) {
            args['body'] = body;
          }
          args['id'] = next();
          return ([AiAction(kind, args)], null);
        }
    }
    if (kAiReadOnlyOps.contains(kind)) {
      return (null,
          '$kind reads, it does not build — it is not a program step. The '
          'shape context already lists every body\'s extent and round '
          'features; to ask more, send a block with "actions": '
          '[{"op": "$kind", ...}] and no program');
    }
    return (null,
        'unknown step — shapes: box, cylinder, cone, sphere, revolve, extrude, '
        'sweep, hole; then shell, fillet, chamfer, handle, shaft_bore, lathe, '
        'enclose');
  }

  /// A half-section [r, h] about an axis through [base], as sketch actions.
  (List<AiAction>?, String?) _revolveActions(
      List<List<num>>? profile,
      String axis,
      List<double> base,
      Map<String, dynamic> Function(Map<String, dynamic>) target,
      String Function() next,
      {Map<String, dynamic>? path}) {
    // (r, h) -> world, then world -> the sketch that holds the axis.
    final (String plane, double off, List<double> Function(num, num) sk,
        List<double> axisAt, String sAxis) = switch (axis) {
      // axis +X: plane xy (z = base.z), r along +Y; sketch x = X, y = Y.
      'x' => ('xy', base[2], (r, h) => [base[0] + h, base[1] + r],
          [0.0, base[1]], 'x'),
      // axis +Z: plane yz (x = base.x), r along +Y; sketch x = -Z, y = Y.
      'z' => ('yz', base[0], (r, h) => [-(base[2] + h), base[1] + r],
          [0.0, base[1]], 'x'),
      // axis +Y: plane xy (z = base.z), r along +X.
      _ => ('xy', base[2], (r, h) => [base[0] + r, base[1] + h],
          [base[0], 0.0], 'y'),
    };
    final id = next();
    Map<String, dynamic> draw;
    if (profile != null) {
      if (profile.any((q) => q.length < 2 || q[0] < -1e-9)) {
        return (null, 'every profile point is [r, h] with r ≥ 0');
      }
      final pts = [for (final q in profile) sk(q[0], q[1])];
      draw = {
        'start': pts.first,
        'segments': [for (final q in pts.skip(1)) {'to': q}],
      };
    } else {
      List<double> tr(Object? q) {
        final l = (q as List).cast<num>();
        return sk(l[0], l[1]);
      }

      draw = {
        'start': tr(path!['start']),
        'segments': [
          for (final seg in (path['segments'] as List).cast<Map>())
            {
              for (final e in seg.entries)
                '${e.key}': const {'to', 'through', 'centre', 'center'}.contains(e.key)
                    ? tr(e.value)
                    : e.value
            }
        ],
      };
    }
    return ([
      AiAction('create_sketch', {'plane': plane, 'offset': off, 'id': id}),
      AiAction('sketch_path', {'sketch': id, ...draw, 'closed': true}),
      AiAction('revolve', target({
        'sketch': id,
        'axis': sAxis,
        'axis_at': axisAt,
        'id': next(),
      })),
    ], null);
  }

  /// One 2D shape in world (u, v) of a plane, as sketch actions on [sk].
  (List<AiAction>?, String?) _drawShape(String sk, Object? s,
      List<double> Function(double, double) to, bool mirror) {
    List<double> pt(Object? q) {
      final l = (q as List).cast<num>();
      return to(l[0].toDouble(), l[1].toDouble());
    }

    List<double> vec(Object? q) {
      final l = (q as List).cast<num>();
      final o = to(0, 0), t = to(l[0].toDouble(), l[1].toDouble());
      return [t[0] - o[0], t[1] - o[1]];
    }

    if (s is List) {
      // A polygon: [[u, v], ...].
      return ([
        AiAction('sketch_polygon', {'sketch': sk, 'points': [for (final q in s) pt(q)]})
      ], null);
    }
    if (s is! Map) return (null, 'a shape is [[u, v], ...] or an object');
    final m = s.cast<String, dynamic>();
    if (m['circle'] is List) {
      final c = (m['circle'] as List).cast<num>();
      if (c.length != 3) return (null, '"circle" is [u, v, d]');
      final q = to(c[0].toDouble(), c[1].toDouble());
      return ([
        AiAction('sketch_circle', {'sketch': sk, 'x': q[0], 'y': q[1], 'diameter': c[2]})
      ], null);
    }
    if (m['rect'] is List) {
      final c = (m['rect'] as List).cast<num>();
      if (c.length != 4) return (null, '"rect" is [u0, v0, u1, v1] (two opposite corners)');
      final a = to(c[0].toDouble(), c[1].toDouble()), b = to(c[2].toDouble(), c[3].toDouble());
      final r = _num(m['r']);
      return ([
        AiAction(r > 0 ? 'sketch_rounded_rect' : 'sketch_rect', {
          'sketch': sk,
          'x': (a[0] + b[0]) / 2,
          'y': (a[1] + b[1]) / 2,
          'width': (a[0] - b[0]).abs(),
          'height': (a[1] - b[1]).abs(),
          if (r > 0) 'radius': r,
          'centered': true,
        })
      ], null);
    }
    if (m['slot'] is List) {
      final c = (m['slot'] as List).cast<num>();
      if (c.length != 5) return (null, '"slot" is [u1, v1, u2, v2, width]');
      final a = to(c[0].toDouble(), c[1].toDouble()), b = to(c[2].toDouble(), c[3].toDouble());
      return ([
        AiAction('sketch_slot', {
          'sketch': sk, 'x1': a[0], 'y1': a[1], 'x2': b[0], 'y2': b[1], 'width': c[4]
        })
      ], null);
    }
    if (m['ngon'] is List) {
      // A regular polygon by its across-flats size — a nut or bolt-head
      // pocket. The vertices are trigonometry the model got wrong by hand
      // (a knob's M6 hex pocket, AI lab); flats run along u unless "angle".
      final c = (m['ngon'] as List).cast<num>();
      if (c.length != 4 || c[2] < 3 || c[3] <= 0) {
        return (null, '"ngon" is [u, v, sides, across_flats]');
      }
      final n = c[2].round();
      final rr = c[3] / 2 / math.cos(math.pi / n);
      // One edge centred on +v: flats top and bottom, along u, for any n.
      final turn = _num(m['angle']) * math.pi / 180 + math.pi / 2 - math.pi / n;
      final pts = [
        for (var k = 0; k < n; k++)
          [
            c[0] + rr * math.cos(turn + 2 * math.pi * k / n),
            c[1] + rr * math.sin(turn + 2 * math.pi * k / n),
          ]
      ];
      return _drawShape(sk, pts, to, mirror);
    }
    if (m['poly'] is List) return _drawShape(sk, m['poly'], to, mirror);
    if (m['start'] != null && m['segments'] is List) {
      return ([
        AiAction('sketch_path', {
          'sketch': sk,
          'start': pt(m['start']),
          'segments': [
            for (final seg in (m['segments'] as List).cast<Map>())
              {
                for (final e in seg.entries)
                  if (const {'to', 'through', 'centre', 'center'}.contains(e.key))
                    '${e.key}': pt(e.value)
                  else if (e.key == 'by')
                    'by': vec(e.value)
                  // A mirrored plane (xz) turns every arc the other way.
                  else if (e.key == 'cw' && mirror)
                    'cw': e.value != true
                  else
                    '${e.key}': e.value,
                if (mirror &&
                    !seg.containsKey('cw') &&
                    (seg.containsKey('centre') || seg.containsKey('center') ||
                        seg.containsKey('radius')))
                  'cw': true,
              }
          ],
          if (m['closed'] == false) 'closed': false,
          if (m['corner_radius'] != null) 'corner_radius': m['corner_radius'],
        })
      ], null);
    }
    return (null,
        'a shape is [[u, v], ...], {"circle": [u, v, d]}, {"rect": [u0, v0, u1, '
        'v1], "r"?}, {"slot": [u1, v1, u2, v2, w]} or {"start", "segments"}');
  }

  // ---- expectations -----------------------------------------------------

  /// What the part IS, read the way a person reads a drawing: the horizontal
  /// section at five heights — how many pieces of material, where they
  /// span, how many openings. A model cannot look at its part; it can compare
  /// these numbers with what it meant (a lid open at the top, a stand that is
  /// a plate standing straight up, a bore swallowed by a mounting hole).
  static List<String> _sectionDigest(KernelSolid solid, double y0, double y1) {
    final out = <String>[];
    for (final f in const [0.05, 0.25, 0.5, 0.75, 0.95]) {
      final y = y0 + (y1 - y0) * f;
      final s = aiSectionLoops(solid.mesh, y);
      if (s.pieces.isEmpty) {
        out.add('y ${_r(y)}: no material');
        continue;
      }
      String box(List<double> b) =>
          'x ${_r(b[0])}..${_r(b[2])} z ${_r(b[1])}..${_r(b[3])}';
      final pieces = s.pieces.length == 1
          ? 'material ${box(s.pieces.first)}'
          : '${s.pieces.length} separate areas: '
              '${s.pieces.take(4).map(box).join('; ')}'
              '${s.pieces.length > 4 ? '; ...' : ''}';
      final holes = s.openings.isEmpty
          ? 'no openings'
          : '${s.openings.length} opening${s.openings.length == 1 ? '' : 's'}'
              ' (largest ${box(s.openings.first)})';
      out.add('y ${_r(y)}: $pieces, $holes');
    }
    return out;
  }

  /// Whether the concave cylinder on the axis through [q] along [dir] is a
  /// complete hole: in the section across that axis there is an opening of
  /// diameter [d] centred on it. True when the axis is not along X, Y or Z
  /// (not checked).
  static bool _roundAllTheWay(
          KernelSolid solid, List<double> q, List<double> dir, double d) =>
      _wrapDegrees(solid, q, dir, d) >= 200;

  /// How far round the material wraps the round gap on the axis through [q]
  /// along [dir]: 360 for a closed hole, less for a channel open along its
  /// side or a groove. 360 when the axis is not along X, Y or Z.
  static int _wrapDegrees(
      KernelSolid solid, List<double> q, List<double> dir, double d) {
    final k = [0, 1, 2].firstWhere((i) => dir[i].abs() > 0.999,
        orElse: () => -1);
    if (k < 0) return 360;
    final (u, v) = switch (k) { 0 => (1, 2), 1 => (0, 2), _ => (0, 1) };
    final tol = math.max(0.2, d * 0.1);
    for (final b in aiSectionLoops(solid.mesh, q[k], axis: k).openings) {
      final cu = (b[0] + b[2]) / 2, cv = (b[1] + b[3]) / 2;
      if ((cu - q[u]).abs() > tol || (cv - q[v]).abs() > tol) continue;
      if (((b[2] - b[0]) - d).abs() <= tol && ((b[3] - b[1]) - d).abs() <= tol) {
        return 360;
      }
    }
    // Not closed: how far round does the material wrap it? A clamp on a bar
    // or a snap clip wraps most of the way (a hole, open on one side); a
    // groove along an edge wraps half or less (not a hole). Measured in 5°
    // bins from the section outline running at the bore's radius.
    final bins = List<bool>.filled(72, false);
    double? angleOn((double, double) pt) {
      final du = pt.$1 - q[u], dv = pt.$2 - q[v];
      final r = math.sqrt(du * du + dv * dv);
      if ((r - d / 2).abs() > tol) return null;
      return (math.atan2(dv, du) * 180 / math.pi + 360) % 360;
    }

    for (final loop in aiSliceLoops(solid.mesh, k, q[k] + 1.3e-7)) {
      for (var i = 0; i < loop.length; i++) {
        final a0 = angleOn(loop[i]), a1 = angleOn(loop[(i + 1) % loop.length]);
        if (a0 == null) continue;
        bins[(a0 / 5).floor() % 72] = true;
        if (a1 == null) continue;
        // The arc between two points on the bore, the short way round.
        var span = a1 - a0;
        if (span > 180) span -= 360;
        if (span < -180) span += 360;
        for (var t = 0.0; t.abs() <= span.abs(); t += 2.5 * span.sign) {
          bins[(((a0 + t) % 360 + 360) % 360 / 5).floor() % 72] = true;
          if (span == 0) break;
        }
      }
    }
    return bins.where((b) => b).length * 5;
  }

  /// The report's "bores": every round gap in the part — a hole, a bore, a
  /// channel open along its side — with its axis, where it runs and how far
  /// the material wraps it. The horizontal sections miss a channel that
  /// runs sideways; this line does not.
  Map<String, dynamic>? _boresReport(
      PartModel p, String body, KernelSolid solid) {
    final groups = digests.of(p, body, app.partKernel)?.roundFeatureList() ??
        const <({DigestFace f, double lo, double hi, bool partial})>[];
    const names = ['x', 'y', 'z'];
    final out = <String>[];
    for (final g in groups) {
      if (!g.f.concave) continue;
      final d = g.f.dir;
      final k = d.x.abs() > 0.999 ? 0 : d.y.abs() > 0.999 ? 1 : d.z.abs() > 0.999 ? 2 : -1;
      if (k < 0) continue;
      final q = [g.f.at.x, g.f.at.y, g.f.at.z];
      final dir = [0.0, 0.0, 0.0]..[k] = 1.0;
      final flip = [d.x, d.y, d.z][k] < 0;
      final lo = flip ? -g.hi : g.lo, hi = flip ? -g.lo : g.hi;
      q[k] = (lo + hi) / 2;
      final wrap = _wrapDegrees(solid, q, dir, g.f.diameter);
      if (wrap < 150) continue; // a blend in an inside corner, a shallow groove
      final (u, v) = switch (k) { 0 => (1, 2), 1 => (0, 2), _ => (0, 1) };
      out.add('Ø${_r(g.f.diameter)} along ${names[k]} ${_r(lo)}..${_r(hi)}, '
          'axis at ${names[u]} ${_r(q[u])} ${names[v]} ${_r(q[v])}: '
          '${wrap >= 360 ? 'round all the way' : 'open along one side (material wraps $wrap°)'}');
      if (out.length >= 10) break;
    }
    return out.isEmpty ? null : {'bores': out};
  }

  Future<List<Map<String, dynamic>>> _expectations(
      PartModel p, String body, Map<String, dynamic> e) async {
    final out = <Map<String, dynamic>>[];
    final solid = currentBodySolid(p, body);
    if (solid == null) return out;
    final bb = solid.shape?.bbox();
    void add(String what, Object? want, Object? got, bool ok) =>
        out.add({'what': what, 'want': want, 'got': got, 'ok': ok});
    final size = e['size'];
    if (size is List && size.length == 3 && bb != null && bb.length == 6) {
      final got = [bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2]];
      var ok = true;
      for (var i = 0; i < 3; i++) {
        final w = size[i];
        if (w is! num) continue; // null = not specified on that axis
        final tol = math.max(0.1, w.abs() * 0.005);
        if ((got[i] - w).abs() > tol) ok = false;
      }
      add('size [x, y, z] mm', size, [for (final g in got) _r(g)], ok);
    }
    final ml = e['holdsMl'];
    if (ml is num) {
      final got = aiCapacityMl(solid.mesh) ?? 0;
      add('holdsMl', ml, _r(got), (got - ml).abs() <= ml * 0.05);
    }
    final vol = e['volume'];
    if (vol is num) {
      add('volume mm³', vol, _r(solid.volume),
          (solid.volume - vol).abs() <= vol * 0.02);
    }
    final pieces = e['pieces'];
    if (pieces is num) {
      final got = meshComponentCount(solid.mesh);
      add('pieces', pieces, got, got == pieces);
    }
    // The section at a height: how many openings the material has there —
    // compartments, cells, pockets, bores — and where they are.
    final sec = e['section'];
    for (final one in sec is List ? sec : [sec]) {
      if (one is! Map) continue;
      // Horizontal (y) by default; x or z cut across a part whose shape
      // shows from the side.
      final k = one['x'] is num ? 0 : one['z'] is num ? 2 : 1;
      const names = ['x', 'y', 'z'];
      final y = one[names[k]];
      final want = one['openings'];
      if (y is! num || want is! num) continue;
      final got = aiSectionOpenings(solid.mesh, y.toDouble(), axis: k);
      final (u, v) = switch (k) { 0 => ('y', 'z'), 1 => ('x', 'z'), _ => ('x', 'y') };
      add(
          'openings in the section at ${names[k]} = ${_r(y.toDouble())}',
          want,
          {
            'count': got.length,
            if (got.isNotEmpty)
              'each [${u}0, ${v}0, ${u}1, ${v}1]': [
                for (final b in got.take(8)) [for (final v in b) _r(v)]
              ],
          },
          got.length == want);
    }
    final holes = e['holes'];
    if (holes is List) {
      final found = await _one(p, AiAction('faces_where', {
        'type': 'cylinder', 'limit': 400, 'body': body,
      }));
      final faces = (found.detail?['faces'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final h in holes.whereType<Map>()) {
        final d = _num(h['d']);
        final want = (h['count'] as num?)?.toInt() ?? 1;
        final axes = <List<double>>[];
        var partial = 0;
        for (final f in faces) {
          if (f['concave'] != true) continue;
          if ((_num(f['diameter']) - d).abs() > math.max(0.05, d * 0.01)) continue;
          final q = (f['axisAt'] as List).cast<num>().map((v) => v.toDouble()).toList();
          final dir = (f['dir'] as List).cast<num>().map((v) => v.toDouble()).toList();
          // One bore can be several faces on one axis.
          final same = axes.any((o) {
            final v = [o[0] - q[0], o[1] - q[1], o[2] - q[2]];
            final along = v[0] * dir[0] + v[1] * dir[1] + v[2] * dir[2];
            return v[0] * v[0] + v[1] * v[1] + v[2] * v[2] - along * along < 0.01;
          });
          if (same) continue;
          // A HOLE is round all the way: a groove or a half-bore on an edge
          // (a clamp's "screw holes" running along its flange) is not one.
          if (!_roundAllTheWay(solid, q, dir, d)) {
            partial++;
            continue;
          }
          axes.add(q);
        }
        add('holes Ø$d', want,
            partial == 0
                ? axes.length
                : {'count': axes.length, 'not round all the way': partial},
            axes.length == want);
      }
    }
    final clear = e['clear_of'];
    if (clear is List) {
      for (final other in clear) {
        final name = _programBodies['$other'] ?? '$other';
        final o = currentBodySolid(p, name);
        if (o == null) {
          add('clear of $other', 0, 'no such body', false);
          continue;
        }
        KernelSolid? common;
        try {
          common = app.partKernel.intersectSolids(solid, o);
          final v = common?.volume ?? 0;
          add('clear of $other (overlap mm³)', 0, _r(v), v <= 0.01);
        } finally {
          common?.shape?.dispose();
        }
      }
    }
    return out;
  }
}

class _ProgramState {
  _ProgramState(this.part, this.prefix, this.replaced);
  final String part, prefix;
  final int replaced;
  String? body;
  var n = 0;
  final built = <String>[];
  /// Steps that changed nothing (a cut in empty space), for the report.
  final skipped = <String>[];

  /// What the app did differently from what was written, for the report.
  final notes = <String>[];

  /// The last step, when it was a smooth revolve: the model before it, how
  /// many features were built then, its index, arguments and the body.
  (PartSnap, int, int, Map<String, dynamic>, String?)? smoothRevolve;
  String next() => '$prefix${++n}';
}

class _LiveProgram {
  _LiveProgram(this.part, this.snap, this.state);
  final String part;
  final PartSnap snap;
  final _ProgramState state;
  var rawDone = 0;
  var broken = false;
  final done = <String>[]; // jsonEncode([kind, params]) of each expanded step
}
