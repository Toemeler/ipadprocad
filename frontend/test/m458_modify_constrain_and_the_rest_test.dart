// M458 — the rest of the toolbox: modify, constrain, dimension, gear, text,
// an offset sketch plane, and direct-edit sizing.
//
// M457 gave the assistant every DRAWING tool. Drawing is half of a sketch.
// The other half is the tools that turn a rough one into a drawn one — trim,
// offset, mirror, rotate — and the constraints and dimensions that make it
// EDITABLE afterwards. A rectangle whose four corners are independent points
// has no width; asked to make it 10 mm wider, the only move is to redraw it
// and hope. A rectangle with a horizontal constraint and a dimension has a
// width, and that width is a number anyone can change later, including the
// user long after the assistant has gone.
//
// A constraint that cannot be satisfied is REMOVED again rather than left to
// poison every later solve — the append/solve/roll-back the app's own gear
// placement uses, and for the reason it exists: once a sketch is
// over-constrained every later drag fails, nowhere near the cause.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart' show CType;
import 'package:prototype/ffi/qcad_engine.dart';

import 'support/shape_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];
  tearDown(apps.clear);

  Future<AppState> square() async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m458_');
    apps.add(app);
    await app.createNamedPart('Draw');
    final made = await AiCad(app).run([
      const AiAction('create_sketch', {'plane': 'xz'}),
      const AiAction('sketch_tool', {'tool': 'rect', 'points': [[0, 0], [40, 40]]}),
    ]);
    expect(made.ok, isTrue, reason: made.encode());
    return app;
  }

  List<Geo> geometryOf(AppState app) =>
      app.currentPart!.childSketches.last.model.geometry;
  SketchModel sketchOf(AppState app) =>
      app.currentPart!.childSketches.last.model;

  group('every modify tool', () {
    test('move shifts the selection and keeps the profile', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'move', 'dx': 10, 'dy': 5})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['entities'], 4);
      expect(report.outcomes.single.detail!['closedProfiles'], 1);
      // Everything moved, so the lowest x is now 10.
      final xs = [for (final g in geometryOf(app)) g.data[0]];
      expect(xs.reduce((a, b) => a < b ? a : b), closeTo(10, 1e-6));
    });

    test('copy leaves the original and adds a second profile', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'copy', 'dx': 60, 'dy': 0})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(geometryOf(app), hasLength(8));
      expect(report.outcomes.single.detail!['closedProfiles'], 2);
    });

    test('mirror about an axis doubles the sketch', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'mirror', 'axis': 'y'})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['closedProfiles'], 2);
    });

    test('rotate and scale transform in place', () async {
      final app = await square();
      final rotated = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'rotate', 'angle': 90})
      ]);
      expect(rotated.ok, isTrue, reason: rotated.encode());
      final scaled = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'scale', 'factor': 2})
      ]);
      expect(scaled.ok, isTrue, reason: scaled.encode());
      expect(geometryOf(app), hasLength(4), reason: 'neither one copies');
    });

    test('offset adds a parallel curve at a distance', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'offset', 'distance': 3})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['offset'], 4);
      expect(geometryOf(app), hasLength(8));
    });

    test('trim removes the piece the point is on', () async {
      final app = await square();
      final before = geometryOf(app).length;
      final report = await AiCad(app).run([
        const AiAction('sketch_modify', {'action': 'trim', 'near': [[20, 0]]})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(geometryOf(app).length, lessThan(before));
      expect(report.outcomes.single.detail!['closedProfiles'], 0,
          reason: 'the outline is open now');
    });

    test('trim and split insist on being told where', () async {
      final app = await square();
      final report = await AiCad(app)
          .run([const AiAction('sketch_modify', {'action': 'trim'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('which piece'));
    });

    test('a selection point with nothing near it is refused', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_modify',
            {'action': 'move', 'dx': 1, 'dy': 0, 'near': [[900, 900]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('near'));
    });

    test('an unknown action lists the ones that exist', () async {
      final app = await square();
      final report = await AiCad(app)
          .run([const AiAction('sketch_modify', {'action': 'bevel'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('offset'));
    });

    test('a pick resolves by distance to the LINE, not to its ends', () async {
      // The bug this caught: a line is sampled as two endpoints, so a pick at
      // the middle of a 40 mm line was 20 mm from it — the same distance as
      // from the line at right angles — and the two were indistinguishable.
      // A perpendicular constraint was then impossible to ask for.
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_constrain',
            {'type': 'perpendicular', 'near': [[20, 0], [40, 20]]})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['entities'], 2);
    });
  });

  group('constraints', () {
    test('a horizontal constraint is added and solved', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_constrain',
            {'type': 'horizontal', 'near': [[20, 0]]})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(sketchOf(app).constraints, hasLength(1));
    });

    test('every constraint type the sketcher has is reachable', () {
      // The map is the claim; this is the check that it covers the enum.
      for (final t in CType.values) {
        if (t == CType.dimension || t == CType.pattern) continue;
        expect(AiCadConstrain.kinds.values, contains(t),
            reason: '${t.name} has no name the assistant can use');
      }
    });

    test('one that cannot be satisfied is rolled back, not left behind',
        () async {
      final app = await square();
      // Fix every corner, then demand the bottom edge be vertical.
      await AiCad(app).run([
        const AiAction('sketch_constrain', {'type': 'fix', 'near': [[20, 0]]})
      ]);
      final before = sketchOf(app).constraints.length;
      final report = await AiCad(app).run([
        const AiAction('sketch_constrain',
            {'type': 'vertical', 'near': [[20, 0]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('not added'));
      expect(sketchOf(app).constraints, hasLength(before),
          reason: 'the sketch must be exactly as it was');
    });

    test('a type that needs two entities says so', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_constrain',
            {'type': 'parallel', 'near': [[20, 0]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('needs 2'));
    });
  });

  group('dimensions', () {
    test('a driving dimension is added and solved', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_dimension',
            {'kind': 'dist', 'value': 50, 'near': [[20, 0]]})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['value'], 50);
      expect(sketchOf(app).constraints.single.value, 50);
    });

    test('a radius must be positive', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_dimension',
            {'kind': 'rad', 'value': -5, 'near': [[20, 0]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('must be > 0'));
    });

    test('an unknown kind names the six', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_dimension',
            {'kind': 'length', 'value': 5, 'near': [[20, 0]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('distx'));
    });
  });

  group('gear and text', () {
    test('an involute gear is a real gear, not a polygon', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_gear', {'teeth': 24, 'module': 2, 'bore': 6}),
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.last.detail!;
      expect(d['teeth'], 24);
      expect(d['pitchDiameterMm'], 48);
      expect(geometryOf(app).any((g) => g.spline == Geo.gearTag), isTrue);
    });

    test('a gear with too few teeth is refused', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_gear', {'teeth': 2, 'module': 2}),
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.last.error, contains('between 6 and 400'));
    });

    test('sketch text lands on the sketch', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_text',
            {'text': 'M8', 'x': 5, 'y': 5, 'height': 6})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(sketchOf(app).texts.single.template, 'M8');
      expect(sketchOf(app).texts.single.height, 6);
    });
  });

  group('a sketch at a height', () {
    test('an offset sketch sits on a moved frame', () async {
      final app = await square();
      final report = await AiCad(app)
          .run([const AiAction('create_sketch', {'plane': 'xz', 'offset': 40})]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['offsetMm'], 40);
      final cs = app.currentPart!.childSketches.last;
      expect(cs.plane, 'face');
      expect(cs.face!.origin.y, closeTo(40, 1e-9));
    });

    test('no offset keeps the plain origin plane', () async {
      final app = await square();
      await AiCad(app).run([const AiAction('create_sketch', {'plane': 'xz'})]);
      final cs = app.currentPart!.childSketches.last;
      expect(cs.plane, 'xz');
      expect(cs.face, isNull);
    });
  });

  group('project and sketch patterns', () {
    test('a sketch pattern repeats the selection', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_pattern',
            {'kind': 'rect', 'count': 3, 'dx': 60, 'dy': 0})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['copies'], 8);
      expect(report.outcomes.single.detail!['closedProfiles'], 3);
    });

    test('a circular sketch pattern closes the ring', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_pattern', {
          'kind': 'circ', 'count': 4, 'angle': 360, 'about': [[200, 0]],
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['closedProfiles'], 4);
    });

    test('it says the copies are not linked', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_pattern',
            {'kind': 'rect', 'count': 2, 'dx': 60, 'dy': 0})
      ]);
      expect(report.outcomes.single.detail!['note'],
          contains('not linked to the original'));
    });

    test('a pattern with no step is refused', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_pattern', {'kind': 'rect', 'count': 3})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('dx and/or dy'));
    });

    test('project brings the solid\'s edges into the sketch', () async {
      final app = await square();
      final built = await AiCad(app)
          .run([const AiAction('extrude', {'distance': 10})]);
      expect(built.ok, isTrue, reason: built.encode());
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 10}),
        const AiAction('sketch_project', {}),
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.last.detail!['projected'], greaterThan(0));
    });

    test('project with no solid says so', () async {
      final app = await square();
      final report = await AiCad(app).run([const AiAction('sketch_project', {})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('no solid yet'));
    });
  });

  group('the protocol covers all of it', () {
    test('every new op is registered with a word for the panel', () {
      for (final op in const [
        'sketch_tool', 'sketch_modify', 'sketch_constrain', 'sketch_dimension',
        'sketch_gear', 'sketch_text', 'sketch_point', 'size_face',
        'sketch_project', 'sketch_pattern',
      ]) {
        expect(kAiOps, contains(op), reason: op);
        expect(AiActivity(AiPhase.working, op: op).work, isNot(AiWork.working),
            reason: op);
      }
    });
  });
}
