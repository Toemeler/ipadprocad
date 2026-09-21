import 'dart:math' as math;

import '../app_state.dart';
import '../ffi/occt_engine.dart' show OcctEdgeInfo;
import '../ffi/qcad_engine.dart';
import '../log.dart';
import '../part_model.dart';
import '../part_render.dart'
    show kFacePlane, kFaceCylinder, kFaceCone, kFaceSphere, kFaceTorus;
import 'ai_actions.dart';
import 'ai_trace.dart';
import 'shape_digest.dart';

/// M441 — where an assistant's intention becomes geometry.
///
/// Everything this file builds is an ORDINARY document object: a `ChildSketch`
/// with real entities on a real layer, an `ExtrudeFeature`/`RevolveFeature`/
/// `FilletFeature`/`ChamferFeature` in the same timeline, rebuilt through the
/// same `recomputeAllFeatures`. There is no agent-only representation and no
/// path around the kernel. The consequence is the point: what the model makes,
/// the user can open, edit, re-dimension, roll back and delete, and what the
/// user made, the model can edit.
///
/// THREE RULES THIS FILE EXISTS TO ENFORCE.
///
/// 1. **A block is one transaction.** The part is snapshotted before the first
///    action. If any action fails, the snapshot goes back and the report says
///    `reverted`. A half-applied design change is worse than none: the model
///    would reason about a document that does not exist.
/// 2. **A refusal is not a failure to mention.** Every outcome carries either
///    what it did (with the numbers) or why it did not. Nothing is silently
///    skipped, because the model's next answer is written from this report.
/// 3. **The report is measured, not assumed.** Distances come back from the
///    feature that was actually built and bounds from the rebuilt body — never
///    from the arguments that were asked for. An extrusion that failed in the
///    kernel reports its `computeError`, not the distance that was requested.
class AiCad {
  AiCad(this.app, [ShapeDigestCache? digests])
      : digests = digests ?? ShapeDigestCache();
  final AppState app;

  /// Shared with [AiWorkspace] so the digest in the turn's context and the one
  /// an op reads are the same object, computed once.
  final ShapeDigestCache digests;

  /// Executes one block. Never throws: an unexpected error becomes a failed
  /// outcome and a rollback, because an exception escaping here would leave
  /// the document mid-edit with nobody to say so.
  Future<AiActionReport> run(List<AiAction> batch, {AiProgress? onStep}) async {
    final p = app.currentPart;
    if (p == null) {
      AiTrace.record('cad.blocked', data: {'blocked': 'noPart'});
      return AiActionReport(outcomes: const [], blocked: 'noPart');
    }
    if (batch.isEmpty) return AiActionReport(outcomes: const []);
    final before = app.aiSnapshot(p);
    final outcomes = <AiActionOutcome>[];
    var mutated = false;
    var failed = false;
    for (var i = 0; i < batch.length; i++) {
      final action = batch[i];
      // Reported BEFORE the action runs, so the panel names what is happening
      // rather than what just finished.
      onStep?.call(action.op, i + 1, batch.length);
      AiActionOutcome outcome;
      // PER OP, WITH ITS OWN CLOCK. The block report says what a block did;
      // this says which op inside it was the slow one and which one turned a
      // batch into a rollback. A fillet that takes eleven seconds in the
      // kernel and an extrude that fails on a profile look identical in the
      // report the model is handed.
      final clock = Stopwatch()..start();
      try {
        outcome = await _one(p, action);
      } catch (e, st) {
        Log.e('ai', 'action ${action.op} threw', e, st);
        AiTrace.record('cad.threw', data: {
          'op': action.op,
          'args': action.args,
          'error': '${e.runtimeType}: $e',
          'stack': '$st',
          'elapsedMs': clock.elapsedMilliseconds,
        });
        outcome = AiActionOutcome.failed(action.op, 'internal error: $e');
      }
      AiTrace.record('cad.action', data: {
        'op': action.op,
        'ok': outcome.ok,
        'elapsedMs': clock.elapsedMilliseconds,
        'args': action.args,
        if (outcome.error != null) 'error': outcome.error,
        if (outcome.detail != null) 'detail': outcome.detail,
      });
      outcomes.add(outcome);
      if (action.op != 'describe_part') mutated = true;
      if (!outcome.ok) {
        failed = true;
        break;
      }
    }
    if (failed && mutated) {
      await app.aiRestore(p, before);
      // The restore swaps whole sketches in; a cached region list keyed by a
      // sketch NAME would otherwise survive the sketch it describes.
      app.aiForgetRegions();
      Log.i('ai', 'action block rolled back after ${outcomes.length} step(s)');
      AiTrace.record('cad.reverted', data: {
        'steps': outcomes.length,
        'failedOn': outcomes.isEmpty ? null : outcomes.last.op,
        'error': outcomes.isEmpty ? null : outcomes.last.error,
      });
      return AiActionReport(outcomes: outcomes, reverted: true, state: _state(p));
    }
    if (mutated && !failed) {
      app.aiJournal(before); // ONE Ctrl+Z for the whole block
      p.dirty = true;
      final tab = app.curTab;
      if (tab != null) await app.savePart(tab);
      app.aiNotify();
    }
    return AiActionReport(outcomes: outcomes, reverted: false, state: _state(p));
  }

  Future<AiActionOutcome> _one(PartModel p, AiAction a) async {
    switch (a.op) {
      case 'describe_part':
        return AiActionOutcome('describe_part', detail: {'part': _state(p)});
      case 'describe_shape':
        return _describeShape(p, a);
      case 'faces_where':
        return _facesWhere(p, a);
      case 'measure':
        return _measure(p, a);
      case 'section':
        return _section(p, a);
      case 'delete_face':
      case 'move_face':
        return _faceEdit(p, a);
      case 'sketch_on_face':
        return _sketchOnFace(p, a);
      case 'create_sketch':
        return _createSketch(p, a);
      case 'sketch_rect':
      case 'sketch_circle':
      case 'sketch_polygon':
      case 'sketch_line':
        return _draw(p, a);
      case 'extrude':
        return _extrude(p, a);
      case 'revolve':
        return _revolve(p, a);
      case 'fillet':
      case 'chamfer':
        return _blend(p, a);
      case 'edit_feature':
        return _editFeature(p, a);
      case 'delete_feature':
        return _deleteFeature(p, a);
      case 'rename_feature':
        return _renameFeature(p, a);
    }
    return AiActionOutcome.failed(a.op, 'unknown op');
  }

  // ---- sketches ---------------------------------------------------------

  static const _planes = {'xy', 'xz', 'yz'};

  AiActionOutcome _createSketch(PartModel p, AiAction a) {
    final plane = (a.text('plane') ?? 'xy').toLowerCase();
    if (!_planes.contains(plane)) {
      return AiActionOutcome.failed(
          a.op, 'plane must be one of ${_planes.join(", ")}');
    }
    if (p.childSketches.length >= 200) {
      return AiActionOutcome.failed(a.op, 'this part already has 200 sketches');
    }
    final sketch = SketchModel(p.nextSketchName());
    sketch.insertLayerAboveMarker(_layerName);
    p.appendChildSketch(
        ChildSketch(sketch, plane, null, true, false, p.nextSeq()));
    app.aiAdmitSketchRow(p);
    Log.i('ai', 'sketch "${sketch.name}" created on $plane of "${p.name}"');
    return AiActionOutcome(a.op,
        detail: {'sketch': sketch.name, 'plane': plane});
  }

  static const _layerName = 'Layer 1';

  /// The sketch an action names, or the newest one. Named explicitly because
  /// "the newest" is a convenience, and a model that has built two sketches
  /// must be able to say which one it means.
  (ChildSketch?, String?) _sketchFor(PartModel p, AiAction a) {
    final named = a.text('sketch');
    if (named != null) {
      final cs = p.sketchByName(named);
      return cs == null ? (null, 'no sketch named "$named"') : (cs, null);
    }
    if (p.childSketches.isEmpty) {
      return (null, 'this part has no sketch yet — run create_sketch first');
    }
    return (p.childSketches.last, null);
  }

  AiActionOutcome _draw(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final sketch = cs.model;
    if (sketch.layers.isEmpty) sketch.insertLayerAboveMarker(_layerName);
    final layer = sketch.layers[sketch.eosAfter > 0 ? sketch.eosAfter - 1 : 0];

    late final Geo made;
    late final Map<String, dynamic> detail;
    // One block per case: switch cases share a scope, and several of these
    // want the same local names.
    switch (a.op) {
      case 'sketch_rect':
        {
          final w = a.number('width'), h = a.number('height');
          final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
          if (w == null || h == null || w <= 0 || h <= 0) {
            return AiActionOutcome.failed(a.op, 'width and height must be > 0');
          }
          final centered = a.flag('centered');
          final x0 = centered ? x - w / 2 : x, y0 = centered ? y - h / 2 : y;
          made = _polyline([
            [x0, y0],
            [x0 + w, y0],
            [x0 + w, y0 + h],
            [x0, y0 + h]
          ], closed: true, layer: layer);
          detail = {
            'shape': 'rectangle',
            'corner': [_r(x0), _r(y0)],
            'width': _r(w),
            'height': _r(h)
          };
        }
      case 'sketch_circle':
        {
          final diameter = a.number('diameter');
          final r = diameter != null ? diameter / 2 : a.number('radius');
          final x = a.number('x') ?? 0, y = a.number('y') ?? 0;
          if (r == null || r <= 0) {
            return AiActionOutcome.failed(
                a.op, 'diameter (or radius) must be > 0');
          }
          made = Geo(Geo.circle, [x, y, r], layer: layer);
          detail = {
            'shape': 'circle',
            'centre': [_r(x), _r(y)],
            'diameter': _r(r * 2)
          };
        }
      case 'sketch_polygon':
        {
          final pts = a.points('points');
          if (pts.length < 3) {
            return AiActionOutcome.failed(
                a.op, 'a polygon needs at least 3 finite points');
          }
          if (pts.length > 400) {
            return AiActionOutcome.failed(a.op, 'at most 400 points');
          }
          made = _polyline(pts,
              closed: a.flag('closed', fallback: true), layer: layer);
          detail = {'shape': 'polygon', 'points': pts.length};
        }
      case 'sketch_line':
        {
          final x1 = a.number('x1'), y1 = a.number('y1');
          final x2 = a.number('x2'), y2 = a.number('y2');
          if (x1 == null || y1 == null || x2 == null || y2 == null) {
            return AiActionOutcome.failed(
                a.op, 'x1, y1, x2 and y2 are required');
          }
          if (x1 == x2 && y1 == y2) {
            return AiActionOutcome.failed(
                a.op, 'the two ends are the same point');
          }
          made = Geo(Geo.line, [x1, y1, x2, y2], layer: layer);
          detail = {
            'shape': 'line',
            'from': [_r(x1), _r(y1)],
            'to': [_r(x2), _r(y2)]
          };
        }
      default:
        return AiActionOutcome.failed(a.op, 'unknown draw op');
    }
    if (sketch.geometry.length >= 2000) {
      return AiActionOutcome.failed(a.op, 'this sketch already holds 2000 entities');
    }
    app.aiCommitSketch(sketch, [...sketch.geometry, made]);
    sketch.dirty = true;
    app.aiForgetRegions(sketch.name);
    final regions = app.sessionRegions(cs).length;
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      ...detail,
      // What the profile finder makes of the sketch NOW. This is the number
      // that decides whether an extrude has anything to work with, and the
      // model gets it before it asks for one.
      'closedProfiles': regions
    });
  }

  Geo _polyline(List<List<double>> pts,
          {required bool closed, required String layer}) =>
      Geo(
          Geo.polyline,
          [
            closed ? 1.0 : 0.0,
            pts.length.toDouble(),
            for (final p in pts) ...[p[0], p[1]]
          ],
          layer: layer);

  // ---- features ---------------------------------------------------------

  static const _outputs = {'new', 'join', 'cut', 'intersect'};

  /// The body a boolean acts on, and the name the feature should carry.
  (KernelSolid?, String) _target(PartModel p, AiAction a, String output) {
    final named = a.text('body');
    if (named != null && p.bodyNames.contains(named)) {
      return (currentBodySolid(p, named), named);
    }
    if (output == 'new') return (null, p.nextSolidName());
    final last = lastSolidFeature(p);
    if (last == null) return (null, p.nextSolidName());
    return (currentBodySolid(p, last.bodyName), last.bodyName);
  }

  String _outputOf(AiAction a, PartModel p) {
    final asked = (a.text('operation') ?? '').toLowerCase();
    if (_outputs.contains(asked)) return asked;
    // No body yet means there is nothing to join to: this is the base feature.
    return p.bodyNames.isEmpty ? 'new' : 'join';
  }

  Future<AiActionOutcome> _extrude(PartModel p, AiAction a) async {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    app.aiForgetRegions(cs.model.name);
    final regions = app.sessionRegions(cs);
    if (regions.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'sketch "${cs.model.name}" has no closed profile to extrude');
    }
    final through = a.flag('through_all');
    final distance = a.number('distance');
    if (!through && (distance == null || distance <= 0)) {
      return AiActionOutcome.failed(a.op, 'distance must be > 0');
    }
    if (!through && distance! > 100000) {
      return AiActionOutcome.failed(a.op, 'distance is beyond 100 m');
    }
    final taper = a.number('taper') ?? 0;
    if (taper.abs() >= 90) {
      return AiActionOutcome.failed(a.op, 'taper must be between -90 and 90');
    }
    final direction = _direction(a);
    if (direction == null) {
      return AiActionOutcome.failed(a.op,
          'direction must be default, flipped or symmetric');
    }
    final output = _outputOf(a, p);
    if (through && output == 'new') {
      return AiActionOutcome.failed(
          a.op, 'through_all needs an existing body to pass through');
    }
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final d = distance ?? 0;
    final f = ExtrudeFeature(
      name: p.nextFeatureName(),
      bodyName: body,
      sketchName: cs.model.name,
      profiles: [
        for (final r in regions)
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area)
      ],
      direction: direction,
      distanceA: d,
      distanceB: direction == ExtrudeDirection.symmetric ? d : 0,
      taperDeg: taper,
      exprA: '$d mm',
      exprB: '$d mm',
      exprTaper: '$taper deg',
      extent: through ? FeatureExtent.throughAll : FeatureExtent.distance,
      output: output,
    );
    p.claimBodyName(body);
    return _commitFeature(p, a, f, base, {
      'sketch': cs.model.name,
      'profiles': f.profiles.length,
      if (!through) 'distance': _r(d),
      'extent': through ? 'throughAll' : 'distance',
      'direction': extrudeDirName(direction),
      'operation': output,
    });
  }

  Future<AiActionOutcome> _revolve(PartModel p, AiAction a) async {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    app.aiForgetRegions(cs.model.name);
    final regions = app.sessionRegions(cs);
    if (regions.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'sketch "${cs.model.name}" has no closed profile to revolve');
    }
    final angle = a.number('angle') ?? 360;
    if (angle <= 0 || angle > 360) {
      return AiActionOutcome.failed(a.op, 'angle must be > 0 and <= 360');
    }
    final axis = (a.text('axis') ?? 'x').toLowerCase();
    if (axis != 'x' && axis != 'y') {
      return AiActionOutcome.failed(a.op, 'axis must be "x" or "y"');
    }
    // The profile must lie wholly on one side of the axis or the kernel builds
    // a self-intersecting body. Catching it here names the offending sketch;
    // the kernel's own refusal would only say the revolve failed.
    final crossing = regions.any((r) => r.outer.pts.any((q) =>
        (axis == 'x' ? q.dy : q.dx) < -1e-9) &&
        r.outer.pts.any((q) => (axis == 'x' ? q.dy : q.dx) > 1e-9));
    if (crossing) {
      return AiActionOutcome.failed(a.op,
          'the profile crosses the $axis axis it would revolve about');
    }
    final output = _outputOf(a, p);
    final (base, body) = _target(p, a, output);
    if (output != 'new' && base == null) {
      return AiActionOutcome.failed(
          a.op, 'no existing body for a $output — use operation "new"');
    }
    final f = RevolveFeature(
      name: p.nextFeatureName('Revolution'),
      bodyName: body,
      sketchName: cs.model.name,
      profiles: [
        for (final r in regions)
          ProfileSel(regionAnchor(r).dx, regionAnchor(r).dy, r.outer.area)
      ],
      axPx: 0,
      axPy: 0,
      axDx: axis == 'x' ? 1.0 : 0.0,
      axDy: axis == 'x' ? 0.0 : 1.0,
      angleA: angle,
      exprA: '$angle deg',
      full: angle >= 360,
      output: output,
    );
    p.claimBodyName(body);
    return _commitFeature(p, a, f, base, {
      'sketch': cs.model.name,
      'profiles': f.profiles.length,
      'angle': _r(angle),
      'axis': axis,
      'operation': output,
    });
  }

  ExtrudeDirection? _direction(AiAction a) =>
      switch ((a.text('direction') ?? 'default').toLowerCase()) {
        'default' => ExtrudeDirection.defaultDir,
        'flipped' || 'reversed' => ExtrudeDirection.flipped,
        'symmetric' || 'midplane' => ExtrudeDirection.symmetric,
        _ => null,
      };

  // ---- fillet / chamfer -------------------------------------------------

  Future<AiActionOutcome> _blend(PartModel p, AiAction a) async {
    final isFillet = a.op == 'fillet';
    final size = a.number(isFillet ? 'radius' : 'distance');
    if (size == null || size <= 0) {
      return AiActionOutcome.failed(
          a.op, '${isFillet ? "radius" : "distance"} must be > 0');
    }
    final named = a.text('body');
    final body = named ??
        (p.bodyNames.isEmpty ? null : lastSolidFeature(p)?.bodyName);
    if (body == null || !p.bodyNames.contains(body)) {
      return AiActionOutcome.failed(
          a.op, named == null ? 'this part has no body yet' : 'no body "$named"');
    }
    final solid = currentBodySolid(p, body);
    if (solid == null) {
      return AiActionOutcome.failed(a.op, 'body "$body" has no built geometry');
    }
    final live = app.partKernel.edgesOf(solid);
    if (live.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'the kernel reported no edges for "$body" — it may not be linked '
          'in this build');
    }
    final picked = _selectEdges(live, a);
    if (picked.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'no edge of "$body" matched that selection (${live.length} live '
          'edges, of which ${live.where((e) => e.filletable).length} can be '
          'blended)');
    }
    final selections = [
      for (final e in picked) EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius)
    ];
    final f = isFillet
        ? FilletFeature(
            name: p.nextFeatureName('Fillet'),
            bodyName: body,
            edges: selections,
            radii: [for (var i = 0; i < selections.length; i++) size],
            exprRadius: '$size mm')
        : ChamferFeature(
            name: p.nextFeatureName('Chamfer'),
            bodyName: body,
            edges: selections,
            distance1: size,
            distance2: size,
            exprD1: '$size mm',
            exprD2: '$size mm');
    return _commitFeature(p, a, f, currentBodySolid(p, body), {
      'body': body,
      'edges': selections.length,
      if (isFillet) 'radius': _r(size) else 'distance': _r(size),
    });
  }

  /// Which live edges an action means.
  ///
  /// Every selector is GEOMETRIC, never an index: a topological index is not
  /// stable across a rebuild, so an agent that named one would be naming a
  /// different edge by the time the feature recomputed. `near` is the precise
  /// form — a point in world millimetres, matched to the edge whose arc-length
  /// midpoint is closest to it, and only within 5 mm so a mistyped coordinate
  /// selects nothing rather than something arbitrary.
  List<OcctEdgeInfo> _selectEdges(List<OcctEdgeInfo> live, AiAction a) {
    final usable = [for (final e in live) if (e.filletable) e];
    final near = a.args['near'];
    if (near is List && near.isNotEmpty) {
      final out = <OcctEdgeInfo>[];
      for (final raw in near) {
        if (raw is! List || raw.length < 3) continue;
        final xs = [for (final v in raw) if (v is num) v.toDouble()];
        if (xs.length < 3 || xs.any((v) => !v.isFinite)) continue;
        OcctEdgeInfo? best;
        var bestD = 5.0;
        for (final e in usable) {
          final d = math.sqrt(math.pow(e.mx - xs[0], 2) +
              math.pow(e.my - xs[1], 2) +
              math.pow(e.mz - xs[2], 2));
          if (d < bestD) {
            bestD = d;
            best = e;
          }
        }
        if (best != null && !out.contains(best)) out.add(best);
      }
      return out;
    }
    // A vertical edge runs along the world up axis, which is Y in this app
    // (see the world-frame note in part_model.dart) — not Z.
    bool vertical(OcctEdgeInfo e) => e.ty.abs() > 0.9;
    return switch ((a.text('edges') ?? 'all').toLowerCase()) {
      'convex' || 'rounds' => [for (final e in usable) if (e.convexity > 0) e],
      'concave' || 'fillets' => [for (final e in usable) if (e.convexity < 0) e],
      'vertical' => [for (final e in usable) if (vertical(e)) e],
      'horizontal' => [for (final e in usable) if (!vertical(e)) e],
      _ => usable,
    };
  }

  // ---- editing what is already there ------------------------------------

  PartFeature? _feature(PartModel p, String name) {
    for (final f in p.features) {
      if (f.name == name) return f;
    }
    return null;
  }

  Future<AiActionOutcome> _editFeature(PartModel p, AiAction a) async {
    final name = a.text('feature');
    if (name == null) return AiActionOutcome.failed(a.op, 'feature is required');
    final f = _feature(p, name);
    if (f == null) {
      return AiActionOutcome.failed(a.op,
          'no feature named "$name" (this part has: '
          '${p.features.map((g) => g.name).join(", ")})');
    }
    final changed = <String, dynamic>{};
    final operation = a.text('operation')?.toLowerCase();
    if (operation != null) {
      if (!_outputs.contains(operation)) {
        return AiActionOutcome.failed(a.op, 'operation must be one of '
            '${_outputs.join(", ")}');
      }
      if (f.modifiesBody) {
        return AiActionOutcome.failed(
            a.op, '${f.typeLabel} has no boolean output');
      }
      f.output = operation;
      changed['operation'] = operation;
    }
    // Each case is its own block: switch cases share one scope in Dart, and
    // two of these want a local called `d`.
    switch (f) {
      case final ExtrudeFeature extrude:
        {
          final d = a.number('distance');
          if (d != null) {
            if (d <= 0) {
              return AiActionOutcome.failed(a.op, 'distance must be > 0');
            }
            extrude.distanceA = d;
            extrude.exprA = '$d mm';
            // A typed distance is only consulted for the plain extent, so an
            // edit that set one and left the feature on Through All would
            // change nothing at all and report that it had.
            extrude.extent = FeatureExtent.distance;
            changed['distance'] = _r(d);
          }
          final b = a.number('distance_b');
          if (b != null && b > 0) {
            extrude.distanceB = b;
            extrude.exprB = '$b mm';
            extrude.direction = ExtrudeDirection.asymmetric;
            changed['distanceB'] = _r(b);
          }
          final t = a.number('taper');
          if (t != null) {
            if (t.abs() >= 90) {
              return AiActionOutcome.failed(
                  a.op, 'taper must be between -90 and 90');
            }
            extrude.taperDeg = t;
            extrude.exprTaper = '$t deg';
            changed['taper'] = _r(t);
          }
        }
      case final RevolveFeature revolve:
        {
          final angle = a.number('angle');
          if (angle != null) {
            if (angle <= 0 || angle > 360) {
              return AiActionOutcome.failed(a.op, 'angle must be > 0 and <= 360');
            }
            revolve.angleA = angle;
            revolve.exprA = '$angle deg';
            revolve.full = angle >= 360;
            changed['angle'] = _r(angle);
          }
        }
      case final FilletFeature fillet:
        {
          final r = a.number('radius');
          if (r != null) {
            if (r <= 0) {
              return AiActionOutcome.failed(a.op, 'radius must be > 0');
            }
            for (var i = 0; i < fillet.radii.length; i++) {
              fillet.radii[i] = r;
            }
            fillet.exprRadius = '$r mm';
            changed['radius'] = _r(r);
          }
        }
      case final ChamferFeature chamfer:
        {
          final d = a.number('distance');
          if (d != null) {
            if (d <= 0) {
              return AiActionOutcome.failed(a.op, 'distance must be > 0');
            }
            chamfer.distance1 = d;
            chamfer.distance2 = d;
            chamfer.exprD1 = '$d mm';
            chamfer.exprD2 = '$d mm';
            changed['distance'] = _r(d);
          }
        }
      default:
        break;
    }
    if (changed.isEmpty) {
      return AiActionOutcome.failed(a.op,
          'nothing to change: ${f.typeLabel} "$name" takes none of the '
          'arguments given');
    }
    app.aiRebuild(p);
    if (f.computeError != null) {
      return AiActionOutcome.failed(
          a.op, 'rebuild failed: ${f.computeError}');
    }
    Log.i('ai', 'feature "$name" edited: $changed');
    return AiActionOutcome(a.op, detail: {'feature': name, 'changed': changed});
  }

  Future<AiActionOutcome> _deleteFeature(PartModel p, AiAction a) async {
    final name = a.text('feature');
    if (name == null) return AiActionOutcome.failed(a.op, 'feature is required');
    final f = _feature(p, name);
    if (f == null) return AiActionOutcome.failed(a.op, 'no feature named "$name"');
    // The batch already holds the snapshot this delete belongs to.
    await app.deleteFeature(f, checkpoint: false);
    return AiActionOutcome(a.op,
        detail: {'deleted': name, 'featuresLeft': p.features.length});
  }

  Future<AiActionOutcome> _renameFeature(PartModel p, AiAction a) async {
    final name = a.text('feature'), to = a.text('name');
    if (name == null || to == null) {
      return AiActionOutcome.failed(a.op, 'feature and name are required');
    }
    final f = _feature(p, name);
    if (f == null) return AiActionOutcome.failed(a.op, 'no feature named "$name"');
    if (p.features.any((g) => !identical(g, f) && g.name == to)) {
      return AiActionOutcome.failed(a.op, '"$to" is already taken');
    }
    if (!app.renameFeature(f, to)) {
      return AiActionOutcome.failed(a.op, 'the rename was refused');
    }
    return AiActionOutcome(a.op, detail: {'feature': to, 'wasNamed': name});
  }

  // ---- inspection: reading the shape, never changing it -----------------

  /// The digest of a named body, or of the largest one.
  ShapeDigest? _digestOf(PartModel p, AiAction a) {
    final named = a.text('body');
    if (named != null) return digests.of(p, named, app.partKernel);
    final all = digests.all(p, app.partKernel);
    return all.isEmpty ? null : all.first;
  }

  AiActionOutcome _describeShape(PartModel p, AiAction a) {
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op,
          p.bodyNames.isEmpty
              ? 'this part has no built body to describe'
              : 'no body "${a.text('body')}" (have: ${p.bodyNames.join(", ")})');
    }
    final detail = (a.text('detail') ?? 'digest').toLowerCase();
    return switch (detail) {
      'sections' => AiActionOutcome(a.op, detail: {
          'body': d.body,
          'axis': d.sectionAxis,
          'sections': [
            for (final s in d.sections)
              {
                'at': _r(s.at),
                'loops': s.loops,
                'width': _r(s.width),
                'height': _r(s.height),
                'areaMm2': _r(s.area)
              }
          ],
          'method': 'plane/triangle intersection on the tessellation (±0.1 mm)',
        }),
      'faces' => AiActionOutcome(a.op, detail: {
          'body': d.body,
          'faceCount': d.faces.length,
          'faces': [for (final f in _rank(d.faces).take(20)) _faceRow(f)],
          if (d.faces.length > 20) 'omitted': d.faces.length - 20,
        }),
      _ => AiActionOutcome(a.op,
          detail: {'body': d.body, 'shape': d.toText()}),
    };
  }

  /// Largest first. An assistant reading a truncated list should see the faces
  /// that matter, not the ones that happened to be indexed first.
  List<DigestFace> _rank(List<DigestFace> faces) =>
      [...faces]..sort((x, y) => y.area.compareTo(x.area));

  Map<String, dynamic> _faceRow(DigestFace f) => {
        'face': 'F${f.id}',
        'type': faceTypeName(f.type),
        if (f.radius > 0) 'diameter': _r(f.diameter),
        'areaMm2': _r(f.area),
        'at': [_r(f.centroid.x), _r(f.centroid.y), _r(f.centroid.z)],
        'dir': [_r(f.dir.x), _r(f.dir.y), _r(f.dir.z)],
        if (f.type != kFacePlane) 'concave': f.concave,
        if (f.tangent) 'blend': true,
      };

  static const _faceTypes = {
    'plane': kFacePlane,
    'cylinder': kFaceCylinder,
    'cone': kFaceCone,
    'sphere': kFaceSphere,
    'torus': kFaceTorus,
  };

  AiActionOutcome _facesWhere(PartModel p, AiAction a) {
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op, 'this part has no built body');
    }
    var picked = _rank(d.faces);
    final type = a.text('type')?.toLowerCase();
    if (type != null) {
      final want = _faceTypes[type];
      if (want == null) {
        return AiActionOutcome.failed(
            a.op, 'type must be one of ${_faceTypes.keys.join(", ")}');
      }
      picked = [for (final f in picked) if (f.type == want) f];
    }
    final dia = a.number('diameter');
    if (dia != null) {
      picked = [
        for (final f in picked)
          if ((f.diameter - dia).abs() < 0.01) f
      ];
    }
    final minArea = a.number('min_area');
    if (minArea != null) {
      picked = [for (final f in picked) if (f.area >= minArea) f];
    }
    final axis = a.text('axis')?.toLowerCase();
    if (axis != null) {
      final want = switch (axis) {
        'x' || '+x' || '-x' => const Vec3(1, 0, 0),
        'y' || '+y' || '-y' => const Vec3(0, 1, 0),
        'z' || '+z' || '-z' => const Vec3(0, 0, 1),
        _ => null,
      };
      if (want == null) {
        return AiActionOutcome.failed(a.op, 'axis must be x, y or z');
      }
      picked = [
        for (final f in picked)
          if (f.dir.dot(want).abs() > 0.99) f
      ];
    }
    final near = a.args['near'];
    if (near is List && near.length >= 3) {
      final xs = [for (final v in near) if (v is num) v.toDouble()];
      if (xs.length >= 3) {
        final at = Vec3(xs[0], xs[1], xs[2]);
        picked = [...picked]
          ..sort((x, y) =>
              (x.centroid - at).length.compareTo((y.centroid - at).length));
      }
    }
    final limit = (a.number('limit') ?? 20).clamp(1, 20).toInt();
    return AiActionOutcome(a.op, detail: {
      'body': d.body,
      'matched': picked.length,
      'faces': [for (final f in picked.take(limit)) _faceRow(f)],
      if (picked.length > limit) 'omitted': picked.length - limit,
    });
  }

  /// A face named as `F<id>`, resolved against the CURRENT digest.
  (DigestFace?, String?) _face(PartModel p, AiAction a, String key) {
    final d = _digestOf(p, a);
    if (d == null) return (null, 'this part has no built body');
    final name = a.text(key);
    if (name == null) return (null, '$key is required, as a face id like "F3"');
    final id = int.tryParse(name.replaceFirst(RegExp('^[Ff]'), ''));
    if (id == null) return (null, '"$name" is not a face id');
    for (final f in d.faces) {
      if (f.id == id) return (f, null);
    }
    return (
      null,
      'no face $name on ${d.body} (it has ${d.faces.length} faces; '
          'use faces_where to find one)'
    );
  }

  AiActionOutcome _measure(PartModel p, AiAction a) {
    final (from, e1) = _face(p, a, 'from');
    if (from == null) return AiActionOutcome.failed(a.op, e1!);
    final (to, e2) = _face(p, a, 'to');
    if (to == null) return AiActionOutcome.failed(a.op, e2!);
    final delta = to.centroid - from.centroid;
    final dot = from.dir.dot(to.dir).clamp(-1.0, 1.0);
    final angle = math.acos(dot) * 180 / math.pi;
    final parallel = dot.abs() > 0.999;
    return AiActionOutcome(a.op, detail: {
      'from': 'F${from.id}',
      'to': 'F${to.id}',
      'centroidDistanceMm': _r(delta.length),
      'angleDeg': _r(angle),
      if (parallel && from.type == kFacePlane && to.type == kFacePlane)
        'planeSeparationMm': _r(delta.dot(from.dir).abs()),
      'method': 'centroids and normals from the tessellation (±1%); '
          'a plane separation is exact where both faces are planar',
    });
  }

  AiActionOutcome _section(PartModel p, AiAction a) {
    final d = _digestOf(p, a);
    if (d == null) {
      return AiActionOutcome.failed(a.op, 'this part has no built body');
    }
    final axisName = (a.text('axis') ?? d.sectionAxis).toLowerCase();
    final axis = switch (axisName) {
      'x' => 0,
      'y' => 1,
      'z' => 2,
      _ => -1,
    };
    if (axis < 0) {
      return AiActionOutcome.failed(a.op, 'axis must be x, y or z');
    }
    final solid = currentBodySolid(p, d.body);
    if (solid == null) {
      return AiActionOutcome.failed(a.op, 'body "${d.body}" has no geometry');
    }
    final profiles = sectionProfiles(solid.mesh, axis, d.min, d.max);
    if (profiles.isEmpty) {
      return AiActionOutcome.failed(
          a.op, 'the plane met no geometry — check the axis and position');
    }
    final at = a.number('at');
    final chosen = at == null
        ? profiles
        : [
            (profiles..sort((x, y) =>
                    (x.at - at).abs().compareTo((y.at - at).abs())))
                .first
          ];
    return AiActionOutcome(a.op, detail: {
      'body': d.body,
      'axis': axisName.toUpperCase(),
      'sections': [
        for (final s in chosen)
          {
            'at': _r(s.at),
            'loops': s.loops,
            'width': _r(s.width),
            'height': _r(s.height),
            'areaMm2': _r(s.area)
          }
      ],
      'method': 'plane/triangle intersection on the tessellation (±0.1 mm)',
    });
  }

  // ---- direct editing: bodies with no feature tree -----------------------

  Future<AiActionOutcome> _faceEdit(PartModel p, AiAction a) async {
    final (face, err) = _face(p, a, 'face');
    if (face == null) return AiActionOutcome.failed(a.op, err!);
    if (face.topoId <= 0) {
      return AiActionOutcome.failed(a.op,
          'the kernel did not supply a topological id for F${face.id}, so it '
          'cannot be addressed — this build\'s shim is too old for face edits');
    }
    final d = _digestOf(p, a)!;
    final body = d.body;
    final base = currentBodySolid(p, body);
    if (base == null) {
      return AiActionOutcome.failed(a.op, 'body "$body" has no geometry');
    }
    final isDelete = a.op == 'delete_face';
    final distance = isDelete ? 0.0 : a.number('distance');
    if (!isDelete && (distance == null || distance == 0)) {
      return AiActionOutcome.failed(a.op, 'distance is required and non-zero');
    }
    // A FacePick is the same "remember the geometry, re-find the index"
    // fingerprint the viewport's own picking produces, so a face the agent
    // names resolves after a rebuild exactly as a tapped one does.
    final pick = FacePick(face.centroid.x, face.centroid.y, face.centroid.z,
        face.dir.x, face.dir.y, face.dir.z, face.area, face.type);
    final f = isDelete
        ? DeleteFaceFeature(
            name: p.nextFeatureName('Delete Face'),
            bodyName: body,
            faces: [pick],
          )
        // Direct edit moves faces by a WORLD delta, not by a scalar. Along the
        // face's own normal is what "offset this face by 2 mm" means, and it
        // is the only reading that does not need a direction argument.
        : DirectEditFeature(
            name: p.nextFeatureName('Direct'),
            bodyName: body,
            faces: [pick],
            op: DirectOp.move,
            dx: face.dir.x * distance!,
            dy: face.dir.y * distance,
            dz: face.dir.z * distance,
          );
    return _commitFeature(p, a, f, base, {
      'body': body,
      'face': 'F${face.id}',
      if (!isDelete) 'distance': _r(distance!),
    });
  }

  Future<AiActionOutcome> _sketchOnFace(PartModel p, AiAction a) async {
    final (face, err) = _face(p, a, 'face');
    if (face == null) return AiActionOutcome.failed(a.op, err!);
    if (face.type != kFacePlane) {
      return AiActionOutcome.failed(a.op,
          'F${face.id} is a ${faceTypeName(face.type)}; a sketch needs a '
          'planar face');
    }
    if (p.childSketches.length >= 200) {
      return AiActionOutcome.failed(a.op, 'this part already has 200 sketches');
    }
    // The app's own face-to-sketch frame, so the agent's sketch sits on the
    // face the same way a tapped one does.
    final frame = faceFrame(face.centroid, face.dir);
    final sketch = SketchModel(p.nextSketchName());
    sketch.insertLayerAboveMarker(_layerName);
    p.appendChildSketch(ChildSketch(
        sketch, kWorkPlaneKey, frame, true, false, p.nextSeq()));
    app.aiAdmitSketchRow(p);
    Log.i('ai', 'sketch "${sketch.name}" on face F${face.id} of "${p.name}"');
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      'face': 'F${face.id}',
      'origin': [
        _r(face.centroid.x),
        _r(face.centroid.y),
        _r(face.centroid.z)
      ],
      'normal': [_r(face.dir.x), _r(face.dir.y), _r(face.dir.z)],
      'note': 'sketch coordinates are in the face plane, origin at the point '
          'above; +X follows the frame the app built for it. The sketch is '
          'pinned to that frame and does not follow the face if the body '
          'changes underneath it.',
    });
  }

  // ---- commit + report --------------------------------------------------

  /// Builds [f], adds it to the timeline, and reports what the KERNEL said.
  ///
  /// A feature that does not compute is never added: an agent that could leave
  /// broken rows behind would accumulate them, and the user would inherit a
  /// timeline nobody can rebuild. The one exception is a build with no kernel
  /// linked at all (the desktop host), where the parameters are stored
  /// honestly and the report says exactly that rather than claiming geometry.
  Future<AiActionOutcome> _commitFeature(PartModel p, AiAction a, PartFeature f,
      KernelSolid? base, Map<String, dynamic> detail) async {
    final ok = recomputeFeature(p, f, app.partKernel, base: base);
    if (!ok && app.partKernel.available) {
      f.disposeSolid();
      return AiActionOutcome.failed(a.op,
          '${f.typeLabel} did not build: '
          '${f.computeError ?? app.partKernel.lastError}');
    }
    f.seq = p.nextSeq();
    p.appendFeature(f);
    applyEndOfPart(p);
    // Inventor consumes the sketch into the feature that first uses it.
    if (f.sketchName.isNotEmpty && consumersOf(p, f.sketchName).length == 1) {
      p.sketchByName(f.sketchName)?.visible = false;
    }
    app.aiRebuild(p);
    Log.i('ai', '${f.kind} "${f.name}" created on "${p.name}" ok=$ok');
    return AiActionOutcome(a.op, detail: {
      'feature': f.name,
      'body': f.bodyName,
      ...detail,
      if (!app.partKernel.available)
        'note': 'No 3D kernel is linked in this build, so the feature is '
            'stored with its parameters but carries no geometry yet.',
      ...?_bodyFacts(p, f.bodyName),
    });
  }

  Map<String, dynamic>? _bodyFacts(PartModel p, String body) {
    final solid = currentBodySolid(p, body);
    if (solid == null) return null;
    return {'volumeMm3': _r(solid.volume)};
  }

  /// What the document says after the block — measured, and the same shape
  /// `describe_part` returns. This is the model's only trustworthy account of
  /// what it just did.
  Map<String, dynamic> _state(PartModel p) {
    final bounds = partContentBounds(p);
    return {
      'name': p.name,
      'units': {'length': 'mm', 'angle': 'deg'},
      'sketches': [
        for (final cs in p.childSketches.take(40))
          {
            'name': cs.model.name,
            'plane': cs.plane,
            'entities': cs.model.geometry.length,
            'closedProfiles': app.sessionRegions(cs).length,
          }
      ],
      'features': [
        for (final f in p.features.take(80))
          {
            'name': f.name,
            'type': f.kind,
            'body': f.bodyName,
            if (!f.modifiesBody) 'operation': f.output,
            if (f.sketchName.isNotEmpty) 'sketch': f.sketchName,
            if (f is ExtrudeFeature && f.extent == FeatureExtent.distance)
              'distance': _r(f.distanceA),
            if (f is ExtrudeFeature) 'extent': featureExtentName(f.extent),
            if (f is RevolveFeature) 'angle': _r(f.sweepDeg),
            if (f is FilletFeature && f.radii.isNotEmpty)
              'radius': _r(f.radii.first),
            if (f is ChamferFeature) 'distance': _r(f.distance1),
            if (f.rolledBack) 'rolledBack': true,
            if (f.computeError != null) 'error': f.computeError,
          }
      ],
      'bodies': [
        for (final (name, _) in p.solidBodies())
          {
            'name': name,
            if (currentBodySolid(p, name) != null)
              'volumeMm3': _r(currentBodySolid(p, name)!.volume),
          }
      ],
      if (bounds != null)
        'boundingBoxMm': {
          'min': [_r(bounds.$1.x), _r(bounds.$1.y), _r(bounds.$1.z)],
          'max': [_r(bounds.$2.x), _r(bounds.$2.y), _r(bounds.$2.z)],
          'size': [
            _r(bounds.$2.x - bounds.$1.x),
            _r(bounds.$2.y - bounds.$1.y),
            _r(bounds.$2.z - bounds.$1.z)
          ],
        },
      'coverage': 'Timeline and measured bounds only. No strength, clearance, '
          'interference or manufacturing check is implied.',
    };
  }

  /// Four decimals is a micron on a millimetre part — past what any of this
  /// geometry is accurate to, and short enough that a report stays readable.
  static double _r(double v) =>
      v.isFinite ? (v * 10000).roundToDouble() / 10000 : 0;
}
