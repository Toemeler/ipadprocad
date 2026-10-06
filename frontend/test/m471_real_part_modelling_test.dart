// M471 — parts a mechanical engineer would model, on the REAL kernel, with
// volumes and topology checked against numbers worked out by hand.
//
// Runs wherever the kernel library is found: set PROTOTYPE_NATIVE_DIR to the
// directory holding libprototype_native.so. Without it every test SKIPS.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available
      ? false
      : 'no kernel library — set PROTOTYPE_NATIVE_DIR (see LINUX.md)';

  Future<(AppState, AiCad)> fresh() async {
    final app = AppState()..partKernel = kernel;
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m471_');
    await app.createNamedPart('Work');
    return (app, AiCad(app));
  }

  double volume(AppState app) {
    final p = app.currentPart!;
    var v = 0.0;
    for (final (name, _) in p.solidBodies()) {
      v += currentBodySolid(p, name)?.volume ?? 0;
    }
    return v;
  }

  /// A 40 x 30 x 10 plate extruded up (+Y) from the XZ origin plane.
  const plate = [
    AiAction('create_sketch', {'plane': 'xz'}),
    AiAction('sketch_rect', {'width': 40, 'height': 30}),
    AiAction('extrude', {'distance': 10}),
  ];

  group('holes', () {
    test('a Through All hole sketched on the plane the plate grew from goes '
        'through, not 1 mm deep', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole',
            {'places': [[20, 15]], 'diameter': 8, 'through_all': true}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // pi * 4^2 * 10, all the way through the 10 mm plate.
      expect(volume(app), closeTo(12000 - math.pi * 16 * 10, 0.05));
    }, skip: skip);

    test('a counterbored hole from that plane opens at the plate face it '
        'sits on', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole', {
          'places': [[20, 15]], 'diameter': 6, 'depth': 10, //
          'type': 'counterbore', 'cb_diameter': 10, 'cb_depth': 3,
        }),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // Drilled into the plate by the feature itself — the panel's path has
      // no assistant to turn it round afterwards.
      expect(r.outcomes.last.detail?['directionFixed'], isNull);
      final removed = math.pi * 9 * 10 + math.pi * (25 - 9) * 3;
      expect(volume(app), closeTo(12000 - removed, 0.05));
    }, skip: skip);
  });

  group('patterns', () {
    test('a 2 x 2 grid of a through hole drills four holes', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 80, 'height': 60}),
        const AiAction('extrude', {'distance': 8}),
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 8}),
        const AiAction('hole',
            {'places': [[10, 10]], 'diameter': 6.6, 'through_all': true}),
        const AiAction('pattern', {
          'kind': 'rect', 'features': ['Hole1'], //
          'direction': 'x', 'count': 2, 'spacing': 60,
          'direction2': '-z', 'count2': 2, 'spacing2': 40,
        }),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(volume(app), closeTo(38400 - 4 * math.pi * 3.3 * 3.3 * 8, 0.05));
    }, skip: skip);

    test('a negative spacing runs the row the other way, never drops it',
        () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 80, 'height': 60}),
        const AiAction('extrude', {'distance': 8}),
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 8}),
        const AiAction('hole',
            {'places': [[70, 10]], 'diameter': 6.6, 'through_all': true}),
        // From (70, z -10): 60 back along x, and 40 further along -z.
        const AiAction('pattern', {
          'kind': 'rect', 'features': ['Hole1'], //
          'direction': 'x', 'count': 2, 'spacing': -60,
          'direction2': 'z', 'count2': 2, 'spacing2': -40,
        }),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.last.detail?['occurrences'], 4);
      expect(volume(app), closeTo(38400 - 4 * math.pi * 3.3 * 3.3 * 8, 0.05));

      final half = await cad.run([
        const AiAction('pattern', {
          'kind': 'rect', 'features': ['Hole1'], //
          'direction': 'x', 'count': 2, 'spacing': -60, 'count2': 2,
        }),
      ]);
      expect(half.ok, isFalse);
      expect(half.outcomes.last.error, contains('spacing2'));
    }, skip: skip);

    test('a bolt circle of six counterbored holes', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 80}),
        const AiAction('extrude', {'distance': 10}),
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 10}),
        const AiAction('hole', {
          'places': [[25, 0]], 'diameter': 6, 'through_all': true, //
          'type': 'counterbore', 'cb_diameter': 10, 'cb_depth': 4,
        }),
        const AiAction('pattern',
            {'kind': 'circ', 'features': ['Hole1'], 'axis': 'y', 'count': 6}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final disc = math.pi * 40 * 40 * 10;
      final one = math.pi * 9 * 10 + math.pi * (25 - 9) * 4;
      expect(volume(app), closeTo(disc - 6 * one, 0.1));
    }, skip: skip);
  });

  group('blends', () {
    test('a hole\'s seam and a round\'s tangent lines are not edges to '
        'blend', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole',
            {'places': [[20, 15]], 'diameter': 8, 'through_all': true}),
        const AiAction('fillet', {'edges': 'vertical', 'radius': 4}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // The four corners — not the seam down the bore.
      expect(r.outcomes.last.detail?['edges'], 4);
      final afterRound = 12000 - math.pi * 160 - 4 * (16 - 4 * math.pi) * 10;
      expect(volume(app), closeTo(afterRound, 0.05));
      // Now every corner left: 8 lines + 8 arcs round the top and bottom
      // outlines, and the bore's two mouths. Not the 8 tangent lines where
      // the corner rounds meet the sides, and not the seam.
      final all = await cad.run([
        const AiAction('fillet', {'edges': 'all', 'radius': 1}),
      ]);
      expect(all.ok, isTrue, reason: all.encode());
      expect(all.outcomes.last.detail?['edges'], 18);
    }, skip: skip);
  });

  group('undo and redo', () {
    test('Redo puts back what Undo took away', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('fillet', {'edges': 'vertical', 'radius': 5}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final rounded = 12000 - 4 * (25 - math.pi * 25 / 4) * 10;
      expect(volume(app), closeTo(rounded, 0.05));
      final p = app.currentPart!;

      // A delete, undone and redone.
      await app.deleteFeature(p.features.firstWhere((f) => f.name == 'Fillet1'));
      expect(volume(app), closeTo(12000, 0.05));
      await app.undoPart();
      expect(p.features.map((f) => f.name), contains('Fillet1'));
      expect(volume(app), closeTo(rounded, 0.05));
      await app.redoPart();
      expect(p.features.map((f) => f.name), isNot(contains('Fillet1')));
      expect(volume(app), closeTo(12000, 0.05));

      // A feature added on top, undone and redone.
      await app.undoPart();
      final c = await cad.run([
        const AiAction('chamfer', {'edges': 'top', 'distance': 1}),
      ]);
      expect(c.ok, isTrue, reason: c.encode());
      final chamfered = volume(app);
      expect(chamfered, lessThan(rounded - 1));
      await app.undoPart();
      expect(volume(app), closeTo(rounded, 0.05));
      await app.redoPart();
      expect(volume(app), closeTo(chamfered, 0.05));
      expect(app.canRedoPart, isFalse);
      await app.undoPart();
      expect(volume(app), closeTo(rounded, 0.05));
    }, skip: skip);
  });

  group('undo covers what the panels create', () {
    test('Ctrl+Z takes back a hole made from the Hole panel', () async {
      final (app, cad) = await fresh();
      final r = await cad.run(plate);
      expect(r.ok, isTrue, reason: r.encode());
      app.startPartSketch();
      app.planePicked('xz');
      app.tool = Tool.point;
      app.toolClick(const Offset(20, 15));
      app.tool = Tool.none;
      app.finishPartSketch();
      final p = app.currentPart!;
      final sk = p.childSketches.last.model.name;
      app.openHole();
      app.holePointPicked(sk, const Offset(20, 15));
      app.setHole(exprDia: '8 mm', extent: FeatureExtent.throughAll);
      expect(await app.applyHole(), isTrue);
      final drilled = 12000 - math.pi * 16 * 10;
      expect(volume(app), closeTo(drilled, 0.05));

      await app.undoPart();
      expect(p.features.whereType<HoleFeature>(), isEmpty);
      expect(volume(app), closeTo(12000, 0.05));
      await app.redoPart();
      expect(p.features.whereType<HoleFeature>(), hasLength(1));
      expect(volume(app), closeTo(drilled, 0.05));
    }, skip: skip);
  });

  group('editing an early feature', () {
    test('rounds on the corners survive making the plate taller or thinner',
        () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('fillet', {'edges': 'vertical', 'radius': 5}),
        const AiAction('chamfer', {'edges': 'top', 'distance': 1}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final p = app.currentPart!;
      // Corner rounds take 4 * (25 - 25pi/4) per mm of height; the top
      // chamfer is the same 1 mm whatever the height.
      final chamfer = 12000 - 4 * (25 - math.pi * 25 / 4) * 10 - volume(app);
      for (final h in [20.0, 6.0]) {
        final e = await cad.run([
          AiAction('edit_feature', {'feature': 'Extrusion1', 'distance': h}),
        ]);
        expect(e.ok, isTrue, reason: e.encode());
        for (final f in p.features) {
          expect(f.computeError, isNull, reason: '${f.name} at h=$h');
        }
        final want = 40 * 30 * h - 4 * (25 - math.pi * 25 / 4) * h - chamfer;
        expect(volume(app), closeTo(want, 0.05), reason: 'h=$h');
      }
    }, skip: skip);

    test('an edit that breaks a feature built on it is refused, not "ok"',
        () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('chamfer', {'edges': 'top', 'distance': 3}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final before = volume(app);
      // 2 mm of plate cannot carry a 3 mm chamfer.
      final e = await cad.run([
        const AiAction('edit_feature', {'feature': 'Extrusion1', 'distance': 2}),
      ]);
      expect(e.ok, isFalse, reason: e.encode());
      expect(e.outcomes.last.error, contains('"Chamfer1"'));
      // Rolled back: the plate is 10 mm again and the chamfer builds.
      final p = app.currentPart!;
      expect((p.features.first as ExtrudeFeature).distanceA, 10);
      for (final f in p.features) {
        expect(f.computeError, isNull, reason: f.name);
      }
      expect(volume(app), closeTo(before, 0.05));
    }, skip: skip);
  });
}
