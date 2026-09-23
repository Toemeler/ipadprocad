part of 'ai_cad.dart';

/// THE REST OF THE MODELLING TOOLS.
///
/// The assistant could reach extrude, revolve, fillet, chamfer, delete-face
/// and move-face. The app has had hole, sweep, loft, coil, split, combine and
/// the four kinds of pattern the whole time — every one of them a feature
/// with its own panel, its own browser row and its own kernel path — and none
/// of them was in [kAiOps]. A model asked for a spring, a swept handle, a
/// counterbored screw hole or a ring of six bosses had to fake it out of
/// extrusions, or say it could not.
///
/// Every op here builds the SAME feature object the app's own panel builds,
/// through the same [_commitFeature], so what the assistant makes is
/// indistinguishable in the timeline from what a person makes: editable,
/// undoable, and rebuilt by the same fold.
extension AiCadSolids on AiCad {
  // ---- hole ------------------------------------------------------------

  /// Inventor's Modify > Hole. Not an extruded cut: a hole is its own feature
  /// with its own mouth geometry, and the app has carried counterbore,
  /// spotface and countersink since M226.
  Future<AiActionOutcome> _hole(PartModel p, AiAction a) async {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);

    final places = <HolePlace>[];
    for (final pt in a.points('places')) {
      places.add(HolePlace(pt[0], pt[1]));
    }
    // A single hole may be given as x/y rather than a list of one.
    if (places.isEmpty) {
      final x = a.number('x'), y = a.number('y');
      if (x != null && y != null) places.add(HolePlace(x, y));
    }
    if (places.isEmpty) {
      return AiActionOutcome.failed(
          a.op,
          'places must be [[x,y], ...] in sketch coordinates, or give one '
          'hole as x and y');
    }
    if (places.length > 200) {
      return AiActionOutcome.failed(a.op, 'at most 200 holes in one feature');
    }

    final dia = a.number('diameter') ?? (a.number('radius') ?? 0) * 2;
    if (dia <= 0) {
      return AiActionOutcome.failed(a.op, 'diameter must be > 0');
    }
    final through = a.flag('through_all');
    final depth = a.number('depth') ?? 0;
    if (!through && depth <= 0) {
      return AiActionOutcome.failed(
          a.op, 'depth must be > 0, or set through_all');
    }

    final type = holeTypeFrom(a.text('type')?.toLowerCase());
    final cbDia = a.number('cb_diameter') ?? dia * 1.8;
    final cbDepth = a.number('cb_depth') ?? dia * 0.6;
    final csDia = a.number('cs_diameter') ?? dia * 2;
    final csAngle = a.number('cs_angle') ?? 90;
    // The same refusals the panel makes, for the same reason: a hole that
    // silently drills a 0 mm counterbore is a wrong part.
    if ((type == HoleType.counterbore || type == HoleType.spotface) &&
        !(cbDia > dia && cbDepth > 0)) {
      return AiActionOutcome.failed(
          a.op,
          'a ${holeTypeLabel(type).toLowerCase()} needs cb_diameter wider '
          'than the hole (${_mm(dia)}) and cb_depth > 0');
    }
    if (type == HoleType.countersink &&
        !(csDia > dia && csAngle > 0 && csAngle < 180)) {
      return AiActionOutcome.failed(
          a.op,
          'a countersink needs cs_diameter wider than the hole '
          '(${_mm(dia)}) and cs_angle between 0 and 180');
    }

    final body = a.text('body') ??
        (p.features.isEmpty ? p.nextSolidName() : p.features.last.bodyName);
    if (p.features.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'a hole needs material to drill — build a body first');
    }

    // A HOLE IS PLACED ON SKETCH POINTS, and this op places them.
    //
    // `places` is not a list of coordinates the feature stores: the app
    // resolves a hole against TAGGED SKETCH POINTS, which is what makes
    // moving the point move the hole, and what keeps a hole and a
    // sketch-driven pattern agreeing about where "a point in this sketch" is.
    // A person draws them with the point tool first; this op does the same
    // thing in the same block, so the model does not have to know that a hole
    // has a prerequisite.
    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(AiCad._layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];
    app.aiCommitSketch(sketch, [
      ...sketch.geometry,
      for (final place in places)
        Geo(Geo.circle, [place.x, place.y, kSketchPointRadius],
            spline: Geo.pointTag, layer: layer)
    ]);
    sketch.dirty = true;
    app.aiForgetRegions(sketch.name);

    final f = HoleFeature(
      name: p.nextFeatureName('Hole'),
      bodyName: body,
      sketchName: cs.model.name,
      places: places,
      dia: dia,
      depth: depth,
      exprDia: '$dia mm',
      exprDepth: '$depth mm',
      extent: through ? FeatureExtent.throughAll : FeatureExtent.distance,
      flip: a.flag('flip'),
      type: type,
      cbDia: cbDia,
      cbDepth: cbDepth,
      exprCbDia: '$cbDia mm',
      exprCbDepth: '$cbDepth mm',
      csDia: csDia,
      csAngle: csAngle,
      exprCsDia: '$csDia mm',
      exprCsAngle: '$csAngle deg',
    );
    return _commitFeature(p, a, f, currentBodySolid(p, body), {
      'sketch': cs.model.name,
      'holes': places.length,
      'diameter': _r(dia),
      'type': holeTypeName(type),
      if (!through) 'depth': _r(depth),
      'extent': through ? 'throughAll' : 'distance',
      if (type == HoleType.counterbore || type == HoleType.spotface)
        'counterbore': {'diameter': _r(cbDia), 'depth': _r(cbDepth)},
      if (type == HoleType.countersink)
        'countersink': {'diameter': _r(csDia), 'angleDeg': _r(csAngle)},
    });
  }

  // ---- sweep -----------------------------------------------------------

  /// A profile driven along a path curve. The handle of a mug, a pipe run, a
  /// bead round a rim — every one of them is a sweep, and faking one out of
  /// a loft or a stack of extrusions is what a model does when it has no
  /// sweep.
  Future<AiActionOutcome> _sweep(PartModel p, AiAction a) async {
    var profileName = a.text('profile_sketch') ?? a.text('sketch');
    final pathName = a.text('path_sketch') ?? a.text('path');
    if (pathName == null) {
      return AiActionOutcome.failed(
          a.op,
          'path_sketch is required: the sketch holding the OPEN curve the '
          'profile travels along');
    }
    final path = p.sketchByName(pathName);
    if (path == null) {
      return AiActionOutcome.failed(a.op, 'no sketch named "$pathName"');
    }
    final joined = _joinPathChain(path);
    if (profileName == pathName) {
      return AiActionOutcome.failed(
          a.op,
          'the profile and the path must be different sketches — usually on '
          'planes at right angles to each other');
    }
    final start = _pathStart(path);
    if (start == null) {
      return AiActionOutcome.failed(
          a.op,
          'sketch "$pathName" has no open curve to sweep along — a path is a '
          'line, an arc or a polyline, not a closed region');
    }
    final (at, heading) = start;
    // ISSUE #84 — THE PROFILE, PLACED BY THE APP. The handle's circle was
    // drawn on XZ while its path set off along +X, so the sweep folded
    // through itself and every blend on the cup failed for eight rounds.
    // Where the path starts and which way it heads are facts the app has;
    // a profile_circle / profile_rect is drawn THERE, square to it.
    final circle = a.number('profile_circle');
    final rectW = a.number('profile_width'), rectH = a.number('profile_height');
    if (circle != null || rectW != null || rectH != null) {
      if (profileName != null) {
        return AiActionOutcome.failed(a.op,
            'give profile_sketch OR profile_circle/profile_width, not both');
      }
      if (circle != null && circle <= 0 ||
          circle == null && (rectW == null || rectH == null || rectW <= 0 ||
              rectH <= 0)) {
        return AiActionOutcome.failed(a.op,
            'profile_circle is a diameter > 0; a rectangle needs both '
            'profile_width and profile_height > 0');
      }
      final frame = workPlaneFrameAt(at, heading);
      final sketch = SketchModel(p.nextSketchName());
      sketch.insertLayerAboveMarker(AiCad._layerName);
      p.appendChildSketch(ChildSketch(
          sketch, kWorkPlaneKey, frame, true, false, p.nextSeq()));
      app.aiAdmitSketchRow(p);
      _madeSketches.add('${p.name}/${sketch.name}');
      final layer =
          sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];
      app.aiCommitSketch(sketch, [
        if (circle != null)
          Geo(Geo.circle, [0, 0, circle / 2], layer: layer)
        else
          Geo(
              Geo.polyline,
              [
                1, 4, //
                -rectW! / 2, -rectH! / 2, rectW / 2, -rectH / 2,
                rectW / 2, rectH / 2, -rectW / 2, rectH / 2,
              ],
              layer: layer),
      ]);
      sketch.dirty = true;
      app.aiForgetRegions(sketch.name);
      profileName = sketch.name;
    }
    final profile = profileName == null
        ? (p.childSketches.isEmpty ? null : p.childSketches.first)
        : p.sketchByName(profileName);
    if (profile == null) {
      return AiActionOutcome.failed(
          a.op, 'no sketch named "${profileName ?? "?"}" to sweep');
    }
    // A profile the model drew itself is checked against the same facts
    // before the kernel is asked, and the refusal says which way to face.
    final pf = sketchFrameOf(profile);
    final orientationArg = (a.text('orientation') ?? 'path').toLowerCase();
    if (orientationArg == 'path' || orientationArg.startsWith('follow')) {
      final square = pf.n.dot(heading).abs();
      if (square < 0.98) {
        return AiActionOutcome.failed(
            a.op,
            'the profile sketch "${profile.model.name}" faces '
            '${worldAxisName(pf.n)} but the path starts heading '
            '${worldAxisName(heading)} — a swept profile must be square to '
            'its path, or the solid folds through itself. Use '
            'profile_circle: D (the app places it), or draw the profile on '
            'the plane whose normal is ${worldAxisName(heading)}, at the '
            'path start (${_r(at.x)}, ${_r(at.y)}, ${_r(at.z)}).');
      }
      final off = (at - pf.origin).dot(pf.n).abs();
      if (off > 0.05) {
        return AiActionOutcome.failed(
            a.op,
            'the profile sketch lies ${_mm(off)} mm from the start of the '
            'path at (${_r(at.x)}, ${_r(at.y)}, ${_r(at.z)}) — put it on '
            'the path start, or use profile_circle');
      }
    }
    if (identical(profile, path)) {
      return AiActionOutcome.failed(
          a.op,
          'the profile and the path must be different sketches — usually on '
          'planes at right angles to each other');
    }

    app.aiForgetRegions(profile.model.name);
    final regions = app.sessionRegions(profile);
    if (regions.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'sketch "${profile.model.name}" has no closed profile to sweep');
    }
    final curve = _pathCurve(path);
    if (curve == null) {
      return AiActionOutcome.failed(
          a.op,
          'sketch "$pathName" has no open curve to sweep along — a path is a '
          'line, an arc or a polyline, not a closed region');
    }

    final orientation = switch ((a.text('orientation') ?? 'path').toLowerCase()) {
      'path' || 'follow' || 'follow_path' => 0,
      'fixed' || 'parallel' => 1,
      _ => -1,
    };
    if (orientation < 0) {
      return AiActionOutcome.failed(
          a.op, 'orientation must be "path" or "fixed"');
    }
    final taper = a.number('taper') ?? 0;
    if (taper.abs() >= 90) {
      return AiActionOutcome.failed(a.op, 'taper must be between -90 and 90');
    }

    final output = _outputOf(a, p);
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final f = SweepFeature(
      name: p.nextFeatureName('Sweep'),
      bodyName: body,
      sketchName: profile.model.name,
      profiles: [
        for (final r in regions)
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area)
      ],
      path: curve,
      orientation: orientation,
      taperDeg: taper,
      // The kernel refuses a non-zero twist rather than quietly dropping it,
      // so this op does not offer one.
      twistDeg: 0,
      exprTaper: '$taper deg',
      exprTwist: '0 deg',
      output: output,
    );
    p.claimBodyName(body);
    return _commitFeature(p, a, f, base, {
      'profileSketch': profile.model.name,
      'pathSketch': pathName,
      if (joined > 0)
        'pathJoined': 'the $joined connected segments of the path were '
            'joined into one smooth curve to sweep along',
      'profiles': f.profiles.length,
      'pathLengthMm': _r(curve.length),
      'orientation': orientation == 0 ? 'path' : 'fixed',
      if (taper != 0) 'taperDeg': _r(taper),
      'operation': output,
    });
  }

  /// ISSUE #87 — A HANDLE IS LINES AND ARCS, and a sweep follows ONE curve.
  ///
  /// The shape a printable handle wants — legs rising at 30 degrees, joined
  /// by a round arc at the far side — is exactly what `sketch_path` draws,
  /// as several entities. A sweep takes one, so the model reached for a
  /// spline through a handful of points instead, and a spline bunched round
  /// the far side either turns tighter than the tube ("path too tight") or
  /// comes out pointed.
  ///
  /// So when the path sketch holds a single connected run of open lines and
  /// arcs, it is replaced by one smooth spline through dense samples of it —
  /// within a fraction of a millimetre of what was drawn, and one entity the
  /// sweep can follow and a person can still edit. Returns how many entities
  /// were joined, or 0 when there was nothing to join.
  int _joinPathChain(ChildSketch path) {
    final geo = path.model.geometry;
    final open = <int>[
      for (var i = 0; i < geo.length; i++)
        if ((geo[i].type == Geo.line || geo[i].type == Geo.arc) &&
            !geo[i].isConstruction)
          i
    ];
    if (open.length < 2) return 0;
    // Anything else drawn in the sketch makes "the path" ambiguous: leave it.
    if (geo.any((g) =>
        !g.isConstruction && g.type != Geo.line && g.type != Geo.arc)) {
      return 0;
    }
    List<Offset> pts(int i) => sampleEntity(geo[i], arcSamples: 24);
    const tol = 1e-3;
    final ends = {for (final i in open) i: pts(i)};
    // Walk from an end that meets nothing.
    bool meets(Offset q, int self) => open.any((j) =>
        j != self &&
        ((ends[j]!.first - q).distance < tol ||
            (ends[j]!.last - q).distance < tol));
    int? start;
    var reversed = false;
    for (final i in open) {
      if (!meets(ends[i]!.first, i)) {
        start = i;
        break;
      }
      if (!meets(ends[i]!.last, i)) {
        start = i;
        reversed = true;
        break;
      }
    }
    if (start == null) return 0; // a closed loop is a profile, not a path
    final chain = <Offset>[];
    final used = <int>{};
    var cur = start;
    var seq = reversed ? ends[cur]!.reversed.toList() : ends[cur]!;
    while (true) {
      used.add(cur);
      for (final q in seq) {
        if (chain.isEmpty || (chain.last - q).distance > tol) chain.add(q);
      }
      final tail = chain.last;
      int? next;
      for (final j in open) {
        if (used.contains(j)) continue;
        if ((ends[j]!.first - tail).distance < tol) {
          next = j;
          seq = ends[j]!;
          break;
        }
        if ((ends[j]!.last - tail).distance < tol) {
          next = j;
          seq = ends[j]!.reversed.toList();
          break;
        }
      }
      if (next == null) break;
      cur = next;
    }
    if (used.length != open.length || chain.length < 3) return 0;
    // EVEN spacing along the length. A straight leg samples to its two ends
    // and an arc to two dozen points; a fit spline through spacing that
    // uneven overshoots between the sparse points, and the swept tube then
    // folds through itself on a wiggle nobody drew.
    var total = 0.0;
    for (var i = 1; i < chain.length; i++) {
      total += (chain[i] - chain[i - 1]).distance;
    }
    final n = (total / 2.5).ceil().clamp(8, 400);
    final even = <Offset>[chain.first];
    var seg = 1;
    var walked = 0.0;
    for (var k = 1; k < n; k++) {
      final want = total * k / n;
      while (seg < chain.length - 1 &&
          walked + (chain[seg] - chain[seg - 1]).distance < want) {
        walked += (chain[seg] - chain[seg - 1]).distance;
        seg++;
      }
      final a0 = chain[seg - 1], a1 = chain[seg];
      final len = (a1 - a0).distance;
      final t = len < 1e-12 ? 0.0 : ((want - walked) / len).clamp(0.0, 1.0);
      even.add(Offset.lerp(a0, a1, t)!);
    }
    even.add(chain.last);
    chain
      ..clear()
      ..addAll(even);
    final layer = geo[open.first].layer;
    app.aiCommitSketch(path.model, [
      for (var i = 0; i < geo.length; i++)
        if (!open.contains(i)) geo[i],
      Geo(
          Geo.polyline,
          [0, chain.length.toDouble(), for (final q in chain) ...[q.dx, q.dy]],
          spline: Geo.splineFit,
          layer: layer),
    ]);
    path.model.dirty = true;
    app.aiForgetRegions(path.model.name);
    return open.length;
  }

  /// Where the sweep path starts, in world millimetres, and the direction it
  /// sets off in — exact for a line or an arc, the first segment for anything
  /// else.
  (Vec3, Vec3)? _pathStart(ChildSketch path) {
    final curve = _pathCurve(path);
    if (curve == null) return null;
    final g = path.model.geometry[curve.geoIndex];
    final f = sketchFrameOf(path);
    Offset p0, dir;
    if (g.type == Geo.arc) {
      final c = Offset(g.data[0], g.data[1]);
      final r = g.data[2], t = g.data[3];
      p0 = Offset(c.dx + r * math.cos(t), c.dy + r * math.sin(t));
      final ccw = Offset(-math.sin(t), math.cos(t));
      dir = g.data.length > 5 && g.data[5] > 0.5 ? -ccw : ccw;
    } else {
      final pts = sampleEntity(g, arcSamples: 64);
      p0 = pts.first;
      dir = pts[1] - pts[0];
    }
    final w0 = f.toWorld(p0), w1 = f.toWorld(p0 + dir);
    final d = w1 - w0;
    if (d.length < 1e-12) return null;
    return (w0, d * (1 / d.length));
  }

  /// The longest OPEN curve in [path] — what a sweep travels along.
  ///
  /// Geometric, like every other selection the assistant makes: the entity
  /// index is a hint the feature re-validates, and the endpoints and length
  /// are the fingerprint that survives a rebuild.
  CurveSel? _pathCurve(ChildSketch path) {
    final geo = path.model.geometry;
    CurveSel? best;
    var bestLength = 0.0;
    for (var i = 0; i < geo.length; i++) {
      final g = geo[i];
      if (g.type == Geo.circle) continue; // closed: not a path
      if (g.type == Geo.polyline && g.data.isNotEmpty && g.data[0] != 0) {
        continue; // a closed polyline is a region, not a path
      }
      final pts = sampleEntity(g, arcSamples: 24);
      if (pts.length < 2) continue;
      var length = 0.0;
      for (var k = 1; k < pts.length; k++) {
        length += (pts[k] - pts[k - 1]).distance;
      }
      if (length <= bestLength) continue;
      bestLength = length;
      best = CurveSel(path.model.name, i, pts.first.dx, pts.first.dy,
          pts.last.dx, pts.last.dy, length);
    }
    return best;
  }

  // ---- loft -------------------------------------------------------------

  /// A solid blended through two or more sections. The one feature that makes
  /// a shape which changes cross-section along its length — a boat hull, a
  /// transition duct, a handle that tapers.
  Future<AiActionOutcome> _loft(PartModel p, AiAction a) async {
    final names = <String>[];
    final asked = a.args['sketches'];
    if (asked is List) {
      for (final n in asked) {
        if (n is String && n.trim().isNotEmpty) names.add(n.trim());
      }
    }
    if (names.isEmpty) {
      return AiActionOutcome.failed(
          a.op,
          'sketches must name two or more sketches, in the order the loft '
          'passes through them');
    }
    if (names.length < 2) {
      return AiActionOutcome.failed(a.op, 'a loft needs at least 2 sections');
    }
    if (names.length > 20) {
      return AiActionOutcome.failed(a.op, 'at most 20 sections');
    }

    final sections = <ProfileSel>[];
    for (final n in names) {
      final cs = p.sketchByName(n);
      if (cs == null) {
        return AiActionOutcome.failed(a.op, 'no sketch named "$n"');
      }
      app.aiForgetRegions(n);
      final regions = app.sessionRegions(cs);
      if (regions.isEmpty) {
        return AiActionOutcome.failed(
            a.op, 'section "$n" has no closed profile');
      }
      final r = regions.first;
      sections.add(
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area));
    }

    final output = _outputOf(a, p);
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final f = LoftFeature(
      name: p.nextFeatureName('Loft'),
      bodyName: body,
      sectionSketches: names,
      sections: sections,
      solidOutput: true,
      ruled: a.flag('ruled'),
      closedLoop: a.flag('closed'),
      mergeTangent: a.flag('merge_tangent'),
      output: output,
    );
    p.claimBodyName(body);
    return _commitFeature(p, a, f, base, {
      'sections': names,
      'ruled': f.ruled,
      'closedLoop': f.closedLoop,
      'operation': output,
    });
  }

  // ---- coil -------------------------------------------------------------

  /// A helix: a spring, a thread, a spiral. Four ways to say the same helix,
  /// exactly as the panel offers them, because which two numbers you have
  /// depends on what you are making.
  Future<AiActionOutcome> _coil(PartModel p, AiAction a) async {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    app.aiForgetRegions(cs.model.name);
    final regions = app.sessionRegions(cs);
    if (regions.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'sketch "${cs.model.name}" has no closed profile to coil');
    }

    final method = switch ((a.text('method') ?? 'revolution_height')
        .toLowerCase()) {
      'revolution_height' || 'revolutions_height' => 0,
      'pitch_revolution' || 'pitch_revolutions' => 1,
      'pitch_height' => 2,
      'spiral' => 3,
      _ => -1,
    };
    if (method < 0) {
      return AiActionOutcome.failed(
          a.op,
          'method must be revolution_height, pitch_revolution, pitch_height '
          'or spiral');
    }
    final revolutions = a.number('revolutions') ?? 0;
    final height = a.number('height') ?? 0;
    final pitch = a.number('pitch') ?? 0;
    // Validate the two values the CHOSEN method uses, so an unused one left
    // at zero does not block a perfectly good coil.
    switch (method) {
      case 1:
        if (pitch <= 0) return AiActionOutcome.failed(a.op, 'pitch must be > 0');
        if (revolutions <= 0) {
          return AiActionOutcome.failed(a.op, 'revolutions must be > 0');
        }
      case 2:
        if (pitch <= 0) return AiActionOutcome.failed(a.op, 'pitch must be > 0');
        if (height <= 0) {
          return AiActionOutcome.failed(a.op, 'height must be > 0');
        }
      case 3:
        if (revolutions <= 0) {
          return AiActionOutcome.failed(a.op, 'revolutions must be > 0');
        }
      default:
        if (revolutions <= 0) {
          return AiActionOutcome.failed(a.op, 'revolutions must be > 0');
        }
        if (height <= 0) {
          return AiActionOutcome.failed(a.op, 'height must be > 0');
        }
    }

    final axis = _sketchAxis(a);
    if (axis == null) {
      return AiActionOutcome.failed(
          a.op, 'axis must be "x" or "y" of the sketch, or a point and a '
              'direction: {axis_x, axis_y, axis_dx, axis_dy}');
    }
    final output = _outputOf(a, p);
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final taper = a.number('taper') ?? 0;
    final f = CoilFeature(
      name: p.nextFeatureName('Coil'),
      bodyName: body,
      sketchName: cs.model.name,
      profiles: [
        for (final r in regions)
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area)
      ],
      axPx: axis.$1,
      axPy: axis.$2,
      axDx: axis.$3,
      axDy: axis.$4,
      method: method,
      revolutions: revolutions,
      height: height,
      pitch: pitch,
      taperDeg: taper,
      exprRevolutions: '$revolutions ul',
      exprHeight: '$height mm',
      exprPitch: '$pitch mm',
      exprTaper: '$taper deg',
      clockwise: a.flag('clockwise'),
      closeStart: a.flag('close_start'),
      closeEnd: a.flag('close_end'),
      output: output,
    );
    p.claimBodyName(body);
    final resolved = f.resolved;
    return _commitFeature(p, a, f, base, {
      'sketch': cs.model.name,
      'method': a.text('method') ?? 'revolution_height',
      'revolutions': _r(resolved.$1),
      'heightMm': _r(resolved.$2),
      if (pitch > 0) 'pitchMm': _r(pitch),
      'clockwise': f.clockwise,
      'operation': output,
    });
  }

  /// The revolve/coil axis in SKETCH coordinates: (px, py, dx, dy).
  (double, double, double, double)? _sketchAxis(AiAction a) {
    final dx = a.number('axis_dx'), dy = a.number('axis_dy');
    if (dx != null && dy != null && (dx != 0 || dy != 0)) {
      return (a.number('axis_x') ?? 0, a.number('axis_y') ?? 0, dx, dy);
    }
    return switch ((a.text('axis') ?? 'y').toLowerCase()) {
      'y' => (0, 0, 0, 1),
      'x' => (0, 0, 1, 0),
      _ => null,
    };
  }

  // ---- split ------------------------------------------------------------

  /// Inventor's Modify > Split, in its trim form: everything on one side of a
  /// plane goes away. How you cut a printed part in half so it fits the bed.
  Future<AiActionOutcome> _split(PartModel p, AiAction a) async {
    final frame = _planeFrameFor(a);
    if (frame == null) {
      return AiActionOutcome.failed(
          a.op,
          'plane must be "xy", "xz" or "yz", optionally with offset, or give '
          'a point and a normal: {px, py, pz, nx, ny, nz}');
    }
    final body = a.text('body') ??
        (p.features.isEmpty ? null : p.features.last.bodyName);
    if (body == null) {
      return AiActionOutcome.failed(a.op, 'this part has no body to split');
    }
    final f = SplitFeature(
      name: p.nextFeatureName('Split'),
      bodyName: body,
      frame: frame.$1,
      label: frame.$2,
      flip: a.flag('flip'),
    );
    return _commitFeature(p, a, f, currentBodySolid(p, body), {
      'body': body,
      'plane': frame.$2,
      'keeps': a.flag('flip') ? 'the +normal side' : 'the -normal side',
    });
  }

  /// A cutting plane from either a named principal plane plus an offset, or
  /// an outright point and normal.
  (PlaneFrame, String)? _planeFrameFor(AiAction a) {
    final nx = a.number('nx'), ny = a.number('ny'), nz = a.number('nz');
    if (nx != null && ny != null && nz != null) {
      final n = Vec3(nx, ny, nz);
      if (n.length < 1e-9) return null;
      final origin =
          Vec3(a.number('px') ?? 0, a.number('py') ?? 0, a.number('pz') ?? 0);
      final unit = n.normalized();
      // Any two vectors perpendicular to the normal will do for u and v: the
      // trim only cares which side of the plane the material is on.
      final helper =
          unit.x.abs() < 0.9 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
      final u = helper.cross(unit).normalized();
      return (
        PlaneFrame('face', u, u.cross(unit).normalized(), unit, origin),
        'plane through (${_mm(origin.x)}, ${_mm(origin.y)}, '
            '${_mm(origin.z)})'
      );
    }
    final key = (a.text('plane') ?? 'xz').toLowerCase();
    if (!kPlaneKeys.contains(key)) return null;
    final base = planeFrame(key);
    final offset = a.number('offset') ?? 0;
    return (
      offset == 0
          ? base
          : PlaneFrame(base.key, base.u, base.v, base.n, base.n * offset),
      offset == 0 ? planeLabel(key) : '${planeLabel(key)} + ${_mm(offset)} mm'
    );
  }

  // ---- combine ----------------------------------------------------------

  /// Boolean between BODIES, as against the boolean an extrude does against
  /// the body it lands in. Two solids modelled separately and then joined,
  /// cut or intersected.
  Future<AiActionOutcome> _combine(PartModel p, AiAction a) async {
    final tools = <String>[];
    final asked = a.args['tools'];
    if (asked is List) {
      for (final n in asked) {
        if (n is String && n.trim().isNotEmpty) tools.add(n.trim());
      }
    } else if (a.text('tool') != null) {
      tools.add(a.text('tool')!);
    }
    if (tools.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'tools must name one or more bodies to combine with');
    }
    final op = (a.text('operation') ?? 'cut').toLowerCase();
    if (!const {'join', 'cut', 'intersect'}.contains(op)) {
      return AiActionOutcome.failed(
          a.op, 'operation must be join, cut or intersect');
    }
    final body = a.text('body') ??
        (p.features.isEmpty ? null : p.features.last.bodyName);
    if (body == null) {
      return AiActionOutcome.failed(a.op, 'this part has no body to combine');
    }
    for (final t in tools) {
      if (!p.bodyNames.contains(t)) {
        return AiActionOutcome.failed(
            a.op,
            'no body named "$t" — this part has '
            '${p.bodyNames.isEmpty ? "none" : p.bodyNames.join(", ")}');
      }
      if (t == body) {
        return AiActionOutcome.failed(
            a.op, 'a body cannot be combined with itself');
      }
    }
    final f = CombineFeature(
      name: p.nextFeatureName('Combine'),
      bodyName: body,
      tools: tools,
      op: op,
      keepTool: a.flag('keep_tool'),
    );
    return _commitFeature(p, a, f, currentBodySolid(p, body), {
      'body': body,
      'tools': tools,
      'operation': op,
      'keepTool': f.keepTool,
    });
  }

  // ---- pattern ----------------------------------------------------------

  /// Inventor's four patterns in one op: rectangular, circular, mirror and
  /// sketch-driven. A bolt circle, a row of ribs, a mirrored bracket — all of
  /// them were previously a model emitting the same feature six times by
  /// hand, with six chances to get a coordinate wrong and no single thing to
  /// edit afterwards.
  Future<AiActionOutcome> _pattern(PartModel p, AiAction a) async {
    if (p.features.isEmpty) {
      return AiActionOutcome.failed(a.op, 'there is nothing to pattern yet');
    }
    final kind = switch ((a.text('kind') ?? 'rect').toLowerCase()) {
      'rect' || 'rectangular' || 'linear' => PatternKind.rectangular,
      'circ' || 'circular' || 'polar' => PatternKind.circular,
      'mirror' => PatternKind.mirror,
      _ => null,
    };
    if (kind == null) {
      return AiActionOutcome.failed(
          a.op, 'kind must be rect, circ or mirror');
    }

    // WHAT is repeated: named features, or the whole body.
    final sources = <String>[];
    final asked = a.args['features'];
    if (asked is List) {
      for (final n in asked) {
        if (n is String && n.trim().isNotEmpty) sources.add(n.trim());
      }
    } else if (a.text('feature') != null) {
      sources.add(a.text('feature')!);
    }
    final wholeBody = sources.isEmpty;
    for (final n in sources) {
      if (_feature(p, n) == null) {
        return AiActionOutcome.failed(a.op, 'no feature named "$n"');
      }
    }
    final body = a.text('body') ?? p.features.last.bodyName;
    final f = PatternFeature(
      name: p.nextFeatureName(patternKindLabel(kind)),
      bodyName: body,
      mode: kind,
      patternSolid: wholeBody,
      sources: wholeBody ? const [] : sources,
    );

    switch (kind) {
      case PatternKind.rectangular:
        final count = (a.number('count') ?? 0).round();
        final spacing = a.number('spacing') ?? a.number('distance') ?? 0;
        if (count < 2) {
          return AiActionOutcome.failed(a.op, 'count must be at least 2');
        }
        if (spacing <= 0) {
          return AiActionOutcome.failed(a.op, 'spacing must be > 0');
        }
        final dir = _worldAxis(a, 'direction') ?? const Vec3(1, 0, 0);
        f
          ..dirA = AxisRef(0, 0, 0, dir.x, dir.y, dir.z, 'Direction')
          ..countA = count
          ..distanceA = spacing
          ..exprCountA = '$count'
          ..exprDistanceA = '$spacing mm'
          ..midplaneA = a.flag('symmetric');
        // An optional second row, so a grid is one feature and not two.
        final count2 = (a.number('count2') ?? 0).round();
        final spacing2 = a.number('spacing2') ?? 0;
        if (count2 >= 2 && spacing2 > 0) {
          final dir2 = _worldAxis(a, 'direction2') ?? const Vec3(0, 0, 1);
          f
            ..dirB = AxisRef(0, 0, 0, dir2.x, dir2.y, dir2.z, 'Direction 2')
            ..countB = count2
            ..distanceB = spacing2
            ..exprCountB = '$count2'
            ..exprDistanceB = '$spacing2 mm';
        }
      case PatternKind.circular:
        final count = (a.number('count') ?? 0).round();
        if (count < 2) {
          return AiActionOutcome.failed(a.op, 'count must be at least 2');
        }
        final angle = a.number('angle') ?? 360;
        if (angle == 0) {
          return AiActionOutcome.failed(a.op, 'angle must not be zero');
        }
        final axis = _worldAxis(a, 'axis') ?? const Vec3(0, 1, 0);
        final at = _worldPoint(a, 'centre') ?? _worldPoint(a, 'center');
        f
          ..axis = AxisRef(at?.x ?? 0, at?.y ?? 0, at?.z ?? 0, axis.x, axis.y,
              axis.z, 'Axis')
          ..countC = count
          ..angleC = angle
          ..exprCountC = '$count'
          ..exprAngleC = '$angle deg';
      case PatternKind.mirror:
        final plane = _planeFrameFor(a);
        if (plane == null) {
          return AiActionOutcome.failed(
              a.op,
              'mirror needs a plane: "xy", "xz" or "yz" with an optional '
              'offset, or a point and a normal');
        }
        final o = plane.$1.origin, n = plane.$1.n;
        f.mirrorPlane = PlaneRef(o.x, o.y, o.z, n.x, n.y, n.z, plane.$2);
      case PatternKind.sketchDriven:
        return AiActionOutcome.failed(a.op, 'unreachable');
    }

    return _commitFeature(p, a, f, currentBodySolid(p, body), {
      'kind': patternKindName(kind),
      'of': wholeBody ? 'the whole body' : sources,
      'occurrences': f.occurrenceCount,
    });
  }

  /// A world direction from either a named axis or an explicit vector.
  Vec3? _worldAxis(AiAction a, String key) {
    final raw = a.args[key];
    if (raw is List && raw.length >= 3) {
      final xs = [for (final v in raw) if (v is num) v.toDouble()];
      if (xs.length >= 3) {
        final v = Vec3(xs[0], xs[1], xs[2]);
        return v.length < 1e-9 ? null : v.normalized();
      }
    }
    return switch ((raw is String ? raw : '').toLowerCase()) {
      'x' || '+x' => const Vec3(1, 0, 0),
      '-x' => const Vec3(-1, 0, 0),
      'y' || '+y' || 'up' => const Vec3(0, 1, 0),
      '-y' || 'down' => const Vec3(0, -1, 0),
      'z' || '+z' => const Vec3(0, 0, 1),
      '-z' => const Vec3(0, 0, -1),
      _ => null,
    };
  }

  Vec3? _worldPoint(AiAction a, String key) {
    final raw = a.args[key];
    if (raw is! List || raw.length < 3) return null;
    final xs = [for (final v in raw) if (v is num) v.toDouble()];
    return xs.length < 3 ? null : Vec3(xs[0], xs[1], xs[2]);
  }
}

extension _AiCadShell on AiCad {
  /// #85 — "make this open at the bottom and be made from 1 mm sheet metal".
  ///
  /// The app had no shell, so the assistant built one by hand for thirty
  /// rounds: projected outlines, offset them, cut prisms, deleted three
  /// attempts, and handed over a wall that measured 0.71 mm. A shell is one
  /// kernel operation with one number, and this op is it.
  ///
  ///   shell {thickness, open: "bottom" | ["top", "bottom"] | faces: ["F3"],
  ///          outward?, body?, id?}
  ///
  /// `open` names sides of the part the way faces_where does: the planar
  /// faces at that extreme of the body, facing out of it. `faces` takes ids
  /// from faces_where when the opening is not a side.
  Future<AiActionOutcome> _shell(PartModel p, AiAction a) async {
    final t = a.number('thickness');
    if (t == null || t <= 0) {
      return AiActionOutcome.failed(a.op, 'thickness must be > 0');
    }
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op, 'this part has no built body to shell');
    }
    final base = currentBodySolid(p, d.body);
    if (base == null) {
      return AiActionOutcome.failed(a.op, 'body "${d.body}" has no geometry');
    }
    final chosen = <DigestFace>[];
    final rawOpen = a.args['open'];
    final sides = rawOpen is String
        ? [rawOpen]
        : rawOpen is List
            ? [for (final v in rawOpen) if (v is String) v]
            : const <String>[];
    const dirs = {
      'top': Vec3(0, 1, 0),
      'bottom': Vec3(0, -1, 0),
      'right': Vec3(1, 0, 0),
      'left': Vec3(-1, 0, 0),
      'front': Vec3(0, 0, 1),
      'back': Vec3(0, 0, -1),
    };
    final size = d.max - d.min;
    final tol = math.max(1e-3, 1e-4 * size.length);
    for (final side in sides) {
      final want = dirs[side.toLowerCase()];
      if (want == null) {
        return AiActionOutcome.failed(
            a.op, 'open must name sides: ${dirs.keys.join(", ")}');
      }
      // The extreme of the body along that direction, and every planar face
      // that faces that way AT it — a stepped bottom is one opening only
      // where the step's lowest face is.
      final extreme = math.max(want.dot(d.max), want.dot(d.min));
      final at = [
        for (final f in d.faces)
          if (f.type == kFacePlane &&
              f.dir.dot(want) > 0.999 &&
              (f.centroid.dot(want) - extreme).abs() <= tol)
            f
      ];
      if (at.isEmpty) {
        return AiActionOutcome.failed(
            a.op,
            'the $side of "${d.body}" is not a flat face — name the faces '
            'to open with faces: ["F…"] from faces_where');
      }
      chosen.addAll(at);
    }
    for (final id in [
      if (a.args['faces'] is List)
        for (final v in a.args['faces'] as List) '$v'
    ]) {
      final (f, err) = _face(p, AiAction(a.op, {'face': id, 'body': d.body}),
          'face');
      if (f == null) return AiActionOutcome.failed(a.op, err!);
      if (!chosen.contains(f)) chosen.add(f);
    }
    if (chosen.isEmpty) {
      return AiActionOutcome.failed(
          a.op,
          'say which side stays open: open: "top" (a cup), "bottom" (a '
          'cover), or faces: ["F3"]. A shell with no opening would be a '
          'sealed void nothing can make.');
    }
    final minSide = math.min(size.x, math.min(size.y, size.z));
    if (t * 2 >= minSide) {
      return AiActionOutcome.failed(
          a.op,
          'a ${_mm(t)} mm wall on each side does not fit in a body whose '
          'thinnest dimension is ${_mm(minSide)} mm');
    }
    final f = ShellFeature(
      name: p.nextFeatureName('Shell'),
      bodyName: d.body,
      faces: [
        for (final g in chosen)
          FacePick(g.centroid.x, g.centroid.y, g.centroid.z, g.dir.x, g.dir.y,
              g.dir.z, g.area, g.type)
      ],
      thickness: t,
      outward: a.flag('outward'),
    );
    return _commitFeature(p, a, f, base, {
      'body': d.body,
      'thickness': _r(t),
      'open': [for (final g in chosen) 'F${g.id}'],
      'wall': a.flag('outward') ? 'outward' : 'inward',
      'note': a.flag('outward')
          ? 'The inside keeps the size the body was drawn at; the outside '
              'grew by the wall.'
          : 'The outside keeps the size it was drawn at; the wall grew '
              'inward.',
    });
  }
}
