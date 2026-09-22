// Issues #83, #84 and #85 — the protocol pieces that do not need a kernel.
//
// The geometry these feed is proven against real OpenCascade in
// ai_real_kernel_test.dart. This file pins the arithmetic, the parsing and the
// bookkeeping underneath it, which must hold on every build including the
// ones with no kernel linked at all.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_expr.dart';
import 'package:prototype/ai/mesh_topology.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart' show OcctMeshData;

import 'support/shape_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('expressions: the number the model means, exactly', () {
    double ev(String s, [Map<String, double> vars = const {}]) =>
        aiEvalExpression(s, (n) => vars[n]);

    test('the #83 clip end is computed, not rounded', () {
      // The model typed 4.330 for this and the profile missed by 0.000127 mm.
      expect(ev('5*cos(30)'), 5 * math.cos(math.pi / 6));
      expect(ev('ro*sin(330)', {'ro': 5}), closeTo(-2.5, 1e-12));
    });

    test('obvious angles are exact, not 1e-16 off', () {
      expect(ev('sin(180)'), 0);
      expect(ev('cos(90)'), 0);
      expect(ev('cos(180)'), -1);
    });

    test('precedence and associativity are the ones on paper', () {
      expect(ev('2+3*4'), 14);
      expect(ev('(2+3)*4'), 20);
      expect(ev('-2^2'), -4);
      expect(ev('2^-1'), 0.5);
      expect(ev('2^3^2'), 512);
      expect(ev('10/4'), 2.5);
      expect(ev('1.5e1 + .5'), 15.5);
    });

    test('functions and a trailing unit', () {
      expect(ev('max(3, 7, 5)'), 7);
      expect(ev('hypot(3,4)'), 5);
      expect(ev('atan2(1,1)'), closeTo(45, 1e-12));
      expect(ev('12 mm'), 12);
      expect(ev('30deg'), 30);
    });

    test('mistakes are named, not guessed at', () {
      expect(() => ev('r_ot*2', {'r_out': 1}),
          throwsA(isA<AiExprError>().having(
              (e) => e.message, 'message', contains('"r_ot"'))));
      expect(() => ev('1/0'), throwsA(isA<AiExprError>()));
      expect(() => ev('sqrt(-1)'), throwsA(isA<AiExprError>()));
      expect(() => ev('cos(30'), throwsA(isA<AiExprError>()));
      expect(() => ev('2 +'), throwsA(isA<AiExprError>()));
      expect(() => ev('sin(1,2)'), throwsA(isA<AiExprError>()));
      expect(() => ev('exec(1)'), throwsA(isA<AiExprError>()));
    });

    test('bounded: nothing a reply can type makes this slow', () {
      expect(() => ev('(' * 100 + '1' + ')' * 100),
          throwsA(isA<AiExprError>()));
      expect(() => ev('1+' * 200 + '1'), throwsA(isA<AiExprError>()));
    });

    test('words stay words; arithmetic is arithmetic', () {
      bool known(String n) => n == 'wall';
      expect(aiLooksLikeExpression('outer', isName: known), isFalse);
      expect(aiLooksLikeExpression('Extrusion1', isName: known), isFalse);
      expect(aiLooksLikeExpression('F3', isName: known), isFalse);
      expect(aiLooksLikeExpression('wall', isName: known), isTrue);
      expect(aiLooksLikeExpression('sk.cx', isName: known), isTrue);
      expect(aiLooksLikeExpression('12 mm', isName: known), isTrue);
      expect(aiLooksLikeExpression('r*2', isName: known), isTrue);
    });
  });

  group('points', () {
    test('polar points land on the circle exactly', () {
      expect(aiPoint({'r': 5, 'deg': 90}), [0.0, 5.0]);
      expect(aiPoint({'r': 2, 'deg': 0, 'cx': 1, 'cy': 1}), [3.0, 1.0]);
      expect(aiPoint([1, 2]), [1.0, 2.0]);
      expect(aiPoint({'x': 1, 'y': 2}), [1.0, 2.0]);
      expect(aiPoint('nope'), isNull);
    });
  });

  group('the block', () {
    test('block-level vars run first and do not count against the cap', () {
      final actions = [
        for (var i = 0; i < kAiMaxActionsPerBlock; i++) '{"op": "describe_part"}'
      ].join(',');
      final b = parseAiActions(
          '```cad\n{"title": "t", "vars": {"a": 1}, "actions": [$actions]}\n```');
      expect(b.parseError, isNull);
      expect(b.actions.first.op, 'vars');
      expect(b.actions.first.args, {'a': 1});
      expect(b.actions.length, kAiMaxActionsPerBlock + 1);
    });

    test('a say-only block is an answer, not a malformed block (#85)', () {
      final b = parseAiActions(
          '```cad\n{"title": "Fertig", "say": "Fertig: 1 mm Schale."}\n```');
      expect(b.parseError, isNull);
      expect(b.actions, isEmpty);
      expect(b.say, 'Fertig: 1 mm Schale.');
    });

    test('a partly kept block says where the line is', () {
      final r = AiActionReport(outcomes: const [
        AiActionOutcome('create_sketch'),
        AiActionOutcome('extrude'),
        AiActionOutcome('create_sketch'),
        AiActionOutcome.failed('extrude', 'no'),
      ], reverted: true, kept: 2);
      expect(r.partial, isTrue);
      expect(r.applied, 2);
      final j = r.toJson();
      expect(j['kept'], 2);
      expect(j['note'], contains('Actions 1-2 are in the document'));
      expect(j['note'], contains('Continue from action 3'));
      final back = AiActionReport.decode(r.encode())!;
      expect(back.kept, 2);
      expect(back.partial, isTrue);
    });

    test('problems ride on the report and survive a round trip', () {
      final r = AiActionReport(
          outcomes: const [AiActionOutcome('extrude')],
          problems: const ['Body "Solid1" is 2 separate pieces']);
      expect(r.toJson()['problems'], hasLength(1));
      expect(AiActionReport.decode(r.encode())!.problems, hasLength(1));
    });
  });

  group('only the newest view travels', () {
    AiAttachment png(String name) => AiAttachment.fromBytes(
        name: name,
        bytes: Uint8List.fromList(
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]));

    test('old renders are dropped, the newest kept, user images untouched',
        () {
      final user = AiMessage(
          role: 'user', text: 'like this', attachments: [png('sketch.png')]);
      final t1 = AiMessage(
          role: 'tool', text: '{"actionResults": []}', attachments: [png('a.png')]);
      final t2 = AiMessage(
          role: 'tool',
          text: '{"actionResults": [], "partAfter": {}}',
          attachments: [png('b.png')]);
      final t3 = AiMessage(
          role: 'tool', text: '{"actionResults": []}', attachments: [png('c.png')]);
      final out = aiCompactTurns([user, t1, t2, t3]);
      expect(out[0].attachments, hasLength(1));
      expect(out[1].attachments, isEmpty,
          reason: 'no snapshot to trim, and the image still went');
      expect(out[2].attachments, isEmpty);
      expect(out[3].attachments.single.name, 'c.png');
    });
  });

  group('connectivity', () {
    test('a box is one piece; two boxes apart are two', () {
      final a = boxMesh(10, 10, 10);
      expect(meshComponentCount(a), 1);
      final pos = Float64List.fromList([
        ...a.positions,
        for (var i = 0; i < a.positions.length; i++)
          a.positions[i] + (i % 3 == 0 ? 50 : 0)
      ]);
      final n = a.positions.length ~/ 3;
      final idx = Int32List.fromList([...a.indices, ...a.indices.map((i) => i + n)]);
      final merged = OcctMeshData(pos, Float64List(pos.length), idx,
          Int32List.fromList([0]), Float64List(0));
      expect(meshComponentCount(merged), 2);
    });
  });

  group('the executor, on the box kernel', () {
    Future<AppState> part() async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_i8385_');
      await app.createNamedPart('Work');
      return app;
    }

    test('vars persist across blocks and feed any numeric argument', () async {
      final app = await part();
      final cad = AiCad(app);
      var r = await cad.run([
        const AiAction('vars', {'w': 40, 'h': 'w/2'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.single.detail!['defined'], {'w': 40.0, 'h': 20.0});
      r = await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect',
            {'width': 'w', 'height': 'h', 'centered': true}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.last.detail!['width'], 40);
      expect(r.outcomes.last.detail!['height'], 20);
    });

    test('a bad expression fails the action and names the argument', () async {
      final app = await part();
      final r = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 'd*2'}),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.last.error, contains('"diameter"'));
      expect(r.outcomes.last.error, contains('"d"'));
    });

    test('names stay names: face ids and feature names are not arithmetic',
        () async {
      final app = await part();
      final r = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 10, 'height': 10}),
        const AiAction('extrude', {'distance': 5}),
        const AiAction('rename_feature',
            {'feature': 'Extrusion1', 'name': 'Base 2'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(app.currentPart!.features.single.name, 'Base 2');
    });

    test('a path that would not close cannot be written', () async {
      final app = await part();
      final r = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_path', {
          'start': [0, 0],
          'segments': [
            {'to': [10, 0]},
            {'to': [10, 10], 'centre': [0, 0]},
          ],
        }),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.last.error, contains('one circle'));
    });

    test('a path closes itself and reports one region', () async {
      final app = await part();
      final r = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_path', {
          'start': [0, 0],
          'segments': [
            {'to': [20, 0], 'round': 2},
            {'by': [0, 10]},
            {'to': [0, 10], 'tangent': true},
          ],
        }),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(r.outcomes.last.detail!['closedProfiles'], 1, reason: r.encode());
      expect(r.outcomes.last.detail!['roundedCorners'], 1);
    });

    test('a ring opening wider than its bore is refused', () async {
      final app = await part();
      final r = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_ring', {'outer': 10, 'inner': 6, 'opening': 7}),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.last.error, contains('nothing would be held'));
    });

    test('shell asks where the opening is', () async {
      final app = await part();
      final cad = AiCad(app);
      await cad.run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 10, 'height': 10}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      final r = await cad.run([const AiAction('shell', {'thickness': 1})]);
      expect(r.ok, isFalse);
      expect(r.outcomes.single.error, contains('which side stays open'));
    });
  });
}
