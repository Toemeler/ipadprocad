// #93 — "das Gehäuse ist viel grösser als es sein müsste und nicht an die
// Form der Innereien angepasst … die Räder … vor allem die Fasen … der Motor
// ist auf einmal einfach verschwunden."
//
//   * The case: a 33 × 37 mm rectangle drawn round a Ø4.4 spool and a Ø28
//     wheel, with an 8.7 mm solid floor where the (vanished) motor stood.
//     `enclose` builds a case from the bodies themselves.
//   * The chamfers: `{"edges": "holes"}` on a turned wheel caught its outer
//     rims, because "holes" meant "every circular edge".
//   * The motor: a block that failed part-way was restored through the same
//     path as Ctrl+Z, which lost imported bodies until M463. Pinned here for
//     the assistant's own rollback.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_knowledge.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

import 'support/shape_fixtures.dart';

class _Recording extends BoxKernel {
  final outlines = <List<Offset>>[];
  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    for (final g in groups) {
      if (g.isNotEmpty) outlines.add(g.first);
    }
    return super.extrude(groups, height, taperDeg, mat34);
  }
}

(double, double) _size(List<Offset> ring) {
  final xs = ring.map((o) => o.dx), ys = ring.map((o) => o.dy);
  return (
    xs.reduce(math.max) - xs.reduce(math.min),
    ys.reduce(math.max) - ys.reduce(math.min)
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('enclose', () {
    test('is an op, a change, and the instructions say when to use it', () {
      expect(kAiOps, contains('enclose'));
      expect(kAiReadOnlyOps, isNot(contains('enclose')));
      expect(kAiActionInstructions, contains('enclose {'));
    });

    test('the case follows the contents: their outline, clearance, wall',
        () async {
      final k = _Recording();
      final app = AppState()..partKernel = k;
      app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_93_');
      await app.createNamedPart('Drive');
      // BoxKernel's box: 60 (X) × 40 (Y, up) × 10 (Z) for a 10 mm extrude.
      final built = await AiCad(app).run(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_rect', {'width': 60, 'height': 10}),
        AiAction('extrude', {'distance': 10}),
      ]);
      expect(built.ok, isTrue, reason: built.encode());
      k.outlines.clear();

      final r = await AiCad(app).run(const [
        AiAction('enclose', {'wall': 2, 'clearance': 0.5})
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // Rebuilds extrude again, so look for the two outlines, not a count.
      final sizes = [for (final o in k.outlines) _size(o)];
      bool has(double w, double d) =>
          sizes.any((s) => (s.$1 - w).abs() < 0.05 && (s.$2 - d).abs() < 0.05);
      expect(has(60 + 2 * 2.5, 10 + 2 * 2.5), isTrue,
          reason: 'outside: clearance + wall all round; got $sizes');
      expect(has(60 + 2 * 0.5, 10 + 2 * 0.5), isTrue,
          reason: 'pocket: clearance all round; got $sizes');
      final d = r.outcomes.single.detail!;
      expect(d['contents'], ['Solid1']);
      expect((d['outsideMm'] as List)[1], closeTo(42, 1e-6),
          reason: '40 of contents on a 2 mm floor, open at the top');
      final p = app.currentPart!;
      expect(
          p.features.map((f) => f.name), containsAll(['case', 'case_pocket']));
      expect(p.bodyNames, hasLength(2), reason: 'the case is its own body');
    });

    test('nothing to enclose says so', () async {
      final app = AppState()..partKernel = _Recording();
      app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_93_');
      await app.createNamedPart('Empty');
      final r = await AiCad(app).run(const [AiAction('enclose', {})]);
      expect(r.ok, isFalse);
    });

    test('the offset outline of a convex hull is exact on the axes', () {
      final sq = [
        const math.Point(0.0, 0.0),
        const math.Point(10.0, 0.0),
        const math.Point(10.0, 10.0),
        const math.Point(0.0, 10.0),
      ];
      final hull = aiConvexHull([...sq, const math.Point(5.0, 5.0)]);
      expect(hull, hasLength(4), reason: 'an interior point is not outline');
      final grown = aiOffsetHull(hull, 2);
      final xs = grown.map((q) => q.x);
      expect(xs.reduce(math.min), closeTo(-2, 1e-9));
      expect(xs.reduce(math.max), closeTo(12, 1e-9));
      for (final q in grown) {
        // Every point is 2 mm from the square, never further.
        final dx = math.max(0.0, math.max(-q.x, q.x - 10));
        final dy = math.max(0.0, math.max(-q.y, q.y - 10));
        expect(math.sqrt(dx * dx + dy * dy), lessThanOrEqualTo(2 + 1e-9));
      }
    });
  });

  group('"holes" is a hole, not every circle', () {
    // A 28 mm wheel with a Ø5.5 bore, 4 mm tall: what the report chamfered.
    final wheel = ringMesh(14, 2.75, 4);
    List<double> circle(double r, double y) => [
          for (var i = 0; i < 48; i++) ...[
            r * math.cos(2 * math.pi * i / 48),
            y,
            r * math.sin(2 * math.pi * i / 48),
          ]
        ];

    test('the bore mouths are mouths, the outer rims are not', () {
      expect(aiRingIsMouth(wheel, circle(2.75, 4), 2.75), isTrue);
      expect(aiRingIsMouth(wheel, circle(2.75, 0), 2.75), isTrue);
      expect(aiRingIsMouth(wheel, circle(14, 4), 14), isFalse);
      expect(aiRingIsMouth(wheel, circle(14, 0), 14), isFalse);
    });

    test('the point test the classification rests on', () {
      expect(aiInsideMesh(wheel, 8, 2, 0), isTrue, reason: 'in the web');
      expect(aiInsideMesh(wheel, 0, 2, 0), isFalse, reason: 'in the bore');
      expect(aiInsideMesh(wheel, 20, 2, 0), isFalse, reason: 'outside');
    });

    test('the instructions say what each selector means', () {
      expect(kAiActionInstructions, contains('"rings" is every circular edge'));
    });
  });

  group('the assistant\'s rollback keeps an imported body (M463)', () {
    test('a block that fails part-way leaves the import standing', () async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_93_');
      await app.createNamedPart('Motor');
      final p = app.currentPart!;
      final motor = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList(const [0]), Float64List(0)),
          7,
          null);
      p.appendFeature(ExtrudeFeature(
          name: 'Import1',
          bodyName: p.nextSolidName(),
          sketchName: '',
          profiles: const [],
          output: 'new')
        ..imported = true
        ..importPath = 'imports/motor.stp'
        ..importIndex = 0
        ..solid = motor
        ..seq = p.nextSeq());
      recomputeAllFeatures(p, app.partKernel);

      final r = await AiCad(app).run(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_rect', {'width': 20, 'height': 20}),
        AiAction('extrude', {'distance': 5, 'operation': 'new'}),
        AiAction('edit_feature', {'feature': 'NoSuchThing', 'distance': 3}),
      ]);
      expect(r.ok, isFalse);
      expect(r.kept, greaterThan(0), reason: 'a partial commit, as in #93');
      final imp = p.features.firstWhere((f) => f.name == 'Import1');
      expect(identical(imp.solid, motor), isTrue,
          reason: 'the motor must survive the restore');
    });
  });

  group('the wheels have a document to design to', () {
    AiKnowledge shipped() {
      final j = jsonDecode(File('assets/knowledge/kb.json').readAsStringSync())
          as Map<String, dynamic>;
      return AiKnowledge.forTest([
        for (final d in (j['documents'] as List).cast<Map>())
          KnowledgeDoc.fromJson(d.cast<String, dynamic>())
      ]);
    }

    test('the requests from #92 and #93 open it', () {
      final kb = shipped();
      for (final q in [
        'modellier als neuen solid eine kleine rolle für 0.2mm durchmesser '
            'schnur',
        'now modell a second wheel. the ratio of the capstan of these 2 '
            'wheels should be 1:10',
      ]) {
        expect(kb.select(q).map((d) => d.id),
            contains('fdm/features/pulleys-and-capstan-drums'),
            reason: q);
      }
    });

    test('"a case for the two" opens the design rules for housings', () {
      final ids = shipped()
          .select('jetzt mach ein 3d druckbares case für die zwei fdm')
          .map((d) => d.id);
      expect(ids, contains('design/form/housings'));
      final d = shipped().byId('design/form/housings')!;
      expect(d.body, contains('`enclose`'));
      expect(d.body, contains('INSIDE OUT'));
    });

    test('it carries the sourced groove rules, and names its sources', () {
      final d = shipped().byId('fdm/features/pulleys-and-capstan-drums')!;
      expect(d.body, contains('1.5 × cord Ø'), reason: 'Rockett');
      expect(d.body, contains('3–5 turns'));
      expect(d.body, contains('through the centre of the cord'));
      expect(d.body, contains('https://www.rockettinc.com/'));
      expect(d.body, contains('https://www.aaedmusa.com/'));
    });

    test('the housing rules are the published ones, and say which are ours',
        () {
      final d = shipped().byId('design/form/housings')!;
      expect(d.body, contains('1.0 mm on FDM'));
      expect(d.body, contains('https://www.hubs.com/'));
      expect(d.body, contains('this app, #93'));
    });
  });
}
