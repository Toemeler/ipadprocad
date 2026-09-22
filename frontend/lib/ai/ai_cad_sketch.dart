part of 'ai_cad.dart';

/// EVERY 2D TOOL, not a chosen handful.
///
/// The friendly draw ops — rect, circle, arc, slot, rounded rect, polygon,
/// line, point — cover what a model reaches for most of the time, and they
/// take the arguments a person would say out loud ("a 40 by 20 rounded
/// rectangle, radius 4"). They are not the whole toolbox, and a model that
/// needs an ellipse, a spline, an involute gear, a tangent arc or a chamfer
/// between two lines should not have to approximate one.
///
/// [buildToolGeometry] is the app's single source of truth for what every 2D
/// tool draws: the viewport preview and the commit path both call it, so what
/// you see while drawing is exactly what lands in the document. This op calls
/// the SAME function with the same picks, which means the assistant draws
/// with the app's tools rather than with a re-implementation of them — and a
/// tool added to the app later is reachable here without touching this file.
extension AiCadSketch on AiCad {
  /// Every tool whose geometry [buildToolGeometry] can build, by the name the
  /// assistant uses for it. The names are descriptive rather than the enum's,
  /// because "rect3PC" is not something a model can be expected to guess.
  static const Map<String, Tool> tools = {
    'line': Tool.line,
    'line_midpoint': Tool.lineMid,
    'spline': Tool.splineInterp,
    'spline_control': Tool.splineCV,
    'equation_curve': Tool.eqCurve,
    'bridge': Tool.bridge,
    'circle': Tool.circleCenter,
    'circle_tangent': Tool.circleTangent,
    'ellipse': Tool.ellipse,
    'arc_3point': Tool.arcThreePoint,
    'arc_tangent': Tool.arcTangent,
    'arc_centre': Tool.arcCenter,
    'rect': Tool.rectTwoPoint,
    'rect_3point': Tool.rect3P,
    'rect_centre': Tool.rect2PC,
    'rect_centre_3point': Tool.rect3PC,
    'slot_centres': Tool.slotCC,
    'slot_overall': Tool.slotOverall,
    'slot_centre_point': Tool.slotCP,
    'slot_3arc': Tool.slot3A,
    'slot_centre_arc': Tool.slotCPA,
    'polygon_regular': Tool.polygon,
    'fillet': Tool.fillet,
    'chamfer': Tool.chamfer,
    'point': Tool.point,
  };

  /// How many picks each one needs, from the app's own [toolMeta]. A variable
  /// tool (the splines) reports its minimum.
  static String pointsNeeded(Tool t) {
    final meta = toolMeta[t];
    if (meta == null) return '?';
    return meta.fixed?.toString() ?? '${meta.minVar} or more';
  }

  /// The catalogue, for the instructions and for a refusal that has to say
  /// what WAS available.
  static String get catalogue {
    final names = tools.keys.toList()..sort();
    return [
      for (final n in names)
        '$n (${pointsNeeded(tools[n]!)} '
            '${pointsNeeded(tools[n]!) == "1" ? "point" : "points"})'
    ].join(', ');
  }

  AiActionOutcome _sketchTool(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);

    final name = (a.text('tool') ?? '').toLowerCase();
    final tool = tools[name];
    if (tool == null) {
      return AiActionOutcome.failed(
          a.op,
          'tool "${a.text('tool') ?? ""}" is not one this sketch has. '
          'Available: $catalogue');
    }

    final picks = [for (final q in a.points('points')) Offset(q[0], q[1])];
    final meta = toolMeta[tool];
    final need = meta?.fixed ?? meta?.minVar ?? 0;
    if (picks.length < need) {
      return AiActionOutcome.failed(
          a.op,
          '"$name" needs ${pointsNeeded(tool)} points in sketch coordinates; '
          'this block gave ${picks.length}');
    }
    if (picks.length > 400) {
      return AiActionOutcome.failed(a.op, 'at most 400 points');
    }

    // The dialog inputs the app's own panels supply, under the names a model
    // would use for them.
    final params = <String, double>{
      if (a.number('sides') != null) 'sides': a.number('sides')!,
      if (a.number('radius') != null) 'radius': a.number('radius')!,
      if (a.number('distance') != null) 'dist': a.number('distance')!,
      if (a.number('distance2') != null) 'dist2': a.number('distance2')!,
      if (a.number('angle') != null) 'ang': a.number('angle')!,
      if (a.number('mode') != null) 'mode': a.number('mode')!,
    };

    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(AiCad._layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];

    // FILLET AND CHAMFER REPLACE, THEY DO NOT ONLY ADD.
    //
    // Both trim the two entities they join. buildToolGeometry hands back only
    // the `adds`, which is right for the preview and wrong for a commit: the
    // arc would land on top of two untrimmed lines and the region finder
    // would see no closed profile. The replacement map is applied here, the
    // way the app's own commit path applies it.
    if (tool == Tool.fillet || tool == Tool.chamfer) {
      final radius = a.number('radius') ?? a.number('distance') ?? 5;
      if (radius <= 0) {
        return AiActionOutcome.failed(
            a.op, '${tool == Tool.fillet ? "radius" : "distance"} must be > 0');
      }
      final result = tool == Tool.fillet
          ? filletInventor(sketch.geometry, picks[0], picks[1], radius)
          : chamferInventor(sketch.geometry, picks[0], picks[1],
              mode: (params['mode'] ?? 0).round(),
              d1: radius,
              d2: a.number('distance2') ?? radius,
              angDeg: a.number('angle') ?? 45);
      if (result == null) {
        return AiActionOutcome.failed(
            a.op,
            'no pair of entities near those two points could be '
            '${tool == Tool.fillet ? "filleted" : "chamfered"} — the points '
            'pick the two entities, one each, near the corner they share');
      }
      final geometry = List<Geo>.of(sketch.geometry);
      result.repl.forEach((i, g) {
        if (i >= 0 && i < geometry.length) geometry[i] = g.onLayer(layer);
      });
      for (final g in result.adds) {
        geometry.add(g.onLayer(layer));
      }
      return _commitGeometry(cs, a, geometry, {
        'tool': name,
        'added': result.adds.length,
        'trimmed': result.repl.length,
      });
    }

    final made = buildToolGeometry(tool, picks,
        existing: sketch.geometry,
        params: params,
        expr: a.text('expr') ?? a.text('equation') ?? '');
    if (made == null || made.isEmpty) {
      return AiActionOutcome.failed(
          a.op,
          '"$name" could not be built from those points. Check the count '
          '(${pointsNeeded(tool)}) and that they are not coincident or '
          'collinear.');
    }
    // The same refusal the app's own commit makes: geometry that cannot be
    // drawn, picked or solved is not committed and then explained later.
    if (hasDegenerateGeometry(made)) {
      return AiActionOutcome.failed(
          a.op,
          '"$name" came out degenerate (a zero-length line, or an arc with '
          'no radius or no sweep) — the points are too close together');
    }
    return _commitGeometry(
        cs, a, [...sketch.geometry, for (final g in made) g.onLayer(layer)],
        {'tool': name, 'entities': made.length});
  }

  /// Commits a whole new geometry list for [cs] and reports the profile count,
  /// which is the number that decides whether an extrude has anything to work
  /// with.
  AiActionOutcome _commitGeometry(ChildSketch cs, AiAction a,
      List<Geo> geometry, Map<String, dynamic> detail) {
    if (geometry.length > 2000) {
      return AiActionOutcome.failed(
          a.op, 'this sketch already holds 2000 entities');
    }
    app.aiCommitSketch(cs.model, geometry);
    cs.model.dirty = true;
    app.aiForgetRegions(cs.model.name);
    return AiActionOutcome(a.op, detail: {
      'sketch': cs.model.name,
      ...detail,
      'closedProfiles': app.sessionRegions(cs).length,
    });
  }

  // ---- modify -----------------------------------------------------------

  /// Every MODIFY tool the sketcher has: move, copy, rotate, scale, mirror,
  /// offset, trim, extend and split.
  ///
  /// These are the tools that turn a rough sketch into a drawn one, and the
  /// assistant had none of them. Without trim it cannot cut two overlapping
  /// circles into a slot outline; without offset it cannot make a wall a
  /// fixed thickness from a curve it already drew; without mirror it draws
  /// the other half by hand and gets it slightly wrong.
  ///
  /// SELECTION IS GEOMETRIC, like everything else the assistant picks. `near`
  /// is a list of points in sketch coordinates and each one takes the entity
  /// closest to it; with no `near` the whole sketch is the selection. An index
  /// would not survive the entity list changing under it.
  AiActionOutcome _sketchModify(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final sketch = cs.model;
    final geometry = List<Geo>.of(sketch.geometry);
    if (geometry.isEmpty) {
      return AiActionOutcome.failed(a.op, 'this sketch is empty');
    }

    final action = (a.text('action') ?? '').toLowerCase();
    const known = {
      'move', 'copy', 'rotate', 'scale', 'stretch', 'mirror', 'offset',
      'trim', 'extend', 'split'
    };
    if (!known.contains(action)) {
      return AiActionOutcome.failed(
          a.op, 'action must be one of ${known.join(", ")}');
    }

    final picks = [for (final q in a.points('near')) Offset(q[0], q[1])];
    final selected = <int>[];
    if (picks.isEmpty) {
      for (var i = 0; i < geometry.length; i++) {
        selected.add(i);
      }
    } else {
      for (final q in picks) {
        final i = _nearestEntity(geometry, q);
        if (i == null) {
          return AiActionOutcome.failed(
              a.op,
              'nothing in this sketch is near (${_mm(q.dx)}, ${_mm(q.dy)})');
        }
        if (!selected.contains(i)) selected.add(i);
      }
    }

    // The one-entity-at-a-point tools take their click POINT, not just the
    // entity: which piece of a trimmed line goes away is decided by where you
    // clicked on it.
    switch (action) {
      case 'trim':
      case 'split':
        if (picks.isEmpty) {
          return AiActionOutcome.failed(
              a.op,
              '$action needs `near`: each point picks an entity AND says '
              'which piece of it you mean');
        }
        var work = geometry;
        for (final q in picks) {
          final i = _nearestEntity(work, q);
          if (i == null) continue;
          work = action == 'trim'
              ? trimEntity(work, i, q)
              : trimCutAway(work, i, q);
        }
        return _commitGeometry(cs, a, work,
            {'action': action, 'at': picks.length});
      case 'extend':
        if (picks.isEmpty) {
          return AiActionOutcome.failed(
              a.op, 'extend needs `near`: the point picks the END to grow');
        }
        var extended = 0;
        for (final q in picks) {
          final i = _nearestEntity(geometry, q);
          if (i == null) continue;
          final grown = extendEntity(geometry, i, q);
          if (grown != null) {
            geometry[i] = grown;
            extended++;
          }
        }
        if (extended == 0) {
          return AiActionOutcome.failed(
              a.op,
              'nothing could be extended — an end only grows to meet another '
              'entity, so there has to be something in its way');
        }
        return _commitGeometry(cs, a, geometry, {'action': 'extend',
          'extended': extended});
      case 'offset':
        final distance = a.number('distance');
        if (distance == null || distance == 0) {
          return AiActionOutcome.failed(a.op, 'distance must not be zero');
        }
        // WHICH WAY IS OUT.
        //
        // offsetEntity takes a POINT on the side to offset towards, and the
        // obvious way to build one — step along the entity's own normal —
        // gives a direction that depends on how that entity happens to be
        // parameterised. On a square drawn as four separate lines two came
        // out offset outward and two inward, which is not an offset of
        // anything; the probe showed nine closed regions from four lines.
        //
        // The selection's centroid fixes it: positive is AWAY from the middle
        // of what was selected and negative is towards it, which is what
        // "offset the profile by 3" means to anyone saying it.
        final centre = _centroidOf(geometry, selected);
        final made = <Geo>[];
        final skipped = <int>[];
        for (final i in selected) {
          final side = _offsetSide(geometry[i], distance, centre);
          if (side == null) {
            skipped.add(i);
            continue;
          }
          final g = offsetEntity(geometry[i], side);
          if (g != null) {
            made.add(g);
          } else {
            skipped.add(i);
          }
        }
        if (made.isEmpty) {
          return AiActionOutcome.failed(
              a.op, 'none of the selected entities can be offset');
        }
        return _commitGeometry(cs, a, [...geometry, ...made], {
          'action': 'offset',
          'offset': made.length,
          'distance': _r(distance),
          'direction': distance > 0 ? 'outward' : 'inward',
          if (skipped.isNotEmpty) 'couldNotOffset': skipped.length,
        });
      default:
        break;
    }

    // Stretch is the one modify tool that is not a point map: it moves only
    // the ENDS inside a window and leaves the rest where they are, which is
    // how a slot is made longer without making it fatter.
    if (action == 'stretch') {
      final dx = a.number('dx') ?? 0, dy = a.number('dy') ?? 0;
      if (dx == 0 && dy == 0) {
        return AiActionOutcome.failed(a.op, 'give dx and/or dy');
      }
      final box = a.points('window');
      if (box.length < 2) {
        return AiActionOutcome.failed(
            a.op,
            'window must be two corner points [[x1,y1],[x2,y2]] — only ends '
            'inside it move');
      }
      final rect = Rect.fromPoints(
          Offset(box[0][0], box[0][1]), Offset(box[1][0], box[1][1]));
      var moved = 0;
      for (final i in selected) {
        final g = stretchGeo(geometry[i], rect, Offset(dx, dy));
        if (!identical(g, geometry[i])) moved++;
        geometry[i] = g;
      }
      if (moved == 0) {
        return AiActionOutcome.failed(
            a.op, 'no entity end lies inside that window');
      }
      return _commitGeometry(
          cs, a, geometry, {'action': 'stretch', 'stretched': moved});
    }

    // The transforming tools. One mapping function, applied to the selection.
    final Offset Function(Offset)? map = switch (action) {
      'move' || 'copy' => _translation(a),
      'rotate' => _rotation(a),
      'scale' => _scaling(a),
      'mirror' => _mirroring(a),
      _ => null,
    };
    if (map == null) {
      return AiActionOutcome.failed(
          a.op,
          switch (action) {
            'move' || 'copy' => 'give dx and dy',
            'rotate' => 'give angle in degrees, and optionally about: [x, y]',
            'scale' => 'give factor > 0, and optionally about: [x, y]',
            _ => 'mirror needs axis: "x" or "y", or a line: '
                '{x1, y1, x2, y2}',
          });
    }
    final moved = [for (final i in selected) transformGeo(geometry[i], map)];
    if (hasDegenerateGeometry(moved)) {
      return AiActionOutcome.failed(
          a.op, '$action would collapse something to zero size');
    }
    if (action == 'move' || action == 'rotate' || action == 'scale') {
      for (var k = 0; k < selected.length; k++) {
        geometry[selected[k]] = moved[k];
      }
      return _commitGeometry(
          cs, a, geometry, {'action': action, 'entities': moved.length});
    }
    // copy and mirror ADD; the originals stay.
    return _commitGeometry(cs, a, [...geometry, ...moved],
        {'action': action, 'added': moved.length});
  }

  /// The entity whose path passes closest to [q], or null when nothing is
  /// within reach of it.
  ///
  /// Measured against the SEGMENTS between samples, not the samples. A line
  /// is sampled as its two endpoints, so measuring to the points alone put a
  /// pick at the middle of a 40 mm line 20 mm away from it — the same
  /// distance as from the line at right angles to it, which made the two
  /// indistinguishable and a perpendicular constraint impossible to ask for.
  int? _nearestEntity(List<Geo> geometry, Offset q) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < geometry.length; i++) {
      final pts = sampleEntity(geometry[i], arcSamples: 32);
      if (pts.isEmpty) continue;
      var d = (pts.first - q).distance;
      for (var k = 1; k < pts.length; k++) {
        final s = _distanceToSegment(q, pts[k - 1], pts[k]);
        if (s < d) d = s;
      }
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    // Generous, because a model gives a point it computed rather than one it
    // clicked — but not unbounded, or a typo silently modifies the far side
    // of the part.
    return best >= 0 && bestD <= 25 ? best : null;
  }

  /// Shortest distance from [q] to the segment [a]-[b].
  double _distanceToSegment(Offset q, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-18) return (q - a).distance;
    var t = ((q.dx - a.dx) * dx + (q.dy - a.dy) * dy) / len2;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    return (q - Offset(a.dx + dx * t, a.dy + dy * t)).distance;
  }

  Offset Function(Offset)? _translation(AiAction a) {
    final dx = a.number('dx'), dy = a.number('dy');
    if (dx == null && dy == null) return null;
    final ox = dx ?? 0, oy = dy ?? 0;
    if (ox == 0 && oy == 0) return null;
    return (q) => Offset(q.dx + ox, q.dy + oy);
  }

  Offset Function(Offset)? _rotation(AiAction a) {
    final deg = a.number('angle');
    if (deg == null || deg % 360 == 0) return null;
    final about = a.points('about');
    final cx = about.isEmpty ? 0.0 : about.first[0];
    final cy = about.isEmpty ? 0.0 : about.first[1];
    final r = deg * math.pi / 180;
    final c = math.cos(r), s = math.sin(r);
    return (q) {
      final x = q.dx - cx, y = q.dy - cy;
      return Offset(cx + x * c - y * s, cy + x * s + y * c);
    };
  }

  Offset Function(Offset)? _scaling(AiAction a) {
    final f = a.number('factor');
    if (f == null || f <= 0 || f == 1) return null;
    final about = a.points('about');
    final cx = about.isEmpty ? 0.0 : about.first[0];
    final cy = about.isEmpty ? 0.0 : about.first[1];
    return (q) => Offset(cx + (q.dx - cx) * f, cy + (q.dy - cy) * f);
  }

  Offset Function(Offset)? _mirroring(AiAction a) {
    final x1 = a.number('x1'), y1 = a.number('y1');
    final x2 = a.number('x2'), y2 = a.number('y2');
    double ax, ay, bx, by;
    if (x1 != null && y1 != null && x2 != null && y2 != null) {
      ax = x1;
      ay = y1;
      bx = x2;
      by = y2;
    } else {
      switch ((a.text('axis') ?? '').toLowerCase()) {
        case 'x':
          ax = 0; ay = 0; bx = 1; by = 0;
        case 'y':
          ax = 0; ay = 0; bx = 0; by = 1;
        default:
          return null;
      }
    }
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-18) return null;
    return (q) {
      // Reflect across the line through (ax,ay) with direction (dx,dy).
      final t = ((q.dx - ax) * dx + (q.dy - ay) * dy) / len2;
      final px = ax + dx * t, py = ay + dy * t;
      return Offset(2 * px - q.dx, 2 * py - q.dy);
    };
  }

  /// A point on the side an offset should go towards: [distance] from the
  /// entity's midpoint, along the normal, turned so that a POSITIVE distance
  /// always points away from [centre].
  Offset? _offsetSide(Geo g, double distance, Offset centre) {
    final pts = sampleEntity(g, arcSamples: 16);
    if (pts.length < 2) return null;
    final mid = pts[pts.length ~/ 2];
    final before = pts[math.max(0, pts.length ~/ 2 - 1)];
    final after = pts[math.min(pts.length - 1, pts.length ~/ 2 + 1)];
    final tx = after.dx - before.dx, ty = after.dy - before.dy;
    final len = math.sqrt(tx * tx + ty * ty);
    if (len < 1e-12) return null;
    var nx = -ty / len, ny = tx / len;
    // Point the normal away from the selection's middle. An entity whose
    // midpoint IS the middle (a circle centred there) has no outward to
    // choose, and its own normal already points out of it.
    final ax = mid.dx - centre.dx, ay = mid.dy - centre.dy;
    if (ax * ax + ay * ay > 1e-12 && nx * ax + ny * ay < 0) {
      nx = -nx;
      ny = -ny;
    }
    return Offset(mid.dx + nx * distance, mid.dy + ny * distance);
  }

  /// The middle of a selection, by sampled points — good enough to say which
  /// way is out, and it does not care whether the shape is convex.
  Offset _centroidOf(List<Geo> geometry, List<int> selected) {
    var sx = 0.0, sy = 0.0, n = 0;
    for (final i in selected) {
      for (final q in sampleEntity(geometry[i], arcSamples: 16)) {
        sx += q.dx;
        sy += q.dy;
        n++;
      }
    }
    return n == 0 ? Offset.zero : Offset(sx / n, sy / n);
  }

  // ---- gear and text ----------------------------------------------------

  /// A parametric involute gear. The app has carried one since M61 — module,
  /// teeth, pressure angle, profile shift, root fillet, bore, internal or
  /// external — and a model asked for a gearbox had to approximate teeth with
  /// a polygon, which is neither a gear nor anything that meshes.
  AiActionOutcome _sketchGear(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final teeth = (a.number('teeth') ?? 0).round();
    if (teeth < 6 || teeth > 400) {
      return AiActionOutcome.failed(
          a.op, 'teeth must be between 6 and 400 (given ${teeth})');
    }
    final module = a.number('module') ?? 2;
    if (module <= 0) {
      return AiActionOutcome.failed(a.op, 'module must be > 0');
    }
    final bore = a.number('bore') ?? 0;
    if (bore < 0) {
      return AiActionOutcome.failed(a.op, 'bore must be 0 or more');
    }
    final params = GearParams(
      module: module,
      teeth: teeth,
      pressureAngleDeg: a.number('pressure_angle') ?? 20,
      profileShift: a.number('profile_shift') ?? 0,
      internal: a.flag('internal'),
      bore: bore,
      fillet: a.flag('fillet', fallback: true),
    );
    final centre = Offset(a.number('x') ?? 0, a.number('y') ?? 0);
    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(AiCad._layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];
    final gear = buildGearGeo(
        centre, (a.number('angle') ?? 0) * math.pi / 180, params,
        layer: layer);
    return _commitGeometry(cs, a, [...sketch.geometry, gear], {
      'shape': 'gear',
      'teeth': teeth,
      'module': _r(module),
      'pitchDiameterMm': _r(module * teeth),
      'internal': params.internal,
      if (bore > 0) 'boreMm': _r(bore),
    });
  }

  /// Parametric sketch text, which extrudes like any other profile — a raised
  /// or engraved label on a part.
  AiActionOutcome _sketchText(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final text = a.text('text');
    if (text == null) {
      return AiActionOutcome.failed(a.op, 'text is required');
    }
    if (text.length > 200) {
      return AiActionOutcome.failed(a.op, 'at most 200 characters');
    }
    final height = a.number('height') ?? 8;
    if (height <= 0) {
      return AiActionOutcome.failed(a.op, 'height must be > 0');
    }
    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(AiCad._layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];
    sketch.texts.add(SketchText(text, a.number('x') ?? 0, a.number('y') ?? 0,
        height: height, layer: layer));
    sketch.dirty = true;
    app.aiForgetRegions(sketch.name);
    app.aiCommitSketch(sketch, sketch.geometry);
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      'text': text,
      'heightMm': _r(height),
      'note': 'Text becomes outlines when the sketch is used, so it extrudes '
          'like any other profile.',
      'closedProfiles': app.sessionRegions(cs).length,
    });
  }

  // ---- project ----------------------------------------------------------

  /// Inventor's Project Geometry: the edges of the solid brought INTO the
  /// sketch, as real sketch entities.
  ///
  /// This is how a second feature is made to line up with the first without
  /// re-deriving its coordinates by hand — which is where "the hole is 0.3 mm
  /// off" comes from. A projected circle is a circle and a projected tilted
  /// circle is a true ellipse, because the projection is exact.
  AiActionOutcome _sketchProject(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    if (p.features.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'there is no solid yet whose edges could be projected');
    }
    final frame = cs.face ?? planeFrame(cs.plane);
    final edges = partEdges(p, frame);
    if (edges.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'no edge of this part projects onto that sketch plane');
    }

    // `near` selects; with none, everything projects. Both are useful: a
    // whole face's outline is the common case, one edge the precise one.
    final picks = [for (final q in a.points('near')) Offset(q[0], q[1])];
    final wanted = <PartEdge>[];
    if (picks.isEmpty) {
      wanted.addAll(edges);
    } else {
      final geos = [for (final e in edges) geoForPartEdge(e, '')];
      for (final q in picks) {
        final i = _nearestEntity(geos, q);
        if (i == null) {
          return AiActionOutcome.failed(
              a.op,
              'no projected edge is near (${_mm(q.dx)}, ${_mm(q.dy)}) on this '
              'sketch plane');
        }
        if (!wanted.contains(edges[i])) wanted.add(edges[i]);
      }
    }
    if (wanted.length > 500) {
      return AiActionOutcome.failed(
          a.op, 'that would project ${wanted.length} edges; select with `near`');
    }

    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(AiCad._layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];
    final made = [for (final e in wanted) geoForPartEdge(e, layer)];
    if (made.isEmpty) {
      return AiActionOutcome.failed(a.op, 'nothing projected');
    }
    return _commitGeometry(cs, a, [...sketch.geometry, ...made], {
      'projected': made.length,
      'of': '${edges.length} projectable edges',
    });
  }

  // ---- sketch patterns --------------------------------------------------

  /// A rectangular or circular array IN THE SKETCH — the 2D counterpart of
  /// the 3D pattern.
  ///
  /// Repeating a hole six times round a bolt circle is better done as one 3D
  /// pattern; repeating a sketch SHAPE before it is ever extruded is a
  /// different thing, and it is what you want when the shapes are meant to be
  /// one profile — a row of slots cut in a single pass, teeth round a rim.
  ///
  /// HONEST ABOUT WHAT THIS IS NOT: the app's own sketch pattern ties each
  /// copy to its source with a pattern CONSTRAINT, so editing the source
  /// drives every copy. This makes independent geometry. Say so in the
  /// report rather than let a model believe the copies are linked.
  AiActionOutcome _sketchPattern(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final sketch = cs.model;
    final geometry = List<Geo>.of(sketch.geometry);
    if (geometry.isEmpty) {
      return AiActionOutcome.failed(a.op, 'this sketch is empty');
    }
    final count = (a.number('count') ?? 0).round();
    if (count < 2 || count > 200) {
      return AiActionOutcome.failed(a.op, 'count must be between 2 and 200');
    }

    final picks = [for (final q in a.points('near')) Offset(q[0], q[1])];
    final selected = <int>[];
    if (picks.isEmpty) {
      for (var i = 0; i < geometry.length; i++) {
        selected.add(i);
      }
    } else {
      for (final q in picks) {
        final i = _nearestEntity(geometry, q);
        if (i == null) {
          return AiActionOutcome.failed(
              a.op, 'nothing is near (${_mm(q.dx)}, ${_mm(q.dy)})');
        }
        if (!selected.contains(i)) selected.add(i);
      }
    }

    final kind = (a.text('kind') ?? 'rect').toLowerCase();
    final made = <Geo>[];
    if (kind == 'rect' || kind == 'rectangular' || kind == 'linear') {
      final dx = a.number('dx') ?? 0, dy = a.number('dy') ?? 0;
      if (dx == 0 && dy == 0) {
        return AiActionOutcome.failed(
            a.op, 'give dx and/or dy — the step from one copy to the next');
      }
      for (var k = 1; k < count; k++) {
        for (final i in selected) {
          made.add(transformGeo(
              geometry[i], (q) => Offset(q.dx + dx * k, q.dy + dy * k)));
        }
      }
    } else if (kind == 'circ' || kind == 'circular' || kind == 'polar') {
      final total = a.number('angle') ?? 360;
      final about = a.points('about');
      final cx = about.isEmpty ? 0.0 : about.first[0];
      final cy = about.isEmpty ? 0.0 : about.first[1];
      // A full turn shares the first and last place, so the step divides by
      // count; a partial sweep puts a copy at each end.
      final full = (total.abs() % 360) < 1e-9;
      final step = (total / (full ? count : count - 1)) * math.pi / 180;
      for (var k = 1; k < count; k++) {
        final c = math.cos(step * k), sn = math.sin(step * k);
        for (final i in selected) {
          made.add(transformGeo(geometry[i], (q) {
            final x = q.dx - cx, y = q.dy - cy;
            return Offset(cx + x * c - y * sn, cy + x * sn + y * c);
          }));
        }
      }
    } else {
      return AiActionOutcome.failed(a.op, 'kind must be rect or circ');
    }

    if (made.isEmpty) {
      return AiActionOutcome.failed(a.op, 'that pattern made no copies');
    }
    if (hasDegenerateGeometry(made)) {
      return AiActionOutcome.failed(
          a.op, 'the pattern collapsed something to zero size');
    }
    return _commitGeometry(cs, a, [...geometry, ...made], {
      'kind': kind,
      'copies': made.length,
      'note': 'These copies are independent geometry, not linked to the '
          'original — editing the source will not move them.',
    });
  }
}
