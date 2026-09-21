part of 'ai_cad.dart';

/// CONSTRAINTS AND DIMENSIONS — what makes a sketch a drawing rather than a
/// picture.
///
/// The assistant could place geometry at computed coordinates and nothing
/// else. That works right up until something has to change: a rectangle whose
/// corners are four independent points has no width to edit, and a model
/// asked to make it 10 mm wider has to redraw it and hope. A sketch with a
/// horizontal constraint and a dimension has a width, and the width is a
/// number anyone can change afterwards — including the user, long after the
/// assistant has gone.
///
/// A constraint that cannot be satisfied is REMOVED again, not left in place
/// to poison every later solve. That is the append/solve/roll-back the app's
/// own gear placement uses, and the reason it exists: once a sketch is
/// over-constrained, every later drag reports "cannot be satisfied" and the
/// cause is nowhere near the symptom.
extension AiCadConstrain on AiCad {
  /// The constraints the sketcher has, by the name the assistant uses.
  static const Map<String, CType> kinds = {
    'coincident': CType.coincident,
    'collinear': CType.collinear,
    'concentric': CType.concentric,
    'fix': CType.fix,
    'parallel': CType.parallel,
    'perpendicular': CType.perpendicular,
    'horizontal': CType.horizontal,
    'vertical': CType.vertical,
    'tangent': CType.tangent,
    'smooth': CType.smooth,
    'symmetric': CType.symmetric,
    'equal': CType.equal,
    'midpoint': CType.midpoint,
  };

  /// Constraints that take POINTS rather than whole entities.
  static const Set<CType> pointBased = {
    CType.coincident,
    CType.midpoint,
  };

  AiActionOutcome _sketchConstrain(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final sketch = cs.model;
    final geometry = sketch.geometry;
    if (geometry.isEmpty) {
      return AiActionOutcome.failed(a.op, 'this sketch is empty');
    }

    final name = (a.text('type') ?? '').toLowerCase();
    final type = kinds[name];
    if (type == null) {
      return AiActionOutcome.failed(
          a.op,
          'type must be one of ${(kinds.keys.toList()..sort()).join(", ")}');
    }

    final picks = [for (final q in a.points('near')) Offset(q[0], q[1])];
    if (picks.isEmpty) {
      return AiActionOutcome.failed(
          a.op,
          '`near` picks what to constrain: one point per entity, in sketch '
          'coordinates');
    }
    final ents = <int>[];
    for (final q in picks) {
      final i = _nearestEntity(geometry, q);
      if (i == null) {
        return AiActionOutcome.failed(
            a.op, 'nothing is near (${_mm(q.dx)}, ${_mm(q.dy)})');
      }
      if (!ents.contains(i)) ents.add(i);
    }

    final need = switch (type) {
      CType.horizontal || CType.vertical || CType.fix => 1,
      CType.symmetric => 3,
      _ => 2,
    };
    if (ents.length < need) {
      return AiActionOutcome.failed(
          a.op,
          '$name needs $need distinct ${need == 1 ? "entity" : "entities"}; '
          '`near` resolved to ${ents.length}');
    }

    final before = sketch.constraints.length;
    if (pointBased.contains(type)) {
      // A point constraint names an END, and which end is decided by which
      // end the pick is nearest — the same rule the sketcher's own click uses.
      final refs = <PRef>[
        for (var k = 0; k < 2 && k < ents.length; k++)
          PRef(ents[k], _nearestPointIndex(geometry[ents[k]], picks[k]))
      ];
      sketch.constraints.add(Constraint(type, pts: refs));
    } else if (type == CType.symmetric) {
      sketch.constraints.add(Constraint(type,
          pts: [
            PRef(ents[0], _nearestPointIndex(geometry[ents[0]], picks[0])),
            PRef(ents[1], _nearestPointIndex(geometry[ents[1]], picks[1])),
          ],
          ents: [ents[2]]));
    } else {
      sketch.constraints.add(Constraint(type, ents: ents.take(need).toList()));
    }

    if (!app.aiSolveSketch(sketch)) {
      sketch.constraints.removeRange(before, sketch.constraints.length);
      return AiActionOutcome.failed(
          a.op,
          'that $name cannot be satisfied with what the sketch already has, '
          'so it was not added. Check the sketch is not already fully '
          'constrained, or constrain a different pair.');
    }
    sketch.dirty = true;
    app.aiForgetRegions(sketch.name);
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      'type': name,
      'entities': ents.take(need).length,
      'constraints': sketch.constraints.length,
      'closedProfiles': app.sessionRegions(cs).length,
    });
  }

  // ---- dimension --------------------------------------------------------

  /// A DRIVING dimension: the number that makes a sketch editable afterwards.
  AiActionOutcome _sketchDimension(PartModel p, AiAction a) {
    final (cs, err) = _sketchFor(p, a);
    if (cs == null) return AiActionOutcome.failed(a.op, err!);
    final sketch = cs.model;
    if (sketch.geometry.isEmpty) {
      return AiActionOutcome.failed(a.op, 'this sketch is empty');
    }
    final value = a.number('value');
    if (value == null) {
      return AiActionOutcome.failed(
          a.op, 'value is the size the dimension drives to');
    }
    const kindsOfDim = {'dist', 'distx', 'disty', 'rad', 'dia', 'ang'};
    final kind = (a.text('kind') ?? 'dist').toLowerCase();
    if (!kindsOfDim.contains(kind)) {
      return AiActionOutcome.failed(
          a.op, 'kind must be one of ${kindsOfDim.join(", ")}');
    }
    if ((kind == 'rad' || kind == 'dia') && value <= 0) {
      return AiActionOutcome.failed(a.op, 'a $kind must be > 0');
    }

    final picks = [for (final q in a.points('near')) Offset(q[0], q[1])];
    if (picks.isEmpty) {
      return AiActionOutcome.failed(
          a.op, '`near` picks what to dimension: one point per entity');
    }
    final ents = <int>[];
    for (final q in picks) {
      final i = _nearestEntity(sketch.geometry, q);
      if (i == null) {
        return AiActionOutcome.failed(
            a.op, 'nothing is near (${_mm(q.dx)}, ${_mm(q.dy)})');
      }
      if (!ents.contains(i)) ents.add(i);
    }

    final before = sketch.constraints.length;
    sketch.constraints.add(Constraint(CType.dimension,
        ents: ents, value: value, dimKind: kind));
    if (!app.aiSolveSketch(sketch)) {
      sketch.constraints.removeRange(before, sketch.constraints.length);
      return AiActionOutcome.failed(
          a.op,
          'that dimension cannot be satisfied — it would over-constrain the '
          'sketch or contradict one already there, so it was not added');
    }
    sketch.dirty = true;
    app.aiForgetRegions(sketch.name);
    return AiActionOutcome(a.op, detail: {
      'sketch': sketch.name,
      'kind': kind,
      'value': _r(value),
      'entities': ents.length,
      'constraints': sketch.constraints.length,
      'closedProfiles': app.sessionRegions(cs).length,
    });
  }

  /// Which defining point of [g] a pick means. Endpoints for a line, the
  /// centre for a circle — the same choices the sketcher offers.
  int _nearestPointIndex(Geo g, Offset q) {
    final pts = switch (g.type) {
      Geo.line => [Offset(g.data[0], g.data[1]), Offset(g.data[2], g.data[3])],
      Geo.circle => [Offset(g.data[0], g.data[1])],
      _ => <Offset>[],
    };
    if (pts.isEmpty) return 0;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (pts[i] - q).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}
