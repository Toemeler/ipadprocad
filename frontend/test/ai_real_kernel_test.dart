// The assistant's modelling ops against the REAL OpenCascade kernel.
//
// Every other assistant test runs on BoxKernel, whose extrusions are fixed
// boxes: it proves bookkeeping and cannot prove geometry. Issues #82-#85 were
// all geometry — a profile 0.0001 mm from closing, a countersink in open air,
// a sweep that twisted through itself, a shell that did not exist — so the
// ops written for them are checked here on the kernel the app ships, with
// volumes worked out by hand.
//
// Runs wherever the kernel library is found: set PROTOTYPE_NATIVE_DIR to the
// directory holding libprototype_native.so (tools/desktop/build_native.sh
// puts it in frontend/build/native). Without it every test here SKIPS with
// that reason rather than passing on a fake.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/mesh_topology.dart';
import 'package:prototype/ai/printability.dart';
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
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_ai_rk_');
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

  group('geometry by construction', () {
    test('a C-clip from expressions closes and builds (#83)', () async {
      final (app, cad) = await fresh();
      // The exact block #83 opened with, but written as the numbers it MEANT.
      final r = await cad.run([
        const AiAction('vars', {'ro': 5, 'ri': 3}),
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_path', {
          'start': ['ro*cos(30)', 'ro*sin(30)'],
          'segments': [
            {'to': ['ro*cos(330)', 'ro*sin(330)'], 'centre': [0, 0]},
            {'to': ['ri*cos(330)', 'ri*sin(330)']},
            {'to': ['ri*cos(30)', 'ri*sin(30)'], 'centre': [0, 0], 'cw': true},
          ],
        }),
        const AiAction('extrude', {'distance': 12}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // 300 of 360 degrees of an annulus between r3 and r5, 12 deep.
      final expected = math.pi * (25 - 9) * (300 / 360) * 12;
      expect(volume(app), closeTo(expected, expected * 0.002));
    }, skip: skip);

    test('sketch_ring with an opening is one closed profile', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_ring', {
          'outer': 12, 'inner': 7, 'opening': 5, 'opening_deg': 0, //
        }),
        const AiAction('extrude', {'distance': 10}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes[1].detail!['closedProfiles'], 1);
      final ring = math.pi * (36 - 12.25) * 10;
      expect(volume(app), lessThan(ring));
      expect(volume(app), greaterThan(ring * 0.8));
    }, skip: skip);

    test('a ring without an opening leaves its middle open', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_ring', {'outer': 20, 'inner': 10}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final ring = math.pi * (100 - 25) * 5;
      expect(volume(app), closeTo(ring, ring * 0.002),
          reason: 'even-odd: the inner disc is a hole, not material');
    }, skip: skip);

    test('a plate with a hole in ONE sketch keeps the hole', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 40, 'height': 30, 'centered': true}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 10}),
        const AiAction('extrude', {'distance': 4}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final v = (40 * 30 - math.pi * 25) * 4;
      expect(volume(app), closeTo(v, v * 0.002));
    }, skip: skip);

    test('a path with rounded corners is exact', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_path', {
          'start': [0, 0],
          'corner_radius': 2,
          'segments': [
            {'to': [30, 0]},
            {'to': [30, 20]},
            {'to': [0, 20]},
          ],
        }),
        const AiAction('extrude', {'distance': 3}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // A 30x20 rectangle minus four corners of (4 - pi) mm² each.
      final v = (600 - 4 * (4 - math.pi)) * 3;
      expect(volume(app), closeTo(v, v * 0.002));
    }, skip: skip);
  });

  group('anchors put features on the part, not at the origin (#82)', () {
    test('sk.cx/sk.cy is the middle of an off-centre plate', () async {
      final (app, cad) = await fresh();
      // #82's plate: centre at world z = -11, so sketch (0,0) is its edge.
      var r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 11, 'width': 46, 'height': 22, 'centered': true}),
        const AiAction('extrude', {'distance': 4}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final before = volume(app);
      r = await cad.run([
        const AiAction('create_sketch', {'on': 'top'}),
        const AiAction(
            'hole', {'x': 'sk.cx', 'y': 'sk.cy', 'diameter': 6, 'through_all': true}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // The whole Ø6 came out of material: a hole on the rim would remove
      // about half of this.
      expect(before - volume(app), closeTo(math.pi * 9 * 4, 0.5));
    }, skip: skip);

    test('a cut that misses the part fails instead of "building"', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 20, 'height': 20, 'centered': true}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 60, 'y': 0, 'diameter': 4}),
        const AiAction('extrude',
            {'distance': 5, 'operation': 'cut', 'through_all': true}),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.last.error, contains('removed no material'));
    }, skip: skip);

    test('a cut pointed away from the part is run the other way', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 20, 'height': 20, 'centered': true}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      final before = volume(app);
      // A sketch on the top face; the default direction is +Y, into air.
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 5}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 4}),
        const AiAction('extrude', {'distance': 2, 'operation': 'cut'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.last.detail?['directionFixed'], isNotNull);
      expect(before - volume(app), closeTo(math.pi * 4 * 2, 0.2));
    }, skip: skip);

    test('lathe turns a profile about a shaft named by its face', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 5, 'y': 3, 'diameter': 2}),
        const AiAction('extrude', {'distance': 10}),
      ]);
      final faces = await cad.run([
        const AiAction('faces_where', {'type': 'cylinder'})
      ]);
      final shaft = (faces.outcomes.first.detail!['faces'] as List).first['face'];
      // A spool: flanges r 4, drum r 3, bore r 1, from y 2 to y 8.
      final r = await cad.run([
        AiAction('lathe', {
          'axis_face': shaft,
          'profile': [[1, 2], [4, 2], [4, 3], [3, 3.5], [3, 6.5], [4, 7], [4, 8], [1, 8]],
          'operation': 'new',
        }),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final at = r.outcomes.last.detail!['axisAt'] as List;
      expect(at[0], closeTo(5, 1e-6));
      // sketch +y on xz is world -Z: the circle at sketch y 3 is at z = -3.
      expect(at[1], closeTo(-3, 1e-6));
      final body = r.outcomes.last.detail!['body'] as String;
      final s = currentBodySolid(app.currentPart!, body)!;
      final pos = s.mesh.positions;
      var x0 = 1e9, x1 = -1e9;
      for (var i = 0; i < pos.length; i += 3) {
        x0 = math.min(x0, pos[i]);
        x1 = math.max(x1, pos[i]);
      }
      expect((x0 + x1) / 2, closeTo(5, 0.01));
      expect(x1 - x0, closeTo(8, 0.02));
    }, skip: skip);

    test('shaft_bore cuts the D of the shaft into the spool', () async {
      final (app, cad) = await fresh();
      // A Ø0.8 D-shaft, flat at x = -0.1, y 0..3.
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_path', {
          'start': [-0.1, '-sqrt(0.15)'],
          'segments': [
            {'to': [-0.1, 'sqrt(0.15)'], 'through': [0.4, 0]}
          ]
        }),
        const AiAction('extrude', {'distance': 3}),
      ]);
      final faces = await cad.run([
        const AiAction('faces_where', {'type': 'cylinder'})
      ]);
      final shaft = (faces.outcomes.first.detail!['faces'] as List).first['face'];
      final r = await cad.run([
        AiAction('lathe', {
          'axis_face': shaft,
          'profile': [[0, 1], [2, 1], [2, 5], [0, 5]],
        }),
        AiAction('shaft_bore', {'face': shaft, 'fit': 'press'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final d = r.outcomes.last.detail!;
      expect(d['boreY'], [0.99, closeTo(3.2, 1e-6)]);
      // Removed: the D (0.3304 mm²) over 2.21 mm.
      expect(d['removedMm3'], closeTo(0.3304 * 2.21, 0.02));
    }, skip: skip);

    test('every block says what a vessel holds', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 70}),
        const AiAction('extrude', {'distance': 80}),
        const AiAction('shell', {'thickness': 2, 'open': 'top'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final holds = (r.state!['holdsMl'] as Map).values.first as num;
      // π · 33² · 78 = 266.9 ml
      expect(holds, closeTo(266.9, 266.9 * 0.02));
    }, skip: skip);

    for (final style in ['round', 'angular']) {
      test('a $style handle meets a tapered wall at both ends', () async {
        final (app, cad) = await fresh();
        final r = await cad.run([
          const AiAction('create_sketch', {'plane': 'xz'}),
          const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 64}),
          const AiAction('extrude', {'distance': 82, 'taper': 5}),
          const AiAction('shell', {'thickness': 2, 'open': 'top'}),
          AiAction('handle', {
            'side': '-z',
            'from_y': 15,
            'to_y': 70,
            'style': style,
            'reach': 22,
          }),
        ]);
        expect(r.ok, isTrue, reason: r.encode());
        final p = app.currentPart!;
        final s = currentBodySolid(p, p.features.last.bodyName)!;
        expect(meshComponentCount(s.mesh), 1);
        // Joined, and the inside is untouched: it still holds what it held.
        expect((r.state!['holdsMl'] as Map).values.first as num,
            greaterThan(230));
        expect(r.outcomes.last.detail!['addedMm3'], greaterThan(1000));
      }, skip: skip);
    }

    test('a new body that runs into another is a problem', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 10}),
        const AiAction('extrude', {'distance': 10}),
      ]);
      final clash = await cad.run([
        const AiAction('lathe', {
          'profile': [[0, 8], [3, 8], [3, 12], [0, 12]],
          'operation': 'new',
        }),
      ]);
      expect(clash.problems.join(), contains('overlap by'), reason: clash.encode());
      final clear = await cad.run([
        const AiAction('lathe', {
          'profile': [[0, 12], [3, 12], [3, 16], [0, 16]],
          'operation': 'new',
          'id': 'clear',
        }),
      ]);
      // Standing on the one before at y = 12 is touching, not a collision.
      expect(clear.problems.where((p) => p.contains('Solid3')), isEmpty,
          reason: clear.encode());
    }, skip: skip);

    test('a join that floats fails instead of "building"', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 20, 'height': 20, 'centered': true}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 30}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 4}),
        const AiAction('extrude', {'distance': 5, 'operation': 'join'}),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.last.error, contains('does not touch'));
      final p = app.currentPart!;
      final body = currentBodySolid(p, p.bodyNames.first)!;
      expect(meshComponentCount(body.mesh), 1);
    }, skip: skip);
  });

  group('shell (#85)', () {
    test('a box shelled 1 mm, open at the bottom', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 50, 'height': 30, 'centered': true}),
        const AiAction('extrude', {'distance': 20}),
        const AiAction('shell', {'thickness': 1, 'open': 'bottom'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // Outside 50x30x20 kept; inside 48x28x19 removed.
      const v = 50 * 30 * 20 - 48 * 28 * 19;
      expect(volume(app), closeTo(v, v * 0.002));
    }, skip: skip);

    test('a cup: a cylinder shelled open at the top', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 80}),
        const AiAction('extrude', {'distance': 72}),
        const AiAction('shell', {'thickness': 2.4, 'open': 'top'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final v = math.pi * 40 * 40 * 72 - math.pi * 37.6 * 37.6 * 69.6;
      expect(volume(app), closeTo(v, v * 0.003));
    }, skip: skip);
  });

  group('sweep (#84)', () {
    test('profile_circle builds the handle square to its path', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_arc',
            {'x1': 38.5, 'y1': 20, 'x2': 65, 'y2': 43, 'x3': 38.5, 'y3': 66}),
        const AiAction('sweep',
            {'path_sketch': 'Sketch1', 'profile_circle': 10, 'operation': 'new'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final p = app.currentPart!;
      final solid = currentBodySolid(p, p.bodyNames.first)!;
      expect(solid.shape!.valid, isTrue);
      // A torus section: circle area x path length.
      final len = r.outcomes.last.detail!['pathLengthMm'] as double;
      expect(solid.volume, closeTo(math.pi * 25 * len, math.pi * 25 * len * 0.02));
    }, skip: skip);

    test('the #84 profile, drawn flat on XZ, is refused before it folds',
        () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_arc',
            {'x1': 43.5, 'y1': 10, 'x2': 71.5, 'y2': 38, 'x3': 43.5, 'y3': 66}),
        const AiAction('create_sketch', {'plane': 'xz', 'offset': 10}),
        const AiAction('sketch_circle', {'x': 43.5, 'y': 0, 'diameter': 10}),
        const AiAction('sweep', {
          'profile_sketch': 'Sketch2',
          'path_sketch': 'Sketch1',
          'operation': 'new'
        }),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.last.error, contains('square'));
      expect(app.currentPart!.features, isEmpty);
    }, skip: skip);
  });

  group('blocks that stumble keep what worked', () {
    test('a step that fails keeps the steps before it', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 20, 'height': 20, 'centered': true}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      final r = await cad.run([
        const AiAction('create_sketch', {'on': 'top'}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 8}),
        const AiAction('extrude', {'distance': 3, 'operation': 'join'}),
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 90, 'y': 0, 'diameter': 4}),
        const AiAction('extrude',
            {'distance': 5, 'operation': 'cut', 'through_all': true}),
      ]);
      expect(r.reverted, isTrue);
      expect(r.kept, 3);
      final p = app.currentPart!;
      expect(p.features.length, 2,
          reason: 'the boss stays; the missed cut and its sketch go');
      expect(p.childSketches.length, 2);
      expect(volume(app), closeTo(20 * 20 * 5 + math.pi * 16 * 3, 0.5));
      final json = r.toJson();
      expect(json['kept'], 3);
      expect(json['note'], contains('Actions 1-3 are in the document'));
    }, skip: skip);
  });

  group('feature ids replace in place (#83)', () {
    test('re-sending an id replaces, it does not duplicate', () async {
      final (app, cad) = await fresh();
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 20, 'height': 20, 'centered': true}),
        const AiAction('extrude', {'distance': 5, 'id': 'plate'}),
        const AiAction('fillet', {'radius': 1, 'edges': 'vertical'}),
      ]);
      final r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 30, 'height': 20, 'centered': true}),
        const AiAction('extrude', {'distance': 5, 'id': 'plate'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final p = app.currentPart!;
      expect(p.features.map((f) => f.name).toList(), ['plate', 'Fillet1'],
          reason: 'same place in the timeline, the fillet rebuilt on top');
      expect(p.features.last.computeError, isNull);
      expect(volume(app), closeTo(30 * 20 * 5 - 4 * (1 - math.pi / 4) * 5, 1));
    }, skip: skip);
  });

  group('#87 — a teacup that prints', () {
    test('near finds a circular rim from any point on it', () async {
      final (app, cad) = await fresh();
      await cad.run(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 76}),
        AiAction('extrude', {'distance': 40}),
      ]);
      // The rim's midpoint by arc length is on the far side; the model
      // pointed at the near side, as it did three times in #87.
      final r = await cad.run(const [
        AiAction('fillet', {'radius': 1, 'near': [[38, 40, 0]]}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.single.detail!['edges'], 1);
    }, skip: skip);

    Future<List<String>> overhangsOf(List<AiAction> build) async {
      final (app, cad) = await fresh();
      final r = await cad.run(build);
      expect(r.ok, isTrue, reason: r.encode());
      final p = app.currentPart!;
      return overhangReport(currentBodySolid(p, p.bodyNames.first)!.mesh);
    }

    test('a cantilevered arm is flagged, even a narrow one', () async {
      final found = await overhangsOf(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_rect', {'x': 0, 'y': 0, 'width': 20, 'height': 10, 'centered': true}),
        AiAction('extrude', {'distance': 40}),
        // A 10 mm wide arm sticking out 30 mm at 25 mm up: #87's handle.
        AiAction('create_sketch', {'plane': 'xz', 'offset': 25}),
        AiAction('sketch_rect', {'x': 10, 'y': -5, 'width': 30, 'height': 10}),
        AiAction('extrude', {'distance': 6, 'operation': 'join'}),
      ]);
      expect(found, isNotEmpty);
      expect(found.first, contains('flat ceiling'));
    }, skip: skip);

    test('a bridge held on both sides is not flagged', () async {
      final found = await overhangsOf(const [
        AiAction('create_sketch', {'plane': 'xy'}),
        // An arch: a 30 x 20 block with an 8 mm wide tunnel under it.
        AiAction('sketch_path', {'start': [-15, 0], 'segments': [
          {'to': [-4, 0]}, {'to': [-4, 10]}, {'to': [4, 10]}, {'to': [4, 0]},
          {'to': [15, 0]}, {'to': [15, 20]}, {'to': [-15, 20]}]}),
        AiAction('extrude', {'distance': 10}),
      ]);
      expect(found, isEmpty, reason: '$found');
    }, skip: skip);

    test('35° from horizontal prints; 20° does not', () async {
      Future<List<String>> ramp(double deg) => overhangsOf([
            const AiAction('create_sketch', {'plane': 'xy'}),
            // A post with a sloped underside leaning out from it.
            AiAction('sketch_path', {'start': [0, 0], 'segments': [
              {'to': [10, 0]}, {'to': [10, 20]},
              {'to': ['10+20', '20+20*tan($deg)']},
              {'to': ['10+20', '30+20*tan($deg)']}, {'to': [0, '30+20*tan($deg)']}]}),
            const AiAction('extrude', {'distance': 10}),
          ]);
      expect(await ramp(35), isEmpty);
      expect(await ramp(20), isNotEmpty);
    }, skip: skip);

    test('a D handle drawn as leg, arc, leg sweeps as one smooth tube',
        () async {
      final (app, cad) = await fresh();
      final r = await cad.run(const [
        AiAction('vars', {'e': '15*tan(35)'}),
        AiAction('create_sketch', {'plane': 'xy', 'id': 'path'}),
        AiAction('sketch_path', {'closed': false, 'start': [31, 12], 'segments': [
          {'to': [46, '12+e']}, {'to': [46, '72-e'], 'tangent': true},
          {'to': [31, 72]}]}),
        AiAction('sweep', {'path_sketch': 'path', 'profile_circle': 11,
          'operation': 'new'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.last.detail!['pathJoined'], isNotNull);
      final p = app.currentPart!;
      final s = currentBodySolid(p, p.bodyNames.first)!;
      expect(s.shape!.valid, isTrue);
      expect(overhangReport(s.mesh), isEmpty);
    }, skip: skip);
  });
}
