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
    final profileName = a.text('profile_sketch') ?? a.text('sketch');
    final pathName = a.text('path_sketch') ?? a.text('path');
    if (pathName == null) {
      return AiActionOutcome.failed(
          a.op,
          'path_sketch is required: the sketch holding the OPEN curve the '
          'profile travels along');
    }
    final profile = profileName == null
        ? (p.childSketches.isEmpty ? null : p.childSketches.first)
        : p.sketchByName(profileName);
    if (profile == null) {
      return AiActionOutcome.failed(
          a.op, 'no sketch named "${profileName ?? "?"}" to sweep');
    }
    final path = p.sketchByName(pathName);
    if (path == null) {
      return AiActionOutcome.failed(a.op, 'no sketch named "$pathName"');
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
      'profiles': f.profiles.length,
      'pathLengthMm': _r(curve.length),
      'orientation': orientation == 0 ? 'path' : 'fixed',
      if (taper != 0) 'taperDeg': _r(taper),
      'operation': output,
    });
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
