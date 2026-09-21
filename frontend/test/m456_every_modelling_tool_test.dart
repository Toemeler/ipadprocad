// M456 — the assistant can reach every tool the app has.
//
// It could extrude, revolve, fillet, chamfer, delete a face and move one.
// The app has carried hole, sweep, loft, coil, split, combine and four kinds
// of pattern the whole time — each one a real feature with its own panel, its
// own browser row and its own kernel path — and not one of them was in
// kAiOps. A model asked for a spring, a swept handle, a counterbored screw
// hole or a ring of six bosses had to fake it out of extrusions or say it
// could not do it. That is not the model being weak; that is the app having
// handed it a quarter of its own toolbox.
//
// Every op here builds the SAME feature object the app's own panel builds and
// commits it through the same path, so what the assistant makes is
// indistinguishable in the timeline from what a person makes: named, listed,
// editable, undoable, rebuilt by the same fold.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'support/shape_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];
  tearDown(apps.clear);

  Future<AppState> partWith(List<AiAction> setup) async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m456_');
    apps.add(app);
    await app.createNamedPart('Work');
    if (setup.isNotEmpty) {
      final made = await AiCad(app).run(setup);
      expect(made.ok, isTrue, reason: made.encode());
    }
    return app;
  }

  /// A plate to drill, pattern, split or combine against.
  Future<AppState> withPlate() => partWith([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 80, 'height': 60}),
        const AiAction('extrude', {'distance': 10}),
      ]);

  PartFeature lastFeature(AppState app) => app.currentPart!.features.last;

  group('hole', () {
    test('a simple hole is a Hole feature, not a cut extrusion', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole',
            {'places': [[20, 20], [60, 20]], 'diameter': 6, 'depth': 8}),
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app);
      expect(f, isA<HoleFeature>());
      expect(f.kind, 'hole');
      expect((f as HoleFeature).places, hasLength(2));
      expect(f.dia, 6);
      expect(f.depth, 8);
      expect(report.outcomes.last.detail!['holes'], 2);
    });

    test('one hole may be given as x and y', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole',
            {'x': 10, 'y': 10, 'diameter': 4, 'through_all': true}),
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app) as HoleFeature;
      expect(f.places.single.x, 10);
      expect(f.extent, FeatureExtent.throughAll);
    });

    test('a counterbore carries its own numbers', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole', {
          'x': 40, 'y': 30, 'diameter': 5, 'depth': 9,
          'type': 'counterbore', 'cb_diameter': 10, 'cb_depth': 4,
        }),
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app) as HoleFeature;
      expect(f.type, HoleType.counterbore);
      expect(f.cbDia, 10);
      expect(f.cbDepth, 4);
      expect(report.outcomes.last.detail!['counterbore'],
          containsPair('diameter', 10));
    });

    test('a counterbore narrower than its hole is refused, with the number',
        () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole', {
          'x': 0, 'y': 0, 'diameter': 8, 'depth': 5,
          'type': 'counterbore', 'cb_diameter': 6, 'cb_depth': 2,
        }),
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.last.error, contains('8.00'));
    });

    test('a countersink checks its angle', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole', {
          'x': 0, 'y': 0, 'diameter': 5, 'depth': 5,
          'type': 'countersink', 'cs_diameter': 10, 'cs_angle': 200,
        }),
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.last.error, contains('between 0 and 180'));
    });

    test('a hole with nothing to drill says so', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xz'}),
      ]);
      final report = await AiCad(app)
          .run([const AiAction('hole', {'x': 0, 'y': 0, 'diameter': 5, 'depth': 5})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('material to drill'));
    });
  });

  group('sweep', () {
    Future<AppState> profileAndPath() => partWith([
          const AiAction('create_sketch', {'plane': 'xz'}),
          const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 8}),
          const AiAction('create_sketch', {'plane': 'xy'}),
          const AiAction('sketch_arc',
              {'x': 0, 'y': 0, 'radius': 30, 'start_deg': 0, 'end_deg': 90}),
        ]);

    test('a profile travels along a path in another sketch', () async {
      final app = await profileAndPath();
      final report = await AiCad(app).run([
        const AiAction('sweep',
            {'profile_sketch': 'Sketch1', 'path_sketch': 'Sketch2'})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app);
      expect(f, isA<SweepFeature>());
      expect((f as SweepFeature).path!.sketchName, 'Sketch2');
      expect((app.partKernel as BoxKernel).sweeps, greaterThanOrEqualTo(1));
      // The path length is measured, not assumed: a quarter of Ø60.
      expect(report.outcomes.single.detail!['pathLengthMm'],
          closeTo(47.1, 1.0));
    });

    test('the profile and the path must be different sketches', () async {
      final app = await profileAndPath();
      final report = await AiCad(app).run([
        const AiAction('sweep',
            {'profile_sketch': 'Sketch1', 'path_sketch': 'Sketch1'})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('different sketches'));
    });

    test('a closed sketch is not a path', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'diameter': 8}),
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_circle', {'diameter': 40}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('sweep',
            {'profile_sketch': 'Sketch1', 'path_sketch': 'Sketch2'})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('no open curve'));
    });

    test('a missing path is named, not guessed at', () async {
      final app = await profileAndPath();
      final report = await AiCad(app)
          .run([const AiAction('sweep', {'profile_sketch': 'Sketch1'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('path_sketch is required'));
    });
  });

  group('loft', () {
    test('it blends through the sections in the order given', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 60, 'height': 40}),
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'diameter': 20}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('loft', {'sketches': ['Sketch1', 'Sketch2']})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app);
      expect(f, isA<LoftFeature>());
      expect((f as LoftFeature).sectionSketches, ['Sketch1', 'Sketch2']);
      expect((app.partKernel as BoxKernel).lofts, greaterThanOrEqualTo(1));
    });

    test('one section is not a loft', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'diameter': 20}),
      ]);
      final report = await AiCad(app)
          .run([const AiAction('loft', {'sketches': ['Sketch1']})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('at least 2'));
    });

    test('a section with no closed profile is named', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'diameter': 20}),
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_line', {'x1': 0, 'y1': 0, 'x2': 10, 'y2': 0}),
      ]);
      final report = await AiCad(app)
          .run([const AiAction('loft', {'sketches': ['Sketch1', 'Sketch2']})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('"Sketch2"'));
    });
  });

  group('coil', () {
    test('a spring: revolutions and height', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_circle', {'x': 20, 'y': 0, 'diameter': 3}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('coil',
            {'axis': 'y', 'revolutions': 8, 'height': 40})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(lastFeature(app), isA<CoilFeature>());
      expect((app.partKernel as BoxKernel).lastCoil, (8.0, 40.0, false));
    });

    test('a thread: pitch and height resolve to revolutions', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_circle', {'x': 10, 'y': 0, 'diameter': 1}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('coil',
            {'method': 'pitch_height', 'pitch': 2, 'height': 20})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      // 20 mm at 2 mm a turn is ten turns — the arithmetic the four methods
      // all funnel through, not a number the caller had to work out.
      expect((app.partKernel as BoxKernel).lastCoil, (10.0, 20.0, false));
      expect(report.outcomes.single.detail!['revolutions'], 10);
    });

    test('a method is validated on the values it actually uses', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_circle', {'x': 10, 'y': 0, 'diameter': 1}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('coil', {'method': 'pitch_height', 'pitch': 0, 'height': 20})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('pitch must be > 0'));
    });

    test('an unknown method names the four that exist', () async {
      final app = await partWith([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_circle', {'x': 10, 'y': 0, 'diameter': 1}),
      ]);
      final report = await AiCad(app)
          .run([const AiAction('coil', {'method': 'helix'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('spiral'));
    });
  });

  group('split and combine', () {
    test('split trims the body at a plane', () async {
      final app = await withPlate();
      final report = await AiCad(app)
          .run([const AiAction('split_body', {'plane': 'xz', 'offset': 5})]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(lastFeature(app), isA<SplitFeature>());
      expect(report.outcomes.single.detail!['plane'], contains('5.00 mm'));
    });

    test('split takes an outright point and normal too', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('split_body',
            {'px': 0, 'py': 4, 'pz': 0, 'nx': 0, 'ny': 1, 'nz': 0})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app) as SplitFeature;
      expect(f.frame.n.y, closeTo(1, 1e-9));
    });

    test('combine names the bodies it does not have', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('combine', {'tools': ['Solid7'], 'operation': 'cut'})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('no body named "Solid7"'));
    });

    test('a body cannot be combined with itself', () async {
      final app = await withPlate();
      final body = app.currentPart!.features.first.bodyName;
      final report = await AiCad(app).run([
        AiAction('combine', {'tools': [body], 'body': body})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('with itself'));
    });
  });

  group('pattern', () {
    test('a rectangular row of a named feature', () async {
      final app = await withPlate();
      final name = app.currentPart!.features.first.name;
      final report = await AiCad(app).run([
        AiAction('pattern', {
          'kind': 'rect', 'features': [name],
          'direction': 'x', 'count': 4, 'spacing': 15,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app);
      expect(f, isA<PatternFeature>());
      expect((f as PatternFeature).mode, PatternKind.rectangular);
      expect(f.countA, 4);
      expect(f.distanceA, 15);
      expect(report.outcomes.single.detail!['occurrences'], 4);
    });

    test('a grid is one feature, not two patterns', () async {
      final app = await withPlate();
      final name = app.currentPart!.features.first.name;
      final report = await AiCad(app).run([
        AiAction('pattern', {
          'kind': 'rect', 'features': [name],
          'direction': 'x', 'count': 3, 'spacing': 10,
          'direction2': 'z', 'count2': 2, 'spacing2': 20,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['occurrences'], 6);
    });

    test('a bolt circle', () async {
      final app = await withPlate();
      final name = app.currentPart!.features.first.name;
      final report = await AiCad(app).run([
        AiAction('pattern', {
          'kind': 'circ', 'features': [name],
          'axis': 'y', 'count': 6, 'angle': 360,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app) as PatternFeature;
      expect(f.mode, PatternKind.circular);
      expect(f.countC, 6);
      expect(f.angleC, 360);
    });

    test('a mirror about a named plane', () async {
      final app = await withPlate();
      final report = await AiCad(app)
          .run([const AiAction('pattern', {'kind': 'mirror', 'plane': 'yz'})]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = lastFeature(app) as PatternFeature;
      expect(f.mode, PatternKind.mirror);
      expect(f.mirrorPlane, isNotNull);
    });

    test('a count of one is not a pattern', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('pattern',
            {'kind': 'rect', 'direction': 'x', 'count': 1, 'spacing': 10})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('at least 2'));
    });

    test('a feature that does not exist is named', () async {
      final app = await withPlate();
      final report = await AiCad(app).run([
        const AiAction('pattern', {
          'kind': 'rect', 'features': ['Nope'],
          'direction': 'x', 'count': 3, 'spacing': 10,
        })
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('no feature named "Nope"'));
    });
  });

  group('the protocol knows about all of them', () {
    test('every new op is registered and has a word for the panel', () {
      for (final op in const [
        'hole', 'sweep', 'loft', 'coil', 'split_body', 'combine', 'pattern'
      ]) {
        expect(kAiOps, contains(op), reason: op);
        expect(AiActivity(AiPhase.working, op: op).work,
            isNot(AiWork.working),
            reason: '$op would show the user "Working…" and nothing more');
      }
    });

    test('none of them is read-only', () {
      for (final op in const [
        'hole', 'sweep', 'loft', 'coil', 'split_body', 'combine', 'pattern'
      ]) {
        expect(kAiReadOnlyOps, isNot(contains(op)), reason: op);
      }
    });
  });
}
